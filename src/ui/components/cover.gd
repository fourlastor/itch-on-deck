extends Control
## A game's cover with its marks. Until the image is there, and for a page
## with no usable cover, it shows the title on a plain ground.

const BadgeScene := preload("res://src/ui/components/badge.tscn")

var _url := ""

@onready var _mask: Panel = $Mask
@onready var _image: TextureRect = $Mask/Image
@onready var _fallback: Label = $Mask/Fallback
@onready var _badges: HBoxContainer = $Badges


## `marks`: which states to show on the cover. "installed" is left out on the
## Installed list, where it would say nothing. `large` is for the big cover.
func show_entry(entry: GameEntry, show_installed: bool = true, large: bool = false) -> void:
	_fallback.text = entry.title()
	set_image(entry.cover_url())
	var blocked := false
	if not entry.is_collection() and not entry.is_installed():
		blocked = not entry.is_installable_here() or not entry.owned
	_mask.modulate.a = 0.3 if blocked else 1.0
	for child in _badges.get_children():
		child.queue_free()
	if entry.is_collection():
		return
	var kinds: Array[StringName] = []
	if entry.draft:
		kinds.append(&"draft")
	if entry.is_installed() and show_installed:
		kinds.append(&"installed")
	if entry.has_update():
		kinds.append(&"update")
	if entry.is_installed() and entry.is_pinned():
		kinds.append(&"pinned")
	if not entry.is_installed():
		if not entry.is_installable_here():
			kinds.append(&"blocked")
		elif not entry.owned:
			kinds.append(&"not_owned")
	for kind in kinds:
		var badge := BadgeScene.instantiate()
		_badges.add_child(badge)
		badge.setup(kind, large)
	var inset := 14.0 if large else 10.0
	_badges.position = Vector2(inset, inset)


func set_image(url: String) -> void:
	_url = url
	_image.texture = null
	_fallback.visible = true
	if url != "":
		Covers.fetch(url, _on_texture.bind(url))


func _on_texture(texture: Texture2D, url: String) -> void:
	# The node may show another game by the time the image arrives.
	if url != _url:
		return
	_image.texture = texture
	_fallback.visible = texture == null
