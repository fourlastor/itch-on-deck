class_name Shelf
extends Control
## One row of covers. The focused one is large and stays in place; left and
## right bring the others to it. Only the covers near the focus exist as
## nodes, so a list of a thousand games costs what a list of ten does.

signal focus_moved(index: int)
signal activated(index: int)

const ItemScene := preload("res://src/ui/components/shelf_item.tscn")
const BIG := Vector2(440, 349)
const SMALL := Vector2(262, 208)
## Where the focused cover stands, from the left edge of the screen.
const ANCHOR_X := 94.0
const GAP := 24.0
const BEFORE := 2
const AFTER := 5
const MOVE_TIME := 0.14
const REPEAT_DELAY := 0.4
const REPEAT_EVERY := 0.1

var entries: Array = []
var index := 0
## False on the Installed list, where an "installed" mark says nothing.
var show_installed := true

var _items: Dictionary = {}
var _tween: Tween
var _held := 0
var _hold_time := 0.0
var _stick := StickStep.new()

@onready var _holder: Control = $Items
@onready var _empty: Label = $Empty


func _ready() -> void:
	focus_entered.connect(_update_rings)
	focus_exited.connect(_update_rings)
	focus_exited.connect(_stick.reset)


## Shows a list. With `keep_place`, the focus stays where it was.
func set_entries(list: Array, keep_place: bool = false) -> void:
	var keep_id := 0
	if keep_place and index < entries.size():
		keep_id = entries[index].get_instance_id()
	entries = list
	var place := 0
	if keep_place:
		place = mini(index, maxi(entries.size() - 1, 0))
		for i in entries.size():
			if entries[i].get_instance_id() == keep_id:
				place = i
				break
	index = place
	for item: Control in _items.values():
		item.queue_free()
	_items.clear()
	_empty.visible = entries.is_empty()
	_layout(false)
	focus_moved.emit(index)


## Redraws the marks of the visible covers, after a state changed.
func refresh() -> void:
	for i: int in _items:
		_items[i].show_entry(entries[i], show_installed, i == index)


func set_empty_text(text: String) -> void:
	_empty.text = text


func current() -> GameEntry:
	if index >= 0 and index < entries.size():
		return entries[index]
	return null


func move(step: int) -> void:
	if entries.is_empty():
		return
	var target := clampi(index + step, 0, entries.size() - 1)
	if target == index:
		return
	index = target
	_layout(true)
	focus_moved.emit(index)


func _process(delta: float) -> void:
	if _held == 0:
		return
	var action := &"ui_left" if _held < 0 else &"ui_right"
	if not has_focus() or not Input.is_action_pressed(action):
		_held = 0
		return
	_hold_time -= delta
	if _hold_time <= 0.0:
		_hold_time = REPEAT_EVERY
		move(_held)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		# One push of the stick is one step; held, it repeats like the D-pad.
		if event.axis == JOY_AXIS_LEFT_X:
			accept_event()
			var pushed := _stick.step(event, JOY_AXIS_LEFT_X)
			if pushed != 0:
				_press(pushed)
	elif event.is_action_pressed(&"ui_left"):
		_press(-1)
	elif event.is_action_pressed(&"ui_right"):
		_press(1)
	elif event.is_action_pressed(&"ui_accept"):
		if not entries.is_empty():
			accept_event()
			activated.emit(index)
	elif event is InputEventKey and event.is_echo() and (event.is_action(&"ui_left") or event.is_action(&"ui_right")):
		# The shelf repeats by itself; a keyboard's own repeat would double it.
		accept_event()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			accept_event()
			move(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			accept_event()
			move(-1)


func _press(direction: int) -> void:
	accept_event()
	_held = direction
	_hold_time = REPEAT_DELAY
	move(direction)


func _layout(animated: bool) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	if entries.is_empty():
		return
	var first := maxi(0, index - BEFORE)
	var last := mini(entries.size() - 1, index + AFTER)
	for i: int in _items.keys():
		if i < first or i > last:
			_items[i].queue_free()
			_items.erase(i)
	var moving: Array = []
	for i in range(first, last + 1):
		var target_x := _x_for(i)
		var target_grow := 1.0 if i == index else 0.0
		var item: Control = _items.get(i)
		if item == null:
			item = ItemScene.instantiate()
			_holder.add_child(item)
			item.clicked.connect(_on_item_clicked.bind(item))
			_items[i] = item
			# A new cover comes in at the place it had before this move.
			item.position = Vector2(target_x, 0)
			item.grow = target_grow
		elif animated:
			moving.append([item, target_x, target_grow])
		else:
			item.position.x = target_x
			item.grow = target_grow
		item.show_entry(entries[i], show_installed, i == index)
	if not moving.is_empty():
		_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		for m: Array in moving:
			_tween.tween_property(m[0], "position:x", m[1], MOVE_TIME)
			_tween.tween_property(m[0], "grow", m[2], MOVE_TIME)
	_update_rings()


func _x_for(i: int) -> float:
	if i <= index:
		return ANCHOR_X - float(index - i) * (SMALL.x + GAP)
	return ANCHOR_X + BIG.x + GAP + float(i - index - 1) * (SMALL.x + GAP)


func _update_rings() -> void:
	for i: int in _items:
		_items[i].set_ring(i == index and has_focus())


func _on_item_clicked(item: Control) -> void:
	grab_focus()
	for i: int in _items:
		if _items[i] == item:
			if i == index:
				activated.emit(index)
			else:
				move(i - index)
			return
