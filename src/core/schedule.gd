class_name Schedule
extends RefCounted
## The systemd user timer that runs the updates with the app closed (SPEC.md
## R19, R20, section 8). The app writes the two units itself and switches
## the timer on or off when a setting changes. No root is needed.

const SERVICE := "itch-on-deck-update.service"
const TIMER := "itch-on-deck-update.timer"
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
		return ""
	# The app alone is looked at once a day.
	var calendar: String = CALENDAR.get(games, "daily")
	var dir := Paths.systemd_user_dir()
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


## How systemd starts the update run: this very program, with no window.
static func command() -> String:
	var exe := OS.get_executable_path()
	if OS.has_feature("editor"):
		var project := ProjectSettings.globalize_path("res://").trim_suffix("/")
		return '"%s" --headless --path "%s" -- update' % [exe, project]
	return '"%s" --headless -- update' % exe


static func service_text() -> String:
	return """[Unit]
Description=itch on Deck: update the installed games

[Service]
Type=oneshot
ExecStart=%s
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


static func _systemctl(arguments: Array) -> int:
	var all: PackedStringArray = ["--user"]
	for a: String in arguments:
		all.append(a)
	return OS.execute("systemctl", all)
