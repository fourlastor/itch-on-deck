class_name Keyboard
extends RefCounted
## Text is typed with Steam's on-screen keyboard in Gaming Mode (R6). Outside
## Steam there is a real keyboard and nothing to do.


static func under_steam() -> bool:
	return OS.has_environment("SteamDeck") or OS.has_environment("SteamGameId") or OS.has_environment("GAMESCOPE_WAYLAND_DISPLAY")


static func show() -> void:
	if under_steam():
		OS.shell_open("steam://open/keyboard")
