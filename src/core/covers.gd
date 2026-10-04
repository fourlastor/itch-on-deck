extends Node
## Cover images. Each is downloaded once and kept under
## ~/.cache/itch-on-deck/covers, so the lists also show covers with no
## connection (R8, R28).

const MAX_PARALLEL := 3
const MAX_WIDTH := 880

var _memory: Dictionary = {}
var _waiting: Dictionary = {}
var _queue: Array[String] = []
var _active := 0


## Calls `done` with a Texture2D, or with null when there is no usable image.
func fetch(url: String, done: Callable) -> void:
	if url == "":
		done.call(null)
		return
	if _memory.has(url):
		done.call(_memory[url])
		return
	if url.begins_with("demo:"):
		var made := _demo_texture(url)
		_memory[url] = made
		done.call(made)
		return
	var path := _disk_path(url)
	if FileAccess.file_exists(path):
		var texture := _load_file(path)
		_memory[url] = texture
		done.call(texture)
		return
	if _waiting.has(url):
		_waiting[url].append(done)
		return
	_waiting[url] = [done]
	_queue.append(url)
	_pump()


## The file a cover is cached in, for uses outside the app (Steam artwork).
func cached_file(url: String) -> String:
	var path := _disk_path(url)
	return path if FileAccess.file_exists(path) else ""


func _pump() -> void:
	while _active < MAX_PARALLEL and not _queue.is_empty():
		var url: String = _queue.pop_front()
		_active += 1
		_download(url)


func _download(url: String) -> void:
	var http := HTTPRequest.new()
	http.timeout = 30.0
	add_child(http)
	var texture: Texture2D = null
	if http.request(url) == OK:
		var done: Array = await http.request_completed
		if done[0] == HTTPRequest.RESULT_SUCCESS and done[1] == 200:
			var body: PackedByteArray = done[3]
			var path := _disk_path(url)
			Paths.ensure_dir(path.get_base_dir())
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null:
				file.store_buffer(body)
				file.close()
			texture = _texture_from(body)
	http.queue_free()
	_active -= 1
	_memory[url] = texture
	var callbacks: Array = _waiting.get(url, [])
	_waiting.erase(url)
	for callback: Callable in callbacks:
		if callback.is_valid():
			callback.call(texture)
	_pump()


func _disk_path(url: String) -> String:
	return Paths.covers_dir().path_join(url.sha1_text())


func _load_file(path: String) -> Texture2D:
	return _texture_from(FileAccess.get_file_as_bytes(path))


func _texture_from(bytes: PackedByteArray) -> Texture2D:
	if bytes.size() < 12:
		return null
	var image := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		err = image.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = image.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[8] == 0x57:
		err = image.load_webp_from_buffer(bytes)
	# Anything else (an animated GIF with no still) is left as no image.
	if err != OK or image.is_empty():
		return null
	if image.get_width() > MAX_WIDTH:
		var height := int(float(image.get_height()) * MAX_WIDTH / float(image.get_width()))
		image.resize(MAX_WIDTH, height, Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Stand-in art for the demo mode: "demo:<base hex>:<accent hex>:<shape>".
func _demo_texture(url: String) -> Texture2D:
	var parts := url.split(":")
	var base := Color.html(parts[1]) if parts.size() > 1 else Color.DIM_GRAY
	var accent := Color.html(parts[2]) if parts.size() > 2 else base.lightened(0.3)
	var shape := parts[3] if parts.size() > 3 else "disc"
	var w := 315
	var h := 250
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(base)
	match shape:
		"band":
			image.fill_rect(Rect2i(0, int(h * 0.62), w, int(h * 0.38)), accent)
		"bars":
			for x: float in [0.18, 0.43, 0.68]:
				image.fill_rect(Rect2i(int(w * x), int(h * 0.25), int(w * 0.14), h), accent)
		"stripes":
			image.fill_rect(Rect2i(0, int(h * 0.46), w, int(h * 0.11)), accent)
			image.fill_rect(Rect2i(0, int(h * 0.64), w, int(h * 0.05)), accent)
		"blocks":
			for cell: Vector2 in [Vector2(0.22, 0.16), Vector2(0.54, 0.16), Vector2(0.22, 0.56), Vector2(0.54, 0.56)]:
				image.fill_rect(Rect2i(int(w * cell.x), int(h * cell.y), int(w * 0.24), int(w * 0.24)), accent)
		"steps":
			image.fill_rect(Rect2i(0, int(h * 0.45), int(w * 0.4), h), accent)
			image.fill_rect(Rect2i(int(w * 0.4), int(h * 0.68), int(w * 0.3), h), accent)
		_:
			var centre := Vector2(w * 0.72, h * 0.72)
			var radius := w * 0.3
			for y in h:
				for x in w:
					if Vector2(x, y).distance_to(centre) <= radius:
						image.set_pixel(x, y, accent)
	return ImageTexture.create_from_image(image)
