#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export GHOSTTY_TMUX_SOURCE_ONLY=1
export TMUX_RESURRECT_DIR="$TMP/resurrect"
export GHOSTTY_TMUX_MAP="$TMP/map"
export GHOSTTY_TMUX_STATE="$TMP/state"
export GHOSTTY_TMUX_LOG="$TMP/log"
export XDG_STATE_HOME="$TMP/xdg-state"
export TMUX_BIN="$TMP/bin/tmux"
export OPENCODE_BIN=/bin/false

mkdir -p "$TMUX_RESURRECT_DIR" "$TMP/bin" "$XDG_STATE_HOME/opencode/tmux-session"

# Fake tmux used only by build_resurrect_map.
cat > "$TMUX_BIN" <<'EOF'
#!/bin/sh
printf 'main\t%%1\tOC | Demo\t/tmp/demo\topencode\n'
EOF
chmod +x "$TMUX_BIN"

# shellcheck source=../bin/tmux-start.sh
. "$ROOT/bin/tmux-start.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "expected [$2], got [$1]"
}

assert_contains() {
  printf '%s' "$1" | grep -qF "$2" || fail "missing [$2] in [$1]"
}

# normalize_opencode_cmd
assert_eq "$(normalize_opencode_cmd opencode)" "opencode -c"
assert_eq "$(normalize_opencode_cmd 'opencode -s ses_x')" "opencode -s ses_x"
assert_eq "$(normalize_opencode_cmd zsh)" "zsh"

# repair_last: a zero-byte save is removed and `last` is relinked to a non-empty one.
: > "$TMUX_RESURRECT_DIR/tmux_resurrect_20260101T000000.txt"
printf 'pane\tx\n' > "$TMUX_RESURRECT_DIR/tmux_resurrect_20250101T000000.txt"
ln -sfn tmux_resurrect_20260101T000000.txt "$TMUX_RESURRECT_DIR/last"
repair_last
assert_eq "$(readlink "$TMUX_RESURRECT_DIR/last")" "tmux_resurrect_20250101T000000.txt"
[ ! -e "$TMUX_RESURRECT_DIR/tmux_resurrect_20260101T000000.txt" ] || fail "zero-byte file was not removed"

# build_resurrect_map
printf 'ses_demo\n' > "$XDG_STATE_HOME/opencode/tmux-session/%1"
build_resurrect_map
assert_contains "$(cat "$GHOSTTY_TMUX_MAP")" "$(printf 'main\tOC | Demo\t/tmp/demo\tses_demo')"

# patch_resurrect_cmd: exact match rewrites to -s
printf 'pane\tmain\t1\t1\t:*\t1\tOC | Demo\t:/tmp/demo\t1\topencode\t:opencode\n' \
  > "$TMUX_RESURRECT_DIR/tmux_resurrect_20250101T000000.txt"
ln -sfn tmux_resurrect_20250101T000000.txt "$TMUX_RESURRECT_DIR/last"
patch_resurrect_cmd
assert_contains "$(cat "$TMUX_RESURRECT_DIR/last")" ":opencode -s ses_demo"

# patch_resurrect_cmd: no map -> bare opencode falls back to -c
: > "$GHOSTTY_TMUX_MAP"
printf 'pane\tmain\t1\t1\t:*\t1\tOC | Demo\t:/tmp/demo\t1\topencode\t:opencode\n' \
  > "$TMUX_RESURRECT_DIR/tmux_resurrect_20250101T000000.txt"
patch_resurrect_cmd
assert_contains "$(cat "$TMUX_RESURRECT_DIR/last")" ":opencode -c"

# patch_resurrect_cmd: ambiguous map -> fallback -c, not a guess
printf 'main\tOC | Demo\t/tmp/demo\tses_one\nmain\tOC | Demo\t/tmp/demo\tses_two\n' \
  > "$GHOSTTY_TMUX_MAP"
printf 'pane\tmain\t1\t1\t:*\t1\tOC | Demo\t:/tmp/demo\t1\topencode\t:opencode\n' \
  > "$TMUX_RESURRECT_DIR/tmux_resurrect_20250101T000000.txt"
patch_resurrect_cmd
assert_contains "$(cat "$TMUX_RESURRECT_DIR/last")" ":opencode -c"

echo "test-resurrect: ok"
