extends Control
## Settings (SPEC.md section 9). The sections are on the left, each with its
## present value under its name; the focused section's controls are on the
## right. A enters a section, B comes back out.

const LocationScene := preload("res://src/ui/components/location_row.tscn")
const RunScene := preload("res://src/ui/components/run_row.tscn")
const RUNS_SHOWN := 4

var _section := 0
var _busy := false
var _app_in_steam := false

@onready var _hints: HintBar = %HintBar
@onready var _sections: Array[Node] = %Sections.get_children()
@onready var _panes: Array[Node] = [%UpdatesPane, %LocationsPane, %BandwidthPane, %AppPane, %ButlerPane, %AccountPane]


func _ready() -> void:
	%Header.back_pressed.connect(Nav.pop)
	for i in _sections.size():
		_sections[i].focus_entered.connect(show_section.bind(i))
		_sections[i].pressed.connect(_enter_section.bind(i))
	%ScheduleChoice.value_changed.connect(_on_schedule_changed)
	%LimitChoice.value_changed.connect(_on_limit_changed)
	%SelfChoice.value_changed.connect(_on_self_update_changed)
	%CheckAll.pressed.connect(_on_check_all)
	%AddLocation.pressed.connect(_on_add_location)
	%AddApp.pressed.connect(_on_add_app)
	%CheckApp.pressed.connect(_on_check_app)
	%CheckButler.pressed.connect(_on_check_butler)
	%SignOut.pressed.connect(_on_sign_out)
	for control: Control in [%ScheduleChoice, %LimitChoice, %SelfChoice, %CheckAll, %AddLocation, %AddApp, %CheckApp, %CheckButler, %SignOut]:
		control.focus_entered.connect(_show_hints)


func open(_args: Dictionary) -> void:
	%ScheduleChoice.select(Config.SCHEDULES.find(Config.schedule()))
	%LimitChoice.select(maxi(Bandwidth.CHOICES.find(int(Config.get_value("bandwidth_kbps", 0))), 0))
	%SelfChoice.select(1 if SelfUpdate.enabled() else 0)
	%ButlerVersion.setup("Version in use", ButlerInstall.VERSION, true)
	%AppVersion.setup("This copy", "Version %s" % SelfUpdate.version() if SelfUpdate.is_a_build() else "Run from the project's sources", true)
	%Who.text = "Signed in as %s." % Session.user_name()
	_show_values()
	_show_runs()
	_show_locations()
	show_section(0)


func first_focus() -> Control:
	return _sections[_section]


func resume() -> void:
	_show_values()
	_show_locations()


## B inside a section comes back to the list of sections.
func back() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and %Panes.is_ancestor_of(focused):
		_sections[_section].grab_focus()
		return true
	return false


## Also used by the screenshot helper.
func show_section(index: int) -> void:
	_section = clampi(index, 0, _panes.size() - 1)
	for i in _panes.size():
		_panes[i].visible = i == _section
		_sections[i].set_pressed_no_signal(i == _section)
	_say("")
	_wire_focus()
	_show_hints()


func _enter_section(index: int) -> void:
	show_section(index)
	var controls := FocusOrder.focusable(_panes[index])
	if not controls.is_empty():
		controls[0].grab_focus()


## Up and down stay inside the list of sections, or inside the open section;
## right goes into the section, left comes back out of it.
func _wire_focus() -> void:
	var controls := FocusOrder.focusable(_panes[_section])
	FocusOrder.column(controls, _sections[_section])
	FocusOrder.column(_sections, null, controls[0] if not controls.is_empty() else null)


func _show_values() -> void:
	_sections[0].value = Schedule.label(Config.schedule())
	_sections[2].value = Bandwidth.label(int(Config.get_value("bandwidth_kbps", 0)))
	_app_in_steam = AppSteamRow.show(%AddApp, "Not in the Steam library")
	var app_parts: PackedStringArray = ["Updates itself" if SelfUpdate.enabled() else "Does not update itself"]
	app_parts.append("in Steam" if _app_in_steam else "not in Steam")
	_sections[3].value = ", ".join(app_parts)
	_sections[4].value = "v" + ButlerInstall.VERSION
	_sections[5].value = Session.user_name()
	var checked := Library.last_update_check
	var known := Library.updates.size()
	if checked > 0:
		%CheckAll.state = "%s · checked %s" % ["No update known" if known == 0 else ("1 update known" if known == 1 else "%d updates known" % known), Format.moment(checked)]
	else:
		%CheckAll.state = "Not checked yet"
	if not SelfUpdate.is_a_build():
		%CheckApp.state = "Only a published build updates itself"
	elif SelfUpdate.newest_version == "":
		%CheckApp.state = "Not checked yet"
	elif SelfUpdate.has_update():
		%CheckApp.state = "Version %s is out" % SelfUpdate.newest_version
	else:
		%CheckApp.state = "This is the newest version"
	var next := Schedule.next_run() if Butler.demo == null else 0
	%Header.set_note(("Next update run %s" % Format.moment(next)) if next > 0 else "")


func _show_runs() -> void:
	for child in %Runs.get_children():
		child.queue_free()
	var runs := UpdateState.runs() if Butler.demo == null else _demo_runs()
	%RunsCaption.text = "Last runs" if not runs.is_empty() else "No update run yet"
	var shown := mini(runs.size(), RUNS_SHOWN)
	for i in shown:
		var run: Dictionary = runs[i]
		var row := RunScene.instantiate()
		%Runs.add_child(row)
		row.setup(Format.moment(int(run.get("at", 0))).capitalize(), UpdateState.describe(run), i == shown - 1)


func _show_locations() -> void:
	var locations: Array = await InstallLocations.for_games()
	if not is_inside_tree():
		return
	for child in %LocationList.get_children():
		child.queue_free()
	var free_total := 0.0
	for location: Dictionary in locations:
		var id := str(location.get("id", ""))
		var games := Library.caves.filter(func(c: Dictionary) -> bool:
			return str(c.get("installInfo", {}).get("installLocation", "")) == id).size()
		var row := LocationScene.instantiate()
		%LocationList.add_child(row)
		row.setup(location, games)
		row.pressed.connect(_on_location_pressed.bind(location, games))
		row.focus_entered.connect(_show_hints)
		var info: Variant = location.get("sizeInfo")
		if info is Dictionary:
			free_total += float(info.get("freeSize", 0))
	_sections[1].value = "%s · %s free" % ["1 folder" if locations.size() == 1 else "%d folders" % locations.size(), Format.size(free_total)]
	_wire_focus()


# --- what the controls do --------------------------------------------------

func _on_schedule_changed(index: int) -> void:
	Config.set_value("schedule", Config.SCHEDULES[index])
	_apply_schedule()


func _on_self_update_changed(index: int) -> void:
	Config.set_value("self_update", index == 1)
	_apply_schedule()
	if index == 1 and not SelfUpdate.is_a_build():
		_say("This copy runs from the project's sources, so there is nothing to update. A published build updates itself.")


func _on_check_app() -> void:
	if _busy or Butler.demo != null:
		return
	if not SelfUpdate.is_a_build():
		_say("This copy runs from the project's sources, so there is nothing to update.")
		return
	_busy = true
	%CheckApp.state = "Asking itch.io"
	var newest: Dictionary = await SelfUpdate.look()
	_busy = false
	if newest.error != "":
		_say("The app's page could not be read: %s" % newest.error)
	elif not SelfUpdate.has_update():
		_say("This is the newest version.")
	elif SelfUpdate.enabled():
		_say("Version %s is out. The update run puts it in the next time it finds the app closed." % newest.version)
	else:
		_say("Version %s is out. Switch on \"Update itch on Deck itself\" to have it put in while the app is closed." % newest.version)
	_show_values()


func _apply_schedule() -> void:
	var problem := Schedule.apply() if Butler.demo == null else ""
	_say(problem)
	_show_values()


func _on_limit_changed(index: int) -> void:
	Config.set_value("bandwidth_kbps", Bandwidth.CHOICES[index])
	await Bandwidth.apply()
	_show_values()


func _on_check_all() -> void:
	if _busy:
		return
	_busy = true
	%CheckAll.state = "Looking for updates"
	var problem: String = await Library.check_updates()
	_busy = false
	_say(("The check did not work: %s" % problem) if problem != "" else "")
	_show_values()


func _on_add_location() -> void:
	var candidates := _location_candidates()
	if candidates.is_empty():
		_say("No other disk was found. Put in an SD card, or mount a disk, and try again.")
		return
	var names: Array = candidates.map(func(path: String) -> String: return Paths.display(path))
	var pick: int = await Nav.choose("Add an install location", "A folder named itch is made on the disk you pick.", names)
	if pick < 0:
		return
	var problem: String = await InstallLocations.add(candidates[pick])
	if problem == "":
		await InstallLocations.remember()
	_say(problem)
	_show_locations()


func _on_location_pressed(location: Dictionary, games: int) -> void:
	if games > 0:
		_say("%s holds %s. Uninstall them before removing the location." % [
			InstallLocations.label(location), "1 game" if games == 1 else "%d games" % games])
		return
	var yes: bool = await Nav.confirm("Remove this location?",
		"%s will no longer be offered for installs. The folder itself is not deleted." % Paths.display(str(location.get("path", ""))),
		"Remove", "Keep it", true)
	if yes:
		_say(await InstallLocations.remove(str(location.get("id", ""))))
		_show_locations()
		%AddLocation.grab_focus()


func _on_add_app() -> void:
	if _app_in_steam:
		_say(Steam.APP_THERE)
		return
	var said: String = await Steam.put_app_in_steam(Nav)
	if said != "":
		_say(said)
	_show_values()
	# Steam writes a new entry down a moment after it is asked; then the row
	# can say that the app is there.
	await get_tree().create_timer(1.5).timeout
	if is_inside_tree():
		_show_values()
		_show_hints()


func _on_check_butler() -> void:
	if _busy:
		return
	_busy = true
	%CheckButler.state = "Asking broth.itch.zone"
	var latest: String = await %Installer.latest_version()
	_busy = false
	if latest == "":
		%CheckButler.state = "No answer"
	elif latest == ButlerInstall.VERSION:
		%CheckButler.state = "%s is the newest" % latest
	else:
		%CheckButler.state = "%s is out" % latest
		_say("butler %s is out. This version of the app was tested with %s and keeps using it; a newer app brings a newer butler." % [latest, ButlerInstall.VERSION])


func _on_sign_out() -> void:
	var yes: bool = await Nav.confirm("Sign out?",
		"This removes the login from this machine. The installed games stay, and can be played from Steam where they were added.",
		"Sign out", "Stay signed in", true)
	if yes:
		await Session.logout()


## Folders that could hold games: an "itch" folder on every disk mounted
## under /run/media, which is where SteamOS puts SD cards.
func _location_candidates() -> Array:
	var out: Array = []
	var known: Array = Config.get_value("install_locations", []).map(func(l: Dictionary) -> String: return str(l.get("path", "")))
	var roots: Array = ["/run/media/" + OS.get_environment("USER"), "/run/media"]
	for root: String in roots:
		if not DirAccess.dir_exists_absolute(root):
			continue
		for name in DirAccess.get_directories_at(root):
			var disk := root.path_join(name)
			if disk in roots:
				continue
			var candidate := disk.path_join("itch")
			if not (candidate in known) and not (candidate in out):
				out.append(candidate)
	var home_default := Paths.default_install_location()
	if not (home_default in known):
		out.append(home_default)
	return out


func _say(text: String) -> void:
	%Status.text = text
	%Status.visible = text != ""


func _show_hints() -> void:
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var hints: Array = []
	var inside: bool = focused != null and %Panes.is_ancestor_of(focused)
	if focused is Segmented:
		hints.append([Glyph.Kind.DPAD, "Change"])
	elif focused == %AddApp and _app_in_steam:
		pass
	elif focused is ActionRow:
		hints.append([Glyph.Kind.A, focused.title])
	elif focused != null and focused.get_parent() == %LocationList:
		hints.append([Glyph.Kind.A, "Remove this location"])
	elif focused != null and not inside:
		hints.append([Glyph.Kind.A, "Open"])
	hints.append([Glyph.Kind.B, "Back to the sections" if inside else "Back"])
	_hints.set_hints(hints, "")


func _demo_runs() -> Array:
	var now := int(Time.get_unix_time_from_system())
	return [
		{"at": now - 3600 * 2, "updated": [{"title": "Hollow Tide", "version": "build 1177310"}]},
		{"at": now - 3600 * 8, "outcome": "no_connection"},
		{"at": now - 3600 * 20, "updated": [{"title": "Sands of the Duel", "version": "7b8ae68"}], "skipped": [{"title": "Bramble Circuit", "reason": "it was running"}]},
		{"at": now - 3600 * 26, "left": [{"title": "Sixteen Rooms", "reason": "2 possible uploads"}]},
	]
