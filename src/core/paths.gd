class_name Paths
extends RefCounted
## Where the app keeps its files (SPEC.md section 4.1). Everything is under the
## home folder. ITCH_ON_DECK_DATA and ITCH_ON_DECK_CONFIG move the two roots,
## which the tests use to stay out of the real ones.

const APP_DIR := "itch-on-deck"


static func home() -> String:
	return OS.get_environment("HOME")


static func data_dir() -> String:
	var override := OS.get_environment("ITCH_ON_DECK_DATA")
	if override != "":
		return override
	var base := OS.get_environment("XDG_DATA_HOME")
	if base == "":
		base = home().path_join(".local/share")
	return base.path_join(APP_DIR)


static func config_home() -> String:
	var base := OS.get_environment("XDG_CONFIG_HOME")
	if base == "":
		base = home().path_join(".config")
	return base


static func config_dir() -> String:
	var override := OS.get_environment("ITCH_ON_DECK_CONFIG")
	if override != "":
		return override
	return config_home().path_join(APP_DIR)


static func cache_dir() -> String:
	var base := OS.get_environment("XDG_CACHE_HOME")
	if base == "":
		base = home().path_join(".cache")
	return base.path_join(APP_DIR)


static func config_path() -> String:
	return config_dir().path_join("config.json")


static func butler_root() -> String:
	return data_dir().path_join("butler")


static func butler_dir(version: String) -> String:
	return butler_root().path_join(version)


static func butler_bin(version: String) -> String:
	return butler_dir(version).path_join("butler")


## A one-line file naming the butler version in use. The run-game script reads
## it, so a Steam shortcut keeps working after butler is updated.
static func butler_current_file() -> String:
	return butler_root().path_join("current")


static func db_path() -> String:
	return data_dir().path_join("db/butler.db")


static func staging_dir() -> String:
	return data_dir().path_join("staging")


static func state_path() -> String:
	return data_dir().path_join("state.json")


static func update_lock_path() -> String:
	return data_dir().path_join("update.lock")


static func run_game_script() -> String:
	return data_dir().path_join("run-game")


static func update_run_script() -> String:
	return data_dir().path_join("update-run")


static func update_helper_bin() -> String:
	return data_dir().path_join("update-helper")


## A cache left by the old launcher, removed when the timer is refreshed.
static func update_run_copy_dir() -> String:
	return cache_dir().path_join("update-run")


static func shortcuts_dir() -> String:
	return data_dir().path_join("shortcuts")


static func covers_dir() -> String:
	return cache_dir().path_join("covers")


static func systemd_user_dir() -> String:
	return config_home().path_join("systemd/user")


static func default_install_location() -> String:
	return home().path_join("Games/itch")


## A path as the user reads it: the home folder shown as "~".
static func display(path: String) -> String:
	var h := home()
	if h != "" and path.begins_with(h):
		return "~" + path.substr(h.length())
	return path


static func ensure_dir(path: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		return true
	return DirAccess.make_dir_recursive_absolute(path) == OK


## Writes a text file in one step: a reader sees the old file or the new one,
## never half of one.
static func write_text_atomic(path: String, text: String) -> bool:
	if not ensure_dir(path.get_base_dir()):
		return false
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return DirAccess.rename_absolute(tmp, path) == OK
