@tool
class_name ActionRow
extends Button
## One thing that can be done with a game or a setting. The row says what it
## does on the left and the present state on the right (R26).

const DARK := Color("1a1816")
const DARK_SOFT := Color("3b1d18")

@export var title := "Play":
	set(value):
		title = value
		_apply()
@export var state := "":
	set(value):
		state = value
		_apply()
@export var symbol: Texture2D:
	set(value):
		symbol = value
		_apply()
@export var symbol_tint := Color("f4efe8"):
	set(value):
		symbol_tint = value
		_apply()


func _ready() -> void:
	focus_entered.connect(_apply)
	focus_exited.connect(_apply)
	_apply()


func set_row(new_title: String, new_state: String) -> void:
	title = new_title
	state = new_state


func _apply() -> void:
	if not is_node_ready():
		return
	var focused := has_focus()
	%Title.text = title
	%State.text = state
	if focused:
		%Title.theme_type_variation = &"LabelRowTitleFocus"
		%State.theme_type_variation = &"LabelRowStateFocus"
	else:
		%Title.theme_type_variation = &"LabelRowTitleOff" if disabled else &"LabelRowTitle"
		%State.theme_type_variation = &"LabelRowState"
	%Symbol.visible = symbol != null
	%Symbol.texture = symbol
	%Symbol.modulate = DARK if focused else symbol_tint
