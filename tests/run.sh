#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

echo "==> syntax"
sh -n "$ROOT/bin/tmux-start.sh"
bash -n "$ROOT/bin/opencode-clean.sh"
bash -n "$ROOT/install.sh"
bash -n "$ROOT/uninstall.sh"

if command -v shellcheck >/dev/null 2>&1; then
  echo "==> shellcheck"
  shellcheck --severity=warning -s sh "$ROOT/bin/tmux-start.sh"
  shellcheck --severity=warning "$ROOT/bin/opencode-clean.sh" \
    "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT"/tests/*.sh
fi

echo "==> unit tests"
bash "$ROOT/tests/test-resurrect.sh"
bash "$ROOT/tests/test-clean-help.sh"
bash "$ROOT/tests/test-install.sh"

echo "all tests passed"
