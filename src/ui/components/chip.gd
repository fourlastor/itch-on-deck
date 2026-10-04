extends PanelContainer
## A state of a game, in words: Installed, Update known, Draft, ...

const KINDS := {
	&"installed": ["Installed", &"PanelChip", &"LabelChip", "check"],
	&"update": ["Update known", &"PanelChipBlue", &"LabelChipBlue", "update"],
	&"draft": ["Draft", &"PanelChipOutline", &"LabelChipStrong", ""],
	&"not_installed": ["Not installed", &"PanelChipOutlineFaint", &"LabelChipSoft", ""],
	&"not_installable": ["Not installable here", &"PanelChipOutline", &"LabelChipStrong", "blocked"],
	&"not_owned": ["Not owned", &"PanelChipOutline", &"LabelChipStrong", "lock"],
	&"pinned": ["Pinned", &"PanelChip", &"LabelChip", "pin"],
	&"in_steam": ["In Steam", &"PanelChip", &"LabelChip", "steam_in"],
}
const LIGHT := Color("f4efe8")
const BLUE_INK := Color("10202c")


func setup(kind: StringName) -> void:
	var spec: Array = KINDS[kind]
	%Text.text = spec[0]
	theme_type_variation = spec[1]
	%Text.theme_type_variation = spec[2]
	var icon: TextureRect = %Icon
	icon.visible = spec[3] != ""
	if icon.visible:
		icon.texture = load("res://assets/icons/%s.svg" % spec[3])
		icon.modulate = BLUE_INK if kind == &"update" else LIGHT
