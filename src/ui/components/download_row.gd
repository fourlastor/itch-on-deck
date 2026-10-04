extends Button
## One line of the download queue: a waiting item, or one that failed.

var download: Dictionary = {}


func setup(d: Dictionary, sub: String, right: String) -> void:
	download = d
	var game: Dictionary = d.get("game", {})
	%Cover.show_entry(GameEntry.for_game(game), false, false)
	%Title.text = str(game.get("title", "Untitled"))
	%Sub.text = sub
	%Right.text = right
