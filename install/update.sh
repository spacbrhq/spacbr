#!/bin/sh
# Re-applies SPACBR: refreshes packages, re-deploys dotfiles (backing
# up local modifications first), rebuilds the Suckless components, and
# re-validates.
#
# Usage: update.sh [SOURCE_DIR]
#
# SOURCE_DIR is a git clone with newer content to update from (e.g.
# after `git pull`). If omitted, defaults to wherever this script
# itself lives. When invoked as `spacbr update`, that's always the
# deployed copy under $XDG_DATA_HOME/spacbr — which never holds
# .config/.local (see deploy_self), so dotfiles won't be re-synced
# unless you point this at an actual updated source.
#
# NOTE: this does not fetch a new release itself — it takes a source
# directory you already have (a git clone you've pulled, or the
# output of extracting a release/build.sh tarball). Wiring this up to
# automatically resolve+download+verify the latest GitHub release the
# way release/bootstrap.sh does is future work, not a shortcut taken
# here.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/install/functions/common.sh"
. "$ROOT/install/functions/detect.sh"
. "$ROOT/install/functions/packages.sh"
. "$ROOT/install/functions/configs.sh"
. "$ROOT/install/functions/suckless.sh"
. "$ROOT/install/functions/checks.sh"

SOURCE_DIR="${1:-$SPACBR_HOME}"
[ -d "$SOURCE_DIR" ] || die "no such source directory: $SOURCE_DIR"
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"

info "SPACBR update — source: $SOURCE_DIR"
require_platform

if [ "$SOURCE_DIR" = "$SPACBR_SELF" ]; then
    warn "No newer source given — dotfiles won't be re-synced (nothing to copy from)."
    warn "Point this at an updated clone instead: spacbr update /path/to/spacbr"
fi

PREV_VERSION=$(cat "$SPACBR_SELF/VERSION" 2>/dev/null || echo "unknown")
NEW_VERSION=$(cat "$SOURCE_DIR/VERSION" 2>/dev/null || echo "unknown")
info "Installed: $PREV_VERSION -> Source: $NEW_VERSION"

install_all_packages
deploy_dotfiles "$SOURCE_DIR"
deploy_self "$SOURCE_DIR"
build_and_install_suckless

info "Validating"
run_all_checks || warn "some checks failed — run 'spacbr doctor' for details"

ok "SPACBR updated to $NEW_VERSION. Backups (if any) are under $BACKUP_DIR"
