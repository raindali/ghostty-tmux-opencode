#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Install the wrapper, the opencode TUI plugin, and the manual cleanup script.
#
#   ./install.sh             install
#   ./install.sh --dry-run   print what would be done
#
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
BIN_DIR=${XDG_BIN_HOME:-$HOME/.local/bin}
TMUX_PLUGIN_DIR=${TMUX_PLUGIN_MANAGER_PATH:-$HOME/.tmux/plugins}

usage() {
  cat <<'EOF'
Install the wrapper, the opencode TUI plugin, and the manual cleanup script.

  ./install.sh             install
  ./install.sh --dry-run   print what would be done
EOF
}

DRY=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY=1
elif [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
elif [ $# -gt 0 ]; then
  echo "Unknown argument: $1" >&2
  usage >&2
  exit 2
fi

run() {
  if [ "$DRY" = 1 ]; then
    printf 'would: %s\n' "$*"
  else
    "$@"
  fi
}

backup() {
  local file=$1
  if [ -e "$file" ]; then
    local backup_file
    backup_file="$file.bak.$(date +%Y%m%d%H%M%S)"
    echo "backup: $file -> $backup_file"
    run mv "$file" "$backup_file"
  fi
}

install_file() {
  local src=$1 dst=$2 mode=${3:-0644}
  run mkdir -p "$(dirname "$dst")"
  backup "$dst"
  echo "install: $dst"
  run cp "$src" "$dst"
  run chmod "$mode" "$dst"
}

echo "==> dependencies"
for cmd in tmux opencode; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  ok: $cmd"
  else
    echo "  warning: $cmd not found in PATH" >&2
  fi
done

for plugin in tmux-resurrect tmux-continuum; do
  if [ -d "$TMUX_PLUGIN_DIR/$plugin" ]; then
    echo "  ok: $plugin"
  else
    echo "  warning: $plugin not found in $TMUX_PLUGIN_DIR" >&2
    echo "           install it with TPM before using the wrapper" >&2
  fi
done

echo "==> files"
install_file "$ROOT/bin/tmux-start.sh" "$CONFIG_HOME/ghostty/tmux-start.sh" 0755
install_file "$ROOT/bin/opencode-clean.sh" "$BIN_DIR/opencode-clean.sh" 0755
install_file "$ROOT/plugins/tmux-session-state/tui.tsx" \
  "$CONFIG_HOME/opencode/plugins/tmux-session-state/tui.tsx" 0644

echo
if [ "$DRY" = 1 ]; then
  echo "Dry run complete."
else
  echo "Installed."
fi
echo
echo "Next steps:"
echo "  1. Add this line to your Ghostty config (~/.config/ghostty/config):"
echo "       initial-command = $CONFIG_HOME/ghostty/tmux-start.sh"
echo "  2. Merge config/tmux.conf.example into ~/.tmux.conf."
echo "  3. Install tmux-resurrect + tmux-continuum with TPM (prefix + I)."
echo "  4. Restart Ghostty."
echo
echo "Logs:         $HOME/.tmux-autostart.log"
echo "State:        $HOME/.tmux/ghostty-last-pane"
echo "Plugin state: $STATE_HOME/opencode/tmux-session/"
echo "Manual clean: $BIN_DIR/opencode-clean.sh"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo; echo "Note: add $BIN_DIR to PATH to run opencode-clean.sh directly." ;;
esac
