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

    info "Boot & authentication"
    # Not gated on "is this a live-install.sh install" -- deploy_autologin
    # is meant to run (and be checked) the same way on a standalone
    # `spacbr install` against a plain Arch box too, per its own comment.
    run_check "tty1 autologin configured" "grep -q -- \"--autologin \$USER \" /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null" "spacbr repair (or spacbr install) to run deploy_autologin"
    run_check "getty@tty1 enabled"  "systemctl is-enabled --quiet getty@tty1.service" "sudo systemctl enable getty@tty1.service"
    # LUKS2, unlike the checks above, genuinely isn't universal: it's
    # always on for a live-install.sh install (docs/architecture.md,
    # "Boot & authentication"), but Phase 2 alone can't retroactively
    # encrypt an already-existing plain Arch box's root partition --
    # same "not applicable, not a failure" shape as the btrfs-only
    # snapper checks below. lsblk's own TYPE field, not a SPACBR-specific
    # device-mapper name like "cryptroot" -- this needs to hold for any
    # dm-crypt root, not just one set up by this repo's own installer.
    if lsblk -no TYPE "$(findmnt -no SOURCE / 2>/dev/null)" 2>/dev/null | grep -qx crypt; then
        # Anchored to the actual HOOKS= line and word-bounded, same
        # reasoning as deploy_plymouth_theme's own HOOKS grep -- avoids a
        # false positive on the large commented-out example block every
        # mkinitcpio.conf ships.
        run_check "mkinitcpio has sd-encrypt hook" "grep -qE '^HOOKS=\(.*\bsd-encrypt\b' /etc/mkinitcpio.conf" "root is LUKS2-encrypted but sd-encrypt isn't in HOOKS -- the system wouldn't be able to unlock its own root from a rebuilt initramfs. See install/live-install.sh's mkinitcpio HOOKS block for the exact line."
        run_check "mkinitcpio has plymouth hook"   "grep -qE '^HOOKS=\(.*\bplymouth\b' /etc/mkinitcpio.conf" "root is LUKS2-encrypted but plymouth isn't in HOOKS -- the LUKS2 unlock prompt would fall back to a plain systemd-ask-password console agent instead of the themed one. spacbr repair, or add it by hand before sd-encrypt in HOOKS."
    fi

    info "Package management"
    # Readable without sudo -n gymnastics (unlike nftables.conf/the
    # polkit rule): /etc/pacman.conf is world-readable 644, so a plain
    # cmp works for every user, not just one with a cached credential.
    run_check "pacman.conf deployed" "cmp -s /etc/pacman.conf \"\$SPACBR_HOME/system/pacman/pacman.conf\" 2>/dev/null" "spacbr repair (or spacbr install) to deploy system/pacman/pacman.conf"
    run_check "multilib enabled"     "pacman-conf --repo-list 2>/dev/null | grep -qx multilib" "spacbr repair (or spacbr install) to deploy system/pacman/pacman.conf, which enables [multilib]"

    info "Suckless components"
    # Checked against the exact ~/.local/bin/<name> path SPACBR installs
    # to, not a bare `command -v` -- found for real that `command -v`
    # alone is both a false negative (this script's own shell process
    # never re-sources the profile that puts ~/.local/bin on PATH, so
    # it can't find a binary that's genuinely there) and a false
    # positive (clipmenu, a real SPACBR package, depends on the
    # official `dmenu` package, so a plain `command -v dmenu` happily
    # finds the vanilla unpatched /usr/bin/dmenu and reports success
    # even if the SPACBR-patched ~/.local/src/dmenu build had actually
    # failed). slock is the one exception, checked separately below --
    # it deliberately installs to /usr/local/bin, not ~/.local/bin, so
    # its setuid-root bit survives even on a system where /home is
    # mounted nosuid.
    run_check "dwm"                 "[ -x \"\$HOME/.local/bin/dwm\" ]" "cd .local/src/dwm && make && make install"
    run_check "dmenu"               "[ -x \"\$HOME/.local/bin/dmenu\" ]" "cd .local/src/dmenu && make && make install"
    run_check "st"                  "[ -x \"\$HOME/.local/bin/st\" ]" "cd .local/src/st && make && make install"
    run_check "dwmblocks"           "[ -x \"\$HOME/.local/bin/dwmblocks\" ]" "cd .local/src/blocks && make && make install"
    run_check "slock"               "command -v slock" "cd .local/src/slock && make && sudo make install"
    run_check "slock is setuid"     "[ -u \"\$(command -v slock)\" ]" "sudo chmod u+s \$(command -v slock)"

    info "Session infrastructure"
    run_check "dunst"               "command -v dunst" "pacman -S dunst"
    # Verified for real: dunst died twice in one session with "X
    # connection to :0 broken" and no Restart= in the stock unit meant
    # it only came back whenever some app's next notify-send happened
    # to trigger D-Bus reactivation. This checks the override actually
    # landed, not just that dunst itself is installed.
    run_check "dunst auto-restart"  "[ \"\$(systemctl --user show dunst.service -p Restart --value 2>/dev/null)\" = on-failure ]" "spacbr repair (deploys .config/systemd/user/dunst.service.d/override.conf), then systemctl --user daemon-reload"
    run_check "picom"               "command -v picom" "pacman -S picom"
    run_check "xss-lock"            "command -v xss-lock" "pacman -S xss-lock"
    # Real, severe bug found and fixed once already: dwm used to launch
    # via `dbus-launch dwm`, which spawns its *own* private bus and
    # points dwm's entire process tree at it instead of the real
    # systemd session bus dunst is D-Bus-activated on. Every
    # notify-send call from anything dwm ever spawns -- every dmenu
    # script, every keybinding -- silently went to a bus dunst was
    # never listening on. Testing notify-send over SSH never caught
    # this, since an SSH shell doesn't inherit dwm's environment and
    # finds the correct bus by auto-discovery instead. Only meaningful
    # with a real X session actually running (pgrep dwm) -- skipped
    # entirely otherwise, same "not applicable" shape as the
    # bluetooth-hardware-absent check below.
    if pgrep -x dwm >/dev/null 2>&1; then
        run_check "dwm on the real D-Bus session bus" "dwm_pid=\$(pgrep -x dwm | head -1); dwm_bus=\$(tr '\\0' '\\n' < /proc/\$dwm_pid/environ 2>/dev/null | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p'); real_bus=\$(systemctl --user show-environment 2>/dev/null | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p'); [ -n \"\$dwm_bus\" ] && [ \"\$dwm_bus\" = \"\$real_bus\" ]" "dwm is on a different D-Bus bus than systemd's real session bus -- notifications from dmenu scripts/keybindings will silently go nowhere. Check .config/xinitrc launches plain 'dwm', not 'dbus-launch dwm'; then log out and back in."
    fi

    info "Networking / audio / bluetooth"
    run_check "NetworkManager"      "command -v nmcli" "pacman -S networkmanager"
    run_check "NetworkManager active" "systemctl is-active --quiet NetworkManager" "sudo systemctl enable --now NetworkManager"
    run_check "nftables installed"  "command -v nft" "pacman -S nftables"
    run_check "nftables enabled"    "systemctl is-enabled --quiet nftables" "sudo systemctl enable --now nftables"
    # nftables.service is Type=oneshot -- it applies the ruleset once
    # and correctly reports "inactive" afterward (no ongoing process),
    # so is-active would be a false negative here. Check the actual
    # kernel ruleset instead: sudo -n, not blocking sudo, same reason
    # as the polkit rule check below -- never hang doctor on a password
    # prompt.
    run_check "firewall ruleset loaded" "sudo -n nft list ruleset 2>/dev/null | grep -q 'hook input'" "spacbr repair (or spacbr install) to deploy system/nftables/nftables.conf -- or re-run 'spacbr doctor' just after using sudo for something else"
    run_check "PipeWire"            "command -v pipewire" "pacman -S pipewire pipewire-pulse"
    run_check "WirePlumber"         "command -v wireplumber" "pacman -S wireplumber"
    # Verified for real: xinitrc used to start `pipewire &`/`pipewire-
    # pulse &`/`wireplumber &` as raw processes, which fought the
    # packages' own already-enabled systemd --user socket units for
    # the same socket paths -- the native PipeWire protocol (wpctl)
    # mostly still worked, but the PulseAudio-compat layer (pactl, and
    # anything using it, like ffmpeg's -f pulse audio recording) never
    # came up at all. xinitrc no longer starts them; this checks
    # systemd's own units are what's actually running instead.
    run_check "pipewire-pulse active" "systemctl --user is-active --quiet pipewire-pulse.socket" "systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service"
    run_check "BlueZ"               "command -v bluetoothctl" "pacman -S bluez bluez-utils"
    # /sys/class/bluetooth only exists if there's actual BT hardware --
    # on a desktop with none, systemd correctly leaves the (enabled)
    # service inactive rather than failing to start it, and that's not
    # a problem to report. Verified for real: a BT-less test machine
    # showed "bluetooth service active" as a false-positive failure
    # before this check accounted for hardware absence.
    run_check "bluetooth service active" "[ ! -d /sys/class/bluetooth ] || systemctl is-active --quiet bluetooth" "sudo systemctl enable --now bluetooth"
    run_check "mpd installed"       "command -v mpd" "pacman -S mpd rmpc"
    # mpd.socket, not mpd.service's own active state: socket-activated,
    # so mpd.service is correctly "inactive" until something (rmpc)
    # actually connects -- same reasoning as the nftables oneshot check
    # above.
    run_check "mpd.socket enabled"  "systemctl --user is-enabled --quiet mpd.socket" "systemctl --user enable --now mpd.socket"
    # Conditional on mpdris2-rs actually being installed, like its own
    # "mpdris2-rs (mpd MPRIS bridge)" check above -- no point failing
    # this if that one already reported it's deliberately not present.
    run_check "mpdris2-rs.service enabled" "! command -v mpdris2-rs >/dev/null 2>&1 || systemctl --user is-enabled --quiet mpdris2-rs.service" "systemctl --user enable --now mpdris2-rs.service"

    info "Snapshots"
    # snapper only makes sense on btrfs -- on any other filesystem,
    # skipping this (like the BT-hardware-absent check above) is
    # correct, not a problem to report.
    if [ "$(findmnt -no FSTYPE / 2>/dev/null)" = "btrfs" ]; then
        run_check "snapper installed"    "command -v snapper" "pacman -S snapper snap-pac"
        run_check "snapper 'root' config" "sudo -n snapper list-configs 2>/dev/null | grep -q '^root '" "spacbr repair (or spacbr install) to run setup_snapper -- or re-run 'spacbr doctor' just after using sudo for something else"
        run_check "snapper timers enabled" "systemctl is-enabled --quiet snapper-timeline.timer && systemctl is-enabled --quiet snapper-cleanup.timer" "sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer"
    fi

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
    # Skipped entirely in a VM, same as install_cpu_microcode itself --
    # a virtual CPU has no real hardware microcode to load, so neither
    # check applies there, the same "not applicable" spirit as the
    # bluetooth-hardware-absent check above.
    if ! detect_is_vm; then
        # Vendor-conditional: the "wrong" package for this CPU isn't a
        # failure to report, it's simply not applicable.
        run_check "CPU microcode package" "case \"\$(awk -F': ' '/vendor_id/{print \$2; exit}' /proc/cpuinfo)\" in GenuineIntel) pacman -Qi intel-ucode >/dev/null 2>&1 ;; AuthenticAMD) pacman -Qi amd-ucode >/dev/null 2>&1 ;; *) true ;; esac" "spacbr repair (runs install_cpu_microcode)"
        # Package-installed is necessary but not sufficient -- this
        # checks it's actually loading at boot, not just sitting in
        # /boot unused (see install_cpu_microcode's comment on the
        # GRUB caveat this would catch).
        run_check "CPU microcode loaded" "journalctl -k -b 0 --no-pager 2>/dev/null | grep -qi microcode" "package installed but not loading at boot -- on GRUB, try: sudo grub-mkconfig -o /boot/grub/grub.cfg"
    fi
    # Vendor-conditional like the CPU microcode check above -- checked
    # independently, not either-or, since a hybrid laptop can have both.
    if command -v lspci >/dev/null 2>&1; then
        _gpu_info="$(lspci -k 2>/dev/null | grep -iE 'vga|3d|display')"
        if echo "$_gpu_info" | grep -qi intel; then
            run_check "Intel GPU driver (mesa)" "pacman -Qi vulkan-intel >/dev/null 2>&1" "spacbr repair (runs install_gpu_drivers)"
        fi
        if echo "$_gpu_info" | grep -qiE 'advanced micro devices|amd|ati '; then
            run_check "AMD GPU driver (mesa)" "pacman -Qi vulkan-radeon >/dev/null 2>&1" "spacbr repair (runs install_gpu_drivers)"
        fi
    fi
    # btrfs excluded even on SSD/NVMe -- see detect_root_btrfs's
    # comment in detect.sh for why (async discard is the kernel default
    # for btrfs since 6.2, confirmed against archinstall's own source).
    if ! detect_root_btrfs && detect_root_nonrotational; then
        run_check "fstrim.timer enabled" "systemctl is-enabled --quiet fstrim.timer" "spacbr repair (runs setup_maintenance_timers)"
    fi

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
    # arc-gtk-theme is built from packages/aur-overrides/arc-gtk-theme
    # (a SPACBR-maintained PKGBUILD fork -- the published AUR one fails
    # to build outright, see that PKGBUILD's own header). Verified for
    # real: if it silently fails to install for any reason, every GTK
    # app just falls back to plain light GTK with zero indication
    # anything is wrong -- checking the config *says* Arc-Dark isn't
    # enough, since that's true even when the theme was never actually
    # installed. This checks the real theme files are on disk.
    run_check "GTK theme installed"        "[ -d /usr/share/themes/Arc-Dark ]" "arc-gtk-theme isn't installed -- re-run 'spacbr install' (or 'spacbr repair') to retry the packages/aur-overrides/arc-gtk-theme build, or install it manually"

    info "XDG layout"
    run_check "~/.config exists"    "[ -d \"\$XDG_CONFIG_HOME\" ]" "mkdir -p ~/.config"
    run_check "~/.local/bin exists" "[ -d \"\$HOME/.local/bin\" ]" "mkdir -p ~/.local/bin"
    run_check "~/.local/bin in PATH" "case \":\$PATH:\" in *:\"\$HOME/.local/bin\":*) true;; *) false;; esac" "check ~/.config/shell/profile is sourced"
    run_check "xinitrc present"     "[ -f \"\$XDG_CONFIG_HOME/xinitrc\" ]" "spacbr repair"

    info "Fonts"
    run_check "Hack font available" "fc-list | grep -qi hack" "pacman -S ttf-hack"

    info "Extras"
    run_check "tmux"      "command -v tmux" "pacman -S tmux"
    run_check "fzf"       "command -v fzf" "pacman -S fzf"
    run_check "nnn"       "command -v nnn" "pacman -S nnn"
    run_check "alacritty" "command -v alacritty" "pacman -S alacritty"
    run_check "paccache.timer enabled"   "systemctl is-enabled --quiet paccache.timer" "spacbr repair (runs setup_maintenance_timers)"
    run_check "reflector.timer enabled"  "systemctl is-enabled --quiet reflector.timer" "spacbr repair (runs setup_maintenance_timers)"
    run_check "netbird" "command -v netbird" "paru -S netbird"
    run_check "netbird enabled" "systemctl is-enabled --quiet netbird@main.service" "spacbr repair (runs setup_netbird) -- still needs 'netbird up' yourself to join a network"
    run_check "syncthing" "command -v syncthing" "pacman -S syncthing"
    run_check "syncthing.service enabled" "systemctl --user is-enabled --quiet syncthing.service" "spacbr repair (runs setup_syncthing)"
    run_check "localsend" "command -v localsend" "paru -S localsend"
    # mpdris2-rs is conditional on mpd actually being wanted -- not a
    # hard requirement the way mpd/rmpc themselves are, so this is
    # informational rather than something spacbr repair chases if it's
    # deliberately not installed.
    run_check "mpdris2-rs (mpd MPRIS bridge)" "command -v mpdris2-rs" "paru -S mpdris2-rs"
    run_check "git-delta" "command -v delta" "pacman -S git-delta"
    run_check "restic"    "command -v restic" "pacman -S restic"
    run_check "Claude Code CLI" "command -v claude" "npm config set prefix \$HOME/.local/share/npm && npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code"

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
