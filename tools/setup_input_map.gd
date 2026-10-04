extends SceneTree
## Writes the app's own input actions into project.godot. Run it after
## changing the list below:
##
##     godot --headless --path . -s tools/setup_input_map.gd
##
## Moving the focus, A (ui_accept) and B (ui_cancel) are Godot's built-in
## actions and are not touched here.


func _init() -> void:
	_action("list_prev", [_joy(JOY_BUTTON_LEFT_SHOULDER), _key(KEY_Q), _key(KEY_PAGEUP)])
	_action("list_next", [_joy(JOY_BUTTON_RIGHT_SHOULDER), _key(KEY_E), _key(KEY_PAGEDOWN)])
	_action("filter", [_joy(JOY_BUTTON_X), _key(KEY_F)])
	_action("search", [_joy(JOY_BUTTON_Y), _key(KEY_SLASH)])
	_action("downloads", [_joy(JOY_BUTTON_BACK), _key(KEY_D)])
	_action("settings", [_joy(JOY_BUTTON_START), _key(KEY_S)])
	var err := ProjectSettings.save()
	print("input map saved: ", error_string(err))
	quit()


func _action(action: String, events: Array) -> void:
	ProjectSettings.set_setting("input/" + action, {"deadzone": 0.5, "events": events})


func _joy(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	return event


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.device = -1
	event.physical_keycode = code
	return event
