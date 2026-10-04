extends Control
## The root of the app. With a command after "--" it does that one job with
## no window and ends (see Cli). Otherwise it brings the app up: butler
## first (fetched on the first launch), then the saved login, then the lists.
##
## Development options, also after "--":
##     --demo                 invented games instead of the butler daemon
##     --shot=<file.png>      save a picture of the window and quit
##     --screen=<name>        which screen to show for the picture
##     --art=<folder>         save the app's Steam library images there and quit


func _ready() -> void:
	Nav.host = %Screens
	Nav.overlay = %Overlay
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and Cli.is_command(args[0]):
		var code: int = await Cli.run(args, self)
		get_tree().quit(code)
		return
	var options := _options(args)
	if options.has("demo"):
		Config.use_scratch()
		Butler.demo = DemoBackend.new()
	Session.changed.connect(_on_session_changed)
	Prompts.register()
	if Butler.demo == null:
		SelfUpdate.mark_window_open()
	await _start()
	if options.has("art"):
		await SteamArt.save_all(self, str(options["art"]))
		get_tree().quit()
	elif options.has("shot"):
		await Shots.take(self, options)


func _start() -> void:
	if Butler.demo == null:
		if not ButlerInstall.is_installed():
			var setup := Nav.reset("setup")
			await setup.finished
		if not Butler.start(Paths.butler_bin(ButlerInstall.VERSION)):
			Nav.reset("setup", {"error": "butler did not start."})
			return
	if await Session.resume():
		await _enter()
	else:
		Nav.reset("sign_in")


## Signed in: get the machine-side state, then show the lists.
func _enter() -> void:
	await InstallLocations.ensure_default()
	await Bandwidth.apply()
	await Library.refresh_installed()
	Nav.reset("library")
	Downloads.start()
	_load_in_background()


func _load_in_background() -> void:
	# The projects come first: they are what marks a game as a draft.
	await Library.load_projects()
	await Library.load_owned()
	await Library.check_updates()
	if Butler.demo == null and SelfUpdate.enabled() and SelfUpdate.is_a_build():
		await SelfUpdate.look()
	if Butler.demo == null:
		Schedule.keep_current()
		await Steam.restore_artwork(Nav)
		if Downloads.pending_count() == 0:
			await Downloads.sweep()


func _on_session_changed() -> void:
	if Session.is_signed_in():
		if Nav.top_name() == "sign_in":
			await _enter()
	elif Nav.top_name() != "sign_in":
		Downloads.stop()
		Library.clear()
		Nav.reset("sign_in")


func _exit_tree() -> void:
	if Butler.demo == null:
		SelfUpdate.mark_window_closed()


func _options(args: PackedStringArray) -> Dictionary:
	var out := {}
	for arg in args:
		if not arg.begins_with("--"):
			continue
		var body := arg.substr(2)
		var eq := body.find("=")
		if eq == -1:
			out[body] = true
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out
