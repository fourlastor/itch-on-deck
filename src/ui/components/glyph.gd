@tool
class_name Glyph
extends PanelContainer
## A controller button, as the hints show it.

enum Kind { A, B, X, Y, L1, R1, VIEW, MENU, DPAD }

const LETTERS := {Kind.A: "A", Kind.B: "B", Kind.X: "X", Kind.Y: "Y", Kind.L1: "L1", Kind.R1: "R1"}
const ICONS := {
	Kind.VIEW: preload("res://assets/icons/view.svg"),
	Kind.MENU: preload("res://assets/icons/menu.svg"),
	Kind.DPAD: preload("res://assets/icons/dpad.svg"),
}
const DARK := Color("1a1816")
const LIGHT := Color("f4efe8")

@export var kind: Kind = Kind.A:
	set(value):
		kind = value
		if is_node_ready():
			_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	var letter: Label = $Letter
	var icon: TextureRect = $Icon
	letter.visible = LETTERS.has(kind)
	icon.visible = ICONS.has(kind)
	if letter.visible:
		letter.text = LETTERS[kind]
	if icon.visible:
		icon.texture = ICONS[kind]
	match kind:
		Kind.L1, Kind.R1:
			theme_type_variation = &"PanelBumper"
			letter.theme_type_variation = &"LabelBumper"
			custom_minimum_size = Vector2(0, 26)
		Kind.DPAD:
			theme_type_variation = &""
			icon.custom_minimum_size = Vector2(28, 28)
			icon.modulate = LIGHT
			custom_minimum_size = Vector2(28, 28)
		_:
			theme_type_variation = &"PanelGlyph"
			letter.theme_type_variation = &"LabelGlyph"
			icon.custom_minimum_size = Vector2(16, 16)
			icon.modulate = DARK
			custom_minimum_size = Vector2(28, 28)
