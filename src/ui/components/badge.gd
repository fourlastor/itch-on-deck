extends PanelContainer
## A mark on a cover: installed, update known, not installable here,
## not owned, pinned, or the word "Draft".

const ICONS := {
	&"installed": preload("res://assets/icons/check.svg"),
	&"update": preload("res://assets/icons/update.svg"),
	&"blocked": preload("res://assets/icons/blocked.svg"),
	&"not_owned": preload("res://assets/icons/lock.svg"),
	&"pinned": preload("res://assets/icons/pin.svg"),
}
const LIGHT := Color("f4efe8")
const BLUE_INK := Color("10202c")


func setup(kind: StringName, large: bool = false) -> void:
	var icon: TextureRect = $Icon
	var text: Label = $Text
	var side := 38.0 if large else 32.0
	if kind == &"draft":
		theme_type_variation = &"PanelBadgeText"
		icon.visible = false
		text.visible = true
		custom_minimum_size = Vector2(0, side)
		return
	text.visible = false
	icon.visible = true
	icon.texture = ICONS[kind]
	icon.custom_minimum_size = Vector2(side - 14.0, side - 14.0)
	custom_minimum_size = Vector2(side, side)
	icon.modulate = LIGHT
	match kind:
		&"update":
			theme_type_variation = &"PanelBadgeBlue"
			icon.modulate = BLUE_INK
		&"blocked", &"not_owned":
			theme_type_variation = &"PanelBadgeGrey"
		_:
			theme_type_variation = &"PanelBadgeDark"
