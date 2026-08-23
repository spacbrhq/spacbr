# Enable the systemd services SPACBR depends on. Sourced, not executed
# directly. Requires common.sh.
#
# Only actual system (root-level) services go here. PipeWire/
# WirePlumber/dunst are systemd --user services, already enabled by
# their own package presets -- xinitrc deliberately does NOT start
# them (see "Audio startup" in docs/architecture.md: doing so as raw
# processes actively conflicted with those units and broke the
# PulseAudio-compat layer). The graphical session itself (dwm,
# dwmblocks, picom, clipmenud) still comes from xinitrc, not systemd.

enable_system_services() {
    info "Enabling system services"
    sudo systemctl enable --now NetworkManager
    sudo systemctl enable --now bluetooth
    sudo systemctl enable --now nftables
    ok "NetworkManager, bluetooth, nftables enabled"
}

# Found for real on a fresh Arch install: nothing ever makes zsh the
# actual login shell -- packages/base installs it and .zshrc has the
# tty1 auto-startx logic, but a fresh useradd'd account defaults to
# bash, which never sources .zshrc at all. Without this, X never
# auto-starts on login and the user has to know to run `exec zsh` or
# `startx` manually. Idempotent: no-ops if already zsh.
set_default_shell() {
    zsh_path="$(command -v zsh || true)"
    [ -z "$zsh_path" ] && { warn "zsh not found — can't set it as the login shell"; return 1; }
    current_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [ "$current_shell" = "$zsh_path" ]; then
        ok "zsh already the login shell"
        return 0
    fi
    sudo usermod -s "$zsh_path" "$USER" && \
        ok "login shell set to zsh (takes effect on next login)" || \
        warn "couldn't set zsh as the login shell — run 'chsh -s $zsh_path' yourself"
}

# setup_snapper -- creates the snapper "root" config (btrfs snapshot
# management, automatic pre/post snapshots around every pacman
# transaction via snap-pac) if root is actually btrfs and one doesn't
# already exist, then enables the periodic timeline/cleanup timers.
#
# No vendored config file here, unlike deploy_polkit_rules/
# deploy_nftables/deploy_modules_load: `snapper create-config`'s own
# generated defaults (0.5 of the filesystem, 10 hourly/daily/monthly/
# yearly timeline snapshots, automatic cleanup) are already sensible
# for a personal desktop -- overriding them would be config for its
# own sake, not solving a real problem.
#
# Note this machine's actual btrfs layout is a flat root subvolume
# (top-level, no dedicated @ subvolume) -- snapshots, diffing, and
# file recovery all work fully regardless, but a clean one-command
# boot-time rollback isn't as guaranteed as it would be with a proper
# @/@home layout. Not something this function tries to fix -- that's
# a filesystem migration, a much bigger and more invasive step than
# "add a safety net."
setup_snapper() {
    command -v snapper >/dev/null 2>&1 || return 0
    [ "$(findmnt -no FSTYPE / 2>/dev/null)" = "btrfs" ] || { warn "root isn't btrfs — skipping snapper config"; return 0; }
    if sudo snapper list-configs 2>/dev/null | grep -q '^root '; then
        ok "snapper 'root' config already exists"
    else
        sudo snapper -c root create-config / && ok "snapper 'root' config created"
    fi
    sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
    ok "snapper timeline/cleanup timers enabled"
}

# setup_mpd -- enables the user-level mpd.socket (socket-activated,
# starts mpd.service on first connection). Not the system-wide
# mpd.service/mpd.socket the package also ships -- that runs as a
# dedicated "mpd" system user, which would need explicit permission
# setup to read ~/Music for no benefit on a single-user desktop.
# ~/Music, and mpd.conf's own state directories, are created here
# since mpd itself doesn't create missing parent directories.
setup_mpd() {
    command -v mpd >/dev/null 2>&1 || return 0
    mkdir -p "$HOME/Music" "$HOME/.local/share/mpd/playlists" "$HOME/.local/state/mpd"
    systemctl --user enable --now mpd.socket
    ok "mpd.socket enabled (mpd.service starts on first connection, e.g. from rmpc)"

    # mpd doesn't expose MPRIS on its own -- verified for real (no
    # org.mpris.* name on the session bus at all without this) --
    # which silently broke two things: dwm's playerctl-based media
    # keys never controlled mpd, and fastfetch's Player/Media modules
    # never had anything to read. mpdris2-rs (AUR, a small Rust MPRIS2
    # bridge) fixes both.
    if command -v mpdris2-rs >/dev/null 2>&1; then
        systemctl --user enable --now mpdris2-rs.service
        ok "mpdris2-rs enabled (bridges mpd to MPRIS)"
    fi
}

# setup_tailscale -- enables tailscaled.service (system-level: it
# manages network interfaces/routing directly, unlike mpd/syncthing).
# Does NOT run `tailscale up` -- that's an interactive login (opens a
# URL to authenticate into a specific tailnet), a real account-linking
# decision only the user should make, not something to automate.
setup_tailscale() {
    command -v tailscale >/dev/null 2>&1 || return 0
    sudo systemctl enable --now tailscaled.service
    ok "tailscaled enabled (run 'tailscale up' yourself to actually join a tailnet)"
}

# setup_syncthing -- enables the user-level syncthing.service (not the
# system-wide syncthing@<user>.service template the package also
# ships -- that needs explicit permission setup for no benefit on a
# single-user desktop, same reasoning as setup_mpd). Doesn't configure
# any devices/folders -- that's done through its web UI
# (127.0.0.1:8384) and is specific to what you're actually syncing
# with what, not something to guess at here.
setup_syncthing() {
    command -v syncthing >/dev/null 2>&1 || return 0
    systemctl --user enable --now syncthing.service
    ok "syncthing enabled (configure devices/folders at 127.0.0.1:8384)"
}
