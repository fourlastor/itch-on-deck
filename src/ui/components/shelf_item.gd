extends Control
## One cover on the shelf. `grow` goes from 0 (one of the row) to 1 (the
## focused one); the covers stand on one line, so growing moves the top up.

signal clicked

const BIG := Vector2(440, 349)
const SMALL := Vector2(262, 208)
const LABEL_GAP := 12.0
const LABEL_HEIGHT := 24.0

var entry: GameEntry
var grow := 0.0:
	set(value):
		grow = value
		_place()

@onready var _cover: Control = $Cover
@onready var _title: Label = $Title
@onready var _ring: Panel = $Ring


func _ready() -> void:
	_place()


func show_entry(e: GameEntry, show_installed: bool, focused: bool) -> void:
	entry = e
	_title.text = e.title()
	if e.is_collection():
		_title.text = "%s · %d" % [e.title(), int(e.collection.get("gamesCount", 0))]
	var blocked := not e.is_collection() and not e.is_installed() and (not e.is_installable_here() or not e.owned)
	_title.theme_type_variation = &"LabelSmallFaint" if blocked else &"LabelSmallMuted"
	_cover.show_entry(e, show_installed, focused)


func set_ring(on: bool) -> void:
	_ring.visible = on


func _place() -> void:
	if not is_node_ready():
		return
	var cover_size := SMALL.lerp(BIG, grow)
	size = Vector2(cover_size.x, BIG.y + LABEL_GAP + LABEL_HEIGHT)
	_cover.position = Vector2(0, BIG.y - cover_size.y)
	_cover.size = cover_size
	_ring.position = _cover.position
	_ring.size = cover_size
	_title.position = Vector2(0, BIG.y + LABEL_GAP)
	_title.size = Vector2(cover_size.x, LABEL_HEIGHT)
	_title.modulate.a = 1.0 - grow


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		clicked.emit()
