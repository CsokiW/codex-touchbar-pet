#!/bin/zsh
set -euo pipefail

APP_BUNDLE="${1:-}"
APP_NAME="CodexTBPet"
LOCK_FILE="$HOME/Library/Application Support/CodexTouchBarPet/manual-quit.lock"

if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
    exit 0
fi

host_session() {
    # PID plus start time distinguishes a new session, including PID reuse after login.
    local host_pid
    for host_pid in $(/usr/bin/pgrep -a -x 'Codex|ChatGPT|GPT' || true); do
        TZ=UTC LC_ALL=C /bin/ps -p "$host_pid" -o pid= -o lstart= 2>/dev/null || true
    done | /usr/bin/awk '{$1=$1; if (NF) print}' | LC_ALL=C /usr/bin/sort
}

manual_quit_applies() {
    local marker_path="$1" current_session="$2"
    [[ -n "$current_session" && -f "$marker_path" && "$(<"$marker_path")" == "$current_session" ]]
}

# Load only the pure session comparison for synthetic tests.
if [[ "${2:-}" == "--functions-only" ]]; then
    return 0
fi

HOST_SESSION="$(host_session)"
if [[ -z "$HOST_SESSION" ]]; then
    /bin/rm -f "$LOCK_FILE" >/dev/null 2>&1 || true
    exit 0
fi

if [[ "${2:-}" == "--mark-manual-quit" ]]; then
    /bin/mkdir -p "${LOCK_FILE:h}"
    print -r -- "$HOST_SESSION" > "$LOCK_FILE"
    exit 0
fi

if manual_quit_applies "$LOCK_FILE" "$HOST_SESSION"; then
    exit 0
fi
/bin/rm -f "$LOCK_FILE" >/dev/null 2>&1 || true

if /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    exit 0
fi

/usr/bin/open "$APP_BUNDLE" >/dev/null 2>&1 || true
