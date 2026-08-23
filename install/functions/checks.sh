# Diagnostic checks shared by `spacbr doctor` and `spacbr info`.
# Sourced, not executed directly. Requires common.sh, detect.sh.

DOCTOR_FAILED=0

# run_check DESCRIPTION TEST_COMMAND REMEDIATION
run_check() {
    if eval "$2" >/dev/null 2>&1; then
        ok "$1"
    else
        error "$1"
        [ -n "$3" ] && printf '   -> %s\n' "$3"
        DOCTOR_FAILED=1
    fi
}

run_all_checks() {
    DOCTOR_FAILED=0
    info "Platform"
    run_check "Arch Linux"          "detect_arch_linux" "SPACBR only supports Arch Linux"
    run_check "x86_64"              "detect_x86_64" "SPACBR only supports x86_64"
    run_check "Xorg present"        "command -v Xorg || command -v X" "pacman -S xorg-server"

    info "Suckless components"
    run_check "dwm"                 "command -v dwm" "cd .local/src/dwm && make && make install"
    run_check "dmenu"               "command -v dmenu" "cd .local/src/dmenu && make && make install"
    run_check "st"                  "command -v st" "cd .local/src/st && make && make install"
    run_check "dwmblocks"           "command -v dwmblocks" "cd .local/src/blocks && make && make install"
    run_check "slock"               "command -v slock" "cd .local/src/slock && make && sudo make install"
    run_check "slock is setuid"     "[ -u \"\$(command -v slock)\" ]" "sudo chmod u+s \$(command -v slock)"

    info "Session infrastructure"
    run_check "dunst"               "command -v dunst" "pacman -S dunst"
    run_check "picom"               "command -v picom" "pacman -S picom"
    run_check "xss-lock"            "command -v xss-lock" "pacman -S xss-lock"

    info "Networking / audio / bluetooth"
    run_check "NetworkManager"      "command -v nmcli" "pacman -S networkmanager"
    run_check "NetworkManager active" "systemctl is-active --quiet NetworkManager" "sudo systemctl enable --now NetworkManager"
    run_check "PipeWire"            "command -v pipewire" "pacman -S pipewire pipewire-pulse"
    run_check "WirePlumber"         "command -v wireplumber" "pacman -S wireplumber"
    run_check "BlueZ"               "command -v bluetoothctl" "pacman -S bluez bluez-utils"
    # /sys/class/bluetooth only exists if there's actual BT hardware --
    # on a desktop with none, systemd correctly leaves the (enabled)
    # service inactive rather than failing to start it, and that's not
    # a problem to report. Verified for real: a BT-less test machine
    # showed "bluetooth service active" as a false-positive failure
    # before this check accounted for hardware absence.
    run_check "bluetooth service active" "[ ! -d /sys/class/bluetooth ] || systemctl is-active --quiet bluetooth" "sudo systemctl enable --now bluetooth"

    info "Hardware utilities"
    run_check "brightnessctl"       "command -v brightnessctl" "pacman -S brightnessctl"
    run_check "xrandr"              "command -v xrandr" "pacman -S xorg-xrandr"
    # ddcutil/i2c-dev: only meaningful on hardware with no real
    # backlight (see .local/src/dwm/config.h's brightness keybindings
    # and packages/hardware's comment) -- a machine with a laptop
    # panel legitimately has no i2c-dev module loaded and that's fine,
    # so this isn't gated on "no backlight" detection, just reported
    # informationally like the bluetooth-hardware-absent check above.
    run_check "ddcutil"             "command -v ddcutil" "pacman -S ddcutil (only needed for external-monitor brightness via DDC/CI)"
    run_check "i2c-dev loaded"      "lsmod | grep -q i2c_dev" "spacbr repair (deploys system/modules-load.d), or: sudo modprobe i2c-dev"

    info "Session extras"
    run_check "clipmenu"            "command -v clipmenu" "pacman -S clipmenu"
    run_check "polkit agent"        "[ -x /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 ]" "pacman -S polkit-gnome"
    # Verified for real: without this rule, the power menu's Reboot/
    # Suspend/Shutdown fail outright ("requires interactive
    # authentication... not enabled by the calling program") when
    # spawned from dwm (no controlling terminal, and polkit's
    # allow_active default doesn't reliably recognize a plain-startx
    # X11 session as "active"). See system/polkit/10-spacbr-power.rules.
    # sudo -n, not a plain [ -f ]: /etc/polkit-1/rules.d is root:polkitd
    # 750 -- verified for real that a plain [ -f ] as the normal user
    # can't even traverse that directory and reports false regardless
    # of whether the file is actually there. -n so this never blocks
    # doctor on a sudo password prompt if there's no cached
    # credential -- it just reports the check as unable to confirm.
    run_check "power menu polkit rule" "sudo -n test -f /etc/polkit-1/rules.d/10-spacbr-power.rules" "spacbr repair (or spacbr install) to deploy system/polkit/10-spacbr-power.rules -- or re-run 'spacbr doctor' just after using sudo for something else, if this only fails because sudo needs a fresh prompt"
    run_check "login shell is zsh"  "[ \"\$(getent passwd \"\$USER\" | cut -d: -f7)\" = \"\$(command -v zsh)\" ]" "sudo usermod -s \$(command -v zsh) \$USER — without this, .zshrc's tty1 auto-startx never runs"

    info "Visual system consistency"
    run_check "dwm colors match palette"   "grep -q '#2f343f' \"\$HOME/.local/src/dwm/config.h\" 2>/dev/null" "dwm/config.h's normbgcolor etc. should match .config/xresources's dwm.* keys"
    run_check "dmenu colors match palette" "grep -q '#2f343f' \"\$HOME/.local/src/dmenu/config.h\" 2>/dev/null" "dmenu/config.h's SchemeNorm should match the same palette dwm/st/slock use"
    run_check "GTK font unified"           "! grep -rq 'Cantarell' \"\$HOME/.config/gtk-2.0\" \"\$HOME/.config/gtk-3.0\" \"\$HOME/.config/gtk-4.0\" 2>/dev/null" "gtk-font-name should be Hack in all three gtk-*.0 configs, not the GTK default"
    # arc-gtk-theme is AUR-only (packages/aur). Verified for real: with
    # no AUR helper present it silently fails to install, and every GTK
    # app just falls back to plain light GTK with zero indication
    # anything is wrong -- checking the config *says* Arc-Dark isn't
    # enough, since that's true even when the theme was never actually
    # installed. This checks the real theme files are on disk.
    run_check "GTK theme installed"        "[ -d /usr/share/themes/Arc-Dark ]" "arc-gtk-theme isn't installed -- install an AUR helper (paru) and re-run 'spacbr install', or install it manually"

    info "XDG layout"
    run_check "~/.config exists"    "[ -d \"\$XDG_CONFIG_HOME\" ]" "mkdir -p ~/.config"
    run_check "~/.local/bin exists" "[ -d \"\$HOME/.local/bin\" ]" "mkdir -p ~/.local/bin"
    run_check "~/.local/bin in PATH" "case \":\$PATH:\" in *:\"\$HOME/.local/bin\":*) true;; *) false;; esac" "check ~/.config/shell/profile is sourced"
    run_check "xinitrc present"     "[ -f \"\$XDG_CONFIG_HOME/xinitrc\" ]" "spacbr repair"

    info "Fonts"
    run_check "Hack font available" "fc-list | grep -qi hack" "pacman -S ttf-hack"

    return $DOCTOR_FAILED
}

print_info() {
    printf '%s\n' "SPACBR $(cat "$SPACBR_SELF/VERSION" 2>/dev/null || cat "$SPACBR_HOME/VERSION" 2>/dev/null || echo "unknown")"
    printf '%s\n' "Arch:       $( [ -f /etc/os-release ] && awk -F= '/PRETTY_NAME/{gsub(/"/,"",$2); print $2}' /etc/os-release )"
    printf '%s\n' "Kernel:     $(uname -r)"
    printf '%s\n' "Arch(uname): $(uname -m)"
    printf '%s\n' "X11:        $(command -v Xorg || command -v X || echo 'not found')"
    printf '%s\n' "dwm:        $(command -v dwm || echo 'not found')"
    printf '%s\n' "Terminal:   $(command -v st || echo 'not found')"
    printf '%s\n' "Shell:      $SHELL"
    # systemctl is-active prints its status text to stdout even when it
    # exits non-zero (inactive/failed), so `$(cmd || echo fallback)`
    # doesn't replace that output on failure -- it appends the fallback
    # after it. Verified for real: an inactive bluetooth.service printed
    # "bluetooth:  inactive" followed by a stray "unknown" line.
    # `|| true` guards the assignment itself: info.sh runs under set -eu,
    # and is-active's non-zero exit on "inactive" would otherwise abort
    # the whole script right here.
    nm_status=$(systemctl is-active NetworkManager 2>/dev/null) || true
    bt_status=$(systemctl is-active bluetooth 2>/dev/null) || true
    printf '%s\n' "NetworkManager: ${nm_status:-unknown}"
    printf '%s\n' "bluetooth:  ${bt_status:-unknown}"
}
