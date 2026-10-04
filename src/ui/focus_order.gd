class_name FocusOrder
extends RefCounted
## Godot picks what the D-pad focuses next by distance alone, so from the
## bottom of one column it jumps into the column beside it. A column wired
## here moves up and down inside itself and stops at its two ends.


## `left` and `right` are where those directions lead from every control of
## the column; with none, the focus stays where it is.
static func column(controls: Array, left: Control = null, right: Control = null) -> void:
	for i in controls.size():
		var control: Control = controls[i]
		var above: Control = controls[maxi(i - 1, 0)]
		var below: Control = controls[mini(i + 1, controls.size() - 1)]
		control.focus_neighbor_top = control.get_path_to(above)
		control.focus_neighbor_bottom = control.get_path_to(below)
		control.focus_previous = control.get_path_to(above)
		control.focus_next = control.get_path_to(below)
		control.focus_neighbor_left = control.get_path_to(left if left != null else control)
		control.focus_neighbor_right = control.get_path_to(right if right != null else control)


## The controls under `node` that take the focus, in the order they are shown.
static func focusable(node: Node, out: Array[Control] = []) -> Array[Control]:
	for child in node.get_children():
		if not (child is Control) or not child.visible or child.is_queued_for_deletion():
			continue
		if child.focus_mode == Control.FOCUS_ALL:
			out.append(child)
		elif not (child is BaseButton):
			focusable(child, out)
	return out
