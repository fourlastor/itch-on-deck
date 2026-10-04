extends Control
## Shown while a game runs (R15). The app does as little as it can until
## the game exits: it redraws nothing and sleeps between looks at butler.

const IDLE_SLEEP_USEC := 250000

var _failed := false
var _started := false
var _normal_sleep := 0


func open(args: Dictionary) -> void:
	var entry: GameEntry = args["entry"]
	%Cover.show_entry(entry, false, false)
	%Title.text = entry.title()
	%State.text = "Starting"
	%HintBar.set_hints([], "")
	Butler.notified.connect(_on_notified)
	_normal_sleep = OS.low_processor_usage_mode_sleep_usec
	OS.low_processor_usage_mode_sleep_usec = IDLE_SLEEP_USEC
	var problem: String = await GameOps.launch(entry.cave_id())
	OS.low_processor_usage_mode_sleep_usec = _normal_sleep
	Butler.notified.disconnect(_on_notified)
	if not is_inside_tree():
		return
	if problem == "" or _started:
		# It ran. How it ended (closed, crashed, killed) is the game's affair.
		Nav.pop()
		return
	_failed = true
	%State.text = "Not started"
	%Note.text = problem
	%HintBar.set_hints([[Glyph.Kind.B, "Back"]], "")


## B does nothing while the game runs: the game has the controller.
func back() -> bool:
	return not _failed


func _on_notified(method: String, _params: Dictionary) -> void:
	match method:
		"LaunchRunning":
			_started = true
			%State.text = "Running"
		"LaunchExited":
			%State.text = "Exited"
		"PrereqsStarted":
			%State.text = "Installing what the game needs"
