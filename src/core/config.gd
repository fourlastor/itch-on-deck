extends Node
## Settings, kept in ~/.config/itch-on-deck/config.json (SPEC.md section 4.1).

signal changed(key: String)

## The update schedule (R19): off, or how often the systemd timer fires.
const SCHEDULES: Array[String] = ["off", "15min", "1h", "6h", "daily"]

const DEFAULTS := {
	"schedule": "off",
	"profile_id": 0,
	"bandwidth_kbps": 0,
	# [{ "id": String, "path": String }], mirrored into butler's database.
	"install_locations": [],
	# cave id -> { "name": String, "desktop_file": String }
	"steam": {},
	"app_in_steam": false,
	# The app updating itself, apart from the games' schedule.
	"self_update": false,
	# The install location made to hold the app's own folder, if any.
	"self_location_id": "",
}

var data: Dictionary = DEFAULTS.duplicate(true)
## False in the demo mode, which must leave the real settings alone.
var persist := true


func _ready() -> void:
	load_file()


func load_file() -> void:
	data = DEFAULTS.duplicate(true)
	var path := Paths.config_path()
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		for key: String in parsed:
			data[key] = parsed[key]
	else:
		push_warning("config.json could not be read; using the defaults")


func save() -> bool:
	if not persist:
		return true
	return Paths.write_text_atomic(Paths.config_path(), JSON.stringify(data, "\t") + "\n")


## Switches to settings that are never written, starting from the defaults.
func use_scratch() -> void:
	persist = false
	data = DEFAULTS.duplicate(true)


func get_value(key: String, fallback: Variant = null) -> Variant:
	return data.get(key, fallback)


func set_value(key: String, value: Variant) -> void:
	data[key] = value
	save()
	changed.emit(key)


func profile_id() -> int:
	return int(data.get("profile_id", 0))


func schedule() -> String:
	var s := str(data.get("schedule", "off"))
	return s if s in SCHEDULES else "off"
