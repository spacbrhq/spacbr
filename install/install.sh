#!/bin/sh
# SPACBR installer. Run from a git clone:
#   git clone <repo> ~/spacbr && cd ~/spacbr && ./install/install.sh
# Safe to re-run: existing packages are skipped, differing existing
# config files are backed up before being overwritten, nothing outside
# SPACBR's own manifest is ever touched.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=install/functions/common.sh
. "$ROOT/install/functions/common.sh"
. "$ROOT/install/functions/detect.sh"
. "$ROOT/install/functions/packages.sh"
. "$ROOT/install/functions/configs.sh"
. "$ROOT/install/functions/suckless.sh"
. "$ROOT/install/functions/services.sh"
. "$ROOT/install/functions/system.sh"
. "$ROOT/install/functions/checks.sh"

banner
info "SPACBR installer — $SPACBR_HOME"

require_platform
require_sudo

# Captured before anything runs: SPACBR_MANIFEST (uninstall.sh's own
# tracking file) only exists once deploy_dotfiles has run at least
# once, so its absence right now is a reliable "this machine has never
# had SPACBR installed before" signal -- used below to fire a one-time
# welcome notification on first login, not on every `spacbr update`/
# `repair` re-run.
fresh_install=0
[ -f "$SPACBR_MANIFEST" ] || fresh_install=1

if [ "${1:-}" != "--yes" ]; then
    printf '\nThis will:\n'
    printf '  - deploy system/pacman/pacman.conf to /etc/pacman.conf (multilib enabled, ParallelDownloads=5, ILoveCandy/VerbosePkgLists) and re-sync repo databases if the repo list changed\n'
    printf '  - install packages from packages/{base,x11,desktop,hardware}, CPU microcode (intel-ucode/amd-ucode, skipped in a VM), and GPU drivers for any detected Intel/AMD hardware\n'
    printf '  - build any packages/aur-overrides/* locally (currently: arc-gtk-theme, ttf-rajdhani) instead of pulling them from the AUR as-is\n'
    printf '  - deploy .config, .local/bin, .local/share, .local/src into %s\n' "$HOME"
    printf '  - build and install dwm, dmenu, st, dwmblocks, slock\n'
    printf '  - enable NetworkManager, bluetooth, and nftables\n'
    printf '  - enable a firewall (nftables): deny all inbound except SSH and ping, unrestricted outbound -- see system/nftables/nftables.conf\n'
    printf '  - if Plymouth is installed (live-install.sh installs it; a plain Arch install may not have it), theme it (shares Limine'\''s wallpaper) and rebuild the initramfs (mkinitcpio -P) -- skipped cleanly otherwise\n'
    printf '  - configure automatic login on tty1 for you (system/autologin/) -- LUKS2 (entered at Plymouth) is this system'\''s only password, nothing else asks for one\n'
    printf '  - set up snapper (if root is btrfs): automatic snapshots before/after every pacman transaction, plus periodic timeline snapshots\n'
    printf '  - enable mpd.socket (user-level, starts mpd on first connection) for the rmpc music client\n'
    printf '  - enable netbird@main.service and syncthing.service (neither joins/configures anything -- netbird up and Syncthing'\''s web UI are yours to do)\n'
    printf '  - install a polkit rule so wheel-group reboot/suspend/poweroff (the power menu'\''s Reboot/Suspend/Shutdown) do not require a password\n'
    printf '  - set your login shell to zsh if it is not already\n'
    printf '  - enable paccache.timer and reflector.timer (periodic package-cache trim and mirrorlist refresh), and fstrim.timer if root is SSD/NVMe and not btrfs\n'
    printf '  - back up any existing files that differ, never delete anything\n\n'
    confirm "Continue?" || die "aborted"
fi

deploy_pacman_conf
install_all_packages
deploy_dotfiles
reload_user_units
deploy_self
build_and_install_suckless
deploy_nftables
deploy_plymouth_theme
deploy_autologin
enable_system_services
deploy_polkit_rules
deploy_modules_load
setup_snapper
setup_mpd
setup_netbird
setup_syncthing
setup_maintenance_timers
set_default_shell

info "Validating installation"
run_all_checks || warn "some checks failed — see above, or run 'spacbr doctor' later. \
Note: a fresh install run's own process never re-reads the shell profile it just \
deployed, so 'dwm'/'~/.local/bin in PATH'-style checks can show a false failure \
here even when everything is actually fine — 'spacbr doctor' in a new shell is \
the check that actually matters."

if [ "$fresh_install" -eq 1 ]; then
    # Consumed once by .config/xinitrc, right after dwm's first-ever
    # startup on this machine -- not fired here, since nothing's
    # running to receive a notification yet at this point in the
    # installer (no X session, no dunst). See xinitrc for why this is
    # the one place SPACBR shows its own name unprompted: dwm's whole
    # interaction model ("keyboard shortcut -> dmenu -> action") is
    # otherwise fully invisible, so a genuinely new user has no way to
    # discover MODKEY+p without being told once.
    mkdir -p "$SPACBR_STATE"
    touch "$SPACBR_STATE/welcome-pending"
fi

ok "SPACBR installed. Backups (if any) are under $BACKUP_DIR"
info "Log out and start X (or reboot) to launch dwm."
