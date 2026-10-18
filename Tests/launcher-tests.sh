#!/bin/zsh
set -euo pipefail
TEST_ROOT="$1"
source "$TEST_ROOT/Resources/codex-token-launcher.sh" "$TEST_ROOT" --functions-only
TEST_MARKER_DIR="$(/usr/bin/mktemp -d)"
TEST_MARKER="$TEST_MARKER_DIR/manual-quit.lock"
trap '/bin/rm -f "$TEST_MARKER"; /bin/rmdir "$TEST_MARKER_DIR"' EXIT
FIRST_SESSION='123 Sun Oct 18 12:00:00 2026'
print -r -- "$FIRST_SESSION" > "$TEST_MARKER"
manual_quit_applies "$TEST_MARKER" "$FIRST_SESSION"
print 'PASS: manual quit suppresses the same host session'
if manual_quit_applies "$TEST_MARKER" '456 Sun Oct 18 12:00:01 2026'; then exit 1; fi
print 'PASS: rapid restart permits a new host PID without observing an empty gap'
if manual_quit_applies "$TEST_MARKER" '123 Mon Oct 19 12:00:00 2026'; then exit 1; fi
print 'PASS: reused PID at next login is a different session'
print 'manual quit' > "$TEST_MARKER"
if manual_quit_applies "$TEST_MARKER" "$FIRST_SESSION"; then exit 1; fi
print 'PASS: legacy permanent marker does not block a new session'
