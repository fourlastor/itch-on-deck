class_name Probe
extends RefCounted
## The spec's "milestone 0": the app's own code driven from the command line,
## with no window, to try the claims marked "to verify" against a real butler
## daemon. It is also the test to run before moving to a newer butler.
##
##     itch-on-deck --headless -- probe caves
##     itch-on-deck --headless -- probe install <game id>
##     itch-on-deck --headless -- probe older <cave id>      go back one build
##     itch-on-deck --headless -- probe updates              look for updates
##     itch-on-deck --headless -- probe update <cave id>     apply a known update
##     itch-on-deck --headless -- probe launch <cave id> [seconds] [plain]
##     itch-on-deck --headless -- probe uninstall <cave id>
##     itch-on-deck --headless -- probe steam <cave id>      add to Steam
##     itch-on-deck --headless -- probe unsteam <cave id>    remove from Steam
##     itch-on-deck --headless -- probe self                 the app's own update
##     itch-on-deck --headless -- probe key [scope ...]      what a browser sign-in may read
##     itch-on-deck --headless -- probe unlisted <game id> <address> [title]
##                                    install a game that is in none of the account's lists


## The first game on itch.io, free and public; the API's own documentation
## uses it as its example. It stands for "a game this account does not own".
const SAMPLE_GAME := 3


static func run(args: PackedStringArray, host: Node) -> int:
	if args.size() < 2:
		printerr("probe: which one? caves, install, older, updates, update, launch, uninstall, steam, unsteam, self, key, unlisted")
		return 2
	if args[1] == "key":
		# Needs neither butler nor the saved login.
		return await _key(host, args.slice(2))
	if not ButlerInstall.is_installed():
		printerr("butler is not installed yet: run `setup` first")
		return 1
	if not Butler.start(Paths.butler_bin(ButlerInstall.VERSION)):
		printerr("butler did not start")
		return 1
	if not await Session.resume():
		printerr("nobody is signed in")
		Butler.stop()
		return 1
	await InstallLocations.ensure_default()
	var code := 0
	match args[1]:
		"caves":
			await _caves()
		"install":
			code = await _install(host, int(args[2]))
		"older":
			code = await _older(host, args[2])
		"updates":
			code = await _updates()
		"update":
			code = await _update(host, args[2])
		"launch":
			code = await _launch(host, args[2], float(args[3]) if args.size() > 3 else 8.0, args.size() > 4 and args[4] == "plain")
		"uninstall":
			code = await _uninstall(args[2])
		"steam", "unsteam":
			code = await _steam(args[1], args[2])
		"self":
			code = await _self()
		"unlisted":
			code = await _unlisted(host, int(args[2]), args[3], args[4] if args.size() > 4 else "")
		_:
			printerr("probe: unknown command ", args[1])
			code = 2
	Butler.stop()
	return code


static func _caves() -> void:
	await Library.refresh_installed()
	if Library.caves.is_empty():
		print("no caves")
	for cave: Dictionary in Library.caves:
		var e := GameEntry.for_cave(cave)
		print("%s  %s  build %s  %s  %s  pinned=%s" % [
			e.cave_id(), e.title(), str(int(e.build().get("id", 0))), Format.size(e.installed_size()),
			e.install_folder(), e.is_pinned()])


static func _install(host: Node, game_id: int) -> int:
	var got: Dictionary = await GameOps.uploads(game_id)
	if got.error != "":
		printerr("uploads: ", got.error)
		return 1
	print("uploads that fit: ", got.uploads.map(func(u: Dictionary) -> String: return GameOps.upload_name(u)))
	print("uploads that do not: ", got.incompatible.map(func(u: Dictionary) -> String: return GameOps.upload_name(u)))
	if got.uploads.is_empty():
		return 1
	var upload: Dictionary = got.uploads[0]
	var planned: Dictionary = await GameOps.plan(game_id, int(upload.get("id", 0)))
	print("plan: needs %s free, final %s %s" % [Format.size(planned.needed), Format.size(planned.final), planned.error])
	var locations: Array = await InstallLocations.list()
	print("install to: ", locations[0].get("path"))
	var game: Dictionary = got.game
	Downloads.start()
	var problem: String = await Downloads.queue_install(game, upload, str(locations[0].get("id", "")))
	if problem != "":
		printerr("queue: ", problem)
		return 1
	return await _wait_for_downloads(host)


## Goes back one build, through the version switch: the way to get an
## install that has an update waiting.
static func _older(host: Node, cave_id: String) -> int:
	Butler.set_handler("InstallVersionSwitchPick", func(params: Dictionary) -> Dictionary:
		var builds: Array = params.get("builds", [])
		print("builds offered: ", builds.map(func(b: Dictionary) -> String: return "%d (v%s)" % [int(b.get("id", 0)), str(b.get("userVersion", ""))]))
		var cave: Dictionary = params.get("cave", {})
		var current := int(cave.get("build", {}).get("id", 0)) if cave.get("build") is Dictionary else 0
		for i in builds.size():
			if int(builds[i].get("id", 0)) < current:
				print("picking build ", int(builds[i].get("id", 0)))
				return {"index": i}
		print("no older build")
		return {"index": -1})
	Downloads.start()
	var res: Dictionary = await Butler.request("Install.VersionSwitch.Queue", {"caveId": cave_id})
	if Butler.failed(res):
		printerr("version switch: ", Butler.error_text(res))
		return 1
	await Downloads.refresh()
	Downloads._drive()
	return await _wait_for_downloads(host)


static func _updates() -> int:
	await Library.refresh_installed()
	var problem: String = await Library.check_updates()
	if problem != "":
		printerr("check: ", problem)
		return 1
	if Library.updates.is_empty():
		print("no updates")
	for cave_id: String in Library.updates:
		var update: Dictionary = Library.updates[cave_id]
		print("%s  %s  direct=%s  %s" % [cave_id, str(update.get("game", {}).get("title", "")), update.get("direct"),
			GameText.update_summary(update)])
	return 0


static func _update(host: Node, cave_id: String) -> int:
	await Library.refresh_installed()
	var problem: String = await Library.check_updates([cave_id])
	var update := Library.update_for_cave(cave_id)
	if problem != "" or update.is_empty():
		print("no update known for this cave ", problem)
		return 1
	var choices: Array = update.get("choices", [])
	print("update: ", GameText.update_summary(update), ", choices: ", choices.size())
	Downloads.start()
	problem = await Downloads.queue_update(cave_id, choices[0])
	if problem != "":
		printerr("queue: ", problem)
		return 1
	return await _wait_for_downloads(host)


## Starts a game and closes it after a while; a person would close it from
## the game's own menu. The game gets Godot's dummy audio driver, so a test
## makes no sound (which only means something to a game made with Godot).
## With `plain` the game gets no argument of ours: for a game made with
## something else, which has to be kept quiet through the environment.
static func _launch(host: Node, cave_id: String, seconds: float, plain: bool = false) -> int:
	await Library.refresh_installed()
	var folder := ""
	for cave: Dictionary in Library.caves:
		if str(cave.get("id", "")) == cave_id:
			folder = GameEntry.for_cave(cave).install_folder()
	var watcher := func(method: String, _params: Dictionary) -> void:
		if method == "LaunchRunning":
			print("running: processes ", Processes.under(folder))
		elif method == "LaunchExited":
			print("exited")
	Butler.notified.connect(watcher)
	host.get_tree().create_timer(seconds).timeout.connect(func() -> void:
		for pid in Processes.under(folder):
			print("closing process %d after %d s" % [pid, int(seconds)])
			OS.kill(pid))
	var started := Time.get_ticks_msec()
	var problem: String = await GameOps.launch(cave_id, "" if plain else "--audio-driver Dummy")
	Butler.notified.disconnect(watcher)
	print("launch returned after %.1f s: %s" % [(Time.get_ticks_msec() - started) / 1000.0, problem if problem != "" else "no error"])
	await _caves()
	return 0 if problem == "" else 1


static func _uninstall(cave_id: String) -> int:
	await Library.refresh_installed()
	for cave: Dictionary in Library.caves:
		if str(cave.get("id", "")) == cave_id:
			var e := GameEntry.for_cave(cave)
			var folder := e.install_folder()
			var problem: String = await GameOps.uninstall(e)
			print("uninstall: ", problem if problem != "" else "done", "; folder still there: ", DirAccess.dir_exists_absolute(folder))
			return 0 if problem == "" else 1
	printerr("no such cave")
	return 1


## The app's own update: what this copy is, and whether butler takes its folder.
static func _self() -> int:
	await Library.refresh_installed()
	print("version: %s; a published build: %s; folder: %s" % [SelfUpdate.version(), SelfUpdate.is_a_build(), SelfUpdate.folder()])
	print("managed by butler: ", SelfUpdate.is_managed())
	var problem: String = await SelfUpdate.adopt()
	print("adopt: ", problem if problem != "" else "butler manages this folder")
	return 0


static func _steam(what: String, cave_id: String) -> int:
	await Library.refresh_installed()
	for cave: Dictionary in Library.caves:
		if str(cave.get("id", "")) != cave_id:
			continue
		var e := GameEntry.for_cave(cave)
		var problem := ""
		if what == "steam":
			# The cover is the shortcut's icon, so it has to be on disk first.
			var done := [false]
			Covers.fetch(e.cover_url(), func(_t: Texture2D) -> void: done[0] = true)
			while not done[0]:
				await Engine.get_main_loop().process_frame
			problem = Steam.add_game(e)
			if problem == "":
				print("artwork written: ", await Steam.apply_artwork(e))
		else:
			problem = Steam.remove_game(cave_id)
		print(what, ": ", problem if problem != "" else "done")
		print("Steam's shortcuts for this game: ", SteamShortcuts.find(Paths.run_game_script(), cave_id))
		print("recorded as in Steam: ", Steam.is_in_steam(cave_id))
		return 0 if problem == "" else 1
	printerr("no such cave")
	return 1


static func _wait_for_downloads(host: Node) -> int:
	var started := Time.get_ticks_msec()
	var last := ""
	var watched := ""
	while Downloads.pending_count() > 0:
		await host.get_tree().create_timer(1.0).timeout
		var active := Downloads.active()
		if active.is_empty():
			break
		watched = str(active.get("id", ""))
		var p := Downloads.progress_of(active)
		var line := "%s %s  %d %%  %s  %s  stage=%s" % [Downloads.reason_text(active), str(active.get("game", {}).get("title", "")),
			int(float(p.get("progress", 0)) * 100.0), Format.speed(float(p.get("bps", 0))), Format.time_left(float(p.get("eta", 0))), str(p.get("stage", ""))]
		if line != last:
			print(line)
			last = line
	await Downloads.refresh()
	print("queue empty after %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	for d: Dictionary in Downloads.failed():
		printerr("failed: ", Downloads.error_text(d))
		if str(d.get("id", "")) == watched:
			return 1
	await _caves()
	return 0


## Installs a game the way a search result would be installed: butler is
## told what the game is instead of reading its page, which a browser sign-in
## is refused (SPEC.md section 14). None of these requests reads the page.
static func _unlisted(host: Node, game_id: int, address: String, title: String) -> int:
	var game := {"id": game_id, "url": address, "title": title if title != "" else address.get_file(), "classification": "game", "type": "default"}
	var found: Dictionary = await Butler.request("Game.FindUploads", {"game": game})
	if Butler.failed(found):
		printerr("uploads: ", Butler.error_text(found))
		return 1
	var uploads: Array = found.result.get("uploads") if found.result.get("uploads") is Array else []
	print("uploads that fit: ", uploads.map(func(u: Dictionary) -> String: return GameOps.upload_name(u)))
	if uploads.is_empty():
		return 1
	var upload: Dictionary = uploads[0]
	# butler plans an upload it has saved; listing them all saves them.
	var all: Dictionary = await Butler.request("Fetch.GameUploads", {"gameId": game_id, "compatible": false, "fresh": true})
	if Butler.failed(all):
		printerr("all uploads: ", Butler.error_text(all))
		return 1
	var planned: Dictionary = await Butler.request("Install.PlanUpload", {"uploadId": int(upload.get("id", 0))})
	if Butler.failed(planned):
		printerr("plan: ", Butler.error_text(planned))
		return 1
	var usage: Variant = planned.result.get("info", {}).get("diskUsage")
	print("plan: needs %s free" % Format.size(float(usage.get("neededFreeSpace", 0)) if usage is Dictionary else 0.0))
	var locations: Array = await InstallLocations.for_games()
	print("install to: ", locations[0].get("path"))
	Downloads.start()
	var problem: String = await Downloads.queue_install(game, upload, str(locations[0].get("id", "")))
	if problem != "":
		printerr("queue: ", problem)
		return 1
	return await _wait_for_downloads(host)


# --- what a browser sign-in may read -----------------------------------------

## Asks itch.io, through the browser, for a key with the app's usual
## permissions plus the scopes named, and tries with it the requests that
## decide what the app can offer (SPEC.md section 14). The key is neither
## shown nor kept, and the login butler holds is not touched.
static func _key(host: Node, extra: PackedStringArray) -> int:
	var scope := OAuthLogin.SCOPES
	if not extra.is_empty():
		scope += " " + " ".join(extra)
	OS.set_environment("ITCH_ON_DECK_OAUTH_SCOPE", scope)
	var oauth := OAuthLogin.new()
	host.add_child(oauth)
	var problem := oauth.start()
	if problem != "":
		printerr(problem)
		return 1
	print("Asking itch.io for: ", scope)
	print("Its permission page is open in the browser. If it says the scope is invalid, that is the answer: stop this with Ctrl+C.")
	problem = await oauth.finished
	var key := oauth.key
	oauth.key = ""
	oauth.queue_free()
	if problem != "":
		printerr(problem)
		return 1
	await _key_checks(host, key)
	return 0


static func _key_checks(host: Node, key: String) -> void:
	var info := await _api_get(host, key, "/credentials/info")
	print("itch.io says this key may: ", info.body.get("scopes", info.body.get("errors", "?")))
	var collections := await _api_get(host, key, "/profile/collections")
	_tell("The account's collections", collections, "collections")
	var list: Variant = collections.body.get("collections")
	if list is Array and not list.is_empty():
		var first: Dictionary = list[0]
		print("    the first one is %s" % ("private" if bool(first.get("private", false)) else "public"))
		_tell("The games of that collection", await _api_get(host, key, "/collections/%d/collection-games" % int(first.get("id", 0))), "collection_games")
	_tell("A search of itch.io", await _api_get(host, key, "/search/games?query=moon"), "games")
	_tell("The page of a game the account does not own", await _api_get(host, key, "/games/%d" % SAMPLE_GAME), "")
	_tell("The uploads of that game", await _api_get(host, key, "/games/%d/uploads" % SAMPLE_GAME), "uploads")


## One GET on itch.io's API: { status, body }.
static func _api_get(host: Node, key: String, path: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	host.add_child(http)
	var out := {"status": 0, "body": {}}
	if http.request("https://api.itch.io" + path, PackedStringArray(["Authorization: Bearer " + key])) == OK:
		var done: Array = await http.request_completed
		out.status = int(done[1])
		var parsed: Variant = JSON.parse_string((done[3] as PackedByteArray).get_string_from_utf8())
		if parsed is Dictionary:
			out.body = parsed
	http.queue_free()
	return out


static func _tell(what: String, answer: Dictionary, list_name: String) -> void:
	if answer.status == 200:
		var items: Variant = answer.body.get(list_name)
		print("  %s: allowed%s" % [what, (", %d came back" % items.size()) if items is Array else ""])
	else:
		var errors: Variant = answer.body.get("errors")
		print("  %s: refused (%d) %s" % [what, answer.status, "; ".join(PackedStringArray(errors)) if errors is Array else ""])
