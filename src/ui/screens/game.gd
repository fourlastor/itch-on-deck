extends Control
## One game (SPEC.md section 9): its cover, facts and states on the left,
## and on the right what can be done with it. Every action row shows the
## present state at its right end.

const ChipScene := preload("res://src/ui/components/chip.tscn")
const FactScene := preload("res://src/ui/components/fact_row.tscn")
const ICON_STEAM_ADD := preload("res://assets/icons/steam_add.svg")
const ICON_STEAM_IN := preload("res://assets/icons/steam_in.svg")
const BLUE := Color("6db6f2")
const LIGHT := Color("f4efe8")

var entry: GameEntry

var _from := "Back"
var _notice := ""
var _busy := false
var _page_uploads: Array = []

@onready var _header: Control = %Header
@onready var _hints: HintBar = %HintBar
@onready var _facts: Array[Node] = [%Fact1, %Fact2, %Fact3, %Fact4]
@onready var _rows: Array[ActionRow] = [%Play, %Update, %Install, %Steam, %Pin, %Uninstall]


func _ready() -> void:
	_header.back_pressed.connect(Nav.pop)
	%Play.pressed.connect(_on_play)
	%Update.pressed.connect(_on_update)
	%Install.pressed.connect(start_install)
	%Steam.pressed.connect(_on_steam)
	%Pin.pressed.connect(_on_pin)
	%Uninstall.pressed.connect(ask_uninstall)
	for row in _rows:
		row.focus_entered.connect(_show_hints)
	Library.caves_changed.connect(_on_state_changed)
	Library.updates_changed.connect(_on_state_changed)
	Downloads.changed.connect(_on_downloads_changed)


func open(args: Dictionary) -> void:
	entry = args["entry"]
	_from = str(args.get("from", "Back"))
	_show()
	if GameText.blocked_reason(entry) != "" and entry.owned:
		_read_page_uploads()


func first_focus() -> Control:
	for row in _rows:
		if row.visible and not row.disabled:
			return row
	return null


func resume() -> void:
	_on_state_changed()


func _on_state_changed() -> void:
	if entry == null:
		return
	var owned := entry.owned
	entry = Library.entry_for(entry.game)
	entry.owned = owned
	_show()
	if not is_instance_valid(get_viewport().gui_get_focus_owner()) or not get_viewport().gui_get_focus_owner().is_visible_in_tree():
		var target := first_focus()
		if target != null and is_visible_in_tree():
			target.grab_focus()


func _on_downloads_changed() -> void:
	if entry != null and is_visible_in_tree():
		_show_actions()


func _show() -> void:
	_header.back_text = _from
	%Cover.show_entry(entry, false, true)
	%Title.text = entry.title()
	%ShortText.text = entry.short_text()
	%ShortText.visible = entry.short_text() != ""
	for child in %Chips.get_children():
		child.queue_free()
	for kind in _chips():
		var chip := ChipScene.instantiate()
		%Chips.add_child(chip)
		chip.setup(kind)
	var facts := _fact_list()
	for i in _facts.size():
		_facts[i].visible = i < facts.size()
		if _facts[i].visible:
			_facts[i].setup(facts[i][0], facts[i][1], i == facts.size() - 1)
	%Notice.visible = _notice != ""
	%NoticeText.text = _notice
	_show_blocked()
	_show_actions()
	_show_hints()


func _chips() -> Array[StringName]:
	var chips: Array[StringName] = []
	if entry.draft:
		chips.append(&"draft")
	if entry.is_installed():
		chips.append(&"installed")
		if entry.has_update():
			chips.append(&"update")
		if entry.is_pinned():
			chips.append(&"pinned")
	elif not entry.is_installable_here():
		chips.append(&"not_installable")
	elif not entry.owned:
		chips.append(&"not_owned")
	else:
		chips.append(&"not_installed")
	return chips


func _fact_list() -> Array:
	var facts: Array = []
	if entry.is_installed():
		facts.append(["Upload", GameOps.upload_name(entry.upload())])
		var build := entry.build()
		if int(build.get("id", 0)) > 0:
			var version := str(build.get("userVersion", ""))
			facts.append(["Installed build", version if version != "" else Format.grouped(int(build.id))])
		facts.append(["On disk", Format.size(entry.installed_size())])
		facts.append(["Location", Paths.display(entry.install_folder().get_base_dir())])
	else:
		facts.append(["Uploads for", entry.platform_names()])
		facts.append(["Page", GameText.page_summary(entry)])
	return facts


## A game that cannot be installed is said to be so plainly, with what its
## page does have (SPEC.md section 6, step 2).
func _show_blocked() -> void:
	var reason := GameText.blocked_reason(entry)
	%Message.visible = reason != ""
	if reason == "":
		return
	%MessageText.text = reason
	for child in %MessageList.get_children():
		child.queue_free()
	%MessageCaption.visible = not _page_uploads.is_empty()
	for i in _page_uploads.size():
		var upload: Dictionary = _page_uploads[i]
		var row := FactScene.instantiate()
		%MessageList.add_child(row)
		var size := Format.size(float(upload.get("size", 0))) if float(upload.get("size", 0)) > 0 else ""
		var what := GameOps.upload_platforms(upload)
		row.setup(GameOps.upload_name(upload), what + (" · " + size if size != "" else ""), i == _page_uploads.size() - 1)


func _read_page_uploads() -> void:
	var got: Dictionary = await GameOps.uploads(entry.id())
	_page_uploads = got.incompatible
	if is_inside_tree():
		_show_blocked()


func _show_actions() -> void:
	var installed := entry.is_installed()
	%Play.visible = installed
	%Update.visible = installed
	%Steam.visible = installed and Steam.is_available()
	%Pin.visible = installed
	%Uninstall.visible = installed
	var download := Downloads.for_game(entry.id())
	%Install.visible = not installed and (entry.can_install() or not download.is_empty())
	if installed:
		%Play.set_row("Play", "Played %s" % Format.play_time(entry.seconds_run()).to_lower() if entry.seconds_run() > 0 else "Not played yet")
		if not download.is_empty():
			%Update.set_row("Updating", _download_state(download))
			%Update.symbol_tint = BLUE
		elif entry.has_update():
			%Update.set_row("Update now", GameText.update_summary(entry.update))
			%Update.symbol_tint = BLUE
		else:
			var checked := Library.last_update_check
			%Update.set_row("Check for updates", ("Last checked %s" % Format.moment(checked)) if checked > 0 else "Not checked yet")
			%Update.symbol_tint = LIGHT
		if Steam.is_in_steam(entry.cave_id()):
			%Steam.set_row("In Steam", "Press A to remove it from Steam")
			%Steam.symbol = ICON_STEAM_IN
		else:
			%Steam.set_row("Add to Steam", "Not in the Steam library")
			%Steam.symbol = ICON_STEAM_ADD
		if entry.is_pinned():
			%Pin.set_row("Unpin this version", "Pinned: updates skip this game")
		else:
			%Pin.set_row("Pin this version", "Off: follows the update schedule")
		%Uninstall.set_row("Uninstall", "Frees %s" % Format.size(entry.installed_size()))
	elif not download.is_empty():
		%Install.set_row("In the download queue", _download_state(download))
	else:
		%Install.set_row("Install", "Choose the upload and where it goes")


func _download_state(download: Dictionary) -> String:
	var p := Downloads.progress_of(download)
	if p.is_empty():
		return "Waiting in the queue"
	return "%d %% · see Downloads" % int(float(p.get("progress", 0)) * 100.0)


func _show_hints() -> void:
	var hints: Array = []
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused is ActionRow and focused.is_visible_in_tree():
		hints.append([Glyph.Kind.A, focused.title])
	hints.append([Glyph.Kind.B, "Back"])
	var right := ""
	if entry != null and entry.is_installed() and Library.last_update_check > 0:
		right = "Checked for updates %s" % Format.moment(Library.last_update_check)
	_hints.set_hints(hints, right)


func _say(text: String) -> void:
	_notice = text
	%Notice.visible = text != ""
	%NoticeText.text = text


# --- actions ----------------------------------------------------------------

func _on_play() -> void:
	_say("")
	Nav.push("running", {"entry": entry})


func _on_update() -> void:
	if _busy:
		return
	if not Downloads.for_game(entry.id()).is_empty():
		Nav.push("downloads")
		return
	_busy = true
	if entry.has_update():
		var choices: Array = entry.update.get("choices", [])
		var pick := 0
		if choices.size() > 1:
			# Several uploads could be the new version: the user decides (R23).
			var names: Array = choices.map(func(c: Dictionary) -> String:
				return "%s · %s" % [GameOps.upload_name(c.get("upload", {})), Format.size(float(c.get("upload", {}).get("size", 0)))])
			pick = await Nav.choose("Which upload is the update?", "butler found more than one that could replace the installed one.", names)
		if pick >= 0 and pick < choices.size():
			var problem: String = await Downloads.queue_update(entry.cave_id(), choices[pick])
			_say(problem if problem != "" else "The update is in the download queue.")
	else:
		_say("Looking for an update.")
		var problem: String = await Library.check_updates([entry.cave_id()])
		if problem != "":
			_say("The check did not work: %s" % problem)
		elif Library.update_for_cave(entry.cave_id()).is_empty():
			_say("No update was found.")
		else:
			_say("")
	_busy = false
	_show_actions()


## Also used by the screenshot helper.
func start_install() -> void:
	if not Downloads.for_game(entry.id()).is_empty():
		Nav.push("downloads")
	else:
		Nav.push("install", {"entry": entry})


func _on_steam() -> void:
	if _busy:
		return
	_busy = true
	if Steam.is_in_steam(entry.cave_id()):
		var problem := Steam.remove_game(entry.cave_id())
		_say(problem if problem != "" else "Removed from Steam. The library shows it after Steam restarts.")
	else:
		var problem := Steam.add_game(entry)
		_say(problem if problem != "" else "Added to Steam. If the library does not show it yet, it will after Steam restarts.")
		if problem == "":
			Steam.apply_artwork(entry)
	_busy = false
	_show_actions()
	_show_hints()


func _on_pin() -> void:
	if _busy:
		return
	_busy = true
	var problem: String = await GameOps.set_pinned(entry.cave_id(), not entry.is_pinned())
	if problem != "":
		_say(problem)
	_busy = false


## Also used by the screenshot helper.
func ask_uninstall() -> void:
	var extra := " and its entry in Steam" if Steam.is_in_steam(entry.cave_id()) else ""
	var body := "This removes the game's folder, %s in %s%s. The game stays in your lists and can be installed again." % [
		Format.size(entry.installed_size()), Paths.display(entry.install_folder().get_base_dir()), extra]
	var yes: bool = await Nav.confirm("Uninstall %s?" % entry.title(), body, "Uninstall", "Keep it", true)
	if not yes:
		return
	var problem: String = await GameOps.uninstall(entry)
	if problem != "":
		_say("The game was not uninstalled: %s" % problem)
	else:
		Nav.pop()
