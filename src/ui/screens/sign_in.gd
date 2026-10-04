extends Control
## Signing in (SPEC.md section 3.1). The browser way needs no key: the user
## allows the app on itch.io's own page. An API key, typed or read from the
## file `butler login` writes, is the other way.
##
## Device sign-in (a QR code approved on a phone) is not here yet: itch.io
## only lets approved applications use it.
##
## This is the first screen of a new install, so the row that puts the app
## in Steam is here too: the rest can then be done in Gaming Mode.

var _busy := false
var _app_in_steam := false

@onready var _oauth: OAuthLogin = %OAuth
@onready var _hints: HintBar = %HintBar


func _ready() -> void:
	%Browser.pressed.connect(_on_browser)
	%UseKey.pressed.connect(_on_key)
	%Saved.pressed.connect(_on_saved)
	%Key.text_submitted.connect(func(_t: String) -> void: _on_key())
	%Key.text_changed.connect(func(_t: String) -> void: _show_rows())
	%Key.editing_toggled.connect(func(on: bool) -> void:
		if on:
			Keyboard.show())
	%AddApp.pressed.connect(_on_add_app)
	_oauth.finished.connect(_on_oauth_finished)
	for control: Control in [%Browser, %Key, %UseKey, %Saved, %AddApp]:
		control.focus_entered.connect(_show_hints)
	%Browser.visible = OAuthLogin.is_configured()
	%Saved.visible = Session.has_saved_key()
	%Saved.state = Paths.display(Session.saved_key_path())
	%AddApp.visible = Steam.is_available()
	%SteamGap.visible = %AddApp.visible
	_show_steam_row()
	_show_rows()
	_show_hints()


func first_focus() -> Control:
	return %Browser if %Browser.visible else %Key


func back() -> bool:
	if _oauth.is_waiting():
		_oauth.cancel()
		_say("Stopped waiting for the browser.")
		_show_rows()
		return true
	# There is nowhere to go back to from here: B offers to close the app.
	return false


func _unhandled_input(event: InputEvent) -> void:
	# A text field starts by itself on Enter or a click; a controller's A has
	# to be handed to it. A second A brings the keyboard back if it was closed.
	if event is InputEventJoypadButton and event.is_action_pressed(&"ui_accept") and %Key.has_focus():
		get_viewport().set_input_as_handled()
		if %Key.is_editing():
			Keyboard.show()
		else:
			%Key.edit()


func _show_rows() -> void:
	var has_key: bool = %Key.text.strip_edges() != ""
	%UseKey.disabled = not has_key
	%UseKey.state = "Checks the key with itch.io" if has_key else "Needs a key first"
	%Browser.state = "Waiting for the browser. B stops." if _oauth.is_waiting() else "Opens itch.io to allow this app"


func _show_steam_row() -> void:
	_app_in_steam = AppSteamRow.show(%AddApp, "To open it in Gaming Mode")


func _on_add_app() -> void:
	if _app_in_steam:
		_say(Steam.APP_THERE)
		return
	var said: String = await Steam.put_app_in_steam(Nav)
	if said != "":
		_say(said)
	_show_steam_row()
	# Steam writes a new entry down a moment after it is asked; then the row
	# can say that the app is there.
	await get_tree().create_timer(1.5).timeout
	if is_inside_tree():
		_show_steam_row()
		_show_hints()


func _on_browser() -> void:
	if _busy:
		return
	var problem := _oauth.start()
	if problem != "":
		_say(problem)
	else:
		_say("itch.io is open in the browser. Log in there if it asks, then allow itch on Deck.")
	_show_rows()
	_show_hints()


func _on_oauth_finished(problem: String) -> void:
	_show_rows()
	if problem != "":
		_say(problem)
		return
	var key := _oauth.key
	_oauth.key = ""
	await _login(key)


func _on_key() -> void:
	var key: String = %Key.text.strip_edges()
	if key == "":
		_say("No key was entered.")
		return
	%Key.unedit()
	await _login(key)


func _on_saved() -> void:
	if _busy:
		return
	_busy = true
	_say("Checking the saved key with itch.io.")
	var problem: String = await Session.login_with_saved_key()
	_busy = false
	if problem != "":
		_say(_explain(problem))


func _login(key: String) -> void:
	if _busy:
		return
	_busy = true
	_say("Checking the key with itch.io.")
	var problem: String = await Session.login_with_api_key(key)
	_busy = false
	if problem != "":
		_say(_explain(problem))
	else:
		%Key.text = ""


## butler's reasons, said so that the next step is clear.
func _explain(problem: String) -> String:
	if problem.contains("does not permit"):
		return "itch.io refused this key: it is not allowed to read the profile. A key made by `butler login` only pushes builds. Make one on itch.io under Settings, API keys, or sign in with the browser."
	if problem.contains("invalid key") or problem.contains("401") or problem.contains("403"):
		return "itch.io did not accept this key (%s)." % problem
	if problem.to_lower().contains("no such host") or problem.to_lower().contains("dial tcp") or problem.to_lower().contains("timeout"):
		return "itch.io could not be reached. Check the connection and try again."
	return "Not signed in: %s" % problem


func _say(text: String) -> void:
	%Status.text = text


func _show_hints() -> void:
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var hints: Array = []
	if focused == %Key:
		hints.append([Glyph.Kind.A, "Type the key"])
	elif focused == %AddApp and _app_in_steam:
		pass
	elif focused is ActionRow:
		hints.append([Glyph.Kind.A, focused.title])
	hints.append([Glyph.Kind.B, "Stop waiting" if _oauth.is_waiting() else "Close the app"])
	_hints.set_hints(hints, "Not signed in")
