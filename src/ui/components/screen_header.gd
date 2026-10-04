extends MarginContainer
## The top of a screen that is not a list: where B leads, a title, and the
## buttons that open Downloads and Settings.

signal back_pressed

@export var title := "":
	set(value):
		title = value
		_apply()
@export var back_text := "Back":
	set(value):
		back_text = value
		_apply()
@export var show_downloads := true:
	set(value):
		show_downloads = value
		_apply()
@export var show_settings := true:
	set(value):
		show_settings = value
		_apply()


func _ready() -> void:
	%Back.pressed.connect(func() -> void: back_pressed.emit())
	%Downloads.pressed.connect(func() -> void: Nav.push("downloads"))
	%Settings.pressed.connect(func() -> void: Nav.push("settings"))
	Downloads.changed.connect(_apply)
	_apply()


func set_note(text: String) -> void:
	%Note.text = text


func _apply() -> void:
	if not is_node_ready():
		return
	%Back.text = back_text
	%Title.text = title
	%Title.visible = title != ""
	%Downloads.visible = show_downloads
	%Settings.visible = show_settings
	%Downloads.count = Downloads.pending_count()
