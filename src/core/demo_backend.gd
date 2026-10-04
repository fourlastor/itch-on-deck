class_name DemoBackend
extends RefCounted
## A stand-in for the butler daemon, with invented games. Started with
## `-- --demo`, it lets the screens be seen and photographed with no account
## and no network. It answers in the shapes the real daemon uses.

const PROFILE := {"id": 1, "user": {"id": 1, "username": "demo", "displayName": "Demo account"}}

var _games: Dictionary = {}
var _caves: Array = []
var _pinned: Dictionary = {}


func _init() -> void:
	_add("sands", 101, "Sands of the Duel", "[Short text from the game's itch.io page]", "8F6420:C9973F:band", ["linux"], 0, false)
	_add("lantern", 102, "Lanternfish Postal Service", "Deliver mail along the trench before your light runs out.", "22407A:4F7DCB:disc", ["linux", "windows"], 500)
	_add("hollow", 103, "Hollow Tide", "Fishing at low tide, with consequences.", "1F5E63:3F9A98:band", ["linux", "windows"], 300)
	_add("bramble", 104, "Bramble Circuit", "Top-down racing through hedges.", "2F6B3A:5FA35E:disc", ["linux"], 0)
	_add("paper", 105, "Paper Orchard", "Fold trees. Grow an orchard on your desk.", "96415A:D27D97:blocks", ["linux", "osx"], 400)
	_add("sixteen", 106, "Sixteen Rooms", "A roguelike that fits in sixteen rooms.", "862B38:C45F6C:blocks", ["linux", "windows"], 0)
	_add("dial", 107, "Dial Tone Detective", "Solve cases with a rotary phone.", "5E3768:9665A3:disc", ["windows"], 600)
	_add("tin", 108, "Tin Can Regatta", "Race boats made of scrap. Two to four players, one screen.", "256E86:5DB1CA:band", ["linux", "windows"], 900)
	_add("kiln", 109, "Kiln", "Throw pots. Fire them. Sell some.", "99402A:D0714F:disc", ["linux"], 200)
	_add("moth", 110, "Mothlight", "A platformer where the lamp is the enemy.", "4B4770:8580B8:blocks", [], 0)
	_games["moth"]["type"] = "html"
	_add("night", 111, "Night Bus to Kelvin", "A short story about the last route of the night.", "2E4A63:5F89AB:stripes", ["linux", "windows", "osx"], 300)
	_add("quarry", 112, "Quarry Cat", "A cat, a quarry, forty puzzles.", "5F5A52:9C958A:steps", ["linux"], 500)
	_add("green", 113, "Greenhouse Protocol", "Keep the plants alive on a station that is not.", "5C6B1F:97AB45:bars", ["linux", "windows"], 700)
	_add("tidewater", 114, "Tidewater Radio", "Tune a radio on a flooded coast.", "2D5A4C:6FA890:disc", ["linux", "windows"], 0)
	_add("lowtide", 115, "Low Tide Golf", "Nine holes that are only there at low water.", "66662A:B5B55C:band", ["windows"], 0)
	_add("riptide", 116, "Riptide Courier", "Deliver parcels by kayak before the tide turns.", "7A3B2E:C9795F:stripes", ["linux"], 800)
	_add("other", 117, "[Another project]", "", "4A453F:6B655D:stripes", ["linux"], 0, false)
	_add("web", 118, "[A web game]", "", "4A453F:6B655D:bars", [], 0)
	_games["web"]["type"] = "html"

	_cave("sands", 204, 11520, 1204811)
	_cave("lantern", 310, 20400, 1198204)
	_cave("hollow", 152, 7500, 1177002)
	_cave("bramble", 88, 2400, 0)
	_cave("paper", 64, 900, 1150431)
	_cave("sixteen", 41, 0, 0)
	_pinned["cave-paper"] = true


func handle(method: String, params: Dictionary) -> Dictionary:
	match method:
		"Version.Get":
			return _ok({"version": "v15.31.0", "versionString": "v15.31.0 (demo)"})
		"Profile.List":
			return _ok({"profiles": [PROFILE]})
		"Profile.UseSavedLogin", "Profile.LoginWithAPIKey":
			return _ok({"profile": PROFILE})
		"Fetch.Caves":
			return _ok({"items": _caves_now()})
		"Fetch.ProfileOwnedKeys":
			var keys: Array = []
			for name: String in ["hollow", "dial", "bramble", "tin", "kiln", "lantern", "moth", "night", "paper", "quarry", "sixteen", "green"]:
				keys.append({"id": _games[name].id + 5000, "gameId": _games[name].id, "game": _games[name]})
			return _ok({"items": keys, "stale": false})
		"Fetch.ProfileGames":
			return _ok({"items": [
				{"game": _games["sands"], "published": false},
				{"game": _games["other"], "published": false},
				{"game": _games["web"], "published": true},
			], "stale": false})
		"Fetch.ProfileCollections":
			return _ok({"items": [
				{"id": 1, "title": "Couch co-op", "gamesCount": 12, "updatedAt": "2026-09-28T10:00:00Z"},
				{"id": 2, "title": "Short games", "gamesCount": 31, "updatedAt": "2026-08-02T10:00:00Z"},
				{"id": 3, "title": "Made with Godot", "gamesCount": 8, "updatedAt": "2026-06-17T10:00:00Z"},
			], "stale": false})
		"Fetch.Collection.Games":
			var items: Array = []
			for name: String in ["tin", "bramble", "sixteen", "quarry", "riptide", "lowtide"]:
				items.append({"game": _games[name]})
			return _ok({"items": items, "stale": false})
		"Search.Local":
			return _ok({"games": [_games["tidewater"], _games["hollow"], _games["lowtide"], _games["riptide"]]})
		"Fetch.GameOwnership":
			var owned_ids: Array = [103, 107, 104, 108, 109, 102, 110, 111, 105, 112, 106, 113]
			return _ok({"owned": int(params.get("gameId", 0)) in owned_ids})
		"CheckUpdate":
			return _ok({"updates": [
				{"caveId": "cave-sands", "game": _games["sands"], "direct": true, "choices": [{"upload": _upload("sands", 204), "build": {"id": 1207345}, "confidence": 1.0}]},
				{"caveId": "cave-lantern", "game": _games["lantern"], "direct": true, "choices": [{"upload": _upload("lantern", 310), "build": {"id": 1201377}, "confidence": 1.0}]},
			], "warnings": []})
		"Install.GetUploads":
			var game := _game_by_id(int(params.get("gameId", 0)))
			if game.is_empty() or not game.get("platforms", {}).has("linux"):
				return _ok({"game": game, "uploads": [], "incompatibleUploads": [
					{"id": 9001, "filename": "%s-win64.zip" % _slug(game), "size": 412 * 1048576, "platforms": {"windows": "all"}, "type": "default"},
					{"id": 9002, "filename": "%s-web.zip" % _slug(game), "size": 0, "platforms": {}, "type": "html"},
				]})
			return _ok({"game": game, "uploads": [
				{"id": 7001, "filename": "%s-linux.zip" % _slug(game), "displayName": "", "size": 1288490188, "platforms": {"linux": "all"}, "type": "default", "demo": false},
				{"id": 7002, "filename": "%s-demo.zip" % _slug(game), "displayName": "", "size": 188743680, "platforms": {"linux": "all"}, "type": "default", "demo": true},
			], "incompatibleUploads": [
				{"id": 7003, "filename": "%s-win64.zip" % _slug(game), "size": 1288490188, "platforms": {"windows": "all"}, "type": "default"},
			]})
		"Install.Plan":
			return _ok({"info": {"diskUsage": {"finalDiskUsage": 2576980377, "neededFreeSpace": 2791728742, "accuracy": "guess"}}})
		"Install.Locations.List":
			return _ok({"installLocations": [
				{"id": "internal", "path": Paths.default_install_location(), "sizeInfo": {"installedSize": 859 * 1048576, "freeSize": 38.0 * 1073741824, "totalSize": 238.0 * 1073741824}},
				{"id": "sd", "path": "/run/media/deck/SD/itch", "sizeInfo": {"installedSize": 0, "freeSize": 201.0 * 1073741824, "totalSize": 476.0 * 1073741824}},
			]})
		"Downloads.List":
			return _ok({"downloads": [
				{"id": "dl-tin", "reason": "install", "position": 0, "game": _games["tin"], "upload": {"size": 1288490188, "filename": "tin-can-regatta-linux.zip"}},
				{"id": "dl-kiln", "reason": "install", "position": 1, "game": _games["kiln"], "upload": {"size": 100663296}},
				{"id": "dl-lantern", "reason": "update", "position": 2, "caveId": "cave-lantern", "game": _games["lantern"], "upload": {"size": 14680064}},
				{"id": "dl-night", "reason": "install", "position": 3, "game": _games["night"], "upload": {"size": 188743680},
					"error": "unexpected EOF", "errorMessage": "The archive ended early. Nothing was left behind.", "finishedAt": "2026-10-04T13:40:00Z"},
			]})
		"Caves.SetPinned":
			_pinned[str(params.get("caveId", ""))] = bool(params.get("pinned", false))
			return _ok({})
		"Uninstall.Perform":
			var cave_id := str(params.get("caveId", ""))
			_caves = _caves.filter(func(c: Dictionary) -> bool: return c.id != cave_id)
			return _ok({})
		"System.StatFS":
			return _ok({"freeSize": 38.0 * 1073741824, "totalSize": 238.0 * 1073741824})
	return _ok({})


func _ok(result: Dictionary) -> Dictionary:
	return {"result": result}


func _add(key: String, id: int, title: String, text: String, art: String, platforms: Array, cents: int, published: bool = true) -> void:
	var p := {}
	for name: String in platforms:
		p[name] = "all"
	_games[key] = {
		"id": id, "title": title, "shortText": text, "coverUrl": "demo:" + art, "stillCoverUrl": "",
		"platforms": p, "minPrice": cents, "published": published, "type": "default", "classification": "game",
		"url": "https://demo.itch.io/%s" % key,
	}


func _cave(key: String, megabytes: int, seconds: int, build_id: int) -> void:
	var cave := {
		"id": "cave-" + key,
		"game": _games[key],
		"upload": _upload(key, megabytes),
		"stats": {"secondsRun": seconds, "installedAt": "2026-09-01T10:00:00Z", "lastTouchedAt": "2026-10-03T20:00:00Z"},
		"installInfo": {"installedSize": megabytes * 1048576, "installLocation": "internal",
			"installFolder": Paths.default_install_location().path_join(key), "pinned": false},
	}
	if build_id > 0:
		cave["build"] = {"id": build_id}
	_caves.append(cave)


func _caves_now() -> Array:
	var out: Array = []
	for cave: Dictionary in _caves:
		var copy := cave.duplicate(true)
		copy.installInfo.pinned = _pinned.get(cave.id, false)
		out.append(copy)
	return out


func _upload(key: String, megabytes: int) -> Dictionary:
	return {"id": _games[key].id + 6000, "filename": "%s-linux.zip" % _slug(_games[key]), "size": megabytes * 1048576,
		"platforms": {"linux": "all"}, "type": "default", "channelName": "linux"}


func _game_by_id(id: int) -> Dictionary:
	for key: String in _games:
		if _games[key].id == id:
			return _games[key]
	return {}


func _slug(game: Dictionary) -> String:
	return str(game.get("title", "game")).to_lower().replace(" ", "-").replace("[", "").replace("]", "")
