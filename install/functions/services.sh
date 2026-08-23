# Enable the systemd services SPACBR depends on. Sourced, not executed
# directly. Requires common.sh.
#
# Only actual system services go here — audio and
# the graphical session itself are started from xinitrc, not systemd.

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
