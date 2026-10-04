class_name OAuthLogin
extends Node
## Signing in through a browser, with no key to type: itch.io's OAuth
## "implicit" flow with a loopback address (https://itch.io/docs/api/oauth).
##
## The app opens itch.io's permission page, in Steam's own browser in
## Gaming Mode and in the default browser elsewhere. When the user allows
## it, itch.io sends the browser to http://127.0.0.1:<PORT>, where this node
## listens. The key arrives in the part of the address after "#", which
## only the page can read, so the page posts it back here.

signal finished(problem: String)

## The OAuth application registered on itch.io for this app. Its redirect
## URI must be exactly REDIRECT. config.json can override it with
## "oauth_client_id", which is how a fork uses its own application.
const CLIENT_ID := "6adb0fecddd84671685c7ea6c3fbb72e"
const PORT := 34881
const REDIRECT := "http://127.0.0.1:34881"
## profile: who the user is, their games, keys and collections.
## game:view:uploads: downloading what they own, develop, or what is free.
const SCOPES := "profile game:view:uploads"
const TIMEOUT := 600.0

const PAGE := """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>itch on Deck</title>
<style>body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
background:#1a1816;color:#f4efe8;font:20px/1.4 system-ui,sans-serif}main{max-width:32em;padding:2em}
h1{font-size:2em;margin:0 0 .4em}p{color:#b9b0a4;margin:0}</style></head>
<body><main><h1 id="title">Finishing the sign-in</h1><p id="text"></p></main>
<script>
var q = new URLSearchParams(location.hash.slice(1));
var key = q.get("access_token");
var title = document.getElementById("title"), text = document.getElementById("text");
function say(a, b) { title.textContent = a; text.textContent = b; }
if (!key) {
  say("itch.io sent no key", "Go back to itch on Deck and try again.");
} else {
  history.replaceState(null, "", "/");
  fetch("/key", {method: "POST", headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: "access_token=" + encodeURIComponent(key) + "&state=" + encodeURIComponent(q.get("state") || "")})
  .then(function (r) {
    if (r.ok) say("Signed in", "You can close this page and go back to itch on Deck.");
    else say("Not signed in", "itch on Deck did not accept the answer. Try again from the app.");
  })
  .catch(function () { say("Not signed in", "itch on Deck is no longer waiting. Try again from the app."); });
}
</script></body></html>
"""

## The key itch.io issued, once `finished` fired with "".
var key := ""

var _server: TCPServer = null
var _peers: Array[StreamPeerTCP] = []
var _buffers: Dictionary = {}
var _state := ""
var _waited := 0.0


static func client_id() -> String:
	var override := str(Config.get_value("oauth_client_id", ""))
	return override if override != "" else CLIENT_ID


## What the app asks itch.io for. ITCH_ON_DECK_OAUTH_SCOPE replaces it,
## which is how other sets of permissions are tried.
static func scopes() -> String:
	var override := OS.get_environment("ITCH_ON_DECK_OAUTH_SCOPE")
	return override if override != "" else SCOPES


## What a key is allowed to do, as itch.io reports it: { scopes, error }.
static func key_info(host: Node, api_key: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	host.add_child(http)
	var out := {"scopes": [], "error": ""}
	if http.request("https://api.itch.io/credentials/info", PackedStringArray(["Authorization: Bearer " + api_key])) != OK:
		out.error = "The request could not be made."
	else:
		var done: Array = await http.request_completed
		var body: PackedByteArray = done[3]
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if done[0] != HTTPRequest.RESULT_SUCCESS or done[1] != 200 or not (parsed is Dictionary):
			out.error = "itch.io answered %d." % done[1]
		else:
			out.scopes = parsed.get("scopes", [])
	http.queue_free()
	return out


static func is_configured() -> bool:
	return client_id() != ""


## Starts listening and opens the browser. Returns "" or why it could not.
func start() -> String:
	cancel()
	key = ""
	_server = TCPServer.new()
	if _server.listen(PORT, "127.0.0.1") != OK:
		_server = null
		return "Port %d on this machine is in use, so the browser cannot answer the app." % PORT
	_state = "%08x%08x" % [randi(), randi()]
	_waited = 0.0
	var url := "https://itch.io/user/oauth?client_id=%s&scope=%s&response_type=token&redirect_uri=%s&state=%s" % [
		client_id().uri_encode(), scopes().uri_encode(), REDIRECT.uri_encode(), _state]
	# In Gaming Mode there is no desktop browser: Steam's own one is asked.
	var target := ("steam://openurl/" + url) if Keyboard.under_steam() else url
	if OS.shell_open(target) != OK:
		cancel()
		return "No browser could be opened."
	return ""


func cancel() -> void:
	for peer in _peers:
		peer.disconnect_from_host()
	_peers.clear()
	_buffers.clear()
	if _server != null:
		_server.stop()
		_server = null


func is_waiting() -> bool:
	return _server != null


func _process(delta: float) -> void:
	if _server == null:
		return
	_waited += delta
	if _waited > TIMEOUT:
		cancel()
		finished.emit("Nothing came back from the browser in ten minutes.")
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		_peers.append(peer)
		_buffers[peer] = PackedByteArray()
	for peer: StreamPeerTCP in _peers.duplicate():
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_drop(peer)
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var got: Array = peer.get_data(available)
			if got[0] == OK:
				var buffer: PackedByteArray = _buffers[peer]
				buffer.append_array(got[1])
				_buffers[peer] = buffer
				_try_answer(peer)
		if _server == null:
			return


func _try_answer(peer: StreamPeerTCP) -> void:
	var text := (_buffers[peer] as PackedByteArray).get_string_from_utf8()
	var split := text.find("\r\n\r\n")
	if split == -1:
		return
	var head := text.substr(0, split)
	var body := text.substr(split + 4)
	var request := head.get_slice("\r\n", 0).split(" ")
	if request.size() < 2:
		_respond(peer, 400, "text/plain", "Bad request")
		return
	if request[0] == "POST" and request[1] == "/key":
		var length := 0
		for line in head.split("\r\n"):
			if line.to_lower().begins_with("content-length:"):
				length = int(line.get_slice(":", 1).strip_edges())
		if body.to_utf8_buffer().size() < length:
			return
		var fields := _form(body)
		if str(fields.get("state", "")) != _state or str(fields.get("access_token", "")) == "":
			_respond(peer, 400, "text/plain", "Not the answer this app is waiting for")
			return
		key = str(fields["access_token"])
		_respond(peer, 200, "text/plain", "ok")
		# Let the answer leave before the listener closes.
		await get_tree().create_timer(0.3).timeout
		cancel()
		finished.emit("")
	elif request[0] == "GET":
		_respond(peer, 200, "text/html; charset=utf-8", PAGE)
	else:
		_respond(peer, 405, "text/plain", "Not allowed")


func _respond(peer: StreamPeerTCP, code: int, kind: String, content: String) -> void:
	var payload := content.to_utf8_buffer()
	var status := "OK" if code == 200 else "Error"
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [
		code, status, kind, payload.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(payload)
	_buffers[peer] = PackedByteArray()


func _drop(peer: StreamPeerTCP) -> void:
	_peers.erase(peer)
	_buffers.erase(peer)


static func _form(body: String) -> Dictionary:
	var out := {}
	for pair in body.split("&", false):
		var eq := pair.find("=")
		if eq == -1:
			continue
		out[pair.substr(0, eq).uri_decode()] = pair.substr(eq + 1).replace("+", " ").uri_decode()
	return out


func _exit_tree() -> void:
	cancel()
