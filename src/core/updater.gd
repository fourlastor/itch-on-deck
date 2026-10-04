class_name Updater
extends RefCounted
## The scheduled update run (SPEC.md section 8), started by a systemd user
## timer with no window: `itch-on-deck --headless -- update`, from a copy of
## the app (see Schedule). It updates the installed games that are not
## pinned, and writes what it did to standard output (the journal) and to
## state.json.
##
## No connection is "not now", never a failure (R22). A game that is running
## is left for the next run (R21). An update with several possible uploads
## is left for the app to show (R23).

const WAIT_FOR_CONNECTION := 60.0
const PROBE_URL := "https://api.itch.io/"

var _host: Node


func run(host: Node) -> int:
	_host = host
	if not _take_lock():
		print("Another update run is in progress; nothing to do.")
		return 0
	var run_record := {
		"at": int(Time.get_unix_time_from_system()),
		"outcome": "nothing", "updated": [], "skipped": [], "left": [], "errors": [],
	}
	var code: int = await _run(run_record)
	UpdateState.add_run(run_record)
	print(UpdateState.describe(run_record))
	Butler.stop()
	_release_lock()
	return code


func _run(record: Dictionary) -> int:
	if not await _wait_for_connection():
		record["outcome"] = "no_connection"
		return 0
	if not ButlerInstall.is_installed():
		return _not_ready(record, "butler is not installed yet. Open the app once.")
	if not Butler.start(Paths.butler_bin(ButlerInstall.VERSION)):
		record["errors"].append("butler did not start")
		record["outcome"] = "failed"
		return 1
	if not await Session.resume():
		return _not_ready(record, "Nobody is signed in. Open the app and sign in.")
	await Bandwidth.apply()
	await Library.refresh_installed()
	var problem: String = await Library.check_updates()
	if problem != "":
		if not await _online():
			record["outcome"] = "no_connection"
			return 0
		record["errors"].append("looking for updates: " + problem)
		record["outcome"] = "failed"
		return 1

	# A record an earlier version made for the app's own folder is not a game.
	var own_cave := SelfUpdate.cave_id()
	await Downloads.sweep()
	Downloads.start()
	for cave_id: String in Library.updates.keys():
		if Config.schedule() == "off" or (own_cave != "" and cave_id == own_cave):
			continue
		var update: Dictionary = Library.updates[cave_id]
		var title := str(update.get("game", {}).get("title", "A game"))
		var choices: Array = update.get("choices", [])
		if choices.size() != 1:
			record["left"].append({"title": title, "reason": "%d possible uploads" % choices.size()})
			continue
		if is_running(_folder_of(cave_id)):
			record["skipped"].append({"title": title, "reason": "it was running"})
			continue
		print("Updating %s." % title)
		problem = await _apply(cave_id, choices[0])
		if problem == "":
			record["updated"].append({"title": title, "version": _version_of(choices[0])})
		elif not await _online():
			# Cut short by a lost connection: removed, and tried again next run.
			record["skipped"].append({"title": title, "reason": "the connection went away"})
		else:
			record["errors"].append("%s: %s" % [title, problem])
	# The app and the games have separate switches.
	if SelfUpdate.enabled() and SelfUpdate.is_a_build():
		await _update_app(record)
	if not record["errors"].is_empty():
		record["outcome"] = "failed"
		return 1
	if not record["updated"].is_empty():
		record["outcome"] = "updated"
	return 0


## The app itself (SelfUpdate): butler puts the page's newest build into the
## app's folder when this copy is another version.
func _update_app(record: Dictionary) -> void:
	var title: String = SelfUpdate.GAME["title"]
	var newest: Dictionary = await SelfUpdate.look()
	if newest.error != "":
		if await _online():
			record["errors"].append("%s: %s" % [title, newest.error])
		return
	if not SelfUpdate.has_update():
		return
	if SelfUpdate.runs_from_own_file():
		# butler cannot write a program file that is running, and this run is
		# running from it. The timer starts the run from a copy (Schedule).
		record["skipped"].append({"title": title, "reason": "this run was started from the app's own program file, which cannot replace itself"})
		return
	if SelfUpdate.window_is_open() or Processes.any_under(SelfUpdate.folder()):
		record["skipped"].append({"title": title, "reason": "the app was open"})
		return
	print("Updating %s." % title)
	var problem: String = await SelfUpdate.apply(newest)
	if problem == "":
		record["updated"].append({"title": title, "version": str(newest.version)})
	elif not await _online():
		record["skipped"].append({"title": title, "reason": "the connection went away"})
	else:
		record["errors"].append("%s: %s" % [title, problem])


## True while a game started through butler, or any program out of the
## game's folder, is running.
static func is_running(folder: String) -> bool:
	if folder == "":
		return false
	var lock := folder.path_join(".itch/runlock.json")
	if FileAccess.file_exists(lock):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(lock))
		if parsed is Dictionary:
			var pid := int(parsed.get("pid", parsed.get("PID", 0)))
			if pid > 0 and DirAccess.dir_exists_absolute("/proc/%d" % pid):
				return true
	return Processes.any_under(folder)


func _apply(cave_id: String, choice: Dictionary) -> String:
	var problem: String = await Downloads.queue_update(cave_id, choice)
	if problem != "":
		return problem
	while Downloads.pending_count() > 0:
		await _host.get_tree().create_timer(1.0).timeout
	await Downloads.refresh()
	for d: Dictionary in Downloads.failed():
		if str(d.get("caveId", "")) == cave_id:
			var reason := Downloads.error_text(d)
			# A failed download is removed, so nothing is left half-installed.
			await Downloads.discard(str(d.get("id", "")))
			await _wait_until_gone(str(d.get("stagingFolder", "")))
			return reason if reason != "" else "the download failed"
	return ""


## butler deletes what a discarded download had fetched a moment after it
## is discarded. The run ends right after, so it waits for that here; what
## is still there after the wait is removed by the next run (Downloads.sweep).
func _wait_until_gone(folder: String) -> void:
	for attempt in 6:
		if folder == "" or not DirAccess.dir_exists_absolute(folder):
			return
		await _host.get_tree().create_timer(0.5).timeout


func _not_ready(record: Dictionary, note: String) -> int:
	record["outcome"] = "not_ready"
	record["note"] = note
	return 0


func _folder_of(cave_id: String) -> String:
	for cave: Dictionary in Library.caves:
		if str(cave.get("id", "")) == cave_id:
			return GameEntry.for_cave(cave).install_folder()
	return ""


static func _version_of(choice: Dictionary) -> String:
	var build: Variant = choice.get("build")
	if build is Dictionary:
		var version := str(build.get("userVersion", ""))
		if version != "":
			return version
		if int(build.get("id", 0)) > 0:
			return "build %d" % int(build.get("id", 0))
	return ""


## Waits up to a minute for itch.io to be reachable: a Deck that just woke
## has no Wi-Fi yet.
func _wait_for_connection() -> bool:
	var waited := 0.0
	while true:
		if await _online():
			return true
		if waited >= WAIT_FOR_CONNECTION:
			return false
		await _host.get_tree().create_timer(5.0).timeout
		waited += 5.0
	return false


func _online() -> bool:
	var http := HTTPRequest.new()
	http.timeout = 8.0
	_host.add_child(http)
	var ok := false
	if http.request(PROBE_URL, PackedStringArray(), HTTPClient.METHOD_HEAD) == OK:
		var done: Array = await http.request_completed
		# Any answer at all means the server was reached.
		ok = done[0] == HTTPRequest.RESULT_SUCCESS
	http.queue_free()
	return ok


# Two runs must never overlap (the timer can fire during a long download).
# Making a folder either works or fails in one step, which makes it a lock.
func _take_lock() -> bool:
	var lock := Paths.update_lock_path()
	Paths.ensure_dir(lock.get_base_dir())
	if DirAccess.make_dir_absolute(lock) != OK:
		var owner := int(FileAccess.get_file_as_string(lock.path_join("pid")))
		if owner > 0 and DirAccess.dir_exists_absolute("/proc/%d" % owner):
			return false
		# Left behind by a run that was killed.
		_release_lock()
		if DirAccess.make_dir_absolute(lock) != OK:
			return false
	var file := FileAccess.open(lock.path_join("pid"), FileAccess.WRITE)
	if file != null:
		file.store_string(str(OS.get_process_id()))
		file.close()
	return true


func _release_lock() -> void:
	var lock := Paths.update_lock_path()
	DirAccess.remove_absolute(lock.path_join("pid"))
	DirAccess.remove_absolute(lock)
