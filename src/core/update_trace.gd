class_name UpdateTrace
extends RefCounted
## How an update arrived, read off what butler says while it applies one:
## as patches, as the whole upload, or as a repair (butler compares the
## folder with the build and fetches what differs). The update run writes it
## after "Updated ...", so the journal and the list of runs show it.

var patches := 0
var patch_size := ""
var upload_size := ""
var repaired := false
var no_record := false

var _total := RegEx.create_from_string("Total upgrade size (.+?) is (?:smaller|larger) than full upload (.+)$")
var _count := RegEx.create_from_string("Will apply (\\d+) patch")
var _upload := RegEx.create_from_string(":: ([0-9.]+ [A-Za-z]+) :: #\\d+")


## Takes one line of butler's log.
func read(message: String) -> void:
	var found := _total.search(message)
	if found != null:
		patch_size = found.get_string(1)
		upload_size = found.get_string(2)
	found = _count.search(message)
	if found != null:
		patches = int(found.get_string(1))
	found = _upload.search(message)
	if found != null and upload_size == "":
		upload_size = found.get_string(1)
	if message.contains("Falling back to heal") or message.contains("Heal is less expensive") or message.contains("Healing container"):
		repaired = true
	if message.contains("No receipt found"):
		no_record = true


## "1 patch, 215.32 KiB", "the whole build, 28.34 MiB", "repaired from the
## build", or "" when butler said nothing that tells.
func summary() -> String:
	if repaired:
		return "repaired from the build"
	if patches > 0:
		var count := "1 patch" if patches == 1 else "%d patches" % patches
		return "%s, %s" % [count, patch_size] if patch_size != "" else count
	if no_record:
		return "the whole build, %s" % upload_size if upload_size != "" else "the whole build"
	return ""
