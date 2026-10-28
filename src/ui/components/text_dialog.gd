extends Control
## One line of text to type, over the screen. `closed` carries the text for
## the first answer, or null for the other and for B. Typing starts at once,
## with Steam's keyboard in Gaming Mode.

signal closed(text: Variant)

var _yes_text := ""
var _no_text := ""


func setup(title: String, body: String, text: String, placeholder: String, yes_text: String, no_text: String, problem: String) -> void:
	_yes_text = yes_text
	_no_text = no_text
	%Title.text = title
	%Body.text = body
	%Body.visible = body != ""
	%ProblemText.text = problem
	%Problem.visible = problem != ""
	%Field.text = text
	%Field.placeholder_text = placeholder
	%Field.caret_column = text.length()
	%Yes.text = yes_text
	%No.text = no_text
	%Yes.pressed.connect(_answer)
	%No.pressed.connect(func() -> void: closed.emit(null))
	%Field.text_submitted.connect(func(_t: String) -> void: _answer())
	%Field.editing_toggled.connect(_on_editing_toggled)
	for control: Control in [%Field, %Yes, %No]:
		control.focus_entered.connect(_show_hints)
	_start_typing.call_deferred()


func _start_typing() -> void:
	%Field.grab_focus()
	%Field.edit()


func _on_editing_toggled(on: bool) -> void:
	if on:
		Keyboard.show()
	_show_hints()


func _answer() -> void:
	closed.emit(%Field.text)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if %Field.is_editing():
			# unedit() does not send editing_toggled, so the hints are redone here.
			%Field.unedit()
			_show_hints()
		else:
			closed.emit(null)
	# A text field takes Enter by itself; a controller's A has to be handed to
	# it. The first A starts typing, and A while typing gives the first answer.
	elif event is InputEventJoypadButton and event.is_action_pressed(&"ui_accept") and %Field.has_focus():
		get_viewport().set_input_as_handled()
		if %Field.is_editing():
			_answer()
		else:
			%Field.edit()


func _show_hints() -> void:
	var a := "Choose"
	var b := _no_text
	if %Field.has_focus():
		a = _yes_text if %Field.is_editing() else "Type"
		if %Field.is_editing():
			b = "Stop typing"
	$Center/Panel/Column/Hints/Select.setup(Glyph.Kind.A, a)
	$Center/Panel/Column/Hints/Close.setup(Glyph.Kind.B, b)
