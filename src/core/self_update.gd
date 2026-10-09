class_name SelfUpdate
extends RefCounted
## The app updating itself. It is a page on itch.io like any other game, so
## butler can fetch its builds: the whole build the first time, a patch after
## that. butler puts a build into the folder the app is in without holding
## that folder as an installed game ("noCave"). Holding it as one would take
## a read of the game's page, which itch.io refuses a sign-in through the
## browser. Reading the page's uploads is allowed to every sign-in, and that
## is how the app sees that there is a newer build.
##
## It has its own switch, apart from the games' schedule, and an update is
## put in by the update run only while the app's window is closed.

## "itch on Deck" on itch.io: fourlastor/itch-on-deck. butler is told what
## the game is, since it may not read the page.
const GAME_ID := 5100889
const GAME := {
	"id": GAME_ID,
	"url": "https://fourlastor.itch.io/itch-on-deck",
	"title": "itch on Deck",
	"classification": "tool",
	"type": "default",
}
const WINDOW_LOCK := "window.pid"

## The page's newest version as `look` last saw it; "" before the first look.
static var newest_version := ""


static func enabled() -> bool:
	return bool(Config.get_value("self_update", false))


## The version of this copy: the commit the publish workflow built it from,
## which is also the build's version on itch.io. "dev" when run from source.
static func version() -> String:
	if FileAccess.file_exists("res://version.txt"):
		var text := FileAccess.get_file_as_string("res://version.txt").strip_edges()
		if text != "":
			return text
	return "dev"


## ITCH_ON_DECK_APP also lets a run started by an older launcher identify
## the installation. New launchers run the installed program directly.
static func program() -> String:
	var named := OS.get_environment("ITCH_ON_DECK_APP")
	return named if named != "" else OS.get_executable_path()


## The folder the app is in.
static func folder() -> String:
	return program().get_base_dir()


## A published build, as opposed to the project run from the editor.
static func is_a_build() -> bool:
	return not OS.has_feature("editor") and version() != "dev"


## True for the installed-game record an earlier version of the app had
## butler make for the app's own folder. It is no longer used, and it stays
## out of every list: uninstalling it would delete the app.
static func is_own_cave(cave: Dictionary) -> bool:
	if cave.is_empty() or int(cave.get("game", {}).get("id", 0)) != GAME_ID:
		return false
	return str(cave.get("installInfo", {}).get("installFolder", "")).trim_suffix("/") == folder().trim_suffix("/")


## The ID of that record, or "".
static func cave_id() -> String:
	for cave: Dictionary in Library.caves:
		if is_own_cave(cave):
			return str(cave.get("id", ""))
	return ""


## Asks itch.io for the app's newest build for this machine:
## { upload, build, version, error }.
static func look() -> Dictionary:
	var out := {"upload": {}, "build": {}, "version": "", "error": ""}
	var res: Dictionary = await Butler.request("Fetch.GameUploads", {"gameId": GAME_ID, "compatible": false, "fresh": true})
	if Butler.failed(res):
		out.error = Butler.error_text(res)
		return out
	var uploads: Variant = res.result.get("uploads")
	for upload: Variant in (uploads if uploads is Array else []):
		if not (upload is Dictionary) or not (upload.get("build") is Dictionary):
			continue
		var platforms: Variant = upload.get("platforms")
		if platforms is Dictionary and platforms.has("linux"):
			out.upload = upload
			out.build = upload["build"]
			out.version = str(upload["build"].get("userVersion", ""))
			newest_version = out.version
			return out
	out.error = "The app's page has no build for this machine."
	return out


## True when the page was seen to have a version that this copy is not.
static func has_update() -> bool:
	return newest_version != "" and newest_version != version()


## Prepare the update without writing to the installation. The native helper
## calls Install.Perform after this process exits, using this saved operation.
static func queue(newest: Dictionary) -> Dictionary:
	var staging := Paths.cache_dir().path_join("self-update")
	# Every try starts clean: what an earlier one left may be for another build.
	await _wipe(staging)
	return await Butler.request("Install.Queue", {
		"noCave": true,
		"installFolder": folder(),
		"stagingFolder": staging,
		"game": GAME,
		"upload": newest.upload,
		"build": newest.build,
		"profileId": Session.profile_id(),
	})


static func _wipe(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		await Butler.request("CleanDownloads.Apply", {"entries": [{"path": path, "size": 0}]})


## The window writes its process ID to a file; the update run reads it.
static func mark_window_open() -> void:
	Paths.write_text_atomic(Paths.data_dir().path_join(WINDOW_LOCK), str(OS.get_process_id()))


static func mark_window_closed() -> void:
	var path := Paths.data_dir().path_join(WINDOW_LOCK)
	# A headless run must not remove a window's marker on its way out.
	if FileAccess.file_exists(path) and int(FileAccess.get_file_as_string(path)) == OS.get_process_id():
		DirAccess.remove_absolute(path)


static func window_is_open() -> bool:
	var path := Paths.data_dir().path_join(WINDOW_LOCK)
	if not FileAccess.file_exists(path):
		return false
	var pid := int(FileAccess.get_file_as_string(path))
	return pid > 0 and pid != OS.get_process_id() and DirAccess.dir_exists_absolute("/proc/%d" % pid)
