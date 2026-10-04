class_name Steam
extends RefCounted
## Putting a game in the Steam library as a non-Steam game (SPEC.md
## section 7). The shortcut starts `run-game <cave id>`, a small script the
## app installs, so the game runs through butler with no window of the app.
##
## Adding asks the running Steam (the steam://addnonsteamgame address, as
## SteamOS's own "Add to Steam" does); nothing restarts. Removing has no such
## address: it edits Steam's shortcuts file, which Steam reads at its start.

const RUN_GAME := """#!/bin/sh
# itch on Deck: starts an installed game through butler, with no window of
# the app. The app writes this file; Steam shortcuts point at it.
DATA="${ITCH_ON_DECK_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/itch-on-deck}"
VERSION=$(cat "$DATA/butler/current" 2>/dev/null)
BUTLER="$DATA/butler/$VERSION/butler"
if [ ! -x "$BUTLER" ]; then
	echo "itch on Deck: butler is missing. Open the app once to fetch it." >&2
	exit 1
fi
exec "$BUTLER" --json --dbpath "$DATA/db/butler.db" launch --cave "$1"
"""


## Steam's folder, or "" when Steam is not installed for this user.
static func root() -> String:
	var home := Paths.home()
	for candidate: String in [
		home.path_join(".local/share/Steam"),
		home.path_join(".steam/steam"),
		home.path_join(".var/app/com.valvesoftware.Steam/.local/share/Steam"),
	]:
		if DirAccess.dir_exists_absolute(candidate.path_join("userdata")):
			return candidate
	return ""


static func is_available() -> bool:
	return root() != ""


## The Steam users of this machine: the folder names under userdata.
static func users() -> PackedStringArray:
	var out: PackedStringArray = []
	var base := root()
	if base == "":
		return out
	for name in DirAccess.get_directories_at(base.path_join("userdata")):
		if name.is_valid_int() and name != "0":
			out.append(name)
	return out


static func is_in_steam(cave_id: String) -> bool:
	var known: Dictionary = Config.get_value("steam", {})
	return known.has(cave_id)


## Adds an installed game. Returns "" or the reason it did not work.
static func add_game(entry: GameEntry) -> String:
	if Butler.demo != null:
		return ""
	if not is_available():
		return "Steam was not found on this machine."
	if not ensure_run_game():
		return "The launcher script could not be written."
	var cave_id := entry.cave_id()
	if not SteamShortcuts.find(Paths.run_game_script(), cave_id).is_empty():
		# Steam has it already; asking again would add it a second time.
		_remember(cave_id, entry.title(), "")
		return ""
	var icon := _icon_for(entry)
	var desktop := _write_desktop(cave_id, entry.title(),
		'"%s" %s' % [Paths.run_game_script(), cave_id], entry.install_folder(), icon)
	if desktop == "":
		return "The shortcut file could not be written."
	var problem := _ask_steam(desktop)
	if problem != "":
		return problem
	_remember(cave_id, entry.title(), desktop)
	return ""


## Gives a game's shortcut its library images, made from the cover. Steam
## names the image files after the ID it gave the shortcut, so this waits
## until Steam has written the entry. Steam itself takes neither the icon
## nor the folder from the shortcut file it is handed.
static func apply_artwork(entry: GameEntry) -> bool:
	var cover := _cover_image(entry)
	if cover == null:
		return false
	var tree := Engine.get_main_loop() as SceneTree
	for attempt in 12:
		var found := SteamShortcuts.find(Paths.run_game_script(), entry.cave_id())
		if not found.is_empty():
			for shortcut: Dictionary in found:
				_write_grid(str(shortcut.user), int(shortcut.app_id), cover)
			return true
		await tree.create_timer(0.5).timeout
	return false


static func _remember(cave_id: String, title: String, desktop: String) -> void:
	var known: Dictionary = Config.get_value("steam", {}).duplicate()
	var before: Dictionary = known.get(cave_id, {})
	known[cave_id] = {"name": title, "desktop_file": desktop if desktop != "" else str(before.get("desktop_file", ""))}
	Config.set_value("steam", known)


## Removes a game's entry from Steam's shortcuts file. Steam shows the change
## after it restarts (R16b). Returns "" or the reason.
static func remove_game(cave_id: String) -> String:
	var shortcuts := SteamShortcuts.find(Paths.run_game_script(), cave_id)
	var problem := SteamShortcuts.remove_matching(Paths.run_game_script(), cave_id)
	if problem != "":
		return problem
	# The library images made for the shortcut go with it.
	for shortcut: Dictionary in shortcuts:
		var dir := SteamShortcuts.grid_dir(str(shortcut.user))
		for suffix: String in [".png", "p.png"]:
			DirAccess.remove_absolute(dir.path_join("%d%s" % [int(shortcut.app_id), suffix]))
	forget(cave_id)
	return ""


## Drops the app's own record of a shortcut, and its files.
static func forget(cave_id: String) -> void:
	var known: Dictionary = Config.get_value("steam", {}).duplicate()
	if not known.has(cave_id):
		return
	var info: Dictionary = known[cave_id]
	var desktop := str(info.get("desktop_file", ""))
	if desktop != "" and FileAccess.file_exists(desktop):
		DirAccess.remove_absolute(desktop)
	known.erase(cave_id)
	Config.set_value("steam", known)


## Adds the app itself (R16c), so it can be opened in Gaming Mode.
static func add_app() -> String:
	if not is_available():
		return "Steam was not found on this machine."
	var desktop := _write_desktop("itch-on-deck", "itch on Deck", app_command(), Paths.data_dir(), _app_icon())
	if desktop == "":
		return "The shortcut file could not be written."
	var problem := _ask_steam(desktop)
	if problem == "":
		Config.set_value("app_in_steam", true)
	return problem


## The command that starts this app: the exported binary, or the editor with
## the project when run from source.
static func app_command() -> String:
	var exe := OS.get_executable_path()
	if OS.has_feature("editor"):
		return '"%s" --path "%s"' % [exe, ProjectSettings.globalize_path("res://").trim_suffix("/")]
	return '"%s"' % exe


static func ensure_run_game() -> bool:
	var path := Paths.run_game_script()
	if not FileAccess.file_exists(path) or FileAccess.get_file_as_string(path) != RUN_GAME:
		if not Paths.write_text_atomic(path, RUN_GAME):
			return false
	# 493 is rwxr-xr-x.
	return FileAccess.set_unix_permissions(path, 493) == OK


static func _write_desktop(name: String, title: String, command: String, folder: String, icon: String) -> String:
	var path := Paths.shortcuts_dir().path_join(name + ".desktop")
	var lines: PackedStringArray = [
		"[Desktop Entry]",
		"Type=Application",
		"Name=" + title.replace("\n", " "),
		"Exec=" + command,
		"Terminal=false",
		"Categories=Game;",
	]
	if folder != "":
		lines.append("Path=" + folder)
	if icon != "":
		lines.append("Icon=" + icon)
	if not Paths.write_text_atomic(path, "\n".join(lines) + "\n"):
		return ""
	FileAccess.set_unix_permissions(path, 493)
	return path


## Hands a .desktop file to the running Steam. Steam only accepts the
## address when this marker file exists, which keeps web pages from using it.
static func _ask_steam(desktop_file: String) -> String:
	var marker := FileAccess.open("/tmp/addnonsteamgamefile", FileAccess.WRITE)
	if marker != null:
		marker.close()
	var url := "steam://addnonsteamgame/" + desktop_file.uri_encode()
	if OS.shell_open(url) != OK:
		if OS.create_process("steam", PackedStringArray([url])) <= 0:
			return "Steam could not be asked to add the shortcut."
	return ""


## The cover, copied next to the shortcut with a file extension Steam knows.
static func _icon_for(entry: GameEntry) -> String:
	var cached := Covers.cached_file(entry.cover_url())
	if cached == "":
		return ""
	var bytes := FileAccess.get_file_as_bytes(cached)
	if bytes.size() < 4:
		return ""
	var extension := "png" if bytes[0] == 0x89 else ("jpg" if bytes[0] == 0xFF else "")
	if extension == "":
		return ""
	var target := Paths.shortcuts_dir().path_join("%s.%s" % [entry.cave_id(), extension])
	Paths.ensure_dir(target.get_base_dir())
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(bytes)
	file.close()
	return target


static func _cover_image(entry: GameEntry) -> Image:
	var cached := Covers.cached_file(entry.cover_url())
	if cached == "":
		return null
	var bytes := FileAccess.get_file_as_bytes(cached)
	var image := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes.size() > 4 and bytes[0] == 0x89:
		err = image.load_png_from_buffer(bytes)
	elif bytes.size() > 4 and bytes[0] == 0xFF:
		err = image.load_jpg_from_buffer(bytes)
	if err != OK or image.is_empty():
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


## Steam shows a wide image in lists and a tall one in the library grid. An
## itch.io cover is 315 by 250, so it is set on a plain ground of each shape.
static func _write_grid(user: String, app_id: int, cover: Image) -> void:
	var dir := SteamShortcuts.grid_dir(user)
	if not Paths.ensure_dir(dir):
		return
	_framed(cover, 920, 430).save_png(dir.path_join("%d.png" % app_id))
	_framed(cover, 600, 900).save_png(dir.path_join("%dp.png" % app_id))


static func _framed(cover: Image, width: int, height: int) -> Image:
	var canvas := Image.create(width, height, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("1a1816"))
	var scale := minf(float(width) / cover.get_width(), float(height) / cover.get_height())
	var fitted: Image = cover.duplicate()
	fitted.resize(int(cover.get_width() * scale), int(cover.get_height() * scale), Image.INTERPOLATE_LANCZOS)
	var at := Vector2i((width - fitted.get_width()) / 2, (height - fitted.get_height()) / 2)
	canvas.blit_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()), at)
	return canvas


static func _app_icon() -> String:
	var target := Paths.shortcuts_dir().path_join("itch-on-deck.png")
	if FileAccess.file_exists(target):
		return target
	var icon: Texture2D = load("res://assets/icon.svg")
	if icon == null:
		return ""
	Paths.ensure_dir(target.get_base_dir())
	return target if icon.get_image().save_png(target) == OK else ""
