#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/Codex Touch Bar Pet.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
EXECUTABLE_PATH="$ROOT_DIR/.build/release/CodexTBPet"
MODULE_CACHE="${TMPDIR:-/tmp}/codex-touchbar-pet-module-cache"
BUILD_ARCH="$(uname -m)"

cd "$ROOT_DIR"

SDK_PATH="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
mkdir -p "$(dirname "$EXECUTABLE_PATH")" "$MODULE_CACHE"
swiftc -O -target "${BUILD_ARCH}-apple-macosx12.0" -sdk "$SDK_PATH" -module-cache-path "$MODULE_CACHE" \
    -Xcc "-fmodules-cache-path=$MODULE_CACHE" \
    -debug-prefix-map "$ROOT_DIR"=. Sources/*.swift -o "$EXECUTABLE_PATH"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/CodexTBPet"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "Resources/codex-token-launcher.sh" "$RESOURCES_DIR/codex-token-launcher.sh"
cp "Resources/TouchBarPet.png" "$RESOURCES_DIR/TouchBarPet.png"
cp LICENSE "$RESOURCES_DIR/LICENSE"
cp THIRD_PARTY_NOTICES.md "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"
chmod +x "$RESOURCES_DIR/codex-token-launcher.sh"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
