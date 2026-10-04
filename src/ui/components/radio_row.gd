class_name RadioRow
extends Button
## One choice of a short list (which upload, which install location). The
## dot shows the chosen one; the focus is the usual coral fill.

const DARK := Color("1a1816")
const LIGHT := Color("f4efe8")
const FAINT := Color("8f877c")

var chosen := false:
	set(value):
		chosen = value
		_apply()
var value: Variant = null


func _ready() -> void:
	focus_entered.connect(_apply)
	focus_exited.connect(_apply)
	_apply()


func setup(title: String, state: String, tag: String = "") -> void:
	%Title.text = title
	%State.text = state
	%Tag.visible = tag != ""
	%TagText.text = tag


func _apply() -> void:
	if not is_node_ready():
		return
	var focused := has_focus()
	%Title.theme_type_variation = &"LabelOptionFocus" if focused else &"LabelOption"
	%State.theme_type_variation = &"LabelRowStateFocus" if focused else &"LabelRowState"
	var ink := DARK if focused else (LIGHT if chosen else FAINT)
	%Ring.self_modulate = ink
	%Dot.visible = chosen
	%Dot.self_modulate = DARK if focused else LIGHT
