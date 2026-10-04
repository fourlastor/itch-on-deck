extends Node
## The download queue (SPEC.md R10-R12). butler holds the queue and works
## through it one item at a time while "Downloads.Drive" is running; this
## node keeps that call alive, mirrors the list and passes on the progress.

signal changed
signal finished(download: Dictionary)

## butler's Download objects, in queue order.
var items: Array = []
## download id -> { stage, progress (0..1), eta (seconds), bps }
var progress: Dictionary = {}
var online := true

var _driving := false
var _wanted := false


func _ready() -> void:
	Butler.notified.connect(_on_notified)


## Everything not finished and not failed.
func pending() -> Array:
	return items.filter(func(d: Dictionary) -> bool: return not _is_done(d) and not _has_error(d))


func pending_count() -> int:
	return pending().size()


## The one being downloaded now: the first of the queue.
func active() -> Dictionary:
	var list := pending()
	return list[0] if not list.is_empty() else {}


func waiting() -> Array:
	var list := pending()
	return list.slice(1) if list.size() > 1 else []


func failed() -> Array:
	return items.filter(func(d: Dictionary) -> bool: return _has_error(d))


func progress_of(download: Dictionary) -> Dictionary:
	return progress.get(str(download.get("id", "")), {})


func for_game(game_id: int) -> Dictionary:
	for d: Dictionary in pending():
		var game: Dictionary = d.get("game", {})
		if int(game.get("id", 0)) == game_id:
			return d
	return {}


func start() -> void:
	_wanted = true
	await refresh()
	_drive()


func stop() -> void:
	_wanted = false
	if _driving:
		await Butler.request("Downloads.Drive.Cancel")
	items = []
	progress.clear()
	changed.emit()


func refresh() -> void:
	var res: Dictionary = await Butler.request("Downloads.List")
	if Butler.failed(res):
		return
	var list: Array = res.result.get("downloads", [])
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("position", 0)) < float(b.get("position", 0)))
	items = list
	changed.emit()


## Puts an install in the queue. Returns "" or the reason it was refused.
func queue_install(game: Dictionary, upload: Dictionary, location_id: String) -> String:
	return await _queue({
		"game": game,
		"upload": upload,
		"installLocationId": location_id,
		"reason": "install",
	})


## Puts an update of an installed game in the queue. `choice` is one of the
## update's choices: an upload, and a build for a wharf upload.
func queue_update(cave_id: String, choice: Dictionary) -> String:
	var params := {"caveId": cave_id, "reason": "update"}
	if choice.get("upload") is Dictionary:
		params["upload"] = choice["upload"]
	if choice.get("build") is Dictionary:
		params["build"] = choice["build"]
	return await _queue(params)


## Stops and removes a download; a partial download is deleted with it (R11).
func discard(download_id: String) -> void:
	await Butler.request("Downloads.Discard", {"downloadId": download_id})
	progress.erase(download_id)
	await refresh()


func retry(download_id: String) -> void:
	await Butler.request("Downloads.Retry", {"downloadId": download_id})
	await refresh()
	_drive()


func clear_finished() -> void:
	await Butler.request("Downloads.ClearFinished")
	await refresh()


## Removes what earlier downloads left behind in the install locations.
## butler deletes a discarded download's folder a moment after it is
## discarded, and a run that ends before that moment leaves the folder
## there. Only folders butler made are touched (they hold its
## operate-context.json), and never the one of a download still listed.
func sweep() -> void:
	var listed: Dictionary = await Butler.request("Downloads.List")
	if Butler.failed(listed):
		return
	var keep: Array[String] = []
	var known: Variant = listed.result.get("downloads")
	for d: Variant in (known if known is Array else []):
		if d is Dictionary:
			keep.append(str(d.get("id", "")))
			keep.append(str(d.get("stagingFolder", "")).get_file())
	var entries: Array = []
	for location: Dictionary in await InstallLocations.list():
		var root := str(location.get("path", "")).path_join("downloads")
		if not DirAccess.dir_exists_absolute(root):
			continue
		for name in DirAccess.get_directories_at(root):
			var folder := root.path_join(name)
			if not (name in keep) and FileAccess.file_exists(folder.path_join("operate-context.json")):
				entries.append({"path": folder, "size": 0})
	if not entries.is_empty():
		await Butler.request("CleanDownloads.Apply", {"entries": entries})


func _queue(params: Dictionary) -> String:
	params["queueDownload"] = true
	params["profileId"] = Session.profile_id()
	var game_id := 0
	if params.get("game") is Dictionary:
		game_id = int(params["game"].get("id", 0))
	var res: Dictionary = await GameOps.request_for_game(game_id, "Install.Queue", params)
	if Butler.failed(res):
		return GameOps.explain(res)
	await refresh()
	_drive()
	return ""


## Keeps "Downloads.Drive" running for as long as there is something to do.
func _drive() -> void:
	if _driving or not _wanted:
		return
	_driving = true
	while _wanted and pending_count() > 0:
		var res: Dictionary = await Butler.request("Downloads.Drive")
		await refresh()
		if Butler.failed(res):
			break
	_driving = false


func _on_notified(method: String, params: Dictionary) -> void:
	match method:
		"Downloads.Drive.Progress":
			var download: Dictionary = params.get("download", {})
			progress[str(download.get("id", ""))] = params.get("progress", {})
			changed.emit()
		"Downloads.Drive.Started", "Downloads.Drive.Errored", "Downloads.Drive.Discarded":
			refresh()
		"Downloads.Drive.Finished":
			var done: Dictionary = params.get("download", {})
			progress.erase(str(done.get("id", "")))
			if str(done.get("caveId", "")) != "":
				Library.forget_update(str(done.get("caveId")))
			await Library.refresh_installed()
			await clear_finished()
			finished.emit(done)
		"Downloads.Drive.NetworkStatus":
			online = str(params.get("status", "online")) == "online"
			changed.emit()


static func _is_done(d: Dictionary) -> bool:
	var at: Variant = d.get("finishedAt")
	return at is String and at != ""


static func _has_error(d: Dictionary) -> bool:
	var message: Variant = d.get("error")
	return message is String and message != ""


## What a download is, in words: "Install", "Update".
static func reason_text(d: Dictionary) -> String:
	match str(d.get("reason", "install")):
		"update":
			return "Update"
		"reinstall":
			return "Reinstall"
		"version-switch":
			return "Version change"
	return "Install"


static func size_of(d: Dictionary) -> float:
	var upload: Variant = d.get("upload")
	if upload is Dictionary:
		return float(upload.get("size", 0))
	return 0.0


## butler's reason for a failure, as one sentence.
static func error_text(d: Dictionary) -> String:
	var friendly := str(d.get("errorMessage", ""))
	if friendly != "":
		return friendly
	return str(d.get("error", ""))
