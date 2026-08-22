#!/bin/sh
# `spacbr doctor` — diagnostic checks only, no changes made.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/install/functions/common.sh"
. "$ROOT/install/functions/detect.sh"
. "$ROOT/install/functions/checks.sh"

if run_all_checks; then
    ok "All checks passed"
    exit 0
else
    warn "Some checks failed — run 'spacbr repair' to attempt fixes"
    exit 1
fi
