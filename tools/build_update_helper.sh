#!/bin/sh
# Embedded into the Godot export, then installed next to the timer launcher.
# Static linking keeps it independent of the Deck's libc version and packages.
set -eu
cd "$(dirname "$0")/.."
CARGO_TARGET_DIR="$(pwd)/build/update-helper"
export CARGO_TARGET_DIR
cargo build --manifest-path tools/update-helper/Cargo.toml --release --locked \
	--target x86_64-unknown-linux-musl
cp "$CARGO_TARGET_DIR/x86_64-unknown-linux-musl/release/update-helper" src/core/update_helper.bin
