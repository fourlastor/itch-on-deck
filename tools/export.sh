#!/bin/sh
# Exports the app for Linux into build/linux, the folder that goes to itch.io:
# one binary with the project inside it, and the licences next to it.
#
# The Godot editor is looked for at the repo root (where the publish workflow
# unpacks it), then at $GODOT, then on PATH.
set -eu
cd "$(dirname "$0")/.."

GODOT_BIN="${GODOT:-}"
if [ -z "$GODOT_BIN" ]; then
	GODOT_BIN=$(ls Godot_v*_mono_linux_x86_64/Godot_v*_mono_linux.x86_64 2>/dev/null | head -n 1 || true)
fi
if [ -z "$GODOT_BIN" ]; then
	GODOT_BIN=$(command -v godot || true)
fi
if [ -z "$GODOT_BIN" ]; then
	echo "No Godot editor found: set GODOT to its path." >&2
	exit 1
fi

# The version of a published build is the commit it was made from; the app
# compares it with the page's newest build before it lets butler adopt its
# folder. A build made by hand is "dev" and never updates itself.
echo "${VERSION:-dev}" > version.txt
sh tools/build_update_helper.sh

OUT=build/linux
rm -rf "$OUT"
mkdir -p "$OUT/licenses"
"$GODOT_BIN" --headless --path . --export-release "Linux" "$OUT/itch-on-deck.x86_64"
test -x "$OUT/itch-on-deck.x86_64"

# The fonts ship under the SIL Open Font License, which has to travel with them;
# the engine's own notices are written by the app itself.
cp assets/fonts/OFL-*.txt "$OUT/licenses/"
cp tools/update-helper/THIRD_PARTY_LICENSES "$OUT/licenses/UPDATE-HELPER.txt"
"$OUT/itch-on-deck.x86_64" --headless --audio-driver Dummy -- licenses "$(pwd)/$OUT/licenses/GODOT.txt"
ls -l "$OUT" "$OUT/licenses"
