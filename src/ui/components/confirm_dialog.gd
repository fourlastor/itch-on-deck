extends Control
## A question over the screen, with two answers. `closed` carries true for
## the first answer ("yes") and false for the other, or for B.

signal closed(yes: bool)


func setup(title: String, body: String, yes_text: String, no_text: String, safe_default: bool) -> void:
	%Title.text = title
	%Body.text = body
	%Yes.text = yes_text
	%No.text = no_text
	%Yes.pressed.connect(func() -> void: closed.emit(true))
	%No.pressed.connect(func() -> void: closed.emit(false))
	$Center/Panel/Column/Hints/Select.setup(Glyph.Kind.A, "Choose")
	$Center/Panel/Column/Hints/Close.setup(Glyph.Kind.B, "Close")
	var first: Button = %No if safe_default else %Yes
	first.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit(false)
