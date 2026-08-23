#!/bin/sh
# Diagnoses and repairs common problems by idempotently
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
. "$ROOT/install/functions/system.sh"
. "$ROOT/install/functions/checks.sh"

SOURCE_DIR="${1:-$SPACBR_HOME}"
[ -d "$SOURCE_DIR" ] || die "no such source directory: $SOURCE_DIR"
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"

info "SPACBR repair — source: $SOURCE_DIR"
require_platform

info "Diagnosing"
run_all_checks || true

# deploy_dotfiles is safe and idempotent (only touches missing or
# differing files, backs up modified ones) -- run it whenever a real
# source is given, regardless of whether any check above failed.
# Verified for real: none of the checks individually verify that
# scripts like ~/.local/bin/wallpaper exist, so deleting one left
# DOCTOR_FAILED at 0 and repair reported "Nothing to repair" while
# actually doing nothing, contradicting this script's own documented
# ability to restore missing .local/bin content.
if [ "$SOURCE_DIR" != "$SPACBR_SELF" ]; then
    deploy_dotfiles "$SOURCE_DIR"
elif [ "$DOCTOR_FAILED" -ne 0 ]; then
    warn "No known-good source given — can fix packages/binaries/services,"
    warn "but not dotfile content. For that: spacbr repair /path/to/spacbr"
fi

if [ "$DOCTOR_FAILED" -eq 0 ]; then
    ok "Nothing else to repair"
    exit 0
fi

warn "Failures found above — attempting repair"
install_all_packages
build_and_install_suckless
enable_system_services
deploy_polkit_rules "$SOURCE_DIR"

info "Re-checking"
run_all_checks && ok "Repair complete" || warn "Some checks still fail — see above"
