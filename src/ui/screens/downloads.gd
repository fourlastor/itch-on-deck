extends Control
## What is downloading and what waits (SPEC.md section 9), with progress,
## speed and time left. One download runs at a time; each can be cancelled,
## and a failed one shows butler's reason and can be tried again (R11).

const RowScene := preload("res://src/ui/components/download_row.tscn")

var _shape := ""

@onready var _hints: HintBar = %HintBar


func _ready() -> void:
	%Header.back_pressed.connect(Nav.pop)
	%Active.pressed.connect(func() -> void: _open_game(Downloads.active()))
	%Active.focus_entered.connect(_show_hints)
	Downloads.changed.connect(_show)


func open(_args: Dictionary) -> void:
	Downloads.refresh()
	_show()


func first_focus() -> Control:
	if %Active.visible:
		return %Active
	for holder: Node in [%Waiting, %Failed]:
		if holder.get_child_count() > 0:
			return holder.get_child(0)
	return null


func _unhandled_input(event: InputEvent) -> void:
	if Nav.dialog_open():
		return
	if event.is_action_pressed(&"filter"):
		var download := _focused_download()
		if not download.is_empty():
			get_viewport().set_input_as_handled()
			Downloads.discard(str(download.get("id", "")))


func _show() -> void:
	if not is_inside_tree():
		return
	var active := Downloads.active()
	var waiting := Downloads.waiting()
	var failed := Downloads.failed()
	# The lists are rebuilt only when their members change, so a progress
	# tick does not take the focus away from a row.
	var shape := ",".join((waiting + failed).map(func(d: Dictionary) -> String: return str(d.get("id", "")))) + "|" + str(active.get("id", ""))
	if shape != _shape:
		var lost_focus := not is_instance_valid(get_viewport().gui_get_focus_owner())
		_shape = shape
		_build(%Waiting, waiting, false)
		_build(%Failed, failed, true)
		%ActiveCaption.visible = not active.is_empty()
		%Active.visible = not active.is_empty()
		%WaitingCaption.visible = not waiting.is_empty()
		%FailedCaption.visible = not failed.is_empty()
		%Empty.visible = active.is_empty() and waiting.is_empty() and failed.is_empty()
		if not active.is_empty():
			var game: Dictionary = active.get("game", {})
			%ActiveCover.show_entry(GameEntry.for_game(game), false, false)
			%ActiveTitle.text = str(game.get("title", "Untitled"))
		if is_visible_in_tree() and not Nav.dialog_open() and (lost_focus or get_viewport().gui_get_focus_owner() == null):
			var target := first_focus()
			if target != null:
				target.grab_focus.call_deferred()
	if not active.is_empty():
		_show_progress(active)
	var parts: PackedStringArray = []
	if not active.is_empty():
		parts.append("1 downloading")
	if not waiting.is_empty():
		parts.append("%d waiting" % waiting.size())
	if not failed.is_empty():
		parts.append("%d failed" % failed.size())
	%Header.set_note(" · ".join(parts))
	_show_hints()


func _show_progress(active: Dictionary) -> void:
	var p := Downloads.progress_of(active)
	var size := Downloads.size_of(active)
	var fraction := clampf(float(p.get("progress", 0.0)), 0.0, 1.0)
	var upload: Dictionary = active.get("upload", {}) if active.get("upload") is Dictionary else {}
	var what := Downloads.reason_text(active)
	var name := GameOps.upload_name(upload) if not upload.is_empty() else ""
	var stage := str(p.get("stage", ""))
	var sub: PackedStringArray = [what]
	if name != "":
		sub.append(name)
	if stage != "" and stage != "download":
		sub.append(stage)
	if not Downloads.online:
		sub.append("waiting for the connection")
	%ActiveSub.text = " · ".join(sub)
	%Bar.value = fraction
	if size > 0.0:
		%Done.text = "%s of %s" % [Format.size(size * fraction), Format.size(size)]
	else:
		%Done.text = ""
	%Percent.text = "%d %%" % int(fraction * 100.0) if not p.is_empty() else "Starting"
	%Speed.text = Format.speed(float(p.get("bps", 0.0)))
	%TimeLeft.text = Format.time_left(float(p.get("eta", 0.0)))


func _build(holder: VBoxContainer, list: Array, failed: bool) -> void:
	for child in holder.get_children():
		child.queue_free()
	var previous := ""
	for d: Dictionary in list:
		var row := RowScene.instantiate()
		holder.add_child(row)
		var size := Downloads.size_of(d)
		var what := Downloads.reason_text(d)
		if failed:
			row.setup(d, "%s · %s" % [what, Downloads.error_text(d)], "Retry")
			row.pressed.connect(func() -> void: Downloads.retry(str(d.get("id", ""))))
		else:
			var sub := what + (" · " + Format.size(size) if size > 0.0 else "")
			row.setup(d, sub, "Next" if previous == "" else "After %s" % previous)
			row.pressed.connect(_open_game.bind(d))
		row.focus_entered.connect(_show_hints)
		var game: Dictionary = d.get("game", {})
		previous = str(game.get("title", ""))


func _open_game(download: Dictionary) -> void:
	var game: Variant = download.get("game")
	if game is Dictionary and not game.is_empty():
		Nav.push("game", {"entry": Library.entry_for(game), "from": "Downloads"})


func _focused_download() -> Dictionary:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == %Active:
		return Downloads.active()
	if focused != null and focused.get("download") is Dictionary:
		return focused.download
	return {}


func _show_hints() -> void:
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var hints: Array = []
	if focused != null and focused.get_parent() == %Failed:
		hints.append([Glyph.Kind.A, "Try again"])
		hints.append([Glyph.Kind.X, "Remove from the list"])
	elif not _focused_download().is_empty():
		hints.append([Glyph.Kind.X, "Cancel this download"])
		hints.append([Glyph.Kind.A, "Open the game"])
	hints.append([Glyph.Kind.B, "Back"])
	_hints.set_hints(hints, "Online" if Downloads.online else "No connection: downloads wait")
