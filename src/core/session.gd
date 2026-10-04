extends Node
## Who is signed in (SPEC.md section 3.1). butler keeps the login in its
## database, so signing in happens once; this node only remembers which
## profile is in use.

signal changed

var profile: Dictionary = {}


func is_signed_in() -> bool:
	return not profile.is_empty()


func profile_id() -> int:
	return int(profile.get("id", 0))


func user_name() -> String:
	var user: Dictionary = profile.get("user", {})
	var display := str(user.get("displayName", ""))
	return display if display != "" else str(user.get("username", ""))


## The file `butler login` writes, also read by an installed itch app.
static func saved_key_path() -> String:
	return Paths.config_home().path_join("itch/butler_creds")


static func has_saved_key() -> bool:
	return FileAccess.file_exists(saved_key_path())


## Comes back to the profile used last time, if butler still has it.
func resume() -> bool:
	var wanted := Config.profile_id()
	var listed: Dictionary = await Butler.request("Profile.List")
	if Butler.failed(listed):
		return false
	var profiles: Array = listed.result.get("profiles", [])
	if profiles.is_empty():
		return false
	var pick: Dictionary = profiles[0]
	for p: Dictionary in profiles:
		if int(p.get("id", 0)) == wanted:
			pick = p
	var res: Dictionary = await Butler.request("Profile.UseSavedLogin", {"profileId": int(pick.get("id", 0))})
	if Butler.failed(res):
		return false
	_set_profile(res.result.get("profile", {}))
	return is_signed_in()


## Returns "" when signed in, or the reason it did not work.
func login_with_api_key(key: String) -> String:
	key = key.strip_edges()
	if key == "":
		return "No key was entered."
	var res: Dictionary = await Butler.request("Profile.LoginWithAPIKey", {"apiKey": key})
	if Butler.failed(res):
		return Butler.error_text(res)
	_set_profile(res.result.get("profile", {}))
	return "" if is_signed_in() else "itch.io did not return a profile."


func login_with_saved_key() -> String:
	var path := saved_key_path()
	if not FileAccess.file_exists(path):
		return "There is no saved key at %s." % Paths.display(path)
	return await login_with_api_key(FileAccess.get_file_as_string(path))


## Signing out removes the profile from butler's database (R3).
func logout() -> void:
	if not is_signed_in():
		return
	await Butler.request("Profile.Forget", {"profileId": profile_id()})
	profile = {}
	Config.set_value("profile_id", 0)
	changed.emit()


func _set_profile(p: Dictionary) -> void:
	profile = p
	if not p.is_empty():
		Config.set_value("profile_id", int(p.get("id", 0)))
	changed.emit()
