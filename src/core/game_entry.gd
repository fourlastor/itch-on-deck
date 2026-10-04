class_name GameEntry
extends RefCounted
## One item of a list: a game (or a collection) together with what this
## machine knows about it. The screens read states from here, so "installed",
## "update known", "not installable here", "draft" and "not owned" mean the
## same thing everywhere (SPEC.md R5, R7).

## butler's Game object, as it came from the daemon.
var game: Dictionary = {}
## The cave, when the game is installed; empty otherwise.
var cave: Dictionary = {}
## A GameUpdate from CheckUpdate, when one is known; empty otherwise.
var update: Dictionary = {}
## One of the user's own projects.
var mine := false
## One of the user's own projects that is not published.
var draft := false
## False for a paid game the account does not own: it is listed, not installable.
var owned := true
## Set instead of `game` for a tile of the Collections list.
var collection: Dictionary = {}


static func for_game(g: Dictionary) -> GameEntry:
	var e := GameEntry.new()
	e.game = g
	return e


static func for_cave(c: Dictionary) -> GameEntry:
	var e := GameEntry.new()
	e.cave = c
	e.game = c.get("game", {})
	return e


static func for_collection(c: Dictionary) -> GameEntry:
	var e := GameEntry.new()
	e.collection = c
	return e


func is_collection() -> bool:
	return not collection.is_empty()


func id() -> int:
	return int(game.get("id", 0))


func title() -> String:
	if is_collection():
		return str(collection.get("title", "Collection"))
	return str(game.get("title", "Untitled"))


func short_text() -> String:
	return str(game.get("shortText", ""))


## The still image is preferred: an animated cover cannot be shown.
func cover_url() -> String:
	var still := str(game.get("stillCoverUrl", ""))
	if still != "":
		return still
	return str(game.get("coverUrl", ""))


func is_installed() -> bool:
	return not cave.is_empty()


func cave_id() -> String:
	return str(cave.get("id", ""))


func has_update() -> bool:
	return not update.is_empty()


func is_pinned() -> bool:
	var info: Dictionary = cave.get("installInfo", {})
	return bool(info.get("pinned", false))


func has_linux_upload() -> bool:
	var platforms: Variant = game.get("platforms")
	if platforms is Dictionary:
		return str(platforms.get("linux", "")) != ""
	return false


## Free to install, as far as price goes.
func is_free() -> bool:
	return float(game.get("minPrice", 0)) <= 0.0


## "Not installable here": the page has no Linux upload (R7).
func is_installable_here() -> bool:
	return is_installed() or has_linux_upload()


func can_install() -> bool:
	return not is_installed() and has_linux_upload() and owned


func installed_size() -> int:
	var info: Dictionary = cave.get("installInfo", {})
	return int(info.get("installedSize", 0))


func install_folder() -> String:
	var info: Dictionary = cave.get("installInfo", {})
	return str(info.get("installFolder", ""))


func install_location_id() -> String:
	var info: Dictionary = cave.get("installInfo", {})
	return str(info.get("installLocation", ""))


func seconds_run() -> int:
	var stats: Dictionary = cave.get("stats", {})
	return int(stats.get("secondsRun", 0))


func upload() -> Dictionary:
	return cave.get("upload", {})


func build() -> Dictionary:
	var b: Variant = cave.get("build")
	return b if b is Dictionary else {}


## What the platforms of the page are, in words: "Linux, Windows".
func platform_names() -> String:
	var names: PackedStringArray = []
	var platforms: Variant = game.get("platforms")
	if platforms is Dictionary:
		if str(platforms.get("linux", "")) != "":
			names.append("Linux")
		if str(platforms.get("windows", "")) != "":
			names.append("Windows")
		if str(platforms.get("osx", "")) != "":
			names.append("macOS")
	if str(game.get("type", "default")) == "html":
		names.append("HTML5")
	return ", ".join(names) if not names.is_empty() else "None listed"
