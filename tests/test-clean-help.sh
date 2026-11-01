#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

out=$("$ROOT/bin/opencode-clean.sh" --help)
printf '%s' "$out" | grep -q 'Usage: opencode-clean.sh' || {
  echo "FAIL: --help did not print usage" >&2
  exit 1
}

set +e
"$ROOT/bin/opencode-clean.sh" --bogus >/dev/null 2>&1
code=$?
set -e
[ "$code" -eq 2 ] || {
  echo "FAIL: unknown argument should exit 2, got $code" >&2
  exit 1
}

echo "test-clean-help: ok"
