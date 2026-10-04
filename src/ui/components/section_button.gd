@tool
extends Button
## One section of the settings: its name, and its present value under it,
## so the list of sections also says how everything is set (R26).

@export var title := "Updates":
	set(value):
		title = value
		_apply()
@export var value := "":
	set(new_value):
		value = new_value
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	%Title.text = title
	%Value.text = value
