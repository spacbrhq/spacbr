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
. "$ROOT/install/functions/system.sh"
. "$ROOT/install/functions/checks.sh"

info "SPACBR installer — $SPACBR_HOME"

require_platform

if [ "${1:-}" != "--yes" ]; then
    printf '\nThis will:\n'
    printf '  - install packages from packages/{base,x11,desktop,hardware}\n'
    printf '  - deploy .config, .local/bin, .local/share, .local/src into %s\n' "$HOME"
    printf '  - build and install dwm, dmenu, st, dwmblocks, slock\n'
    printf '  - enable NetworkManager, bluetooth, and nftables\n'
    printf '  - enable a firewall (nftables): deny all inbound except SSH and ping, unrestricted outbound -- see system/nftables/nftables.conf\n'
    printf '  - set up snapper (if root is btrfs): automatic snapshots before/after every pacman transaction, plus periodic timeline snapshots\n'
    printf '  - install a polkit rule so wheel-group reboot/suspend/poweroff (the power menu'\''s Reboot/Suspend/Shutdown) do not require a password\n'
    printf '  - set your login shell to zsh if it is not already (needed for .zshrc'\''s tty1 auto-startx)\n'
    printf '  - back up any existing files that differ, never delete anything\n\n'
    confirm "Continue?" || die "aborted"
fi

install_all_packages
deploy_dotfiles
deploy_self
build_and_install_suckless
deploy_nftables
enable_system_services
deploy_polkit_rules
deploy_modules_load
setup_snapper
set_default_shell

info "Validating installation"
run_all_checks || warn "some checks failed — see above, or run 'spacbr doctor' later. \
Note: a fresh install run's own process never re-reads the shell profile it just \
deployed, so 'dwm'/'~/.local/bin in PATH'-style checks can show a false failure \
here even when everything is actually fine — 'spacbr doctor' in a new shell is \
the check that actually matters."

ok "SPACBR installed. Backups (if any) are under $BACKUP_DIR"
info "Log out and start X (or reboot) to launch dwm."
