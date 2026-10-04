class_name Cli
extends RefCounted
## Running the app with no window:
##
##     itch-on-deck --headless -- update     the scheduled update run (SPEC.md section 8)
##     itch-on-deck --headless -- setup      fetch butler, then stop
##     itch-on-deck --headless -- rpc Fetch.Caves '{"profileId": "$profile"}'
##     itch-on-deck --headless -- check      load every script and scene
##
## `rpc` is a development aid: it sends one request to the daemon and prints
## the answer. "$profile" stands for the signed-in profile.

const COMMANDS: Array[String] = ["setup", "rpc", "update", "login-saved", "login-browser", "check", "probe", "licenses", "schedule"]


static func is_command(arg: String) -> bool:
	return arg in COMMANDS


static func run(args: PackedStringArray, host: Node) -> int:
	match args[0]:
		"setup":
			return 0 if await _ensure_butler(host) else 1
		"rpc":
			return await _rpc(args, host)
		"update":
			return await Updater.new().run(host)
		"login-saved":
			return await _login_saved(host)
		"check":
			return _check()
		"probe":
			return await Probe.run(args, host)
		"licenses":
			return _licenses(args)
		"schedule":
			return _schedule(args)
		"login-browser":
			return await _login_browser(host)
	return 2


## Loads every script, scene and resource under src/ and names the ones
## that do not load: a quick test after a change.
static func _check() -> int:
	var files := _walk("res://src")
	var failures := 0
	for path in files:
		if not (path.ends_with(".gd") or path.ends_with(".tscn") or path.ends_with(".tres")):
			continue
		var resource := load(path)
		if resource == null:
			printerr("does not load: ", path)
			failures += 1
		elif resource is PackedScene:
			var node := (resource as PackedScene).instantiate()
			if node == null:
				printerr("cannot be instantiated: ", path)
				failures += 1
			else:
				node.free()
	print("checked %d files, %d failed" % [files.size(), failures])
	return 1 if failures > 0 else 0


## Sets the update schedule as the Settings screen does: off, 15min, 1h,
## 6h or daily. With no value it only reports.
static func _schedule(args: PackedStringArray) -> int:
	if args.size() > 1:
		if not (args[1] in Config.SCHEDULES):
			printerr("schedule: one of ", Config.SCHEDULES)
			return 2
		Config.set_value("schedule", args[1])
		var problem := Schedule.apply()
		if problem != "":
			printerr(problem)
			return 1
	print("schedule: %s; timer on: %s; next run: %s" % [Config.schedule(), Schedule.is_on(), Format.moment(Schedule.next_run())])
	print("runs as: ", Schedule.command())
	return 0


## Writes the notices the Godot engine asks to have shipped with a build.
static func _licenses(args: PackedStringArray) -> int:
	if args.size() < 2:
		printerr("usage: licenses <file>")
		return 2
	var text := "itch on Deck is made with the Godot Engine.\n\n" + Engine.get_license_text() + "\n\n"
	for part: Dictionary in Engine.get_copyright_info():
		text += "%s\n" % str(part.get("name", ""))
		for piece: Dictionary in part.get("parts", []):
			text += "    %s: %s\n" % [", ".join(piece.get("copyright", [])), str(piece.get("license", ""))]
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		printerr("cannot write ", args[1])
		return 1
	file.store_string(text)
	file.close()
	return 0


static func _walk(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for name in DirAccess.get_directories_at(dir):
		out.append_array(_walk(dir.path_join(name)))
	for name in DirAccess.get_files_at(dir):
		out.append(dir.path_join(name))
	return out


static func _ensure_butler(host: Node) -> bool:
	if ButlerInstall.is_installed():
		return true
	var installer := ButlerInstall.new()
	host.add_child(installer)
	installer.progress.connect(func(text: String, fraction: float) -> void:
		print("%s: %d %%" % [text, int(fraction * 100.0)]))
	var ok: bool = await installer.install()
	if not ok:
		printerr(installer.error)
	installer.queue_free()
	return ok


## Signs in with the key `butler login` saved, as the sign-in screen's
## "Use a saved key" does. The key is never printed.
static func _login_saved(host: Node) -> int:
	if not await _ensure_butler(host):
		return 1
	if not Butler.start(Paths.butler_bin(ButlerInstall.VERSION)):
		printerr("butler did not start")
		return 1
	var problem: String = await Session.login_with_saved_key()
	if problem != "":
		printerr(problem)
		Butler.stop()
		return 1
	print("Signed in as %s (profile %d)." % [Session.user_name(), Session.profile_id()])
	Butler.stop()
	return 0


## Signs in through the browser, as the sign-in screen's first button does.
static func _login_browser(host: Node) -> int:
	if not await _ensure_butler(host):
		return 1
	if not Butler.start(Paths.butler_bin(ButlerInstall.VERSION)):
		printerr("butler did not start")
		return 1
	var oauth := OAuthLogin.new()
	host.add_child(oauth)
	var problem := oauth.start()
	if problem != "":
		printerr(problem)
		Butler.stop()
		return 1
	print("itch.io is open in the browser. Waiting for the answer.")
	problem = await oauth.finished
	if problem == "":
		var info: Dictionary = await OAuthLogin.key_info(host, oauth.key)
		print("itch.io says this key may: ", info.scopes, " ", info.error)
		problem = await Session.login_with_api_key(oauth.key)
	oauth.key = ""
	if problem != "":
		printerr(problem)
		Butler.stop()
		return 1
	print("Signed in as %s (profile %d)." % [Session.user_name(), Session.profile_id()])
	Butler.stop()
	return 0


static func _rpc(args: PackedStringArray, host: Node) -> int:
	if args.size() < 2:
		printerr("usage: rpc <Method> [json params]")
		return 2
	if not await _ensure_butler(host):
		return 1
	if not Butler.start(Paths.butler_bin(ButlerInstall.VERSION)):
		printerr("butler did not start")
		return 1
	var params: Dictionary = {}
	if args.size() > 2:
		var parsed: Variant = JSON.parse_string(args[2])
		if not (parsed is Dictionary):
			printerr("the params are not a JSON object")
			return 2
		params = parsed
	var profile := Config.profile_id()
	if profile > 0:
		await Butler.request("Profile.UseSavedLogin", {"profileId": profile})
	for key: String in params:
		if params[key] is String and params[key] == "$profile":
			params[key] = profile
	var printer := func(method: String, p: Dictionary) -> void:
		print("~ %s %s" % [method, JSON.stringify(p)])
	Butler.notified.connect(printer)
	var res: Dictionary = await Butler.request(args[1], params)
	Butler.notified.disconnect(printer)
	print(JSON.stringify(res, "  "))
	Butler.stop()
	return 1 if Butler.failed(res) else 0
