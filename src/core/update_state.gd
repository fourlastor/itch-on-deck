class_name UpdateState
extends RefCounted
## What the last update runs did, kept in state.json for the app to show
## (SPEC.md R24, section 8 step 6).

const KEEP := 20


static func runs() -> Array:
	return _load().get("runs", [])


static func add_run(run: Dictionary) -> void:
	var state := _load()
	var list: Array = state.get("runs", [])
	list.push_front(run)
	if list.size() > KEEP:
		list.resize(KEEP)
	state["runs"] = list
	Paths.write_text_atomic(Paths.state_path(), JSON.stringify(state, "\t") + "\n")


## One run in a sentence or two: what was updated, skipped or went wrong.
static func describe(run: Dictionary) -> String:
	var parts: PackedStringArray = []
	match str(run.get("outcome", "")):
		"no_connection":
			return "No connection. Nothing changed."
		"busy":
			return "Another run was still going. Nothing changed."
		"not_ready":
			return str(run.get("note", "The app is not set up yet."))
	for item: Dictionary in run.get("updated", []):
		var version := str(item.get("version", ""))
		parts.append("Updated %s%s." % [str(item.get("title", "")), (" to " + version) if version != "" else ""])
	for item: Dictionary in run.get("skipped", []):
		parts.append("Skipped %s: %s." % [str(item.get("title", "")), str(item.get("reason", ""))])
	for item: Dictionary in run.get("left", []):
		parts.append("%s has %s: pick one in the app." % [str(item.get("title", "")), str(item.get("reason", ""))])
	for message: String in run.get("errors", []):
		parts.append("Failed: %s." % message.trim_suffix("."))
	if parts.is_empty():
		return "Nothing to update."
	return " ".join(parts)


static func _load() -> Dictionary:
	var path := Paths.state_path()
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
