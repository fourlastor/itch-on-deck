class_name Shots
extends RefCounted
## Development aid: shows one screen and saves a picture of it, so a change
## to the look can be checked without a controller in hand.
##
##     itch-on-deck -- --demo --screen=library:1 --shot=/tmp/owned.png
##     itch-on-deck -- --demo --pad=right,a,b,r1 --shot=/tmp/after.png
##
## --pad presses controller buttons one after the other, as a Deck would,
## once the screen is shown: a b x y l1 r1 view menu left right up down.
## "type:some text" types into the focused field.


static func take(host: Node, options: Dictionary) -> void:
	var tree := host.get_tree()
	await tree.create_timer(0.3).timeout
	var spec := str(options.get("screen", "")).split(":")
	var arg := spec[1] if spec.size() > 1 else ""
	match spec[0]:
		"library":
			Nav.top().show_tab(int(arg))
			if arg == "4":
				await Library.search("tide")
		"move":
			Nav.top().show_tab(1)
			await tree.create_timer(0.2).timeout
			Nav.top().get_node("%Shelf").move(int(arg))
		"collection":
			Nav.top().show_tab(2)
			await tree.create_timer(0.3).timeout
			Nav.top().get_node("%Shelf").activated.emit(0)
		"game", "install", "uninstall", "owned":
			var list_name := Library.INSTALLED if spec[0] in ["game", "uninstall"] else Library.OWNED
			if list_name == Library.OWNED:
				await Library.load_owned()
			var entry: GameEntry = Library.list(list_name)[int(arg) if arg != "" else 0]
			var screen := Nav.push("game", {"entry": entry, "from": "Installed"})
			if spec[0] == "install":
				await tree.create_timer(0.4).timeout
				screen.start_install()
			elif spec[0] == "uninstall":
				await tree.create_timer(0.4).timeout
				screen.ask_uninstall()
		"downloads", "settings", "sign_in", "setup", "running":
			var pushed := Nav.push(spec[0], {"demo": true})
			if arg != "" and pushed.has_method("show_section"):
				pushed.show_section(int(arg))
	if options.has("pad"):
		await tree.create_timer(0.5).timeout
		for name in str(options["pad"]).split(",", false):
			await _press(host, name.strip_edges())
	await tree.create_timer(float(options.get("wait", "0.9"))).timeout
	var focused := host.get_viewport().gui_get_focus_owner()
	var editing := (", editing" if focused.is_editing() else ", not editing") if focused is LineEdit else ""
	print("screen: ", Nav.top_name(), "; focus: ", focused, editing)
	var image := host.get_viewport().get_texture().get_image()
	var path := str(options["shot"])
	var err := image.save_png(path)
	print("shot ", path, " ", image.get_size(), " ", error_string(err))
	tree.quit()


const PAD := {
	"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y,
	"l1": JOY_BUTTON_LEFT_SHOULDER, "r1": JOY_BUTTON_RIGHT_SHOULDER,
	"view": JOY_BUTTON_BACK, "menu": JOY_BUTTON_START,
	"left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT,
	"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN,
}


static func _press(host: Node, button: String) -> void:
	var tree := host.get_tree()
	if button.begins_with("type:"):
		var field := host.get_viewport().gui_get_focus_owner() as LineEdit
		if field != null:
			field.insert_text_at_caret(button.trim_prefix("type:"))
			field.text_changed.emit(field.text)
		await tree.create_timer(0.2).timeout
		return
	if not PAD.has(button):
		printerr("no such button: ", button)
		return
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = PAD[button]
		event.pressed = pressed
		Input.parse_input_event(event)
		await tree.create_timer(0.08).timeout
	await tree.create_timer(0.35).timeout
