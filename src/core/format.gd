class_name Format
extends RefCounted
## Numbers and times as the screens show them: short and factual (R26).


## 204 MB, 1.2 GB, 38 GB.
static func size(bytes: float) -> String:
	if bytes < 0:
		return ""
	var units: Array[String] = ["B", "KB", "MB", "GB", "TB"]
	var value := bytes
	var unit := 0
	while value >= 1000.0 and unit < units.size() - 1:
		value /= 1024.0
		unit += 1
	if unit == 0:
		return "%d B" % int(value)
	if value >= 100.0 or unit <= 2:
		return "%d %s" % [int(round(value)), units[unit]]
	if value >= 10.0:
		return "%d %s" % [int(round(value)), units[unit]]
	return "%.1f %s" % [value, units[unit]]


## 4.6 MB/s
static func speed(bytes_per_second: float) -> String:
	if bytes_per_second <= 0:
		return ""
	var mb := bytes_per_second / (1024.0 * 1024.0)
	if mb >= 1.0:
		return "%.1f MB/s" % mb
	return "%d KB/s" % int(bytes_per_second / 1024.0)


## "About 3 min left", from seconds.
static func time_left(seconds: float) -> String:
	if seconds <= 0:
		return ""
	if seconds < 60:
		return "Under a minute left"
	if seconds < 3600:
		return "About %d min left" % int(round(seconds / 60.0))
	var hours := int(seconds / 3600.0)
	var minutes := int(fmod(seconds, 3600.0) / 60.0)
	return "About %d h %d min left" % [hours, minutes]


## Play time: "3 h 12 min", "40 min", "Not played yet".
static func play_time(seconds: int) -> String:
	if seconds <= 0:
		return "Not played yet"
	if seconds < 60:
		return "Under a minute"
	var hours := seconds / 3600
	var minutes := (seconds % 3600) / 60
	if hours == 0:
		return "%d min" % minutes
	return "%d h %d min" % [hours, minutes]


## A moment, relative to now: "today 14:00", "yesterday 21:40", "28 September".
static func moment(unix_time: int) -> String:
	if unix_time <= 0:
		return "never"
	var now := Time.get_unix_time_from_system()
	var offset := _zone_offset()
	var then := Time.get_datetime_dict_from_unix_time(unix_time + offset)
	var today := Time.get_datetime_dict_from_unix_time(int(now) + offset)
	var clock := "%02d:%02d" % [then.hour, then.minute]
	var day_then := int((unix_time + offset) / 86400)
	var day_now := int((int(now) + offset) / 86400)
	if day_then == day_now:
		return "today " + clock
	if day_then == day_now - 1:
		return "yesterday " + clock
	var months: Array[String] = ["January", "February", "March", "April", "May", "June", "July",
		"August", "September", "October", "November", "December"]
	var text := "%d %s" % [then.day, months[then.month - 1]]
	if then.year != today.year:
		text += " %d" % then.year
	return text


## Turns butler's RFC 3339 date ("2026-09-28T10:12:00Z") into Unix time.
static func parse_date(rfc: Variant) -> int:
	if not (rfc is String) or rfc == "":
		return 0
	return int(Time.get_unix_time_from_datetime_string(rfc))


## A whole number with thin spaces: 1 204 811.
static func grouped(number: int) -> String:
	var digits := str(absi(number))
	var out := ""
	while digits.length() > 3:
		out = " " + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	out = digits + out
	return ("-" if number < 0 else "") + out


static func _zone_offset() -> int:
	var zone := Time.get_time_zone_from_system()
	return int(zone.get("bias", 0)) * 60
