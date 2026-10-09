"""Process-level tests: a real ELF app exits before its executable is opened
for writing, while the native helper keeps the update lock and speaks JSON-RPC.
The daemon stand-in tests failures/races without touching a real account.
Run: sh tools/build_update_helper.sh && python3 -m unittest discover -s tools/tests -v
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "src/core/update_helper.bin"
APP_SOURCE = r'''
use std::{env, fs, process, thread, time::Duration};
fn main() {
    fs::write(env::var_os("TEST_APP_PID").unwrap(), process::id().to_string()).unwrap();
    fs::write(env::var_os("TEST_OWNER").unwrap(), env::var("ITCH_ON_DECK_UPDATE_OWNER").unwrap()).unwrap();
    if let Some(job) = env::var_os("TEST_JOB") {
        fs::copy(job, env::var_os("ITCH_ON_DECK_UPDATE_JOB").unwrap()).unwrap();
    }
    if env::var_os("TEST_APP_WAIT").is_some() {
        loop { thread::sleep(Duration::from_secs(60)); }
    }
    process::exit(env::var("TEST_APP_CODE").unwrap().parse().unwrap());
}
'''
DAEMON_SOURCE = r'''#!/usr/bin/env python3
import json, os, pathlib, time
data = pathlib.Path(os.environ["ITCH_ON_DECK_DATA"])
def reply(obj):
    print(json.dumps(dict(jsonrpc="2.0", **obj)), flush=True)
(data / "daemon-args.json").write_text(json.dumps(__import__('sys').argv))
for line in __import__('sys').stdin:
    msg = json.loads(line)
    if "method" not in msg:
        (data / "unexpected-reply.json").write_text(json.dumps(msg))
        continue
    method = msg["method"]
    with (data / "requests.jsonl").open("a") as f:
        f.write(json.dumps(msg) + "\n")
    if method == "Install.Perform":
        owner = int((data / "update.lock/pid").read_text())
        assert owner == os.getppid()
        pid = int(pathlib.Path(os.environ["TEST_APP_PID"]).read_text())
        assert not pathlib.Path('/proc/' + str(pid)).exists(), 'Godot/app still running!'
        # This is an actual write-open of the ELF that just ran: ETXTBSY
        # would kill this daemon if the helper applied the update too early.
        fd = os.open(os.environ["TEST_APP"], os.O_WRONLY)
        os.close(fd)
        (data / "perform-started").touch()
        if os.environ.get("TEST_DAEMON_WAIT"):
            while not (data / "continue").exists(): time.sleep(.02)
        mode = os.environ.get("TEST_MODE", "success")
        if mode == "crash": __import__('sys').exit(7)
        if mode == "invalid": print('not JSON', flush=True); continue
        if mode == "missing-result": reply(dict(id=msg['id'])); continue
        if mode in ("failure", "offline"):
            reply(dict(id=msg['id'], error=dict(code=1, message='dial tcp: network is unreachable' if mode == 'offline' else 'patch could not be applied')))
            continue
        logs = {
            'success': ['Total upgrade size 215.32 KiB is smaller than full upload 28.34 MiB', 'Will apply 1 patches'],
            'heal': ['Healing container'],
            'first': ['No receipt found.', ':: 28.34 MiB :: #42'],
        }[mode]
        for log in logs: reply(dict(method='Log', params=dict(message=log)))
        reply(dict(id=99, method='Unexpected.Request', params={}))
        reply(dict(id=12345, result={}))  # unrelated response is not completion
        reply(dict(id=msg['id'], result={}))
    elif method == "CleanDownloads.Apply":
        for entry in msg['params']['entries']:
            __import__('shutil').rmtree(entry['path'], ignore_errors=True)
        reply(dict(id=msg['id'], result={}))
    else:
        reply(dict(id=msg['id'], result={}))
'''


class UpdateHelperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compile_dir = tempfile.TemporaryDirectory(prefix="itch-helper-compile-")
        cls.app_template = Path(cls.compile_dir.name) / "app"
        source = cls.app_template.with_suffix(".rs")
        source.write_text(APP_SOURCE)
        subprocess.run(["rustc", "-o", str(cls.app_template), str(source)], check=True)
        if not HELPER.exists(): raise RuntimeError("Build the native helper first")

    @classmethod
    def tearDownClass(cls):
        cls.compile_dir.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="itch helper spaces '")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data = self.root / "data"
        self.data.mkdir()
        self.install = self.root / "install"
        self.install.mkdir()
        self.app = self.install / "app"
        shutil.copy2(self.app_template, self.app)
        self.daemon = self.root / "fake-butler"
        self.daemon.write_text(DAEMON_SOURCE)
        self.daemon.chmod(0o755)
        self.stage = self.root / "stage"
        self.stage.mkdir()
        (self.stage / "pending").touch()
        self.record = dict(at=42, outcome="nothing", updated=[], skipped=[], left=[], errors=[])
        self.job = dict(id="queued-op", stagingFolder=str(self.stage), installFolder=str(self.install), title="itch on Deck", version="next", butler=str(self.daemon), db=str(self.data / "db"), bandwidth=5000, record=self.record)
        self.job_file = self.root / "job.json"
        self.write_job()
        self.env = dict(os.environ, ITCH_ON_DECK_DATA=str(self.data), TEST_APP=str(self.app), TEST_APP_PID=str(self.root / "app.pid"), TEST_OWNER=str(self.root / "owner.pid"), TEST_JOB=str(self.job_file), TEST_APP_CODE="0")

    def write_job(self):
        self.job_file.write_text(json.dumps(self.job))

    def run_helper(self, **env):
        self.env.update(env)
        result = subprocess.run([str(HELPER), str(self.app)], env=self.env, capture_output=True, text=True, timeout=10)
        self.assertFalse((self.data / "update.lock").exists(), result.stderr)
        return result

    def latest(self):
        return json.loads((self.data / "state.json").read_text())["runs"][0]

    def requests(self):
        path = self.data / "requests.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def wait_for(self, path):
        deadline = time.monotonic() + 5
        while not path.exists():
            if time.monotonic() > deadline: self.fail(f"Timed out waiting for {path}")
            time.sleep(.02)

    def test_exit_then_perform_with_fresh_daemon_and_patch_report(self):
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.latest()["updated"][0]["how"], "1 patch, 215.32 KiB")
        self.assertEqual(self.latest()["outcome"], "updated")
        self.assertEqual([r["method"] for r in self.requests()], ["Network.SetBandwidthThrottle", "Install.Perform", "CleanDownloads.Apply"])
        self.assertEqual(self.requests()[0]["params"], dict(enabled=True, rate=5000))
        self.assertEqual(self.requests()[1]["params"], dict(id="queued-op", stagingFolder=str(self.stage)))
        args = json.loads((self.data / "daemon-args.json").read_text())
        self.assertEqual(args[args.index("--destiny-pid") + 1], (self.root / "owner.pid").read_text())
        self.assertEqual(json.loads((self.data / "unexpected-reply.json").read_text())["error"]["code"], -32601)
        self.assertFalse(self.stage.exists())
        self.assertFalse((self.data / "update-run").exists())

    def test_first_install_and_heal_reports(self):
        for mode, how in (("first", "the whole build, 28.34 MiB"), ("heal", "repaired from the build")):
            with self.subTest(mode=mode):
                result = self.run_helper(TEST_MODE=mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.latest()["updated"][0]["how"], how)

    def test_failure_is_saved_and_stage_is_cleaned(self):
        result = self.run_helper(TEST_MODE="failure")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.latest()["outcome"], "failed")
        self.assertIn("patch could not be applied", self.latest()["errors"][0])
        self.assertFalse(self.stage.exists())

    def test_connection_loss_is_a_skip(self):
        result = self.run_helper(TEST_MODE="offline")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.latest()["errors"], [])
        self.assertEqual(self.latest()["skipped"][0]["reason"], "the connection went away")

    def test_daemon_crash_and_malformed_responses_are_failures(self):
        for mode in ("crash", "invalid", "missing-result"):
            with self.subTest(mode=mode):
                result = self.run_helper(TEST_MODE=mode)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(self.latest()["outcome"], "failed")

    def test_window_opened_after_queue_is_rechecked(self):
        (self.data / "window.pid").write_text(str(os.getpid()))
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.latest()["skipped"][0]["reason"], "the app was open")
        self.assertNotIn("Install.Perform", [r["method"] for r in self.requests()])
        self.assertFalse(self.stage.exists())

    def test_running_program_under_app_folder_is_rechecked(self):
        sleep = self.install / "sleep"
        shutil.copy2("/bin/sleep", sleep)
        process = subprocess.Popen([str(sleep), "30"])
        try:
            result = self.run_helper()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.latest()["skipped"][0]["reason"], "the app was open")
            self.assertNotIn("Install.Perform", [r["method"] for r in self.requests()])
        finally:
            process.terminate(); process.wait(timeout=5)

    def test_game_failures_and_history_survive_app_success(self):
        self.record["errors"] = ["A game: failed"]
        self.write_job()
        (self.data / "state.json").write_text(json.dumps(dict(extra="keep", runs=[dict(at=i) for i in range(25)])))
        result = self.run_helper(TEST_APP_CODE="1")
        self.assertEqual(result.returncode, 1)
        state = json.loads((self.data / "state.json").read_text())
        self.assertEqual(state["extra"], "keep")
        self.assertEqual(len(state["runs"]), 20)
        self.assertEqual(self.latest()["errors"], ["A game: failed"])
        self.assertEqual(len(self.latest()["updated"]), 1)

    def test_no_job_does_not_start_a_daemon_or_add_a_run(self):
        del self.env["TEST_JOB"]
        result = self.run_helper(TEST_APP_CODE="7")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(self.requests(), [])
        self.assertFalse((self.data / "state.json").exists())

    def test_overlapping_run_is_blocked_until_perform_finishes(self):
        self.env["TEST_DAEMON_WAIT"] = "1"
        process = subprocess.Popen([str(HELPER), str(self.app)], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.wait_for(self.data / "perform-started")
            second = subprocess.run([str(HELPER), str(self.app)], env=self.env, capture_output=True, text=True, timeout=5)
            self.assertEqual(second.returncode, 0)
            self.assertIn("Another update run", second.stdout)
            self.assertTrue((self.data / "update.lock").exists())
            (self.data / "continue").touch()
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, stdout + stderr)
            self.assertFalse((self.data / "update.lock").exists())
        finally:
            if process.poll() is None: process.kill(); process.wait()

    def test_signal_stops_daemon_records_interruption_and_releases_lock(self):
        self.env["TEST_DAEMON_WAIT"] = "1"
        process = subprocess.Popen([str(HELPER), str(self.app)], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.wait_for(self.data / "perform-started")
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 143, stdout + stderr)
            self.assertIn("interrupted", self.latest()["errors"][0])
            self.assertFalse((self.data / "update.lock").exists())
        finally:
            if process.poll() is None: process.kill(); process.wait()

    def test_killed_helper_leaves_lock_in_its_running_child(self):
        self.env["TEST_APP_WAIT"] = "1"
        process = subprocess.Popen([str(HELPER), str(self.app)], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        app_pid = None
        try:
            self.wait_for(self.root / "app.pid")
            app_pid = int((self.root / "app.pid").read_text())
            process.kill(); process.wait(timeout=5)
            second = subprocess.run([str(HELPER), str(self.app)], env=self.env, capture_output=True, text=True, timeout=5)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertIn("Another update run", second.stdout)
            self.assertTrue(Path(f"/proc/{app_pid}").exists())
        finally:
            if process.poll() is None: process.kill(); process.wait()
            if app_pid is not None: os.kill(app_pid, signal.SIGTERM)

    def test_stale_lock_is_recovered_without_replaying_old_job(self):
        lock = self.data / "update.lock"
        lock.mkdir()
        (lock / "pid").write_text("2147483647")
        (lock / "self-update.json").write_text("stale garbage")
        (lock / "self-update.json.tmp").write_text("interrupted atomic write")
        del self.env["TEST_JOB"]
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.requests(), [])


if __name__ == "__main__":
    unittest.main()
