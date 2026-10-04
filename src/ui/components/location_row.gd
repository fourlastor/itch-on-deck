extends Button
## One install location: its folder, how full its disk is, and what is in it.

var location: Dictionary = {}


func setup(l: Dictionary, games: int) -> void:
	location = l
	var info: Dictionary = l.get("sizeInfo", {}) if l.get("sizeInfo") is Dictionary else {}
	var free := float(info.get("freeSize", 0))
	var total := float(info.get("totalSize", 0))
	var installed := float(info.get("installedSize", 0))
	%Name.text = InstallLocations.label(l)
	%Path.text = Paths.display(str(l.get("path", "")))
	if total > 0.0:
		%Free.text = "%s free of %s" % [Format.size(free), Format.size(total)]
		%Meter.value = clampf(1.0 - free / total, 0.0, 1.0)
	else:
		# The disk is not there: an SD card that was taken out.
		%Free.text = "Not available"
		%Meter.value = 0.0
	if games == 0:
		%Info.text = "No games here yet"
	else:
		%Info.text = "%s · %s" % ["1 game" if games == 1 else "%d games" % games, Format.size(installed)]
