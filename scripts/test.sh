#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$ROOT_DIR/.build/synthetic-tests"
MODULE_CACHE="${TMPDIR:-/tmp}/codex-touchbar-pet-module-cache"
mkdir -p "$TEST_DIR" "$MODULE_CACHE"
cd "$ROOT_DIR"
sources=()
for source in Sources/*.swift; do
    if [[ "$source" != "Sources/main.swift" ]]; then sources+=("$source"); fi
done
swiftc -module-cache-path "$MODULE_CACHE" -Xcc "-fmodules-cache-path=$MODULE_CACHE" \
    Tests/AppServerFixture/main.swift -o "$TEST_DIR/success-fixture"
cp "$TEST_DIR/success-fixture" "$TEST_DIR/timeout-fixture"
cp "$TEST_DIR/success-fixture" "$TEST_DIR/initialize-timeout-fixture"
swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -module-cache-path "$MODULE_CACHE" \
    -Xcc "-fmodules-cache-path=$MODULE_CACHE" \
    "${sources[@]}" Tests/main.swift -o "$TEST_DIR/state-checks"
"$TEST_DIR/state-checks"
/bin/zsh Tests/launcher-tests.sh "$ROOT_DIR"
