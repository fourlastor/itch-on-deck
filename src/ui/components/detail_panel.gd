extends PanelContainer
## Under the shelf: the focused game's title, states, short text and up to
## four facts (R7).

const ChipScene := preload("res://src/ui/components/chip.tscn")

@onready var _title: Label = %Title
@onready var _chips: HBoxContainer = %Chips
@onready var _text: Label = %ShortText
@onready var _facts: Array[Node] = [%Fact1, %Fact2, %Fact3, %Fact4]


func show_content(title: String, chips: Array[StringName], text: String, facts: Array) -> void:
	_title.text = title
	for child in _chips.get_children():
		child.queue_free()
	for kind in chips:
		var chip := ChipScene.instantiate()
		_chips.add_child(chip)
		chip.setup(kind)
	_chips.visible = not chips.is_empty()
	_text.text = text
	_text.visible = text != ""
	for i in _facts.size():
		var row := _facts[i]
		row.visible = i < facts.size()
		if row.visible:
			row.setup(facts[i][0], facts[i][1], i == facts.size() - 1)


func clear() -> void:
	var no_chips: Array[StringName] = []
	show_content("", no_chips, "", [])
