class_name SteamShortcuts
extends RefCounted
## Steam's shortcuts file, userdata/<user>/config/shortcuts.vdf: a binary
## key-value file listing the non-Steam games (SPEC.md section 7, way 2).
##
## The app reads it to learn the ID Steam gave a shortcut, which names the
## artwork files, and edits it only to remove one of its own entries. The
## rules of the itch app apply: a file that cannot be read back exactly is
## never rewritten, the file is replaced in one step, and a copy of the
## original is kept. Steam reads the file when it starts, so a removal shows
## after Steam restarts.

const MAP := 0
const TEXT := 1
const NUMBER := 2
const END := 8
const BACKUP_SUFFIX := ".before-itch-on-deck"


## The shortcuts of every Steam user that start `exe` with `argument`:
## [{ user, file, app_id, name }].
static func find(exe: String, argument: String) -> Array:
	var out: Array = []
	for user in Steam.users():
		var file := _file_of(user)
		var root: Variant = _read(file)
		if root == null:
			continue
		for entry: Dictionary in _shortcut_entries(root):
			if _matches(entry, exe, argument):
				out.append({"user": user, "file": file, "app_id": _app_id(entry), "name": _text(entry, "AppName")})
	return out


## Removes the shortcuts that start `exe` with `argument`. Returns "" or
## the reason nothing was changed.
static func remove_matching(exe: String, argument: String) -> String:
	var removed := 0
	for user in Steam.users():
		var file := _file_of(user)
		if not FileAccess.file_exists(file):
			continue
		var original := FileAccess.get_file_as_bytes(file)
		var root: Variant = _parse(original)
		if root == null or _serialize(root) != original:
			return "Steam's shortcuts file could not be read back exactly, so it was left alone. Remove the game in Steam: select it, Manage, Remove non-Steam game."
		var holder: Dictionary = _shortcuts_map(root)
		if holder.is_empty():
			continue
		var kept: Array = []
		for entry: Dictionary in holder.v:
			if entry.t == MAP and _matches(entry, exe, argument):
				removed += 1
			else:
				kept.append(entry)
		if kept.size() == holder.v.size():
			continue
		# Steam numbers the entries from 0 with no gaps.
		var index := 0
		for entry: Dictionary in kept:
			if entry.t == MAP:
				entry.k = str(index).to_utf8_buffer()
				index += 1
		holder.v = kept
		var backup := file + BACKUP_SUFFIX
		if not FileAccess.file_exists(backup):
			DirAccess.copy_absolute(file, backup)
		var tmp := file + ".tmp"
		var out := FileAccess.open(tmp, FileAccess.WRITE)
		if out == null:
			return "Steam's shortcuts file could not be written."
		out.store_buffer(_serialize(root))
		out.close()
		if DirAccess.rename_absolute(tmp, file) != OK:
			return "Steam's shortcuts file could not be replaced."
	if removed == 0:
		return "Steam has no shortcut for this game."
	return ""


## The folder Steam reads a shortcut's library images from.
static func grid_dir(user: String) -> String:
	return Steam.root().path_join("userdata").path_join(user).path_join("config/grid")


static func _file_of(user: String) -> String:
	return Steam.root().path_join("userdata").path_join(user).path_join("config/shortcuts.vdf")


static func _read(file: String) -> Variant:
	if not FileAccess.file_exists(file):
		return null
	return _parse(FileAccess.get_file_as_bytes(file))


# --- the entries -------------------------------------------------------------

static func _shortcuts_map(root: Array) -> Dictionary:
	for entry: Dictionary in root:
		if entry.t == MAP and (entry.k as PackedByteArray).get_string_from_utf8().to_lower() == "shortcuts":
			return entry
	return {}


static func _shortcut_entries(root: Array) -> Array:
	var holder := _shortcuts_map(root)
	if holder.is_empty():
		return []
	return (holder.v as Array).filter(func(e: Dictionary) -> bool: return e.t == MAP)


static func _field(entry: Dictionary, name: String) -> Variant:
	for field: Dictionary in entry.v:
		if (field.k as PackedByteArray).get_string_from_utf8().to_lower() == name.to_lower():
			return field.v
	return null


static func _text(entry: Dictionary, name: String) -> String:
	var value: Variant = _field(entry, name)
	return (value as PackedByteArray).get_string_from_utf8() if value is PackedByteArray else ""


static func _matches(entry: Dictionary, exe: String, argument: String) -> bool:
	return _text(entry, "Exe").contains(exe) and _text(entry, "LaunchOptions").contains(argument)


## The ID as Steam uses it in file names: the stored number, unsigned.
static func _app_id(entry: Dictionary) -> int:
	var value: Variant = _field(entry, "appid")
	if not (value is int):
		return 0
	return value if value >= 0 else value + 4294967296


# --- the file format ---------------------------------------------------------
#
# A map is a run of entries closed by the byte 8. An entry is a type byte, a
# name ending in a zero byte, and a value: a nested map (type 0), a text
# ending in a zero byte (type 1), or four bytes of a whole number (type 2).
# Names and texts are kept as bytes, so writing gives back what was read.

static func _parse(bytes: PackedByteArray) -> Variant:
	var state := {"pos": 0, "ok": true}
	var root := _parse_map(bytes, state, true)
	if not state.ok or state.pos != bytes.size():
		return null
	return root


static func _parse_map(bytes: PackedByteArray, state: Dictionary, top: bool) -> Array:
	var entries: Array = []
	while state.ok:
		if state.pos >= bytes.size():
			# Only the outermost level may end with the file.
			state.ok = top
			break
		var type := bytes[state.pos]
		state.pos += 1
		if type == END:
			if top:
				entries.append({"t": END, "k": PackedByteArray(), "v": null})
				continue
			break
		var key := _parse_text(bytes, state)
		if not state.ok:
			break
		match type:
			MAP:
				entries.append({"t": MAP, "k": key, "v": _parse_map(bytes, state, false)})
			TEXT:
				entries.append({"t": TEXT, "k": key, "v": _parse_text(bytes, state)})
			NUMBER:
				if state.pos + 4 > bytes.size():
					state.ok = false
				else:
					entries.append({"t": NUMBER, "k": key, "v": bytes.decode_s32(state.pos)})
					state.pos += 4
			_:
				# A kind of value this app does not know: do not touch the file.
				state.ok = false
	return entries


static func _parse_text(bytes: PackedByteArray, state: Dictionary) -> PackedByteArray:
	var end := bytes.find(0, state.pos)
	if end == -1:
		state.ok = false
		return PackedByteArray()
	var text := bytes.slice(state.pos, end)
	state.pos = end + 1
	return text


static func _serialize(entries: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for entry: Dictionary in entries:
		out.append(entry.t)
		if entry.t == END:
			continue
		out.append_array(entry.k)
		out.append(0)
		match entry.t:
			MAP:
				out.append_array(_serialize(entry.v))
				out.append(END)
			TEXT:
				out.append_array(entry.v)
				out.append(0)
			NUMBER:
				var number := PackedByteArray([0, 0, 0, 0])
				number.encode_s32(0, entry.v)
				out.append_array(number)
	return out
