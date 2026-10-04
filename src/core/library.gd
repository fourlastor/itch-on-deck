extends Node
## What the lists show (SPEC.md section 3.2): the installed games, the owned
## ones, the collections, the user's own projects and the search results,
## each as GameEntry items. butler caches what it fetched, so with no
## connection the lists still fill, marked as possibly out of date (R8).

signal list_changed(list: String)
signal caves_changed
signal updates_changed

const INSTALLED := "installed"
const OWNED := "owned"
const COLLECTIONS := "collections"
const PROJECTS := "projects"
const SEARCH := "search"
const COLLECTION_GAMES := "collection_games"

const PAGE := 100

## list name -> Array of GameEntry
var entries: Dictionary = {}
## list name -> true when butler could not refresh it
var out_of_date: Dictionary = {}
## list name -> Unix time of the last successful refresh
var refreshed_at: Dictionary = {}
## list name -> butler's reason, when the list could not be read at all
var problems: Dictionary = {}
## cave id -> GameUpdate, as CheckUpdate returned it
var updates: Dictionary = {}
var caves: Array = []
var last_update_check := 0
var search_query := ""
var open_collection: Dictionary = {}

var _cave_by_game: Dictionary = {}
var _owned: Dictionary = {}
var _projects: Dictionary = {}
var _loading: Dictionary = {}


func _ready() -> void:
	for list: String in [INSTALLED, OWNED, COLLECTIONS, PROJECTS, SEARCH, COLLECTION_GAMES]:
		entries[list] = []


func clear() -> void:
	for list: String in entries:
		entries[list] = []
	out_of_date.clear()
	problems.clear()
	refreshed_at.clear()
	updates.clear()
	caves.clear()
	_cave_by_game.clear()
	_owned.clear()
	_projects.clear()
	search_query = ""
	open_collection = {}


func list(name: String) -> Array:
	return entries.get(name, [])


func is_loading(name: String) -> bool:
	return _loading.get(name, false)


func cave_for_game(game_id: int) -> Dictionary:
	return _cave_by_game.get(game_id, {})


func update_for_cave(cave_id: String) -> Dictionary:
	return updates.get(cave_id, {})


## Builds the entry of one game from everything known about it.
func entry_for(game: Dictionary) -> GameEntry:
	var e := GameEntry.for_game(game)
	_decorate(e)
	return e


# --- installed -------------------------------------------------------------

func refresh_installed() -> void:
	var fetched := await _fetch_pages("Fetch.Caves", {"profileId": Session.profile_id(), "sortBy": "lastTouched"}, false, false)
	if fetched.error != "":
		return
	caves = fetched.items
	_cave_by_game.clear()
	for cave: Dictionary in caves:
		var game: Dictionary = cave.get("game", {})
		var game_id := int(game.get("id", 0))
		if SelfUpdate.is_own_cave(cave):
			continue
		if not _cave_by_game.has(game_id):
			_cave_by_game[game_id] = cave
	_rebuild_installed()
	# The other lists show the installed state too.
	for other: String in [OWNED, PROJECTS, SEARCH, COLLECTION_GAMES]:
		for e: GameEntry in entries[other]:
			_decorate(e)
		list_changed.emit(other)
	caves_changed.emit()


func _rebuild_installed() -> void:
	var out: Array = []
	for cave: Dictionary in caves:
		# The app's own folder is butler's to update, not a game to show.
		if SelfUpdate.is_own_cave(cave):
			continue
		var e := GameEntry.for_cave(cave)
		_decorate(e)
		out.append(e)
	entries[INSTALLED] = out
	refreshed_at[INSTALLED] = int(Time.get_unix_time_from_system())
	list_changed.emit(INSTALLED)


# --- owned, projects, collections ------------------------------------------

func load_owned(force_fresh := false) -> void:
	await _load_list(OWNED, "Fetch.ProfileOwnedKeys", {"profileId": Session.profile_id()}, force_fresh,
		func(items: Array) -> Array:
			var out: Array = []
			_owned.clear()
			for key: Dictionary in items:
				var game: Variant = key.get("game")
				if not (game is Dictionary):
					continue
				_owned[int(game.get("id", 0))] = true
				out.append(entry_for(game))
			return out)


func load_projects(force_fresh := false) -> void:
	await _load_list(PROJECTS, "Fetch.ProfileGames", {"profileId": Session.profile_id()}, force_fresh,
		func(items: Array) -> Array:
			var out: Array = []
			_projects.clear()
			for item: Dictionary in items:
				var game: Variant = item.get("game")
				if not (game is Dictionary):
					continue
				_projects[int(game.get("id", 0))] = bool(item.get("published", true))
				out.append(entry_for(game))
			return out)
	# A draft shows as one in the other lists as well.
	for e: GameEntry in entries[INSTALLED]:
		_decorate(e)
	list_changed.emit(INSTALLED)


func load_collections(force_fresh := false) -> void:
	await _load_list(COLLECTIONS, "Fetch.ProfileCollections", {"profileId": Session.profile_id()}, force_fresh,
		func(items: Array) -> Array:
			var out: Array = []
			for c: Dictionary in items:
				out.append(GameEntry.for_collection(c))
			return out)


func load_collection_games(collection: Dictionary, force_fresh := false) -> void:
	open_collection = collection
	entries[COLLECTION_GAMES] = []
	list_changed.emit(COLLECTION_GAMES)
	var params := {"profileId": Session.profile_id(), "collectionId": int(collection.get("id", 0))}
	await _load_list(COLLECTION_GAMES, "Fetch.Collection.Games", params, force_fresh,
		func(items: Array) -> Array:
			var out: Array = []
			for item: Dictionary in items:
				var game: Variant = item.get("game")
				if game is Dictionary:
					out.append(entry_for(game))
			return out)
	await _resolve_ownership(COLLECTION_GAMES)


# --- search ----------------------------------------------------------------

## Looks through the games this account can reach: owned, in its
## collections, its own projects and the installed ones. butler 15.31 has no
## request that searches itch.io itself: its "Search.Games" reads only its
## own database, so the spec's search of public pages (R6) is not possible
## through butler.
func search(query: String) -> String:
	search_query = query.strip_edges()
	if search_query == "":
		entries[SEARCH] = []
		list_changed.emit(SEARCH)
		return ""
	_loading[SEARCH] = true
	list_changed.emit(SEARCH)
	var res: Dictionary = await Butler.request("Search.Local", {"profileId": Session.profile_id(), "query": search_query})
	_loading[SEARCH] = false
	if Butler.failed(res):
		out_of_date[SEARCH] = true
		list_changed.emit(SEARCH)
		return Butler.error_text(res)
	var out: Array = []
	for game: Variant in res.result.get("games", []):
		if game is Dictionary:
			out.append(entry_for(game))
	entries[SEARCH] = out
	out_of_date.erase(SEARCH)
	refreshed_at[SEARCH] = int(Time.get_unix_time_from_system())
	list_changed.emit(SEARCH)
	await _resolve_ownership(SEARCH)
	return ""


# --- updates ---------------------------------------------------------------

## Looks for updates (R18). With no cave ids, every installed game is checked
## and butler leaves out the pinned ones.
func check_updates(cave_ids: Array = []) -> String:
	var params: Dictionary = {"verbose": false}
	if not cave_ids.is_empty():
		params["caveIds"] = cave_ids
	var res: Dictionary = await Butler.request("CheckUpdate", params)
	if Butler.failed(res):
		return Butler.error_text(res)
	if cave_ids.is_empty():
		updates.clear()
	else:
		for id: String in cave_ids:
			updates.erase(id)
	for update: Dictionary in res.result.get("updates", []):
		updates[str(update.get("caveId", ""))] = update
	# The app is not updated through a cave (see SelfUpdate).
	updates.erase(SelfUpdate.cave_id())
	last_update_check = int(Time.get_unix_time_from_system())
	_refresh_states()
	updates_changed.emit()
	return ""


func forget_update(cave_id: String) -> void:
	if updates.erase(cave_id):
		_refresh_states()
		updates_changed.emit()


## Makes butler's copy of a game fresh by fetching again the list it is in
## (see GameOps.request_for_game).
func freshen(game_id: int) -> void:
	var params := {"profileId": Session.profile_id()}
	if _projects.has(game_id) or not _owned.has(game_id):
		var fetched := await _fetch_pages("Fetch.ProfileGames", params, true, true)
		for item: Dictionary in fetched.items:
			var game: Variant = item.get("game")
			if game is Dictionary and int(game.get("id", 0)) == game_id:
				return
	await _fetch_pages("Fetch.ProfileOwnedKeys", params, true, true)


# --- helpers ---------------------------------------------------------------

## Fills a list from butler's cache first, then from itch.io when the cache
## is old. A failed refresh keeps what was shown and marks it out of date.
func _load_list(name: String, method: String, params: Dictionary, force_fresh: bool, build: Callable) -> void:
	if _loading.get(name, false):
		return
	_loading[name] = true
	list_changed.emit(name)
	var fetched := await _fetch_pages(method, params, force_fresh, true)
	if fetched.error == "":
		entries[name] = build.call(fetched.items)
		list_changed.emit(name)
		if fetched.stale and not force_fresh:
			var again := await _fetch_pages(method, params, true, true)
			if again.error == "":
				entries[name] = build.call(again.items)
				fetched = again
			else:
				fetched.stale = true
	if fetched.error != "":
		problems[name] = fetched.error
	else:
		problems.erase(name)
	if fetched.error != "" or fetched.stale:
		out_of_date[name] = true
	else:
		out_of_date.erase(name)
		refreshed_at[name] = int(Time.get_unix_time_from_system())
	_loading[name] = false
	list_changed.emit(name)


func _fetch_pages(method: String, params: Dictionary, fresh: bool, with_fresh: bool) -> Dictionary:
	var items: Array = []
	var stale := false
	var cursor: Variant = null
	while true:
		var p := params.duplicate()
		p["limit"] = PAGE
		if with_fresh:
			p["fresh"] = fresh
		if cursor != null:
			p["cursor"] = cursor
		var res: Dictionary = await Butler.request(method, p)
		if Butler.failed(res):
			return {"items": items, "stale": true, "error": Butler.error_text(res)}
		items.append_array(res.result.get("items", []))
		stale = stale or bool(res.result.get("stale", false))
		cursor = res.result.get("nextCursor")
		if cursor == null or str(cursor) == "":
			break
	return {"items": items, "stale": stale, "error": ""}


## Marks the paid games of a list that the account does not own. butler
## answers this from its own database, with no network.
func _resolve_ownership(name: String) -> void:
	var changed := false
	for e: GameEntry in entries[name].duplicate():
		if e.is_free() or e.mine or e.is_installed() or _owned.has(e.id()):
			continue
		var res: Dictionary = await Butler.request("Fetch.GameOwnership", {"profileId": Session.profile_id(), "gameId": e.id()})
		var owned := not Butler.failed(res) and bool(res.result.get("owned", false))
		if owned:
			_owned[e.id()] = true
		if e.owned != owned:
			e.owned = owned
			changed = true
	if changed:
		list_changed.emit(name)


func _decorate(e: GameEntry) -> void:
	if e.is_collection():
		return
	var game_id := e.id()
	if e.cave.is_empty() or not _cave_by_game.has(game_id) or str(_cave_by_game[game_id].get("id")) != e.cave_id():
		e.cave = _cave_by_game.get(game_id, {})
	e.update = updates.get(e.cave_id(), {}) if e.is_installed() else {}
	e.mine = _projects.has(game_id)
	e.draft = e.mine and not bool(_projects[game_id])


func _refresh_states() -> void:
	for name: String in entries:
		for e: GameEntry in entries[name]:
			_decorate(e)
		list_changed.emit(name)
