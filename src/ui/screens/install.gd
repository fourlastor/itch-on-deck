extends Control
## Confirming an install (SPEC.md section 6): the uploads that fit this
## machine, where to put the game, how much it downloads and how much room
## it needs. Nothing is installed until the user presses Install (R9).

const RadioScene := preload("res://src/ui/components/radio_row.tscn")

var entry: GameEntry

var _uploads: Array = []
var _locations: Array = []
var _upload := 0
var _location := 0
var _needed := 0.0
var _ready_to_install := false
var _busy := false

@onready var _hints: HintBar = %HintBar


func _ready() -> void:
	%Header.back_pressed.connect(Nav.pop)
	%Cancel.pressed.connect(Nav.pop)
	%Confirm.pressed.connect(_on_confirm)
	%Confirm.focus_entered.connect(_show_hints)
	%Cancel.focus_entered.connect(_show_hints)


func open(args: Dictionary) -> void:
	entry = args["entry"]
	%Cover.show_entry(entry, false, true)
	%Title.text = entry.title()
	%ShortText.text = entry.short_text()
	%ShortText.visible = entry.short_text() != ""
	%Fits.setup("Fits this machine", "Reading")
	%NoFit.setup("Does not fit", "", true)
	%Confirm.disabled = true
	_show_hints()
	_load()


func first_focus() -> Control:
	return %Cancel


func _load() -> void:
	var got: Dictionary = await GameOps.uploads(entry.id())
	_locations = await InstallLocations.for_games()
	if not is_inside_tree():
		return
	if got.error != "":
		%Summary.text = "The uploads could not be read: %s" % got.error
		%Fits.setup("Fits this machine", "Unknown")
		return
	_uploads = got.uploads
	var other: Array = got.incompatible
	%Fits.setup("Fits this machine", _count(_uploads.size()))
	%NoFit.setup("Does not fit", _count(other.size()) if not other.is_empty() else "Nothing", true)
	if _uploads.is_empty():
		%Summary.text = "No upload of this game fits this machine."
		return
	if _locations.is_empty():
		%Summary.text = "There is no install location. Add one in Settings."
		return
	# The location with the most room is offered first.
	for i in _locations.size():
		if _free(_locations[i]) > _free(_locations[_location]):
			_location = i
	_build_rows()
	await _plan()
	if is_inside_tree():
		%Confirm.grab_focus()


func _build_rows() -> void:
	for child in %Uploads.get_children():
		child.queue_free()
	for child in %Locations.get_children():
		child.queue_free()
	for i in _uploads.size():
		var upload: Dictionary = _uploads[i]
		var row: RadioRow = RadioScene.instantiate()
		%Uploads.add_child(row)
		var tag := "Demo" if bool(upload.get("demo", false)) else ("Pre-order" if bool(upload.get("preorder", false)) else "")
		row.setup(GameOps.upload_platforms(upload), "%s · %s" % [GameOps.upload_name(upload), Format.size(float(upload.get("size", 0)))], tag)
		row.chosen = i == _upload
		row.pressed.connect(_choose_upload.bind(i))
		row.focus_entered.connect(_show_hints)
	for i in _locations.size():
		var location: Dictionary = _locations[i]
		var row: RadioRow = RadioScene.instantiate()
		%Locations.add_child(row)
		row.setup(InstallLocations.label(location), "%s · %s free" % [Paths.display(str(location.get("path", ""))), Format.size(_free(location))])
		row.chosen = i == _location
		row.pressed.connect(_choose_location.bind(i))
		row.focus_entered.connect(_show_hints)


func _choose_upload(index: int) -> void:
	_upload = index
	for i in %Uploads.get_child_count():
		%Uploads.get_child(i).chosen = i == index
	_plan()


func _choose_location(index: int) -> void:
	_location = index
	for i in %Locations.get_child_count():
		%Locations.get_child(i).chosen = i == index
	_show_summary()


## Asks butler how much the chosen upload needs (Install.Plan).
func _plan() -> void:
	_ready_to_install = false
	%Confirm.disabled = true
	%Summary.text = "Working out the size."
	var upload: Dictionary = _uploads[_upload]
	var planned: Dictionary = await GameOps.plan(entry.id(), int(upload.get("id", 0)))
	if not is_inside_tree() or upload != _uploads[_upload]:
		return
	if planned.error != "":
		%Summary.text = "butler could not plan this install: %s" % planned.error
		return
	_needed = planned.needed
	_ready_to_install = true
	_show_summary()


func _show_summary() -> void:
	if not _ready_to_install:
		return
	var upload: Dictionary = _uploads[_upload]
	var location: Dictionary = _locations[_location]
	var free := _free(location)
	var download := Format.size(float(upload.get("size", 0)))
	var name := InstallLocations.label(location)
	if _needed > 0.0 and _needed > free:
		# Too little room: say how much is missing, and do not start.
		%Summary.text = "Not enough room on %s: %s needed, %s free, %s missing." % [
			name, Format.size(_needed), Format.size(free), Format.size(_needed - free)]
		%Confirm.disabled = true
		%Confirm.set_row("Install", "No room on %s" % name)
		return
	if _needed > 0.0:
		%Summary.text = "Download %s. Needs %s free while installing." % [download, Format.size(_needed)]
	else:
		%Summary.text = "Download %s." % download
	%Confirm.disabled = false
	%Confirm.set_row("Install", "%s to %s" % [download, name])


func _on_confirm() -> void:
	if _busy or not _ready_to_install or %Confirm.disabled:
		return
	_busy = true
	var location: Dictionary = _locations[_location]
	var problem: String = await Downloads.queue_install(entry.game, _uploads[_upload], str(location.get("id", "")))
	_busy = false
	if problem != "":
		%Summary.text = "The install could not be queued: %s" % problem
		return
	# Back to the game, then on to the queue, where the progress shows.
	Nav.pop()
	Nav.push("downloads")


func _show_hints() -> void:
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var hints: Array = []
	if focused == %Confirm:
		hints.append([Glyph.Kind.A, "Install"])
	elif focused == %Cancel:
		hints.append([Glyph.Kind.A, "Cancel"])
	elif focused is RadioRow:
		hints.append([Glyph.Kind.A, "Choose this one"])
	hints.append([Glyph.Kind.B, "Cancel"])
	var waiting := Downloads.pending_count()
	_hints.set_hints(hints, "Joins the download queue" + (", after %d others" % waiting if waiting > 0 else ""))


static func _free(location: Dictionary) -> float:
	var info: Variant = location.get("sizeInfo")
	return float(info.get("freeSize", 0)) if info is Dictionary else 0.0


static func _count(n: int) -> String:
	return "1 upload" if n == 1 else "%d uploads" % n
