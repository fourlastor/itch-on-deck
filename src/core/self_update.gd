class_name SelfUpdate
extends RefCounted
## The app updating itself. It is a page on itch.io like any other game, so
## an update is a butler patch. The folder this copy runs from is handed to
## butler as it is ("Install.Adopt": nothing is downloaded or moved), and
## from then on butler updates that folder like any installed game.
##
## It has its own switch, apart from the games' schedule, and an update is
## applied by the update run only while the app's window is closed.

## "Itch on Deck" on itch.io: fourlastor/itch-on-deck.
const GAME_ID := 5100889
const WINDOW_LOCK := "window.pid"


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


## The app's program file. The update run is started from a copy of it,
## because a program file cannot be written while a program runs from it;
## the copy is told in ITCH_ON_DECK_APP where the real one is (see Schedule).
static func program() -> String:
	var named := OS.get_environment("ITCH_ON_DECK_APP")
	return named if named != "" else OS.get_executable_path()


## The folder the app is in.
static func folder() -> String:
	return program().get_base_dir()


## True when this process runs from the app's own program file, which butler
## can then not replace.
static func runs_from_own_file() -> bool:
	return OS.get_executable_path() == program()


## A published build, as opposed to the project run from the editor.
static func is_a_build() -> bool:
	return not OS.has_feature("editor") and version() != "dev"


## True for the cave that is this very copy of the app.
static func is_own_cave(cave: Dictionary) -> bool:
	if cave.is_empty() or int(cave.get("game", {}).get("id", 0)) != GAME_ID:
		return false
	return str(cave.get("installInfo", {}).get("installFolder", "")).trim_suffix("/") == folder().trim_suffix("/")


## The cave of this copy, or "" while butler does not know the folder.
static func cave_id() -> String:
	for cave: Dictionary in Library.caves:
		if is_own_cave(cave):
			return str(cave.get("id", ""))
	return ""


static func is_managed() -> bool:
	return cave_id() != ""


## Hands the folder this copy runs from to butler. Returns "" when butler
## manages it, or why it does not.
static func adopt() -> String:
	if not is_a_build():
		return "This copy runs from the project's sources, so there is nothing for butler to update."
	if is_managed():
		return ""
	var got: Dictionary = await GameOps.uploads(GAME_ID)
	if got.error != "":
		return "The app's page could not be read: %s" % got.error
	if got.uploads.is_empty():
		return "The app's page has no build for this machine."
	var upload: Dictionary = got.uploads[0]
	var build: Dictionary = upload.get("build", {}) if upload.get("build") is Dictionary else {}
	var newest := str(build.get("userVersion", ""))
	# butler has to be told exactly which build the folder holds. That is only
	# known when this copy is the newest one.
	if newest != version():
		return "This copy is version %s and the page has %s. Download the newest build once; from then on it updates itself." % [version(), newest if newest != "" else "another one"]
	var here := folder().trim_suffix("/")
	var location := await _location_for(here.get_base_dir())
	if location == "":
		return "The folder %s could not be registered with butler." % Paths.display(here.get_base_dir())
	var res: Dictionary = await GameOps.request_for_game(GAME_ID, "Install.Adopt", {
		"gameId": GAME_ID,
		"uploadId": int(upload.get("id", 0)),
		"buildId": int(build.get("id", 0)),
		"installLocationId": location,
		"installFolderName": here.get_file(),
		"profileId": Session.profile_id(),
	})
	if Butler.failed(res):
		return GameOps.explain(res)
	await Library.refresh_installed()
	return ""


## The install location that is the parent of the app's folder. One made for
## this purpose is remembered, so the lists of locations leave it out.
static func _location_for(parent: String) -> String:
	for location: Dictionary in await InstallLocations.list():
		if str(location.get("path", "")).trim_suffix("/") == parent:
			return str(location.get("id", ""))
	var res: Dictionary = await Butler.request("Install.Locations.Add", {"path": parent})
	if Butler.failed(res):
		return ""
	var id := str(res.result.get("installLocation", {}).get("id", ""))
	Config.set_value("self_location_id", id)
	return id


## The window writes its process ID to a file; the update run reads it.
static func mark_window_open() -> void:
	Paths.write_text_atomic(Paths.data_dir().path_join(WINDOW_LOCK), str(OS.get_process_id()))


static func mark_window_closed() -> void:
	DirAccess.remove_absolute(Paths.data_dir().path_join(WINDOW_LOCK))


static func window_is_open() -> bool:
	var path := Paths.data_dir().path_join(WINDOW_LOCK)
	if not FileAccess.file_exists(path):
		return false
	var pid := int(FileAccess.get_file_as_string(path))
	return pid > 0 and pid != OS.get_process_id() and DirAccess.dir_exists_absolute("/proc/%d" % pid)
