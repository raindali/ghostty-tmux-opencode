#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Remove the installed wrapper, TUI plugin, and cleanup script.
# User data (logs, tmux-resurrect saves) is left untouched.
#
set -euo pipefail

CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
BIN_DIR=${XDG_BIN_HOME:-$HOME/.local/bin}

remove_file() {
  local file=$1
  if [ -e "$file" ]; then
    rm -f "$file"
    echo "removed: $file"
  fi
}

remove_file "$CONFIG_HOME/ghostty/tmux-start.sh"
remove_file "$CONFIG_HOME/opencode/plugins/tmux-session-state/tui.tsx"
remove_file "$BIN_DIR/opencode-clean.sh"

rmdir "$CONFIG_HOME/opencode/plugins/tmux-session-state" 2>/dev/null || true
rmdir "$CONFIG_HOME/opencode/plugins" 2>/dev/null || true

cat <<EOF
Uninstalled.

Manual cleanup:
  - Remove the 'initial-command' line from ~/.config/ghostty/config.
  - Remove the tmux-resurrect block from ~/.tmux.conf.

Left in place (your data):
  - $HOME/.tmux-autostart.log
  - $HOME/.tmux/ghostty-last-pane
  - $HOME/.tmux/resurrect/
  - $STATE_HOME/opencode/tmux-session/
EOF
