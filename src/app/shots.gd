class_name Shots
extends RefCounted
## Development aid: shows one screen and saves a picture of it, so a change
## to the look can be checked without a controller in hand.
##
##     itch-on-deck -- --demo --screen=library:1 --shot=/tmp/owned.png


static func take(host: Node, options: Dictionary) -> void:
	var tree := host.get_tree()
	await tree.create_timer(0.3).timeout
	var spec := str(options.get("screen", "")).split(":")
	var arg := spec[1] if spec.size() > 1 else ""
	match spec[0]:
		"library":
			Nav.top().show_tab(int(arg))
			if arg == "4":
				await Library.search("tide")
		"move":
			Nav.top().show_tab(1)
			await tree.create_timer(0.2).timeout
			Nav.top().get_node("%Shelf").move(int(arg))
		"collection":
			Nav.top().show_tab(2)
			await tree.create_timer(0.3).timeout
			Nav.top().get_node("%Shelf").activated.emit(0)
		"game", "install", "uninstall", "owned":
			var list_name := Library.INSTALLED if spec[0] in ["game", "uninstall"] else Library.OWNED
			if list_name == Library.OWNED:
				await Library.load_owned()
			var entry: GameEntry = Library.list(list_name)[int(arg) if arg != "" else 0]
			var screen := Nav.push("game", {"entry": entry, "from": "Installed"})
			if spec[0] == "install":
				await tree.create_timer(0.4).timeout
				screen.start_install()
			elif spec[0] == "uninstall":
				await tree.create_timer(0.4).timeout
				screen.ask_uninstall()
		"downloads", "settings", "sign_in", "setup", "running":
			var pushed := Nav.push(spec[0], {"demo": true})
			if arg != "" and pushed.has_method("show_section"):
				pushed.show_section(int(arg))
	await tree.create_timer(float(options.get("wait", "0.9"))).timeout
	var image := host.get_viewport().get_texture().get_image()
	var path := str(options["shot"])
	var err := image.save_png(path)
	print("shot ", path, " ", image.get_size(), " ", error_string(err))
	tree.quit()
