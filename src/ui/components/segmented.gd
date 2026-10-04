class_name Segmented
extends PanelContainer
## A choice between a few values, shown all at once (the update interval).
## It takes the focus as a whole; left and right change the value. The
## choices are the Button children of its row, set up in the scene.

signal value_changed(index: int)

var index := 0

@onready var _row: HBoxContainer = $Row


func _ready() -> void:
	focus_entered.connect(_apply)
	focus_exited.connect(_apply)
	for i in _row.get_child_count():
		var button: Button = _row.get_child(i)
		button.pressed.connect(_on_segment_pressed.bind(i))
	_apply()


func select(new_index: int) -> void:
	index = clampi(new_index, 0, _row.get_child_count() - 1)
	_apply()


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left"):
		accept_event()
		_step(-1)
	elif event.is_action_pressed(&"ui_right"):
		accept_event()
		_step(1)


func _step(by: int) -> void:
	var target := clampi(index + by, 0, _row.get_child_count() - 1)
	if target != index:
		index = target
		_apply()
		value_changed.emit(index)


func _on_segment_pressed(i: int) -> void:
	grab_focus()
	if i != index:
		index = i
		value_changed.emit(index)
	_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	for i in _row.get_child_count():
		var button: Button = _row.get_child(i)
		button.set_pressed_no_signal(i == index)
		button.theme_type_variation = &"SegmentButtonActive" if (i == index and has_focus()) else &"SegmentButton"
