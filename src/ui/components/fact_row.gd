extends VBoxContainer
## One fact about a game: what it is, and its value.


func setup(key: String, value: String, last: bool = false) -> void:
	%Key.text = key
	%Value.text = value
	%Line.visible = not last
