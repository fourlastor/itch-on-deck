class_name GameText
extends RefCounted
## The few sentences about a game that more than one screen needs.


## What is known about an update, in a few words.
static func update_summary(update: Dictionary) -> String:
	var choices: Array = update.get("choices", [])
	if choices.size() > 1:
		return "%d possible uploads" % choices.size()
	if choices.is_empty():
		return "A newer version is known"
	var choice: Dictionary = choices[0]
	var build: Variant = choice.get("build")
	if build is Dictionary and int(build.get("id", 0)) > 0:
		var version := str(build.get("userVersion", ""))
		if version != "":
			return "Version %s is known" % version
		return "Build %s is known" % Format.grouped(int(build.get("id", 0)))
	return "A newer upload is known"


static func page_summary(e: GameEntry) -> String:
	if e.draft:
		return "Draft, not public"
	if e.is_free():
		return "Public, free"
	return "Public, paid" if not e.mine else "Public"


## Why a game cannot be installed, or "" when it can.
static func blocked_reason(e: GameEntry) -> String:
	if e.is_installed():
		return ""
	if not e.is_installable_here():
		return "This game has no Linux upload, so it cannot be installed on this machine."
	if not e.owned:
		return "This is a paid game that this account does not own. The app cannot buy games; it can be bought on itch.io."
	return ""
