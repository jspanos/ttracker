#!/usr/bin/env bash
# ttracker tmux telemetry hook
# Sources rich context directly from tmux and sends it to the tracker via a
# Unix socket, bypassing the title-scraping approach entirely.
#
# Installation — add to ~/.tmux.conf:
#   set-hook -g after-select-pane   "run-shell '~/.tmux/plugins/ttracker/tmux_telemetry.sh send'"
#   set-hook -g after-select-window "run-shell '~/.tmux/plugins/ttracker/tmux_telemetry.sh send'"
#   set-hook -g pane-focus-in       "run-shell '~/.tmux/plugins/ttracker/tmux_telemetry.sh send'"
#   set-hook -g client-attached     "run-shell '~/.tmux/plugins/ttracker/tmux_telemetry.sh send'"
#
# Or via tpm (Tmux Plugin Manager) — see README.

SOCKET="$HOME/.ttracker/tmux.sock"
LOGFILE="$HOME/.ttracker/tmux_telemetry.log"

send_telemetry() {
    # ── Gather context ─────────────────────────────────────────────────────

    SESSION_NAME=$(tmux display-message -p '#S'           2>/dev/null)
    WINDOW_INDEX=$(tmux display-message -p '#I'           2>/dev/null)
    WINDOW_NAME=$(tmux  display-message -p '#W'           2>/dev/null)
    PANE_INDEX=$(tmux   display-message -p '#P'           2>/dev/null)
    PANE_TITLE=$(tmux   display-message -p '#T'           2>/dev/null)

    # Current directory of the active pane's process
    PANE_PID=$(tmux display-message -p '#{pane_pid}'      2>/dev/null)
    PANE_DIR=""
    if [[ -n "$PANE_PID" ]]; then
        # lsof gives us the cwd of the foreground process group
        PANE_DIR=$(lsof -p "$PANE_PID" -Fn 2>/dev/null \
                   | grep '^n' | head -1 | sed 's/^n//')
        # Fallback: read /proc-equivalent via fcntl on macOS
        if [[ -z "$PANE_DIR" || "$PANE_DIR" == "/" ]]; then
            PANE_DIR=$(lsof -p "$PANE_PID" -d cwd -Fn 2>/dev/null \
                       | grep '^n' | head -1 | sed 's/^n//')
        fi
    fi

    # Running command in the pane (first word of ps output)
    PANE_CMD=""
    if [[ -n "$PANE_PID" ]]; then
        PANE_CMD=$(ps -o comm= -p "$PANE_PID" 2>/dev/null | tail -1)
    fi

    # Number of panes in current window
    PANE_COUNT=$(tmux list-panes 2>/dev/null | wc -l | tr -d ' ')

    # Zoomed?
    PANE_ZOOMED=$(tmux display-message -p '#{window_zoomed_flag}' 2>/dev/null)

    # Active window/session counts
    WINDOW_COUNT=$(tmux list-windows 2>/dev/null | wc -l | tr -d ' ')
    SESSION_COUNT=$(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ')

    # git context (if in a repo)
    GIT_BRANCH="" GIT_REPO=""
    if [[ -n "$PANE_DIR" && -d "$PANE_DIR" ]]; then
        GIT_BRANCH=$(git -C "$PANE_DIR" symbolic-ref --short HEAD 2>/dev/null)
        GIT_REPO=$(git   -C "$PANE_DIR" rev-parse --show-toplevel 2>/dev/null)
        GIT_REPO=$(basename "$GIT_REPO" 2>/dev/null)
    fi

    TIMESTAMP=$(date +%s)

    # ── Build JSON payload ─────────────────────────────────────────────────

    PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({
    'type':          'tmux',
    'timestamp':     $TIMESTAMP,
    'session_name':  $(python3 -c "import json; print(json.dumps('$SESSION_NAME'))"),
    'window_index':  '$WINDOW_INDEX',
    'window_name':   $(python3 -c "import json; print(json.dumps('$WINDOW_NAME'))"),
    'pane_index':    '$PANE_INDEX',
    'pane_title':    $(python3 -c "import json; print(json.dumps('$PANE_TITLE'))"),
    'pane_dir':      $(python3 -c "import json; print(json.dumps('$PANE_DIR'))"),
    'pane_cmd':      $(python3 -c "import json; print(json.dumps('$PANE_CMD'))"),
    'pane_count':    int('$PANE_COUNT') if '$PANE_COUNT'.isdigit() else 1,
    'pane_zoomed':   '$PANE_ZOOMED' == '1',
    'window_count':  int('$WINDOW_COUNT') if '$WINDOW_COUNT'.isdigit() else 1,
    'session_count': int('$SESSION_COUNT') if '$SESSION_COUNT'.isdigit() else 1,
    'git_branch':    $(python3 -c "import json; print(json.dumps('$GIT_BRANCH'))"),
    'git_repo':      $(python3 -c "import json; print(json.dumps('$GIT_REPO'))"),
}))
" 2>/dev/null)

    if [[ -z "$PAYLOAD" ]]; then return; fi

    # ── Send to tracker socket ─────────────────────────────────────────────

    mkdir -p "$HOME/.ttracker"
    if [[ -S "$SOCKET" ]]; then
        echo "$PAYLOAD" | nc -U "$SOCKET" >/dev/null 2>&1 &
    else
        # Socket not up yet — write to a queue file the tracker will read on startup
        echo "$PAYLOAD" >> "$HOME/.ttracker/tmux_queue.jsonl"
    fi
}

case "${1:-send}" in
    send) send_telemetry ;;
    test) send_telemetry && echo "Sent" ;;
    *)    echo "Usage: $0 [send|test]" ;;
esac
