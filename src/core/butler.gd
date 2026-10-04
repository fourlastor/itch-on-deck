extends Node
## The butler daemon: one child process, spoken to in JSON-RPC 2.0 over its
## standard streams, one message per line (SPEC.md section 4.2).
##
##     var res := await Butler.request("Version.Get")
##     if Butler.failed(res):
##         print(Butler.error_text(res))
##     else:
##         print(res.result.versionString)
##
## Traffic goes three ways: requests from the app, notifications from the
## daemon (the `notified` signal), and requests from the daemon that the app
## must answer (`set_handler`).

signal notified(method: String, params: Dictionary)
signal stopped

const ERR_NOT_RUNNING := -1
const ERR_STOPPED := -2
const READ_CHUNK := 65536

## A stand-in for the daemon, used by the demo mode and the screenshots.
var demo: RefCounted = null

var _pipe: FileAccess = null
var _stderr: FileAccess = null
var _pid := 0
var _out := PackedByteArray()
var _err := PackedByteArray()
var _next_id := 1
var _pending: Dictionary = {}
var _handlers: Dictionary = {}
var _exit_poll := 0.0
var _debug := OS.get_environment("ITCH_ON_DECK_DEBUG") != ""


class Pending:
	extends RefCounted
	signal done(response: Dictionary)
	var method := ""


static func failed(response: Dictionary) -> bool:
	return response.has("error")


static func error_code(response: Dictionary) -> int:
	if not response.has("error"):
		return 0
	return int(response.error.get("code", 0))


static func error_text(response: Dictionary) -> String:
	if not response.has("error"):
		return ""
	return str(response.error.get("message", "butler gave no reason"))


func is_running() -> bool:
	return demo != null or _pid != 0


## Starts the daemon. It ends by itself when this app's process ends
## (--destiny-pid), so a crash of the app leaves nothing behind.
func start(butler_path: String) -> bool:
	if is_running():
		return true
	Paths.ensure_dir(Paths.db_path().get_base_dir())
	var args := PackedStringArray([
		"--json",
		"--dbpath", Paths.db_path(),
		"daemon",
		"--transport", "stdio",
		"--destiny-pid", str(OS.get_process_id()),
	])
	var info := OS.execute_with_pipe(butler_path, args, false)
	if info.is_empty():
		return false
	_pipe = info["stdio"]
	_stderr = info["stderr"]
	_pid = info["pid"]
	_out.clear()
	_err.clear()
	_exit_poll = 0.0
	return true


func stop() -> void:
	if _pid == 0:
		return
	_send({"jsonrpc": "2.0", "id": _take_id(), "method": "Meta.Shutdown", "params": {}})
	_on_exit()


## Sends a request and waits for its answer: a Dictionary with either
## "result" or "error" ({ code, message }).
func request(method: String, params: Dictionary = {}) -> Dictionary:
	if demo != null:
		await get_tree().process_frame
		return demo.handle(method, params)
	if _pid == 0:
		return {"error": {"code": ERR_NOT_RUNNING, "message": "butler is not running"}}
	var id := _take_id()
	var pending := Pending.new()
	pending.method = method
	_pending[id] = pending
	_send({"jsonrpc": "2.0", "id": id, "method": method, "params": params})
	var response: Dictionary = await pending.done
	return response


## Registers the answer to a request the daemon makes (PickUpload, ...).
## The handler takes the params and returns a Dictionary; it may await.
func set_handler(method: String, handler: Callable) -> void:
	_handlers[method] = handler


func clear_handler(method: String) -> void:
	_handlers.erase(method)


func _take_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


func _process(delta: float) -> void:
	if _pid == 0:
		return
	_out = _pump(_pipe, _out, _on_line)
	_err = _pump(_stderr, _err, _on_stderr_line)
	_exit_poll += delta
	if _exit_poll >= 1.0:
		_exit_poll = 0.0
		if OS.get_process_exit_code(_pid) != -1 or not OS.is_process_running(_pid):
			# One last read: the daemon may have written before it ended.
			_out = _pump(_pipe, _out, _on_line)
			_on_exit()


func _exit_tree() -> void:
	stop()


## Reads what the pipe holds and hands over every complete line.
func _pump(pipe: FileAccess, buffer: PackedByteArray, on_line: Callable) -> PackedByteArray:
	if pipe == null:
		return buffer
	for i in 64:
		var chunk := pipe.get_buffer(READ_CHUNK)
		if chunk.is_empty():
			break
		buffer.append_array(chunk)
	var start := 0
	while true:
		var newline := buffer.find(10, start)
		if newline == -1:
			break
		on_line.call(buffer.slice(start, newline).get_string_from_utf8())
		start = newline + 1
	if start > 0:
		buffer = buffer.slice(start)
	return buffer


func _on_line(line: String) -> void:
	if line.strip_edges() == "":
		return
	var json := JSON.new()
	if json.parse(line) != OK or not (json.data is Dictionary):
		if _debug:
			printerr("[butler] ", line)
		return
	var msg: Dictionary = json.data
	if _debug:
		printerr("[rpc <] ", _clip(line))
	if msg.has("method"):
		var params: Dictionary = {}
		if msg.get("params") is Dictionary:
			params = msg["params"]
		if msg.has("id") and msg["id"] != null:
			_serve(msg["id"], str(msg["method"]), params)
		else:
			notified.emit(str(msg["method"]), params)
	elif msg.has("id") and msg["id"] != null:
		var id := int(msg["id"])
		if _pending.has(id):
			var pending: Pending = _pending[id]
			_pending.erase(id)
			if msg.get("error") is Dictionary:
				pending.done.emit({"error": msg["error"]})
			elif msg.get("result") is Dictionary:
				pending.done.emit({"result": msg["result"]})
			else:
				pending.done.emit({"result": {}})


func _on_stderr_line(line: String) -> void:
	if _debug and line.strip_edges() != "":
		printerr("[butler] ", line)


func _serve(id: Variant, method: String, params: Dictionary) -> void:
	var handler: Callable = _handlers.get(method, Callable())
	if not handler.is_valid():
		_send({"jsonrpc": "2.0", "id": id, "error": {"code": -32601, "message": "itch on Deck does not answer " + method}})
		return
	var result: Variant = await handler.call(params)
	_send({"jsonrpc": "2.0", "id": id, "result": result if result is Dictionary else {}})


func _send(msg: Dictionary) -> void:
	if _pipe == null:
		return
	var line := JSON.stringify(_ints(msg))
	if _debug:
		printerr("[rpc >] ", _clip(_redacted(msg, line)))
	_pipe.store_string(line + "\n")
	_pipe.flush()


func _on_exit() -> void:
	if _pid == 0:
		return
	_pid = 0
	if _pipe != null:
		_pipe.close()
	if _stderr != null:
		_stderr.close()
	_pipe = null
	_stderr = null
	var waiting := _pending.values()
	_pending.clear()
	for pending: Pending in waiting:
		pending.done.emit({"error": {"code": ERR_STOPPED, "message": "butler stopped"}})
	stopped.emit()


## Godot reads every JSON number as a float and writes 5.0 for it; butler
## refuses "5.0" where it expects a whole number. So whole floats go out as
## integers.
static func _ints(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			if is_finite(f) and f == floorf(f) and absf(f) < 9.0e15:
				return int(f)
			return f
		TYPE_DICTIONARY:
			var out := {}
			for key: Variant in value:
				out[key] = _ints(value[key])
			return out
		TYPE_ARRAY:
			var out := []
			for item: Variant in value:
				out.append(_ints(item))
			return out
	return value


## A login request carries the API key: never print it.
static func _redacted(msg: Dictionary, line: String) -> String:
	var method := str(msg.get("method", ""))
	if method.begins_with("Profile.Login"):
		return '{"method":"%s","params":"(not shown)"}' % method
	return line


static func _clip(text: String) -> String:
	return text if text.length() <= 600 else text.substr(0, 600) + " ..."
