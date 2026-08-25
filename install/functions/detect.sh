# System detection. Sourced, not executed directly. Requires common.sh.

detect_arch_linux() {
    [ -f /etc/arch-release ] && return 0
    [ -f /etc/os-release ] && grep -q '^ID=arch' /etc/os-release && return 0
    return 1
}

detect_x86_64() {
    [ "$(uname -m)" = "x86_64" ]
}

# detect_root_nonrotational -- true if root's underlying block device
# reports itself as non-rotational (SSD/NVMe) via
# /sys/block/<disk>/queue/rotational. Shared by setup_maintenance_timers
# (services.sh, decides whether to enable fstrim.timer) and its
# matching doctor check, so the two can't drift apart. PKNAME maps a
# partition to its parent disk (e.g. nvme0n1p2 -> nvme0n1); the sed
# fallback handles the case PKNAME comes back empty (root directly on
# a bare disk, or an lsblk that doesn't support PKNAME).
detect_root_nonrotational() {
    local root_dev root_disk
    root_dev="$(findmnt -no SOURCE / 2>/dev/null)"
    [ -n "$root_dev" ] || return 1
    root_disk="$(lsblk -no PKNAME "$root_dev" 2>/dev/null)"
    [ -z "$root_disk" ] && root_disk="$(basename "$root_dev" | sed -E 's/p?[0-9]+$//')"
    [ "$(cat "/sys/block/$root_disk/queue/rotational" 2>/dev/null)" = "0" ]
}

# detect_is_vm -- true if running inside a VM, via systemd-detect-virt
# (part of systemd, a hard base dependency already, no new package).
# `-q` sets exit status only (0 = virtualized), no output to parse.
# Shared by install_cpu_microcode (packages.sh, skips microcode
# entirely in a VM) and its matching doctor checks, so the two can't
# drift apart -- same pairing pattern as detect_root_nonrotational.
detect_is_vm() {
    command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt -q
}

# detect_root_btrfs -- true if root's filesystem type is btrfs.
# Shared by setup_snapper's own inline check (services.sh) and the
# fstrim.timer logic (setup_maintenance_timers, its doctor check):
# btrfs has had async discard enabled by default since kernel 6.2
# (confirmed against archlinux/archinstall issue #1837 and the kernel
# source it links), which makes periodic fstrim.timer redundant on
# btrfs specifically -- archinstall's own installer.py disables it for
# exactly this reason (_prepare_fs_type: `if fs_type == BTRFS:
# self._disable_fstrim = True`). Not harmful to run both, just pointless,
# and this repo's own package philosophy (§39) treats pointless as
# reason enough to skip.
detect_root_btrfs() {
    [ "$(findmnt -no FSTYPE / 2>/dev/null)" = "btrfs" ]
}

require_platform() {
    detect_arch_linux || die "SPACBR targets Arch Linux only. /etc/arch-release or /etc/os-release ID=arch not found."
    detect_x86_64 || die "SPACBR targets x86_64 only. Detected: $(uname -m)"
    ok "Arch Linux, x86_64"
}

# require_sudo -- nearly every install/update/repair step (package
# installs, system file deploys, service management) runs through
# sudo. Checked as its own explicit pre-flight step instead of left to
# fail wherever the first `sudo` call in a much longer script happens
# to land -- a genuinely minimal Arch install (a manual `pacstrap
# /mnt base linux linux-firmware` install per the Arch wiki, not
# archinstall's guided flow, which normally sets this up itself) has
# neither sudo installed nor a wheel-group user configured by default:
# the `base` group doesn't include sudo at all. A raw "sudo: command
# not found" or "eightharsh is not in the sudoers file" surfacing 40
# lines into package installation is a bad first impression for
# exactly the audience most likely to hit it -- someone following the
# manual install path for the first time.
require_sudo() {
    [ "$(id -u)" -eq 0 ] && die "run this as a regular user with sudo access, not as root. Create one first: useradd -m -G wheel -s /bin/bash <user> && passwd <user>, then log in as that user and re-run this."
    command -v sudo >/dev/null 2>&1 || die "sudo not found. As root: pacman -S sudo && usermod -aG wheel \$USER && EDITOR=nano visudo (uncomment '%wheel ALL=(ALL:ALL) ALL'), then log out and back in and re-run this."
    sudo -v || die "sudo didn't accept your credentials. Confirm your user is actually in the wheel group (groups \$USER) and that sudoers has '%wheel ALL=(ALL:ALL) ALL' uncommented (EDITOR=nano visudo)."
    ok "sudo access confirmed"

    # Keep the cached credential warm for the rest of the run. Found for
    # real: a paru AUR build (299 packages plus building paru itself,
    # then netbird/mpdris2-rs from source) easily outlasts sudo's
    # default timestamp_timeout, and the resulting mid-build password
    # re-prompt is buried in cargo/makepkg output -- easy to miss even
    # watching the terminal, and paru gives up after 3 failed attempts,
    # silently failing just that package instead of stopping the script.
    # Refreshed in the background every minute, killed on exit.
    ( while true; do sleep 60; sudo -n true 2>/dev/null; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
}
