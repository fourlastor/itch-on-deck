class_name GameOps
extends RefCounted
## What can be done with one game: read its uploads, plan an install, play,
## pin, uninstall (SPEC.md sections 3.3-3.5).


## The uploads that fit this machine and the ones that do not (section 6).
static func uploads(game_id: int) -> Dictionary:
	var res: Dictionary = await request_for_game(game_id, "Install.GetUploads", {"gameId": game_id, "profileId": Session.profile_id()})
	if Butler.failed(res):
		return {"error": explain(res), "uploads": [], "incompatible": [], "game": {}}
	return {
		"error": "",
		"uploads": res.result.get("uploads", []),
		"incompatible": res.result.get("incompatibleUploads", []),
		"game": res.result.get("game", {}),
	}


## Sends a request about one game. A sign-in through the browser gets a key
## that may list the user's games but not read a single game's page, and
## butler rereads a game it has not seen for a few minutes. When that is
## refused, the list holding the game is fetched again, which is allowed
## and makes butler's copy fresh, and the request is sent once more.
static func request_for_game(game_id: int, method: String, params: Dictionary) -> Dictionary:
	var res: Dictionary = await Butler.request(method, params)
	if Butler.failed(res) and Butler.error_text(res).contains("does not permit `game:view`"):
		await Library.freshen(game_id)
		res = await Butler.request(method, params)
	return res


## butler's reason, with the cases this app can say more about.
static func explain(res: Dictionary) -> String:
	var text := Butler.error_text(res)
	if text.contains("does not permit"):
		return "itch.io does not let this sign-in do that (%s). An API key from itch.io, under Settings, API keys, is allowed more." % text.get_slice(": ", text.get_slice_count(": ") - 1)
	return text


## Final size and free space needed for one upload. { error, final, needed }
static func plan(game_id: int, upload_id: int) -> Dictionary:
	var res: Dictionary = await request_for_game(game_id, "Install.Plan", {
		"gameId": game_id, "uploadId": upload_id, "profileId": Session.profile_id(),
	})
	if Butler.failed(res):
		return {"error": explain(res), "final": 0.0, "needed": 0.0}
	var info: Dictionary = res.result.get("info", {})
	if str(info.get("errorMessage", "")) != "":
		return {"error": str(info.errorMessage), "final": 0.0, "needed": 0.0}
	var usage: Dictionary = info.get("diskUsage", {}) if info.get("diskUsage") is Dictionary else {}
	return {
		"error": "",
		"final": float(usage.get("finalDiskUsage", 0)),
		"needed": float(usage.get("neededFreeSpace", 0)),
	}


static func set_pinned(cave_id: String, pinned: bool) -> String:
	var res: Dictionary = await Butler.request("Caves.SetPinned", {"caveId": cave_id, "pinned": pinned})
	if Butler.failed(res):
		return Butler.error_text(res)
	await Library.refresh_installed()
	return ""


## Removes the game's folder and its cave (R13), and its Steam entry (R16a).
static func uninstall(entry: GameEntry) -> String:
	var cave_id := entry.cave_id()
	var res: Dictionary = await Butler.request("Uninstall.Perform", {"caveId": cave_id, "hard": true})
	if Butler.failed(res):
		return Butler.error_text(res)
	if Steam.is_in_steam(cave_id):
		# Uninstalling a game removes its Steam entry too (R16a).
		if Steam.remove_game(cave_id) != "":
			Steam.forget(cave_id)
	Library.forget_update(cave_id)
	await Library.refresh_installed()
	return ""


## Starts the game and returns when it has exited. Only programs that run
## natively are allowed, so nothing needing a browser is started half-way
## (R17). Returns "" or the reason it did not start.
static func launch(cave_id: String, extra_arguments: String = "") -> String:
	var params := {
		"caveId": cave_id,
		"prereqsDir": Paths.data_dir().path_join("prereqs"),
		"profileId": Session.profile_id(),
		"allowedStrategies": ["native"],
	}
	if extra_arguments != "":
		# Tokens without %command% are added to the game's own command.
		params["commandTemplate"] = extra_arguments
	var res: Dictionary = await Butler.request("Launch", params)
	await Library.refresh_installed()
	if Butler.failed(res):
		return launch_error(res)
	return ""


static func launch_error(res: Dictionary) -> String:
	match Butler.error_code(res):
		5000:
			return "butler found nothing in this game's folder that it can start."
		5001:
			return "The thing this game was set to start is no longer there."
		5002:
			return "This game needs a browser or another program the app cannot give it."
		6000:
			return "This game needs a Java runtime, which is not installed."
		19000:
			return "This game asks for a sandbox, and none is available on this machine."
	return Butler.error_text(res)


## A file name for an upload, the way the page shows it.
static func upload_name(upload: Dictionary) -> String:
	var name := str(upload.get("displayName", ""))
	if name == "":
		name = str(upload.get("filename", ""))
	return name if name != "" else "Upload %d" % int(upload.get("id", 0))


static func upload_platforms(upload: Dictionary) -> String:
	var names: PackedStringArray = []
	var platforms: Variant = upload.get("platforms")
	if platforms is Dictionary:
		if str(platforms.get("linux", "")) != "":
			names.append("Linux")
		if str(platforms.get("windows", "")) != "":
			names.append("Windows")
		if str(platforms.get("osx", "")) != "":
			names.append("macOS")
	var kind := str(upload.get("type", "default"))
	if kind == "html":
		names.append("HTML5, plays in a browser")
	elif kind != "default" and names.is_empty():
		names.append(kind.capitalize())
	return ", ".join(names) if not names.is_empty() else "No platform given"
