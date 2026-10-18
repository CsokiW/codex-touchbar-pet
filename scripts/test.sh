#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$ROOT_DIR/.build/synthetic-tests"
MODULE_CACHE="${TMPDIR:-/tmp}/codex-touchbar-pet-module-cache"
mkdir -p "$TEST_DIR" "$MODULE_CACHE"
cd "$ROOT_DIR"
swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -module-cache-path "$MODULE_CACHE" \
    -Xcc "-fmodules-cache-path=$MODULE_CACHE" \
    Sources/CodexPetStateMonitor.swift Sources/CodexTaskTiming.swift Sources/TouchBarPetView.swift \
    Tests/main.swift -o "$TEST_DIR/state-checks"
"$TEST_DIR/state-checks"
