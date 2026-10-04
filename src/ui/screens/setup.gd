extends Control
## The first launch: the app fetches butler by itself (SPEC.md R27).
## `finished` fires once butler is in place.

signal finished

@onready var _installer: ButlerInstall = %Installer


func _ready() -> void:
	_installer.progress.connect(_on_progress)
	%Retry.pressed.connect(_run)
	%HintBar.set_hints([[Glyph.Kind.B, "Close the app"]], "butler %s" % ButlerInstall.VERSION)


func open(args: Dictionary) -> void:
	if args.has("error"):
		_fail(str(args["error"]))
	elif not args.has("demo"):
		_run()


func first_focus() -> Control:
	return %Retry if %Retry.visible else null


## B offers to close the app: nothing here can be gone back to.
func back() -> bool:
	return false


func _run() -> void:
	%Retry.visible = false
	%Title.text = "Getting butler"
	%Status.text = "Asking broth.itch.zone for butler %s." % ButlerInstall.VERSION
	%HintBar.set_hints([[Glyph.Kind.B, "Close the app"]], "butler %s" % ButlerInstall.VERSION)
	var ok: bool = await _installer.install()
	if ok:
		%Bar.value = 1.0
		%Status.text = "butler %s is in place." % ButlerInstall.VERSION
		finished.emit()
	else:
		_fail(_installer.error)


func _fail(reason: String) -> void:
	%Title.text = "butler is not here yet"
	%Status.text = "%s Nothing was left half-installed." % reason
	%Retry.visible = true
	%Retry.grab_focus.call_deferred()
	%HintBar.set_hints([[Glyph.Kind.A, "Try again"], [Glyph.Kind.B, "Close the app"]], "butler %s" % ButlerInstall.VERSION)


func _on_progress(text: String, fraction: float) -> void:
	%Bar.value = fraction
	%Status.text = "%s: %d %%" % [text, int(fraction * 100.0)]
