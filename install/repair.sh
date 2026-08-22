#!/bin/sh
# Diagnoses and repairs common problems (CLAUDE.md §66) by idempotently
# re-applying the same steps install/update use: reinstalling only
# missing packages, rebuilding Suckless binaries from the already-
# deployed source under ~/.local/src, and re-enabling services.
# Nothing here deletes user data.
#
# Usage: repair.sh [SOURCE_DIR]
#
# Missing/corrupted *content* in .config or .local/bin can only be
# restored from a known-good source. Without SOURCE_DIR (a git clone
# to restore from), this can fix packages, binaries, and services, but
# not dotfile content — see the same limitation in update.sh.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/install/functions/common.sh"
. "$ROOT/install/functions/detect.sh"
. "$ROOT/install/functions/packages.sh"
. "$ROOT/install/functions/configs.sh"
. "$ROOT/install/functions/suckless.sh"
. "$ROOT/install/functions/services.sh"
. "$ROOT/install/functions/checks.sh"

SOURCE_DIR="${1:-$SPACBR_HOME}"
[ -d "$SOURCE_DIR" ] || die "no such source directory: $SOURCE_DIR"
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"

info "SPACBR repair — source: $SOURCE_DIR"
require_platform

info "Diagnosing"
run_all_checks || true

if [ "$DOCTOR_FAILED" -eq 0 ]; then
    ok "Nothing to repair"
    exit 0
fi

warn "Failures found above — attempting repair"
if [ "$SOURCE_DIR" = "$SPACBR_SELF" ]; then
    warn "No known-good source given — can fix packages/binaries/services,"
    warn "but not dotfile content. For that: spacbr repair /path/to/spacbr"
fi
install_all_packages
deploy_dotfiles "$SOURCE_DIR"
build_and_install_suckless
enable_system_services

info "Re-checking"
run_all_checks && ok "Repair complete" || warn "Some checks still fail — see above"
