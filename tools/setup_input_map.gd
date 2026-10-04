extends SceneTree
## Writes the app's own input actions into project.godot. Run it after
## changing the list below:
##
##     godot --headless --path . -s tools/setup_input_map.gd
##
## Moving the focus is Godot's built-in ui_left, ui_right, ui_up and ui_down,
## which come with the D-pad and the left stick. Its ui_accept and ui_cancel
## come with keys only, so A and B are added to them here; and Y is taken off
## ui_select, because Y opens the search.


func _init() -> void:
	_action("ui_accept", [_key(KEY_ENTER, false), _key(KEY_KP_ENTER, false), _key(KEY_SPACE, false), _joy(JOY_BUTTON_A)])
	_action("ui_cancel", [_key(KEY_ESCAPE, false), _joy(JOY_BUTTON_B)])
	_action("ui_select", [_key(KEY_SPACE, false)])
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


## `physical` binds the place of the key on the keyboard, whatever its letter
## is in the user's layout; the keys of the built-in actions are bound by name.
func _key(code: Key, physical: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.device = -1
	if physical:
		event.physical_keycode = code
	else:
		event.keycode = code
	return event
