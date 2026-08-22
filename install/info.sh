#!/bin/sh
# `spacbr info` — system/version summary.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/install/functions/common.sh"
. "$ROOT/install/functions/checks.sh"

print_info
