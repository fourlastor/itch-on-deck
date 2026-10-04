class_name ButlerInstall
extends Node
## Gets butler onto the machine (SPEC.md R27, G4): downloads one pinned
## version from broth, itch.io's own distribution server, checks the archive,
## unpacks it into ~/.local/share/itch-on-deck/butler/<version>/ and runs it
## once before trusting it.

signal progress(text: String, fraction: float)

## The version this app was tested against. `daemon` and `launch` are hidden
## commands of butler, so a newer one is used only after the tests pass on it.
const VERSION := "15.31.0"
const CHANNEL := "linux-amd64"
const BROTH := "https://broth.itch.zone/butler"
## SHA-256 of the archive, for every version the app may install.
const ARCHIVE_SHA256 := {
	"15.31.0": "4f2a3f22b12f870923504d4b6935535cad377b45859f5fe9419e3adc0611a48c",
}

var error := ""

var _http: HTTPRequest = null


static func is_installed(version: String = VERSION) -> bool:
	return FileAccess.file_exists(Paths.butler_bin(version))


static func archive_url(version: String) -> String:
	return "%s/%s/%s/archive/default" % [BROTH, CHANNEL, version]


## Downloads, checks and unpacks. Returns false and sets `error` on failure;
## nothing is left behind in that case.
func install(version: String = VERSION) -> bool:
	error = ""
	if is_installed(version):
		_write_current(version)
		return true
	var root := Paths.butler_root()
	if not Paths.ensure_dir(root):
		return _fail("The folder %s cannot be made." % Paths.display(root))
	var zip_path := root.path_join(version + ".zip.part")
	var tmp_dir := root.path_join(version + ".tmp")
	_remove_tree(tmp_dir)

	progress.emit("Downloading butler %s" % version, 0.0)
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.download_file = zip_path
	add_child(_http)
	var err := _http.request(archive_url(version))
	if err != OK:
		_drop_http()
		return _fail("The download could not start (error %d)." % err)
	var done: Array = await _http.request_completed
	_drop_http()
	var result: int = done[0]
	var code: int = done[1]
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(zip_path)
		if result != HTTPRequest.RESULT_SUCCESS:
			return _fail("No connection to broth.itch.zone (result %d)." % result)
		return _fail("broth.itch.zone answered %d." % code)

	progress.emit("Checking butler %s" % version, 1.0)
	var sha := FileAccess.get_sha256(zip_path)
	if ARCHIVE_SHA256.has(version) and sha != ARCHIVE_SHA256[version]:
		DirAccess.remove_absolute(zip_path)
		return _fail("The butler archive is not the expected one (SHA-256 %s)." % sha)

	if not _unzip(zip_path, tmp_dir):
		DirAccess.remove_absolute(zip_path)
		_remove_tree(tmp_dir)
		return _fail("The butler archive could not be unpacked.")
	DirAccess.remove_absolute(zip_path)

	var output: Array = []
	var exit_code := OS.execute(tmp_dir.path_join("butler"), PackedStringArray(["-V"]), output, true)
	var said := "".join(output)
	if exit_code != 0 or not said.contains(version):
		_remove_tree(tmp_dir)
		return _fail("The downloaded butler does not run as version %s." % version)

	if DirAccess.rename_absolute(tmp_dir, Paths.butler_dir(version)) != OK:
		_remove_tree(tmp_dir)
		return _fail("butler could not be put in place.")
	_write_current(version)
	if not ARCHIVE_SHA256.has(version):
		print("butler %s archive SHA-256: %s" % [version, sha])
	return true


## The newest version broth offers, or "" when it cannot be asked.
func latest_version() -> String:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	if http.request("%s/%s/LATEST" % [BROTH, CHANNEL]) != OK:
		http.queue_free()
		return ""
	var done: Array = await http.request_completed
	http.queue_free()
	if done[0] != HTTPRequest.RESULT_SUCCESS or done[1] != 200:
		return ""
	var body: PackedByteArray = done[3]
	return body.get_string_from_utf8().strip_edges()


func _process(_delta: float) -> void:
	if _http == null:
		return
	var total := _http.get_body_size()
	var got := _http.get_downloaded_bytes()
	if total > 0:
		progress.emit("Downloading butler %s" % VERSION, clampf(float(got) / float(total), 0.0, 1.0))


func _unzip(zip_path: String, dest: String) -> bool:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return false
	if not Paths.ensure_dir(dest):
		zip.close()
		return false
	var ok := true
	for entry: String in zip.get_files():
		# An archive must not write outside its own folder.
		if entry.begins_with("/") or entry.contains(".."):
			ok = false
			break
		var target := dest.path_join(entry)
		if entry.ends_with("/"):
			Paths.ensure_dir(target)
			continue
		Paths.ensure_dir(target.get_base_dir())
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			ok = false
			break
		file.store_buffer(zip.read_file(entry))
		file.close()
		# 493 is rwxr-xr-x: butler and its two 7-zip libraries.
		FileAccess.set_unix_permissions(target, 493)
	zip.close()
	return ok and FileAccess.file_exists(dest.path_join("butler"))


func _write_current(version: String) -> void:
	Paths.write_text_atomic(Paths.butler_current_file(), version + "\n")


func _drop_http() -> void:
	if _http != null:
		_http.queue_free()
		_http = null


func _fail(message: String) -> bool:
	error = message
	return false


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for dir in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(dir))
	DirAccess.remove_absolute(path)
