//! Own one scheduled run; apply the queued self-update only after Godot exits.
use serde_json::{json, Value};
use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufRead, BufReader, Write};
use std::os::fd::AsRawFd;
use std::os::unix::{ffi::OsStrExt, fs::DirBuilderExt, fs::OpenOptionsExt, process::ExitStatusExt};
use std::path::{Path, PathBuf};
use std::process::{self, Child, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::atomic::{AtomicI32, Ordering};

static INTERRUPTED: AtomicI32 = AtomicI32::new(0);
static CHILD_PID: AtomicI32 = AtomicI32::new(0);

extern "C" fn on_signal(signal: libc::c_int) {
    INTERRUPTED.store(signal, Ordering::Relaxed);
    let pid = CHILD_PID.load(Ordering::Relaxed);
    if pid > 0 {
        // kill is async-signal-safe; the normal path reaps the child.
        unsafe { libc::kill(pid, libc::SIGTERM) };
    }
}

fn install_signals() -> io::Result<()> {
    // No SA_RESTART: a blocked daemon read must wake up on interruption.
    unsafe {
        let mut action: libc::sigaction = std::mem::zeroed();
        action.sa_sigaction = on_signal as *const () as usize;
        libc::sigemptyset(&mut action.sa_mask);
        for signal in [libc::SIGTERM, libc::SIGINT] {
            if libc::sigaction(signal, &action, std::ptr::null_mut()) != 0 {
                return Err(io::Error::last_os_error());
            }
        }
    }
    Ok(())
}

fn interrupted() -> bool {
    INTERRUPTED.load(Ordering::Relaxed) != 0
}

fn watch_child(child: &Child) {
    CHILD_PID.store(child.id() as i32, Ordering::Relaxed);
    if interrupted() {
        unsafe { libc::kill(child.id() as i32, libc::SIGTERM) };
    }
}

fn wait_child(child: &mut Child) -> io::Result<i32> {
    let status = child.wait()?;
    CHILD_PID.store(0, Ordering::Relaxed);
    Ok(status.code().unwrap_or(128 + status.signal().unwrap_or(1)))
}

fn string<'a>(value: &'a Value, key: &str) -> &'a str {
    value[key].as_str().unwrap_or("")
}

fn alive(pid: u32) -> bool {
    pid > 0 && Path::new(&format!("/proc/{pid}")).exists()
}

fn read_pid(path: &Path) -> u32 {
    fs::read_to_string(path)
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0)
}

fn read_json(path: &Path) -> Result<Value, String> {
    let file = File::open(path).map_err(|e| e.to_string())?;
    if file.metadata().map_err(|e| e.to_string())?.len() > 16 * 1024 * 1024 {
        return Err("JSON file is too large".into());
    }
    serde_json::from_reader(file).map_err(|e| e.to_string())
}

fn write_json(path: &Path, value: &Value) -> io::Result<()> {
    let temporary = path.with_file_name(format!(
        "{}.tmp",
        path.file_name().unwrap().to_string_lossy()
    ));
    let result: io::Result<()> = (|| {
        let mut file = File::create(&temporary)?;
        serde_json::to_writer(&mut file, value)?;
        file.write_all(b"\n")?;
        file.sync_all()?;
        fs::rename(&temporary, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(temporary);
    }
    result
}

struct RunLock {
    directory: PathBuf,
    _file: File,
}

impl RunLock {
    fn take(data: &Path) -> io::Result<Option<Self>> {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o600)
            .open(data.join("update-run.lock"))?;
        let fd = file.as_raw_fd();
        if unsafe { libc::flock(fd, libc::LOCK_EX | libc::LOCK_NB) } != 0 {
            let error = io::Error::last_os_error();
            return if error.kind() == io::ErrorKind::WouldBlock {
                Ok(None)
            } else {
                Err(error)
            };
        }
        let directory = data.join("update.lock");
        if alive(read_pid(&directory.join("pid"))) {
            return Ok(None);
        }
        match fs::DirBuilder::new().mode(0o700).create(&directory) {
            Ok(()) => (),
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => (),
            Err(e) => return Err(e),
        }
        // Children inherit the flock, so killing the owner cannot admit a
        // second run while its app or daemon is still using the installation.
        let flags = unsafe { libc::fcntl(fd, libc::F_GETFD) };
        if flags < 0 || unsafe { libc::fcntl(fd, libc::F_SETFD, flags & !libc::FD_CLOEXEC) } < 0 {
            return Err(io::Error::last_os_error());
        }
        let lock = Self {
            directory,
            _file: file,
        };
        fs::write(lock.directory.join("pid"), process::id().to_string())?;
        let _ = fs::remove_file(lock.job_path()); // Never replay a stale operation.
        Ok(Some(lock))
    }

    fn job_path(&self) -> PathBuf {
        self.directory.join("self-update.json")
    }
}

impl Drop for RunLock {
    fn drop(&mut self) {
        for name in ["self-update.json", "self-update.json.tmp", "pid"] {
            let _ = fs::remove_file(self.directory.join(name));
        }
        let _ = fs::remove_dir(&self.directory);
    }
}

fn app_open(data: &Path, folder: &Path) -> bool {
    if alive(read_pid(&data.join("window.pid"))) {
        return true;
    }
    let Ok(entries) = fs::read_dir("/proc") else {
        return true;
    };
    for entry in entries.flatten() {
        let Some(pid) = entry
            .file_name()
            .to_str()
            .and_then(|s| s.parse::<u32>().ok())
        else {
            continue;
        };
        if pid == process::id() {
            continue;
        }
        if fs::read_link(entry.path().join("exe")).is_ok_and(|p| p.starts_with(folder)) {
            return true;
        }
        if let Ok(args) = fs::read(entry.path().join("cmdline")) {
            // Scripts put their interpreter first and their own path second.
            if args
                .split(|b| *b == 0)
                .take(2)
                .any(|s| Path::new(std::ffi::OsStr::from_bytes(s)).starts_with(folder))
            {
                return true;
            }
        }
    }
    false
}

#[derive(Default)]
struct Trace {
    patches: u32,
    patch_size: String,
    upload_size: String,
    repaired: bool,
    no_receipt: bool,
}

impl Trace {
    fn log(&mut self, message: &str) {
        if let Some((_, rest)) = message.split_once("Total upgrade size ") {
            for separator in [
                " is smaller than full upload ",
                " is larger than full upload ",
            ] {
                if let Some((patch, upload)) = rest.split_once(separator) {
                    self.patch_size = patch.into();
                    self.upload_size = upload.into();
                }
            }
        }
        if let Some((_, rest)) = message.split_once("Will apply ") {
            self.patches = rest
                .split_whitespace()
                .next()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0);
        }
        if self.upload_size.is_empty() {
            if let Some((_, rest)) = message.split_once(":: ") {
                if let Some((size, _)) = rest.split_once(" :: #") {
                    self.upload_size = size.into();
                }
            }
        }
        self.repaired |= [
            "Falling back to heal",
            "Heal is less expensive",
            "Healing container",
        ]
        .iter()
        .any(|s| message.contains(s));
        self.no_receipt |= message.contains("No receipt found");
    }

    fn description(&self) -> String {
        if self.repaired {
            return "repaired from the build".into();
        }
        if self.patches > 0 {
            let mut text = format!(
                "{} {}",
                self.patches,
                if self.patches == 1 {
                    "patch"
                } else {
                    "patches"
                }
            );
            if !self.patch_size.is_empty() {
                text.push_str(&format!(", {}", self.patch_size));
            }
            return text;
        }
        if self.no_receipt {
            return format!(
                "the whole build{}",
                if self.upload_size.is_empty() {
                    String::new()
                } else {
                    format!(", {}", self.upload_size)
                }
            );
        }
        String::new()
    }
}

struct Daemon {
    child: Child,
    input: Option<ChildStdin>,
    output: BufReader<ChildStdout>,
    next_id: u32,
    trace: Trace,
}

impl Daemon {
    fn start(job: &Value) -> Result<Self, String> {
        let mut child = Command::new(string(job, "butler"))
            .args([
                "--json",
                "--dbpath",
                string(job, "db"),
                "daemon",
                "--transport",
                "stdio",
                "--destiny-pid",
                &process::id().to_string(),
            ])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .map_err(|e| format!("butler did not start: {e}"))?;
        watch_child(&child);
        Ok(Self {
            input: child.stdin.take(),
            output: BufReader::new(child.stdout.take().unwrap()),
            child,
            next_id: 0,
            trace: Trace::default(),
        })
    }

    fn send(&mut self, message: &Value) -> Result<(), String> {
        let input = self.input.as_mut().unwrap();
        serde_json::to_writer(&mut *input, message).map_err(|e| e.to_string())?;
        input
            .write_all(b"\n")
            .and_then(|_| input.flush())
            .map_err(|_| "butler's request pipe closed".into())
    }

    fn request(&mut self, method: &str, params: Value) -> Result<Value, String> {
        if interrupted() {
            return Err("the update run was interrupted".into());
        }
        self.next_id += 1;
        let id = self.next_id;
        self.send(&json!({"jsonrpc":"2.0", "id":id, "method":method, "params":params}))?;
        loop {
            if interrupted() {
                return Err("the update run was interrupted".into());
            }
            let mut line = String::new();
            match self.output.read_line(&mut line) {
                Ok(0) => {
                    return Err(if interrupted() {
                        "the update run was interrupted"
                    } else {
                        "butler stopped before answering"
                    }
                    .into())
                }
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(e.to_string()),
                _ => (),
            }
            let message: Value =
                serde_json::from_str(&line).map_err(|_| "butler sent invalid JSON")?;
            if let Some(method) = message["method"].as_str() {
                if method == "Log" {
                    self.trace.log(string(&message["params"], "message"));
                }
                if !message["id"].is_null() {
                    self.send(&json!({"jsonrpc":"2.0", "id":message["id"], "error":{"code":-32601, "message":"The self-update helper cannot answer this request"}}))?;
                }
            } else if message["id"].as_u64() == Some(id as u64) {
                if let Some(error) = message.get("error") {
                    return Err(error["message"]
                        .as_str()
                        .unwrap_or("butler gave no reason")
                        .into());
                }
                return message
                    .get("result")
                    .cloned()
                    .ok_or_else(|| "butler's response has no result".into());
            }
        }
    }
}

impl Drop for Daemon {
    fn drop(&mut self) {
        self.input.take();
        unsafe { libc::kill(self.child.id() as i32, libc::SIGTERM) };
        let _ = wait_child(&mut self.child);
    }
}

fn array<'a>(value: &'a mut Value, key: &str) -> &'a mut Vec<Value> {
    if !value[key].is_array() {
        value[key] = json!([]);
    }
    value[key].as_array_mut().unwrap()
}

fn skip(record: &mut Value, job: &Value, reason: &str) {
    array(record, "skipped").push(json!({"title":job["title"], "reason":reason}));
}

fn network_error(message: &str) -> bool {
    [
        "dial tcp",
        "network is unreachable",
        "no such host",
        "i/o timeout",
        "connection reset",
        "connection refused",
        "unexpected EOF",
        "TLS handshake timeout",
    ]
    .iter()
    .any(|s| message.contains(s))
}

fn print_record(record: &Value) {
    let mut any = false;
    for key in ["updated", "skipped", "left", "errors"] {
        for item in record[key].as_array().into_iter().flatten() {
            any = true;
            match key {
                "updated" => {
                    let version = string(item, "version");
                    let how = string(item, "how");
                    println!(
                        "Updated {}{}{}.",
                        string(item, "title"),
                        if version.is_empty() {
                            String::new()
                        } else {
                            format!(" to {version}")
                        },
                        if how.is_empty() {
                            String::new()
                        } else {
                            format!(" ({how})")
                        }
                    );
                }
                "skipped" => println!(
                    "Skipped {}: {}.",
                    string(item, "title"),
                    string(item, "reason")
                ),
                "left" => println!(
                    "{} has {}: pick one in the app.",
                    string(item, "title"),
                    string(item, "reason")
                ),
                _ => println!("Failed: {}", item.as_str().unwrap_or("")),
            }
        }
    }
    if !any {
        println!("Nothing to update.");
    }
}

fn perform(data: &Path, job: &Value) -> Result<i32, String> {
    if !job["record"].is_object()
        || ["id", "stagingFolder", "installFolder", "butler", "db"]
            .iter()
            .any(|key| string(job, key).is_empty())
    {
        return Err("invalid self-update handoff".into());
    }
    let mut record = job["record"].clone();
    let blocked = app_open(data, Path::new(string(job, "installFolder")));
    if blocked {
        skip(&mut record, job, "the app was open");
    }
    let result: Result<(), String> = (|| {
        if interrupted() {
            return Err("the update run was interrupted".into());
        }
        let mut daemon = Daemon::start(job)?;
        let install = (|| {
            if blocked {
                return Ok(());
            }
            let rate = job["bandwidth"].as_u64().unwrap_or(0);
            daemon.request(
                "Network.SetBandwidthThrottle",
                json!({"enabled":rate > 0, "rate":rate}),
            )?;
            println!("Updating {}.", string(job, "title"));
            daemon.request(
                "Install.Perform",
                json!({"id":job["id"], "stagingFolder":job["stagingFolder"]}),
            )?;
            array(&mut record, "updated").push(json!({"title":job["title"], "version":job["version"], "how":daemon.trace.description()}));
            Ok(())
        })();
        if !interrupted() {
            // Ask butler to clean its staging; never delete arbitrary trees here.
            let _ = daemon.request(
                "CleanDownloads.Apply",
                json!({"entries":[{"path":job["stagingFolder"], "size":0}]}),
            );
        }
        install
    })();
    if let Err(message) = result {
        if network_error(&message) {
            skip(&mut record, job, "the connection went away");
        } else {
            array(&mut record, "errors")
                .push(json!(format!("{}: {message}", string(job, "title"))));
        }
    }
    let failed = !array(&mut record, "errors").is_empty();
    record["outcome"] = json!(if failed {
        "failed"
    } else if !array(&mut record, "updated").is_empty() {
        "updated"
    } else {
        "nothing"
    });
    print_record(&record);
    let path = data.join("state.json");
    let mut state = read_json(&path)
        .ok()
        .filter(Value::is_object)
        .unwrap_or_else(|| json!({}));
    let runs = array(&mut state, "runs");
    runs.insert(0, record);
    runs.truncate(20);
    write_json(&path, &state).map_err(|e| format!("the update result could not be saved: {e}"))?;
    Ok(i32::from(failed))
}

fn run() -> Result<i32, String> {
    let args: Vec<_> = env::args_os().collect();
    if args.len() != 2 {
        eprintln!("Usage: update-helper <app executable>");
        return Ok(2);
    }
    install_signals().map_err(|e| e.to_string())?;
    let variable = |key| {
        env::var_os(key)
            .filter(|s| !s.is_empty())
            .map(PathBuf::from)
    };
    let data = variable("ITCH_ON_DECK_DATA")
        .or_else(|| variable("XDG_DATA_HOME").map(|p| p.join("itch-on-deck")))
        .or_else(|| variable("HOME").map(|p| p.join(".local/share/itch-on-deck")))
        .ok_or("no data directory")?;
    let Some(lock) = RunLock::take(&data).map_err(|e| format!("taking the update lock: {e}"))?
    else {
        println!("Another update run is in progress; nothing to do.");
        return Ok(0);
    };
    let mut app = Command::new(&args[1])
        .args(["--headless", "--audio-driver", "Dummy", "--", "update"])
        .env("ITCH_ON_DECK_UPDATE_OWNER", process::id().to_string())
        .env("ITCH_ON_DECK_UPDATE_JOB", lock.job_path())
        .env_remove("ITCH_ON_DECK_APP")
        .spawn()
        .map_err(|e| format!("starting the app: {e}"))?;
    watch_child(&app);
    let mut code = wait_child(&mut app).map_err(|e| e.to_string())?;
    if lock.job_path().exists() {
        let job = read_json(&lock.job_path())
            .map_err(|e| format!("unreadable self-update handoff: {e}"))?;
        let applied = perform(&data, &job)?;
        if applied != 0 {
            code = applied;
        }
    }
    if interrupted() {
        code = 128 + INTERRUPTED.load(Ordering::Relaxed);
    }
    Ok(code)
}

fn main() {
    let code = run().unwrap_or_else(|e| {
        eprintln!("itch on Deck: {e}.");
        1
    });
    process::exit(code);
}
