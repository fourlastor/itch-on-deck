class_name AppSteamRow
extends RefCounted
## How the row that puts the app in Steam reads, in Settings and on the
## sign-in screen. Once Steam has the app, the row says so and offers
## nothing: there is nothing left to add.

const ICON_ADD := preload("res://assets/icons/steam_add.svg")
const ICON_IN := preload("res://assets/icons/steam_in.svg")


## Fills the row. `plain_state` is what its right end says while the app is
## not in Steam. Returns true when Steam has the app.
static func show(row: ActionRow, plain_state: String) -> bool:
	var there := Butler.demo == null and Steam.app_entry_found()
	if there:
		row.set_row("In Steam", "itch on Deck is in the Steam library")
	elif Butler.demo == null and Steam.app_was_added():
		# Steam was asked, and its file does not show the entry (yet, or any more).
		row.set_row("Add itch on Deck to Steam", "Steam was asked before")
	else:
		row.set_row("Add itch on Deck to Steam", plain_state)
	# A row with no symbol in its scene stays without one.
	if row.symbol != null:
		row.symbol = ICON_IN if there else ICON_ADD
	return there
