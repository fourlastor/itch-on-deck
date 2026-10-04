extends VBoxContainer
## One past update run: when it ran and what it did (R24).


func setup(when: String, what: String, last: bool) -> void:
	%When.text = when
	%What.text = what
	%Line.visible = not last
