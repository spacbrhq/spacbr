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
