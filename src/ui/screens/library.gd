extends Control
## The list screens: Installed, Owned, Collections, My projects and Search
## (SPEC.md section 9), each one shelf of covers. The shoulder buttons
## change list, Y searches itch.io, X filters the list by text.

const LISTS: Array[String] = [Library.INSTALLED, Library.OWNED, Library.COLLECTIONS, Library.PROJECTS, Library.SEARCH]
const SEARCH_TAB := 4
const EMPTY_TEXT := {
	Library.INSTALLED: "Nothing is installed yet. Games you install from the other lists appear here.",
	Library.OWNED: "No owned games were found for this account.",
	Library.COLLECTIONS: "This account has no collections.",
	Library.PROJECTS: "This account has no projects.",
	Library.SEARCH: "Press Y to search the games this account can reach: owned, in your collections, your own projects and the installed ones.",
	Library.COLLECTION_GAMES: "This collection has no games.",
}

var tab := 0

var _in_collection := false
var _filters: Dictionary = {}
var _editing := ""
var _asked: Dictionary = {}

@onready var _top: Control = %TopBar
@onready var _shelf: Shelf = %Shelf
@onready var _detail: Control = %Detail
@onready var _hints: HintBar = %HintBar
@onready var _input: LineEdit = %Input


func _ready() -> void:
	_top.tab_selected.connect(show_tab)
	_top.downloads_pressed.connect(func() -> void: Nav.push("downloads"))
	_top.settings_pressed.connect(func() -> void: Nav.push("settings"))
	_shelf.focus_moved.connect(func(_i: int) -> void: _show_focused())
	_shelf.activated.connect(_on_activated)
	_input.text_submitted.connect(_on_text_submitted)
	Library.list_changed.connect(_on_list_changed)
	Downloads.changed.connect(_show_download_count)
	_show_download_count()
	show_tab(0)


func first_focus() -> Control:
	return _shelf


func resume() -> void:
	_refill(true)


func back() -> bool:
	if _editing != "":
		_stop_editing()
		return true
	if _in_collection:
		_in_collection = false
		_refill(false)
		return true
	if _filter() != "":
		_filters.erase(_list_name())
		_refill(false)
		return true
	return false


func show_tab(index: int) -> void:
	tab = posmod(index, LISTS.size())
	_in_collection = false
	_stop_editing()
	_top.set_tab(tab)
	var list_name := LISTS[tab]
	if not _asked.has(list_name):
		_asked[list_name] = true
		match list_name:
			Library.OWNED:
				Library.load_owned()
			Library.PROJECTS:
				Library.load_projects()
			Library.COLLECTIONS:
				Library.load_collections()
	_refill(false)


func _unhandled_input(event: InputEvent) -> void:
	if Nav.dialog_open():
		return
	if _editing != "":
		# The field takes Enter by itself; a controller's A has to be handed to it.
		if event is InputEventJoypadButton and event.is_action_pressed(&"ui_accept"):
			get_viewport().set_input_as_handled()
			_on_text_submitted(_input.text)
		return
	if event.is_action_pressed(&"list_prev"):
		get_viewport().set_input_as_handled()
		show_tab(tab - 1)
	elif event.is_action_pressed(&"list_next"):
		get_viewport().set_input_as_handled()
		show_tab(tab + 1)
	elif event.is_action_pressed(&"search"):
		get_viewport().set_input_as_handled()
		if tab != SEARCH_TAB:
			show_tab(SEARCH_TAB)
		_start_editing("search")
	elif event.is_action_pressed(&"filter") and tab != SEARCH_TAB:
		get_viewport().set_input_as_handled()
		_start_editing("filter")


func _list_name() -> String:
	return Library.COLLECTION_GAMES if _in_collection else LISTS[tab]


func _filter() -> String:
	return str(_filters.get(_list_name(), ""))


func _refill(keep_place: bool) -> void:
	var list_name := _list_name()
	var all: Array = Library.list(list_name)
	var wanted := _filter().to_lower()
	var shown: Array = all
	if wanted != "":
		shown = all.filter(func(e: GameEntry) -> bool: return e.title().to_lower().contains(wanted))
	_shelf.show_installed = list_name != Library.INSTALLED
	if Library.is_loading(list_name) and all.is_empty():
		_shelf.set_empty_text("Reading the list.")
	elif all.is_empty() and str(Library.problems.get(list_name, "")).contains("does not permit"):
		_shelf.set_empty_text("itch.io does not let this sign-in read this list. A sign-in with an API key from itch.io (Settings, API keys) is allowed to.")
	elif wanted != "" and shown.is_empty():
		_shelf.set_empty_text("No title in this list contains “%s”." % _filter())
	elif list_name == Library.SEARCH and Library.search_query != "":
		_shelf.set_empty_text("Nothing this account can reach has “%s” in its title." % Library.search_query)
	else:
		_shelf.set_empty_text(EMPTY_TEXT[list_name])
	_shelf.set_entries(shown, keep_place)
	_show_status()
	_show_focused()


func _on_list_changed(list_name: String) -> void:
	if list_name == _list_name() and is_visible_in_tree():
		_refill(true)


func _on_activated(_index: int) -> void:
	var entry := _shelf.current()
	if entry == null:
		return
	if entry.is_collection():
		_in_collection = true
		Library.load_collection_games(entry.collection)
		_refill(false)
	else:
		Nav.push("game", {"entry": entry, "from": _crumb()})


func _crumb() -> String:
	if _in_collection:
		return str(Library.open_collection.get("title", "Collection"))
	return ["Installed", "Owned", "Collections", "My projects", "Search"][tab]


# --- the row under the top bar: search field, filter, or the offline note ---

func _show_status() -> void:
	var list_name := _list_name()
	var searching := tab == SEARCH_TAB and not _in_collection
	var field := _editing != "" or searching or _filter() != ""
	var offline: bool = Library.out_of_date.has(list_name) and not Library.problems.get(list_name, "").contains("does not permit") and not field
	%Banner.visible = offline
	%Field.visible = field
	%StatusRow.visible = field or offline
	%Spacer.visible = not %StatusRow.visible
	%Gap.custom_minimum_size.y = 12.0 if %StatusRow.visible else 16.0
	if offline:
		var saved := int(Library.refreshed_at.get(list_name, 0))
		if saved > 0:
			%BannerText.text = "This list was saved %s and may be out of date. Installed games still play." % Format.moment(saved)
		else:
			%BannerText.text = "This list is the one saved earlier and may be out of date. Installed games still play."
	if field and _editing == "":
		if searching:
			_input.text = Library.search_query
			_input.placeholder_text = "Press Y and type what to look for"
			var count := Library.list(Library.SEARCH).size()
			%FieldNote.text = ("%d found" % count) if Library.search_query != "" else ""
		else:
			_input.text = _filter()
			%FieldNote.text = "Filter of this list"


func _start_editing(what: String) -> void:
	_editing = what
	%StatusRow.visible = true
	%Field.visible = true
	%Banner.visible = false
	%Spacer.visible = false
	if what == "search":
		_input.placeholder_text = "Search your games"
		_input.text = Library.search_query
		%FieldNote.text = "Owned, collections, projects, installed"
	else:
		_input.placeholder_text = "Show only titles that contain"
		_input.text = _filter()
		%FieldNote.text = "Leave it empty to show everything"
	_input.grab_focus()
	_input.edit()
	Keyboard.show()
	_show_hints()


func _stop_editing() -> void:
	if _editing == "":
		return
	_editing = ""
	_input.unedit()
	_shelf.grab_focus()
	_show_status()
	_show_hints()


func _on_text_submitted(text: String) -> void:
	var what := _editing
	_editing = ""
	_input.unedit()
	_shelf.grab_focus()
	if what == "search":
		Library.search(text)
	elif what == "filter":
		if text.strip_edges() == "":
			_filters.erase(_list_name())
		else:
			_filters[_list_name()] = text.strip_edges()
	_refill(false)


# --- the panel under the shelf ---------------------------------------------

func _show_focused() -> void:
	var entry := _shelf.current()
	if entry == null:
		_detail.clear()
	elif entry.is_collection():
		var c := entry.collection
		var changed := Format.parse_date(c.get("updatedAt", ""))
		var no_chips: Array[StringName] = []
		_detail.show_content(entry.title(), no_chips,
			"A collection of %d games." % int(c.get("gamesCount", 0)),
			[["Games", str(int(c.get("gamesCount", 0)))], ["Last changed", Format.moment(changed)]])
	else:
		_detail.show_content(entry.title(), _chips(entry), entry.short_text(), _facts(entry))
	_show_hints()


func _chips(e: GameEntry) -> Array[StringName]:
	var chips: Array[StringName] = []
	if e.draft:
		chips.append(&"draft")
	if e.is_installed():
		if _list_name() != Library.INSTALLED:
			chips.append(&"installed")
		if e.has_update():
			chips.append(&"update")
		if e.is_pinned():
			chips.append(&"pinned")
		if Config.get_value("steam", {}).has(e.cave_id()):
			chips.append(&"in_steam")
	elif not e.is_installable_here():
		chips.append(&"not_installable")
	elif not e.owned:
		chips.append(&"not_owned")
	else:
		chips.append(&"not_installed")
	return chips


func _facts(e: GameEntry) -> Array:
	var facts: Array = []
	if e.is_installed():
		if e.has_update():
			facts.append(["Update", GameText.update_summary(e.update)])
		facts.append(["On disk", Format.size(e.installed_size())])
		facts.append(["Location", Paths.display(e.install_folder().get_base_dir())])
		facts.append(["Played", Format.play_time(e.seconds_run())])
	else:
		facts.append(["Uploads for", e.platform_names()])
		facts.append(["Page", GameText.page_summary(e)])
	return facts


func _show_hints() -> void:
	var entry := _shelf.current()
	var hints: Array = []
	if _editing != "":
		hints.append([Glyph.Kind.A, "Search" if _editing == "search" else "Filter"])
		hints.append([Glyph.Kind.B, "Cancel"])
		_hints.set_hints(hints, "")
		return
	if entry != null:
		hints.append([Glyph.Kind.A, "Open the collection" if entry.is_collection() else "Open"])
	if tab == SEARCH_TAB and not _in_collection:
		hints.append([Glyph.Kind.Y, "Change the search" if Library.search_query != "" else "Search"])
	else:
		hints.append([Glyph.Kind.X, "Filter this list"])
		hints.append([Glyph.Kind.Y, "Search"])
	if _in_collection:
		hints.append([Glyph.Kind.B, "Collections"])
	elif _filter() != "":
		hints.append([Glyph.Kind.B, "Clear the filter"])
	_hints.set_hints(hints, _position_text())


func _position_text() -> String:
	var list_name := _list_name()
	var parts: PackedStringArray = []
	if not _shelf.entries.is_empty():
		parts.append("%d of %d" % [_shelf.index + 1, _shelf.entries.size()])
	if _in_collection:
		parts.append(str(Library.open_collection.get("title", "")))
	if list_name == Library.SEARCH:
		parts.append("from the games this account can reach")
	elif Library.out_of_date.has(list_name):
		var saved := int(Library.refreshed_at.get(list_name, 0))
		parts.append(("saved " + Format.moment(saved)) if saved > 0 else "may be out of date")
	elif Library.refreshed_at.has(list_name):
		parts.append("refreshed " + Format.moment(int(Library.refreshed_at[list_name])))
	return " · ".join(parts)


func _show_download_count() -> void:
	_top.set_download_count(Downloads.pending_count())
