extends MarginContainer
## The top of the list screens: the five lists (the shoulder buttons move
## between them) and the two things with a button of their own.

signal tab_selected(index: int)
signal downloads_pressed
signal settings_pressed

const TAB_COUNT := 5

var tab := 0

@onready var _tabs: Array[Button] = [%Installed, %Owned, %Collections, %Projects, %Search]


func _ready() -> void:
	for i in _tabs.size():
		_tabs[i].pressed.connect(_on_tab_pressed.bind(i))
	%Downloads.pressed.connect(func() -> void: downloads_pressed.emit())
	%Settings.pressed.connect(func() -> void: settings_pressed.emit())
	set_tab(tab)


func set_tab(index: int) -> void:
	tab = clampi(index, 0, TAB_COUNT - 1)
	# set_pressed_no_signal leaves the rest of the button group alone.
	for i in _tabs.size():
		_tabs[i].set_pressed_no_signal(i == tab)


func set_download_count(count: int) -> void:
	%Downloads.count = count


func _on_tab_pressed(index: int) -> void:
	if index != tab:
		tab = index
		tab_selected.emit(index)
