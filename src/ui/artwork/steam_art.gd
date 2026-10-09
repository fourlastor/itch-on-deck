class_name SteamArt
extends RefCounted
## The library images Steam shows for the app's own entry. They are the
## scenes beside this file, drawn into pictures when the entry needs them,
## so the project stores no pictures of them.

## What Steam ends each picture's file name with, then its scene and size.
## The logo is the name alone on nothing; Steam lays it over the hero.
const PICTURES := {
	"": ["wide", Vector2i(920, 430)],
	"p": ["tall", Vector2i(600, 900)],
	"_hero": ["hero", Vector2i(1920, 620)],
	"_logo": ["logo", Vector2i(1040, 240)],
}
const SEE_THROUGH := "_logo"

## The pictures for the app's page on itch.io: the cover and the banner that
## stands in for the title. The app does not use them; --art draws them
## beside the Steam ones, to be uploaded by hand.
const PAGE := {
	"cover": Vector2i(630, 500),
	"banner": Vector2i(1920, 400),
}


## Draws them all: the ending of the file name, then the picture. `host` is
## any node of the running app. Empty when there is no window to draw with.
static func render(host: Node) -> Dictionary:
	var out := {}
	if DisplayServer.get_name() == "headless":
		return out
	for ending: String in PICTURES:
		var image := await _draw(host, "steam_%s" % PICTURES[ending][0], PICTURES[ending][1])
		if ending == SEE_THROUGH:
			image = _cut_out(image)
		else:
			image.convert(Image.FORMAT_RGB8)
		out[ending] = image
	return out


## Draws one of the scenes beside this file into a picture of `size`.
static func _draw(host: Node, scene_name: String, size: Vector2i) -> Image:
	var scene: PackedScene = load("res://src/ui/artwork/%s.tscn" % scene_name)
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(scene.instantiate())
	host.add_child(viewport)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image


## A picture drawn on nothing comes back with its colours dimmed by their own
## transparency, and a PNG wants them as they are; without this the letters
## get a dark rim. The empty border goes too, so Steam shows the name large.
static func _cut_out(image: Image) -> Image:
	image.convert(Image.FORMAT_RGBA8)
	var used := image.get_used_rect()
	if used.has_area():
		image = image.get_region(used)
	var bytes := image.get_data()
	for i in range(0, bytes.size(), 4):
		var alpha := bytes[i + 3]
		if alpha > 0 and alpha < 255:
			for channel in 3:
				bytes[i + channel] = mini(255, bytes[i + channel] * 255 / alpha)
	return Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, bytes)


## Saves them in a folder under plain names, and the page's pictures with
## them; for looking at them, and for uploading the page's ones.
static func save_all(host: Node, folder: String) -> void:
	var pictures := await render(host)
	for ending: String in pictures:
		var path := folder.path_join("steam_%s.png" % PICTURES[ending][0])
		print("art ", path, " ", pictures[ending].get_size(), " ", error_string(pictures[ending].save_png(path)))
	for name: String in PAGE:
		var image := await _draw(host, "page_%s" % name, PAGE[name])
		image.convert(Image.FORMAT_RGB8)
		var path := folder.path_join("page_%s.png" % name)
		print("art ", path, " ", image.get_size(), " ", error_string(image.save_png(path)))
