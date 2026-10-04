extends Node
## Which screen is shown. Screens are scenes; they are stacked, so going
## back returns to the previous one as it was left.
##
## A screen may have:
##     func open(args: Dictionary)   called once, after it entered the tree
##     func resume()                 called when the screen above it closed
##     func first_focus() -> Control what to focus when it is shown
##     func back() -> bool           handles B itself; true when it did

const SCREENS := {
	"setup": "res://src/ui/screens/setup.tscn",
	"sign_in": "res://src/ui/screens/sign_in.tscn",
	"library": "res://src/ui/screens/library.tscn",
	"game": "res://src/ui/screens/game.tscn",
	"install": "res://src/ui/screens/install.tscn",
	"downloads": "res://src/ui/screens/downloads.tscn",
	"settings": "res://src/ui/screens/settings.tscn",
	"running": "res://src/ui/screens/running.tscn",
}
const DialogScene := "res://src/ui/components/confirm_dialog.tscn"
const ChoiceScene := "res://src/ui/components/choice_dialog.tscn"

var host: Control
var overlay: Control

var _stack: Array[Control] = []
var _dialogs: Array[Control] = []


func top() -> Control:
	return _stack.back() if not _stack.is_empty() else null


func top_name() -> String:
	var screen := top()
	return str(screen.get_meta("screen_name", "")) if screen != null else ""


## Replaces everything with one screen.
func reset(screen_name: String, args: Dictionary = {}) -> Control:
	for screen in _stack:
		screen.queue_free()
	_stack.clear()
	return push(screen_name, args)


func push(screen_name: String, args: Dictionary = {}) -> Control:
	var below := top()
	if below != null:
		below.set_meta("last_focus", get_viewport().gui_get_focus_owner())
		below.visible = false
		below.process_mode = Node.PROCESS_MODE_DISABLED
	var scene: PackedScene = load(SCREENS[screen_name])
	var screen: Control = scene.instantiate()
	screen.set_meta("screen_name", screen_name)
	host.add_child(screen)
	_stack.append(screen)
	if screen.has_method("open"):
		screen.open(args)
	_focus(screen)
	return screen


func pop() -> void:
	if _stack.size() <= 1:
		return
	var screen: Control = _stack.pop_back()
	screen.queue_free()
	var below := top()
	below.visible = true
	below.process_mode = Node.PROCESS_MODE_INHERIT
	if below.has_method("resume"):
		below.resume()
	var last: Variant = below.get_meta("last_focus", null)
	if is_instance_valid(last) and last is Control and last.is_visible_in_tree():
		last.grab_focus()
	else:
		_focus(below)


## Asks a yes-or-no question over the current screen. `safe_default` puts
## the focus on the answer that changes nothing.
func confirm(title: String, body: String, yes_text: String, no_text: String, safe_default: bool = true) -> bool:
	var dialog: Control = load(DialogScene).instantiate()
	return await _run_dialog(dialog, func() -> void: dialog.setup(title, body, yes_text, no_text, safe_default))


## Shows a list to pick from; returns the index, or -1 when closed.
func choose(title: String, body: String, options: Array) -> int:
	var dialog: Control = load(ChoiceScene).instantiate()
	return await _run_dialog(dialog, func() -> void: dialog.setup(title, body, options))


func dialog_open() -> bool:
	return not _dialogs.is_empty()


func _run_dialog(dialog: Control, setup: Callable) -> Variant:
	var previous := get_viewport().gui_get_focus_owner()
	_dialogs.append(dialog)
	_confine_focus()
	overlay.add_child(dialog)
	setup.call()
	var answer: Variant = await dialog.closed
	dialog.queue_free()
	_dialogs.erase(dialog)
	_confine_focus()
	if is_instance_valid(previous) and previous.is_visible_in_tree():
		previous.grab_focus()
	elif _dialogs.is_empty() and top() != null:
		# What had the focus is gone (a list was rebuilt meanwhile).
		_focus(top())
	return answer


## Only the topmost dialog can hold the focus. Without this the D-pad walks
## out of a dialog onto the screen under it, and A then presses what is there.
func _confine_focus() -> void:
	host.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED if _dialogs.is_empty() else Control.FOCUS_BEHAVIOR_DISABLED
	for i in _dialogs.size():
		_dialogs[i].focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED if i == _dialogs.size() - 1 else Control.FOCUS_BEHAVIOR_DISABLED


func _focus(screen: Control) -> void:
	if screen.has_method("first_focus"):
		var target: Control = screen.first_focus()
		if target != null:
			target.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if dialog_open() or _stack.is_empty():
		return
	var current := top_name()
	if event.is_action_pressed(&"ui_cancel"):
		var screen := top()
		if screen.has_method("back") and screen.back():
			get_viewport().set_input_as_handled()
		elif _stack.size() > 1:
			get_viewport().set_input_as_handled()
			pop()
	elif not Session.is_signed_in() or current in ["setup", "sign_in", "running"]:
		return
	elif event.is_action_pressed(&"downloads") and current != "downloads":
		get_viewport().set_input_as_handled()
		push("downloads")
	elif event.is_action_pressed(&"settings") and current != "settings":
		get_viewport().set_input_as_handled()
		push("settings")
