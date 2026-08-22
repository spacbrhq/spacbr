#!/bin/sh
# SPACBR installer. Run from a git clone:
#   git clone <repo> ~/spacbr && cd ~/spacbr && ./install/install.sh
# Safe to re-run: existing packages are skipped, differing existing
# config files are backed up before being overwritten, nothing outside
# SPACBR's own manifest is ever touched.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=functions/common.sh
. "$ROOT/install/functions/common.sh"
. "$ROOT/install/functions/detect.sh"
. "$ROOT/install/functions/packages.sh"
. "$ROOT/install/functions/configs.sh"
. "$ROOT/install/functions/suckless.sh"
. "$ROOT/install/functions/services.sh"
. "$ROOT/install/functions/checks.sh"

info "SPACBR installer — $SPACBR_HOME"

require_platform

if [ "${1:-}" != "--yes" ]; then
    printf '\nThis will:\n'
    printf '  - install packages from packages/{base,x11,desktop,hardware}\n'
    printf '  - deploy .config, .local/bin, .local/share, .local/src into %s\n' "$HOME"
    printf '  - build and install dwm, dmenu, st, dwmblocks, slock\n'
    printf '  - enable NetworkManager and bluetooth\n'
    printf '  - back up any existing files that differ, never delete anything\n\n'
    confirm "Continue?" || die "aborted"
fi

install_all_packages
deploy_dotfiles
deploy_self
build_and_install_suckless
enable_system_services

info "Validating installation"
run_all_checks || warn "some checks failed — see above, or run 'spacbr doctor' later"

ok "SPACBR installed. Backups (if any) are under $BACKUP_DIR"
info "Log out and start X (or reboot) to launch dwm."
