extends Control
## A short list to pick from, over the screen: which upload, which thing to
## launch. `closed` carries the index, or -1 for B.

signal closed(index: int)


func setup(title: String, body: String, options: Array) -> void:
	%Title.text = title
	%Body.text = body
	%Body.visible = body != ""
	var first: Button = null
	for i in options.size():
		var button := Button.new()
		button.text = str(options[i])
		button.custom_minimum_size = Vector2(0, 56)
		button.theme_type_variation = &"ButtonDialog"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void: closed.emit(i))
		%Options.add_child(button)
		if first == null:
			first = button
	if first != null:
		first.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit(-1)
