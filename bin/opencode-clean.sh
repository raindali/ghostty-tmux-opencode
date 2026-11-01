#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Stop opencode TUIs without killing tmux sessions.
#
#   ./opencode-clean.sh                stop opencode TUIs, keep tmux sessions and shells
#   ./opencode-clean.sh --dry-run      print what would be done
#   ./opencode-clean.sh --kill-session also kill tmux sessions that contain opencode
#
set -uo pipefail

TMUX_BIN=${TMUX_BIN:-$(command -v tmux 2>/dev/null || true)}
OPENCODE=${OPENCODE:-$(command -v opencode 2>/dev/null || true)}
[ -n "$TMUX_BIN" ] || TMUX_BIN=/opt/homebrew/bin/tmux
[ -n "$OPENCODE" ] || OPENCODE=/opt/homebrew/bin/opencode

DRY=0
KILL_SESSION=0

usage() {
  cat <<'EOF'
Usage: opencode-clean.sh [--dry-run] [--kill-session]

  (default)       stop opencode TUIs, keep tmux sessions and shells
  --dry-run       print what would be done
  --kill-session  also kill tmux sessions that contain opencode
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --kill-session) KILL_SESSION=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

# When run inside tmux, skip the current session so we never kill ourselves.
# Do not trust $TMUX (it can be stale in long-lived processes); match our tty
# against the pane ttys instead.
TAB=$'\t'
CURRENT_SESSION=""
MY_TTY=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')
if [ -n "$MY_TTY" ] && [ "$MY_TTY" != "??" ]; then
  CURRENT_SESSION=$("$TMUX_BIN" list-panes -a -F "#{pane_tty}${TAB}#{session_name}" 2>/dev/null |
    awk -F"$TAB" -v t="/dev/$MY_TTY" '$1==t{print $2; exit}')
fi

descendants() {
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do
    echo "$c"
    descendants "$c"
  done
}

# Stop opencode inside one pane, keeping the pane and shell alive.
clean_pane() {
  local pane_id=$1 pane_pid=$2 dir=$3
  local pane_cmd pids

  pane_cmd=$(ps -o command= -p "$pane_pid" 2>/dev/null | sed 's/^ *//')

  # opencode is the pane's direct process: respawn a shell in the same directory.
  case "$pane_cmd" in
    opencode|*/opencode|opencode\ *|*/opencode\ *)
      if [ "$DRY" = 1 ]; then
        echo "  would respawn: $pane_id at $dir"
      else
        shell=${SHELL:-/bin/sh}
        "$TMUX_BIN" respawn-pane -k -t "$pane_id" -c "$dir" "$shell" 2>/dev/null &&
          echo "  respawned: $pane_id at $dir"
        sleep 0.2
        if ps -o command= -p "$pane_pid" 2>/dev/null | grep -Eq '(^|/)(opencode)( |$)'; then
          kill "$pane_pid" 2>/dev/null || true
          sleep 0.2
          kill -9 "$pane_pid" 2>/dev/null || true
        fi
      fi
      return 0
      ;;
  esac

  # Common case: opencode is a child of the pane shell. Kill it, keep the shell.
  pids=$(descendants "$pane_pid" | while IFS= read -r p; do
    local c
    c=$(ps -o command= -p "$p" 2>/dev/null | sed 's/^ *//')
    [[ "$c" == *"serve --service"* ]] && continue
    if [[ "$c" =~ (^|/)(opencode)( |$) ]]; then
      echo "$p"
    fi
  done)

  [ -n "$pids" ] || return 0

  if [ "$DRY" = 1 ]; then
    echo "  would kill: $(printf '%s' "$pids" | tr '\n' ' ')"
  else
    printf '%s\n' "$pids" | xargs kill 2>/dev/null || true
    sleep 0.2
    printf '%s\n' "$pids" | xargs kill -9 2>/dev/null || true
    echo "  killed opencode in $pane_id: $(printf '%s' "$pids" | tr '\n' ' ')"
  fi
}

clean_session() {
  local s=$1 pane_id pane_pid dir cur
  "$TMUX_BIN" list-panes -t "$s" -F $'#{pane_id}\t#{pane_pid}\t#{pane_current_path}\t#{pane_current_command}' 2>/dev/null |
  while IFS=$'\t' read -r pane_id pane_pid dir cur; do
    [ "$cur" = "opencode" ] || continue
    clean_pane "$pane_id" "$pane_pid" "$dir"
  done
}

session_has_opencode() {
  "$TMUX_BIN" list-panes -t "$1" -F '#{pane_current_command}' 2>/dev/null | grep -qx opencode
}

echo "==> tmux sessions"
if "$TMUX_BIN" list-sessions >/dev/null 2>&1; then
  while IFS= read -r s; do
    if [ -n "$CURRENT_SESSION" ] && [ "$s" = "$CURRENT_SESSION" ]; then
      echo "  keep: ${s} (current session, skipped)"
      continue
    fi

    if [ "$KILL_SESSION" = 1 ]; then
      if session_has_opencode "$s"; then
        if [ "$DRY" = 1 ]; then
          echo "  would kill session: $s"
        else
          "$TMUX_BIN" kill-session -t "$s" && echo "  killed session: $s"
        fi
      else
        echo "  keep: ${s} (no opencode)"
      fi
    else
      if session_has_opencode "$s"; then
        echo "  session: $s"
        clean_session "$s"
      else
        echo "  keep: ${s} (no opencode)"
      fi
    fi
  done < <("$TMUX_BIN" list-sessions -F '#{session_name}')
else
  echo "  no tmux sessions"
fi

# We use ps (not pgrep) because we need full command lines to exclude the
# shared `serve --service` process.
echo "==> orphaned opencode TUIs (ppid=1, not inside tmux)"
ttys=$("$TMUX_BIN" list-panes -a -F '#{pane_tty}' 2>/dev/null | sed 's#^/dev/##')
found=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  pid=$(echo "$line" | awk '{print $1}')
  ppid=$(echo "$line" | awk '{print $2}')
  tty=$(echo "$line" | awk '{print $3}')
  [ "$ppid" = 1 ] || continue
  if [ -n "$ttys" ] && printf '%s\n' "$ttys" | grep -qx "$tty"; then
    continue
  fi
  found=1
  if [ "$DRY" = 1 ]; then
    echo "  would kill: pid=$pid tty=$tty"
  else
    kill "$pid" 2>/dev/null && echo "  killed: pid=$pid tty=$tty"
  fi
done < <(ps -axo pid=,ppid=,tty=,command= | grep -E '(^|[ /])opencode( |$)' \
           | grep -v ' serve' | grep -v ' mcp')
[ "$found" = 1 ] || echo "  none"

echo "==> opencode background service"
if ps -axo command= | grep -v grep \
     | grep -E '(^|/)opencode( |$)' | grep -v 'serve --service' | grep -q .; then
  echo "  an opencode TUI is still running; keeping the service"
else
  if [ "$DRY" = 1 ]; then
    echo "  would stop: opencode service stop"
  else
    "$OPENCODE" service stop >/dev/null 2>&1 || true
    echo "  stopped"
  fi
fi
