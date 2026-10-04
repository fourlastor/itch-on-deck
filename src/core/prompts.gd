class_name Prompts
extends RefCounted
## The questions the butler daemon asks while it works (SPEC.md section
## 4.4), answered by asking the user. The update run never registers these,
## so butler gets a refusal there and the matter is left for the app.


static func register() -> void:
	Butler.set_handler("PickUpload", _pick_upload)
	Butler.set_handler("PickManifestAction", _pick_action)
	Butler.set_handler("AcceptLicense", _accept_license)
	Butler.set_handler("PrereqsFailed", _prereqs_failed)
	Butler.set_handler("AllowSandboxSetup", _allow_sandbox)
	# Device sign-in: nothing about this machine is sent to itch.io.
	Butler.set_handler("Profile.LoginWithDevice.RequestDeviceInfo", func(_p: Dictionary) -> Dictionary:
		return {"deviceInfo": ""})


static func _pick_upload(params: Dictionary) -> Dictionary:
	var uploads: Array = params.get("uploads", [])
	var names: Array = uploads.map(func(u: Dictionary) -> String:
		return "%s · %s" % [GameOps.upload_name(u), Format.size(float(u.get("size", 0)))])
	var index: int = await Nav.choose("Which upload?", "More than one upload of this game fits this machine.", names)
	return {"index": index}


static func _pick_action(params: Dictionary) -> Dictionary:
	var actions: Array = params.get("actions", [])
	var names: Array = actions.map(func(a: Dictionary) -> String: return str(a.get("name", "Start")))
	var index: int = await Nav.choose("What should be started?", "This game offers more than one thing to start.", names)
	return {"index": index}


static func _accept_license(params: Dictionary) -> Dictionary:
	var text := str(params.get("text", ""))
	if text.length() > 900:
		text = text.substr(0, 900) + " ..."
	var yes: bool = await Nav.confirm("This game comes with a licence", text, "Accept", "Do not accept", true)
	return {"accept": yes}


static func _prereqs_failed(params: Dictionary) -> Dictionary:
	var yes: bool = await Nav.confirm("Something the game needs did not install",
		"%s The game may not work without it." % str(params.get("error", "")), "Start it anyway", "Do not start", true)
	return {"continue": yes}


static func _allow_sandbox(_params: Dictionary) -> Dictionary:
	var yes: bool = await Nav.confirm("Set up the sandbox?",
		"This game asks to run in a sandbox, which has to be set up once on this machine.", "Set it up", "Do not", true)
	return {"allow": yes}
