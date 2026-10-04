class_name Processes
extends RefCounted
## Which programs are running out of a folder. The update run uses it to
## leave a game alone while it is being played (SPEC.md R21), because butler
## does not say which process a launched game is.
##
## It reads /proc directly. Asking a shell tool would not work: the shell
## that runs the tool has the folder in its own command line.


## The IDs of the processes whose program file, or whose first arguments
## (a script handed to an interpreter), lie under `folder`.
static func under(folder: String) -> PackedInt32Array:
	var out: PackedInt32Array = []
	if folder == "":
		return out
	var prefix := folder.trim_suffix("/") + "/"
	var me := OS.get_process_id()
	for name in DirAccess.get_directories_at("/proc"):
		if not name.is_valid_int() or int(name) == me:
			continue
		var dir := DirAccess.open("/proc/" + name)
		if dir == null:
			continue
		# Empty for another user's process, which cannot be one of our games.
		if dir.read_link("exe").begins_with(prefix):
			out.append(int(name))
			continue
		var arguments := _command_line("/proc/%s/cmdline" % name)
		for i in mini(arguments.size(), 2):
			if arguments[i].begins_with(prefix):
				out.append(int(name))
				break
	return out


static func any_under(folder: String) -> bool:
	return not under(folder).is_empty()


static func _command_line(path: String) -> PackedStringArray:
	var parts: PackedStringArray = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return parts
	# The file reports no length, so a fixed read is used; arguments are
	# separated by a zero byte.
	var bytes := file.get_buffer(4096)
	var start := 0
	for i in bytes.size():
		if bytes[i] == 0:
			parts.append(bytes.slice(start, i).get_string_from_utf8())
			start = i + 1
	return parts
