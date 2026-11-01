#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

help=$("$ROOT/install.sh" --help)
printf '%s' "$help" | grep -q 'Install the wrapper' || {
  echo "FAIL: install.sh --help did not print usage" >&2
  exit 1
}

dry=$("$ROOT/install.sh" --dry-run)
printf '%s' "$dry" | grep -q 'Dry run complete.' || {
  echo "FAIL: install.sh --dry-run did not complete" >&2
  exit 1
}

echo "test-install: ok"
