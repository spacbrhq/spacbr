# Enable the systemd services SPACBR depends on. Sourced, not executed
# directly. Requires common.sh.
#
# Only actual system services go here — audio and
# the graphical session itself are started from xinitrc, not systemd.

enable_system_services() {
    info "Enabling system services"
    sudo systemctl enable --now NetworkManager
    sudo systemctl enable --now bluetooth
    ok "NetworkManager, bluetooth enabled"
}
