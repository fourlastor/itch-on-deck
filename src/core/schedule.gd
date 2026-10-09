class_name Schedule
extends RefCounted
## The systemd user timer that runs the updates with the app closed (SPEC.md
## R19, R20, section 8). The app writes the two units itself and switches
## the timer on or off when a setting changes. No root is needed.

const SERVICE := "itch-on-deck-update.service"
const TIMER := "itch-on-deck-update.timer"

## The native helper runs the installed app directly and waits for it to
## exit before having a fresh butler daemon apply a queued self-update.
const LAUNCHER := """#!/bin/sh
# itch on Deck: the helper owns the update run, including its final self-update.
APP="$1"
if [ ! -x "$APP" ]; then
	echo "itch on Deck: $APP is not there. Open the app once: it writes this job again." >&2
	exit 1
fi
exec "$(dirname "$0")/update-helper" "$APP"
"""
const CALENDAR := {"15min": "*:0/15", "1h": "hourly", "6h": "00/6:00", "daily": "daily"}
const LABELS := {"off": "Off", "15min": "Every 15 minutes", "1h": "Every hour", "6h": "Every 6 hours", "daily": "Once a day"}


static func label(schedule: String) -> String:
	return LABELS.get(schedule, "Off")


## Brings systemd in line with the settings. Returns "" or what went wrong.
static func apply() -> String:
	var games := Config.schedule()
	var wanted := games != "off" or SelfUpdate.enabled()
	if not wanted:
		_systemctl(["disable", "--now", TIMER])
		_remove_copy()
		return ""
	# The app alone is looked at once a day.
	var calendar: String = CALENDAR.get(games, "daily")
	var dir := Paths.systemd_user_dir()
	if not _write_launcher():
		return "The update run's launcher could not be written to %s." % Paths.display(Paths.update_run_script())
	_remove_copy()
	if not Paths.write_text_atomic(dir.path_join(SERVICE), service_text()):
		return "The unit files could not be written to %s." % Paths.display(dir)
	if not Paths.write_text_atomic(dir.path_join(TIMER), timer_text(calendar)):
		return "The unit files could not be written to %s." % Paths.display(dir)
	if _systemctl(["daemon-reload"]) != 0:
		return "systemd did not take the new units (systemctl --user daemon-reload failed)."
	if _systemctl(["enable", "--now", TIMER]) != 0:
		return "The timer could not be switched on (systemctl --user enable failed)."
	# A changed interval only counts after a restart of the timer.
	_systemctl(["restart", TIMER])
	return ""


## At the start of the app: writes the timer's files again when they are
## not what this copy would write. That is so after the app was moved to
## another folder, and after a version that wrote them differently.
static func keep_current() -> void:
	if Config.schedule() == "off" and not SelfUpdate.enabled():
		return
	if _text_of(Paths.systemd_user_dir().path_join(SERVICE)) != service_text() or _text_of(Paths.update_run_script()) != LAUNCHER or _helper_changed():
		apply()


static func is_on() -> bool:
	var out: Array = []
	OS.execute("systemctl", PackedStringArray(["--user", "is-active", TIMER]), out)
	return "".join(out).strip_edges() == "active"


## When the timer fires next, as Unix time; 0 when it is off.
static func next_run() -> int:
	var out: Array = []
	if OS.execute("systemctl", PackedStringArray(["--user", "show", TIMER, "--property=NextElapseUSecRealtime"]), out) != 0:
		return 0
	# "NextElapseUSecRealtime=Sun 2026-10-04 19:00:00 CEST", in local time.
	var parts := "".join(out).strip_edges().get_slice("=", 1).split(" ", false)
	if parts.size() < 3:
		return 0
	var as_utc := Time.get_unix_time_from_datetime_string("%sT%s" % [parts[1], parts[2]])
	var zone := Time.get_time_zone_from_system()
	return int(as_utc) - int(zone.get("bias", 0)) * 60


## How systemd starts the update run: the launcher, which runs the installed
## program with no window. From the project's sources it is the editor
## that runs, and nothing ever replaces that.
static func command() -> String:
	if OS.has_feature("editor"):
		var project := ProjectSettings.globalize_path("res://").trim_suffix("/")
		return '"%s" --headless --path "%s" -- update' % [OS.get_executable_path(), project]
	return '"%s" "%s"' % [Paths.update_run_script(), SelfUpdate.program()]


static func service_text() -> String:
	return """[Unit]
Description=itch on Deck: update the installed games

[Service]
Type=oneshot
ExecStart=%s
SyslogIdentifier=itch-on-deck
Nice=10
IOSchedulingClass=idle
""" % command()


static func timer_text(calendar: String) -> String:
	return """[Unit]
Description=itch on Deck: look for updates

[Timer]
OnStartupSec=2min
OnCalendar=%s
Persistent=true

[Install]
WantedBy=timers.target
""" % calendar


static func _write_launcher() -> bool:
	if not OS.has_feature("editor") and not _write_helper():
		return false
	var path := Paths.update_run_script()
	if _text_of(path) != LAUNCHER and not Paths.write_text_atomic(path, LAUNCHER):
		return false
	# 493 is rwxr-xr-x.
	return FileAccess.set_unix_permissions(path, 493) == OK


static func _helper_changed() -> bool:
	if OS.has_feature("editor"):
		return false
	return FileAccess.get_sha256(Paths.update_helper_bin()) != FileAccess.get_sha256("res://src/core/update_helper.bin")


static func _write_helper() -> bool:
	var path := Paths.update_helper_bin()
	if _helper_changed():
		var bytes := FileAccess.get_file_as_bytes("res://src/core/update_helper.bin")
		if bytes.is_empty() or not Paths.ensure_dir(path.get_base_dir()):
			return false
		var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
		if file == null:
			return false
		file.store_buffer(bytes)
		file.close()
		if FileAccess.set_unix_permissions(path + ".tmp", 493) != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
			return false
	return FileAccess.set_unix_permissions(path, 493) == OK


## Retire the previous launcher's full copy of the app.
static func _remove_copy() -> void:
	var dir := Paths.update_run_copy_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)


static func _text_of(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


static func _systemctl(arguments: Array) -> int:
	var all: PackedStringArray = ["--user"]
	for a: String in arguments:
		all.append(a)
	return OS.execute("systemctl", all)
