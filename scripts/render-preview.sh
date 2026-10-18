#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PREVIEW_DIR="$ROOT_DIR/.build/Preview.app"
MODULE_CACHE="${TMPDIR:-/tmp}/codex-touchbar-pet-module-cache"
mkdir -p "$PREVIEW_DIR/Contents/MacOS" "$PREVIEW_DIR/Contents/Resources" "$ROOT_DIR/docs" "$MODULE_CACHE"
cd "$ROOT_DIR"
cp Resources/TouchBarPet.png "$PREVIEW_DIR/Contents/Resources/"
sources=()
for source in Sources/*.swift; do
    if [[ "$source" != "Sources/main.swift" ]]; then sources+=("$source"); fi
done
swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -module-cache-path "$MODULE_CACHE" \
    -Xcc "-fmodules-cache-path=$MODULE_CACHE" "${sources[@]}" scripts/Preview/main.swift \
    -o "$PREVIEW_DIR/Contents/MacOS/Preview"
"$PREVIEW_DIR/Contents/MacOS/Preview" "$@"
