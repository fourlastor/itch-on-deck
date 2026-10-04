class_name InstallLocations
extends RefCounted
## The folders games are installed under (SPEC.md R14). butler keeps the
## list; config.json holds a copy, so the list survives a new database.


static func list() -> Array:
	var res: Dictionary = await Butler.request("Install.Locations.List")
	if Butler.failed(res):
		return []
	return res.result.get("installLocations", [])


## The locations games can be installed to: all of them except the one that
## only exists to hold the app's own folder (see SelfUpdate).
static func for_games() -> Array:
	var own := str(Config.get_value("self_location_id", ""))
	var all: Array = await list()
	return all.filter(func(l: Dictionary) -> bool: return own == "" or str(l.get("id", "")) != own)


## ~/Games/itch to start with, plus whatever the settings file remembers.
static func ensure_default() -> void:
	var known: Array = await for_games()
	var paths: Array = known.map(func(l: Dictionary) -> String: return str(l.get("path", "")))
	var wanted: Array = [Paths.default_install_location()]
	for saved: Variant in Config.get_value("install_locations", []):
		if saved is Dictionary and str(saved.get("path", "")) != "":
			wanted.append(str(saved.path))
	var added := false
	for path: String in wanted:
		if path in paths:
			continue
		if not known.is_empty() and path == Paths.default_install_location():
			# The user has other locations and removed the default one.
			continue
		if await add(path) == "":
			paths.append(path)
			added = true
	if added or Config.get_value("install_locations", []).is_empty():
		await remember()


## Returns "" when added, or the reason it was not.
static func add(path: String) -> String:
	if not Paths.ensure_dir(path):
		return "The folder %s cannot be made." % Paths.display(path)
	var res: Dictionary = await Butler.request("Install.Locations.Add", {"path": path})
	if Butler.failed(res):
		return Butler.error_text(res)
	return ""


static func remove(id: String) -> String:
	var res: Dictionary = await Butler.request("Install.Locations.Remove", {"id": id})
	if Butler.failed(res):
		return Butler.error_text(res)
	await remember()
	return ""


static func remember() -> void:
	var copy: Array = []
	for location: Dictionary in await for_games():
		copy.append({"id": str(location.get("id", "")), "path": str(location.get("path", ""))})
	Config.set_value("install_locations", copy)


## A name for a location: "Internal" for the home disk, else the folder.
static func label(location: Dictionary) -> String:
	var path := str(location.get("path", ""))
	if path.begins_with("/run/media/"):
		return "SD card"
	if path.begins_with(Paths.home()):
		return "Internal"
	return path.get_file() if path.get_file() != "" else path
