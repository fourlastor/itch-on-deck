class_name HintBar
extends PanelContainer
## The bar at the bottom of every screen: what the buttons do here, and one
## line of state on the right.

const HintScene := preload("res://src/ui/components/hint.tscn")

@onready var _hints: HBoxContainer = %Hints
@onready var _right: Label = %Right


## `hints` is a list of [Glyph.Kind, text] pairs.
func set_hints(hints: Array, right_text: String = "") -> void:
	for child in _hints.get_children():
		child.queue_free()
	for pair: Array in hints:
		var hint := HintScene.instantiate()
		_hints.add_child(hint)
		hint.setup(pair[0], pair[1])
	_right.text = right_text


func set_right(text: String) -> void:
	_right.text = text
