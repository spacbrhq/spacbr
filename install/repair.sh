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
require_sudo

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
#
# deploy_self here too, not just in update.sh -- a real bug, found for
# real: without it, `spacbr repair /path/to/newer/clone` refreshed
# dotfiles but left $SPACBR_SELF's own install/functions/*.sh,
# packages/*, and system/* permanently on whatever was deployed by the
# last `spacbr install`/`spacbr update`, no matter how new a source
# directory you pointed repair at. Since `spacbr repair` (via the CLI
# shim) always execs the *deployed* repair.sh, a fix landing in
# functions/*.sh never reached the copy that was actually running --
# caught when a call to a function added after the last deploy_self
# (reload_user_units, added in an earlier session) failed with
# "command not found" against a stale deployed configs.sh, even though
# the source clone passed to repair had it all along.
if [ "$SOURCE_DIR" != "$SPACBR_SELF" ]; then
    deploy_dotfiles "$SOURCE_DIR"
    reload_user_units
    deploy_self "$SOURCE_DIR"
elif [ "$DOCTOR_FAILED" -ne 0 ]; then
    warn "No known-good source given — can fix packages/binaries/services,"
    warn "but not dotfile content. For that: spacbr repair /path/to/spacbr"
fi

if [ "$DOCTOR_FAILED" -eq 0 ]; then
    ok "Nothing else to repair"
    exit 0
fi

warn "Failures found above — attempting repair"
deploy_pacman_conf "$SOURCE_DIR"
install_all_packages
build_and_install_suckless
deploy_nftables "$SOURCE_DIR"
enable_system_services
deploy_polkit_rules "$SOURCE_DIR"
deploy_modules_load "$SOURCE_DIR"
setup_snapper
setup_mpd
setup_netbird
setup_syncthing
setup_maintenance_timers

info "Re-checking"
if run_all_checks; then
    ok "Repair complete"
else
    warn "Some checks still fail — see above"
fi
