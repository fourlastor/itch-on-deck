@tool
extends PanelContainer
## A rounded button of the top bar: the controller button that opens the
## thing, its name and a count. It is clicked with a mouse; a controller uses
## the button it shows.

signal pressed

@export var text := "Downloads":
	set(value):
		text = value
		if is_node_ready():
			_apply()
@export var glyph: Glyph.Kind = Glyph.Kind.VIEW:
	set(value):
		glyph = value
		if is_node_ready():
			_apply()
@export var count := 0:
	set(value):
		count = value
		if is_node_ready():
			_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	%Text.text = text
	%Glyph.kind = glyph
	%Count.visible = count > 0
	%Value.text = str(count)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit()
