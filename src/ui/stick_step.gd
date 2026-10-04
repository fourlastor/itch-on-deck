class_name StickStep
extends RefCounted
## Turns the travel of a stick into single steps. A stick sends a run of
## events while it moves, and every one of them past the dead zone counts as
## its action being pressed, so a control that steps on "pressed" runs to its
## end on one push. Godot's own focus moves guard against that; a control
## that reads left and right itself has to as well.
##
## One push is one step: the stick must come back towards the middle before
## it steps again, and a little wobble near the edge of the dead zone does
## not count as coming back.

## Past this the stick is pushed; under OFF it is let go.
const ON := 0.6
const OFF := 0.35

var _direction := 0


## Takes any event. Returns -1 or 1 when it is the start of a push along
## `axis`, and 0 otherwise.
func step(event: InputEvent, axis: JoyAxis) -> int:
	var motion := event as InputEventJoypadMotion
	if motion == null or motion.axis != axis:
		return 0
	var now := _direction
	if motion.axis_value >= ON:
		now = 1
	elif motion.axis_value <= -ON:
		now = -1
	elif absf(motion.axis_value) <= OFF:
		now = 0
	if now == _direction:
		return 0
	_direction = now
	return now


## Forgets a push that was under way, for when the control loses the focus
## and so does not see the stick come back.
func reset() -> void:
	_direction = 0
