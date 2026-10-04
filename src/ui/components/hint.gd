extends HBoxContainer
## One entry of the hint bar: a button and what it does.


func setup(kind: Glyph.Kind, text: String) -> void:
	$Glyph.kind = kind
	$Text.text = text
