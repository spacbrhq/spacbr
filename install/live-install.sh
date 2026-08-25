#!/bin/sh
# SPACBR live installer -- run this from the Arch Linux live ISO,
# before anything else exists. Mirrors archinstall's own guided-
# installer UX (answer a handful of questions, confirm once clearly,
# then it does everything) but deliberately does NOT try to be a
# general-purpose installer the way archinstall is -- no LVM, no RAID,
# no disk-encryption, no partition-layout customization, no profile
# menu. One disk, one layout, one opinionated configuration. SPACBR is
# an opinionated personal system (CLAUDE.md SS1); this is the
# opinionated personal installer to match. If you need something this
# script doesn't do, use archinstall (or a manual install) to get a
# base Arch system running, then pick up at "Getting the installer
# onto the machine" in docs/prerequisites.md.
#
# TWO-PHASE MODEL, same "tiny bootstrap -> real installer" shape this
# repo already uses for release/bootstrap.sh:
#   Phase 1 (this script, live ISO, as root): partition, format,
#     mount, pacstrap a minimal base system, configure just enough to
#     boot and log in, clone this repo into the new user's home.
#   Phase 2 (install/install.sh, after rebooting into the new system,
#     as that user): everything SPACBR actually is -- packages,
#     dotfiles, Suckless builds, dmenu scripts, services, CPU
#     microcode, GPU drivers, maintenance timers.
#
# This script deliberately does NOT try to run install.sh itself
# inside the arch-chroot here. It can't: install.sh enables services
# with `systemctl enable --now`, and there is no running systemd
# instance inside an arch-chroot for "--now" to start anything
# against -- only `systemctl enable` (a symlink, no running init
# needed) works there. Reboot into the real, running system and let
# install.sh do its actual job there.
#
# Configuration baked in below (see docs/architecture.md's "Live
# installer" section for the full reasoning on every choice):
#   - Locale: en_US.UTF-8 only, no prompt -- not something to
#     second-guess when it's already decided.
#   - Keyboard: prompted (vconsole KEYMAP), default "us".
#   - Console font: default8x16 (kbd's own standard default, not
#     something worth prompting for).
#   - Mirrors: reflector, HTTPS only, Japan + South Korea (real,
#     specific, deliberately narrow country selection -- not "closest
#     to me", which this script has no reliable way to determine on
#     a live ISO anyway).
#   - Disk: single disk, GPT, 1GiB EFI System Partition + btrfs for
#     everything else, mounted directly (no subvolume -- matches
#     archinstall's own default_layout exactly, verified against a
#     real user_configuration.json). No swap partition -- zram instead
#     (zstd compression), matching archinstall's own current default.
#   - Bootloader: Limine, UEFI, Unified Kernel Images, installed to
#     the *removable* EFI path (EFI/BOOT/BOOTX64.EFI) rather than a
#     machine-specific NVRAM boot entry -- more portable, survives a
#     NVRAM reset, no efibootmgr entry to go stale.
#   - Kernels: linux AND linux-lts, each gets its own UKI/boot entry.
#   - Plymouth: enabled, wired into mkinitcpio's HOOKS.
#   - NTP: systemd-timesyncd enabled.
#   - Timezone: prompted, defaults to Asia/Kolkata.
#   - Root password + a real sudo user, both prompted.
#
# NOT tested end-to-end against real hardware or a VM -- built by
# directly reading archinstall's own installer.py for every proven
# pattern this follows (disk safety confirmation, GPT layout, Limine's
# exact install sequence and config format, UKI generation via
# mkinitcpio presets), cross-checked against this repo's own real test
# machine's actual shipped mkinitcpio.d preset/HOOKS files where
# archinstall's own source left something ambiguous -- but never
# actually run start-to-finish. A live ISO install is a genuinely
# destructive operation with no undo. Test this in a disposable VM
# before ever pointing it at real hardware. If anything here looks
# wrong, stop and fix it before continuing, don't push through.

set -eu

# ---------------------------------------------------------------------
# Self-contained helpers (common.sh doesn't exist yet -- this repo
# isn't cloned until Phase 1 finishes)
# ---------------------------------------------------------------------

_color() { [ -t 1 ] && printf '\033[%sm' "$1" || true; }
_reset() { [ -t 1 ] && printf '\033[0m' || true; }
info()   { printf '%s %s\n' "$(_color 36)::$(_reset)" "$*"; }
ok()     { printf '%s %s\n' "$(_color 32)✓$(_reset)" "$*"; }
warn()   { printf '%s %s\n' "$(_color 33)!$(_reset)" "$*" >&2; }
error()  { printf '%s %s\n' "$(_color 31)✗$(_reset)" "$*" >&2; }
die()    { error "$*"; exit 1; }

confirm() {
    printf '%s [y/N] ' "$1"
    read -r reply
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# Reads a value with a default shown in brackets; empty input keeps
# the default. Not for passwords -- see read_password below.
prompt() {
    _var_name="$1"; _label="$2"; _default="${3:-}"
    if [ -n "$_default" ]; then
        printf '%s [%s]: ' "$_label" "$_default"
    else
        printf '%s: ' "$_label"
    fi
    read -r _input
    eval "$_var_name=\"\${_input:-\$_default}\""
}

# Reads a password twice with echo off, dies on mismatch. Plain POSIX
# `stty -echo`/`stty echo` rather than bash's `read -s`, since this
# needs to work under whatever /bin/sh actually is on the live ISO.
#
# `|| true` on both stty calls: found for real that a plain
# `ssh host 'command'` (no -t, no real tty allocated) makes `stty
# -echo` fail outright ("Inappropriate ioctl for device"), and under
# this script's own `set -eu`, that one failed stty call killed the
# entire script instantly at the very first password prompt -- before
# any disk operation had even been offered, but still a real crash for
# no good reason. `stty` failing here just means this session has no
# real tty to hide input on; degrading to visible password entry in
# that specific case is a reasonable fallback, not a security
# incident -- the normal path (a real console, or `ssh -t`) still
# hides it correctly.
read_password() {
    _var_name="$1"; _label="$2"
    while true; do
        stty -echo 2>/dev/null || true
        printf '%s: ' "$_label"
        read -r _pw1
        printf '\n'
        printf '%s (again): ' "$_label"
        read -r _pw2
        printf '\n'
        stty echo 2>/dev/null || true
        if [ "$_pw1" != "$_pw2" ]; then
            warn "passwords didn't match, try again"
            continue
        fi
        if [ -z "$_pw1" ]; then
            warn "password can't be empty, try again"
            continue
        fi
        break
    done
    eval "$_var_name=\"\$_pw1\""
}

# ---------------------------------------------------------------------
# Pre-flight checks -- refuse to run anywhere this could do real harm
# ---------------------------------------------------------------------

[ "$(id -u)" -eq 0 ] || die "run this as root -- you should already be root by default on the Arch live ISO."

[ -d /sys/firmware/efi ] || die "this machine isn't booted in UEFI mode (no /sys/firmware/efi). This script only supports UEFI + Limine -- rebooting the live USB in UEFI mode (check your firmware/BIOS boot menu) is usually the fix. For legacy BIOS, use archinstall or a manual install instead."

# Best-effort "is this actually the live ISO, not someone's real
# installed system" check -- refuses to run on an already-installed
# machine rather than risk it. The live ISO's root is a squashfs
# overlay; a real installed system's isn't.
if ! mount | grep -q ' on / .*\(squashfs\|overlay\|airootfs\)'; then
    die "this doesn't look like the Arch live ISO environment (root isn't squashfs/overlay). Refusing to run -- this script partitions a disk, and running it against an already-installed system would destroy it. If you're already on an installed Arch system, you don't need this script: see docs/prerequisites.md instead."
fi

command -v sgdisk >/dev/null 2>&1 || die "sgdisk not found (gptfdisk) -- this shouldn't happen on the stock Arch ISO. Is this actually the Arch live ISO?"
command -v pacstrap >/dev/null 2>&1 || die "pacstrap not found (arch-install-scripts) -- this shouldn't happen on the stock Arch ISO."

info "Checking network connectivity..."
if ! curl -fsS --max-time 5 -o /dev/null https://archlinux.org 2>/dev/null; then
    die "no network connectivity (couldn't reach archlinux.org). Connect first -- 'iwctl' for Wi-Fi, or plug in Ethernet -- then re-run this."
fi
ok "network reachable"

# ---------------------------------------------------------------------
# Fixed configuration -- not prompted, deliberately decided (see the
# header comment above and docs/architecture.md for the reasoning
# behind each one)
# ---------------------------------------------------------------------

LOCALE="en_US.UTF-8"
CONSOLE_FONT="default8x16"
MIRROR_COUNTRIES="Japan,South Korea"
KERNELS="linux linux-lts"

# ---------------------------------------------------------------------
# Gather configuration -- all prompts up front, nothing destructive
# runs until the final confirmation after this whole section
# ---------------------------------------------------------------------

printf '\n%s\n\n' "SPACBR live installer -- Phase 1 (disk, base system, bootloader)"

info "Available disks:"
lsblk -dpno NAME,SIZE,MODEL,TYPE | awk '$4=="disk"{ $4=""; print }'
printf '\n'
prompt DISK "Disk to install to (full path, e.g. /dev/nvme0n1 or /dev/sda)" ""
[ -b "$DISK" ] || die "no such block device: $DISK"

case "$DISK" in
    *nvme*|*mmcblk*) PART_PREFIX="${DISK}p" ;;
    *) PART_PREFIX="$DISK" ;;
esac
EFI_PART="${PART_PREFIX}1"
ROOT_PART="${PART_PREFIX}2"

prompt TARGET_HOSTNAME "Hostname" "spacbr"
prompt USERNAME "Username (this account gets sudo -- SPACBR itself installs as this user)" ""
[ -n "$USERNAME" ] || die "username can't be empty"
read_password USER_PASSWORD "Password for $USERNAME"
read_password ROOT_PASSWORD "root password (for emergency/rescue access -- CLAUDE.md SS88: you must always be able to reach a recovery shell)"
prompt KEYMAP "Keyboard layout (vconsole keymap, e.g. us, uk, de-latin1)" "us"
if ! loadkeys "$KEYMAP" 2>/dev/null; then
    warn "'$KEYMAP' doesn't look like a valid keymap (loadkeys rejected it) -- falling back to 'us'"
    KEYMAP="us"
fi
prompt TIMEZONE "Timezone (Region/City -- 'timedatectl list-timezones' to check)" "Asia/Kolkata"
prompt SPACBR_REPO_URL "SPACBR repo URL to clone (override if spacbrhq/spacbr on GitHub isn't live yet -- see release/README.md)" "https://github.com/spacbrhq/spacbr"

# ---------------------------------------------------------------------
# Final confirmation -- the one gate before anything destructive
# ---------------------------------------------------------------------

printf '\n%s\n' "About to:"
printf '  - COMPLETELY ERASE %s (every partition, all data, unrecoverable)\n' "$DISK"
printf '  - Create: %s (1GiB, EFI System Partition, FAT32), %s (rest of disk, btrfs)\n' "$EFI_PART" "$ROOT_PART"
printf '  - btrfs mounted directly at / (no subvolume, matching archinstall default_layout)\n'
printf '  - Install a minimal Arch base (kernels: %s) + Limine (UKI, removable EFI path)\n' "$KERNELS"
printf '  - Locale %s, keymap %s, console font %s, timezone %s\n' "$LOCALE" "$KEYMAP" "$CONSOLE_FONT" "$TIMEZONE"
printf '  - Mirrors: reflector, HTTPS, %s\n' "$MIRROR_COUNTRIES"
printf '  - Hostname "%s", user "%s" with sudo, root password set (rescue access)\n' "$TARGET_HOSTNAME" "$USERNAME"
printf '  - NetworkManager + systemd-timesyncd (NTP) + sshd enabled, zram swap, Plymouth (fade-in theme)\n'
printf '  - Clone %s into /home/%s/spacbr\n' "$SPACBR_REPO_URL" "$USERNAME"
printf '  - Set up %s to run install/install.sh automatically the FIRST time you log\n' "$USERNAME"
printf '    in after reboot (normal password login, not auto-login) -- that installs\n'
printf '    the actual SPACBR desktop (packages, dotfiles, Suckless, services, GPU\n'
printf '    drivers) and starts dwm on its own once done. One reboot, one login,\n'
printf '    nothing else to type.\n\n'

printf 'Type the disk path again to confirm ERASING %s: ' "$DISK"
read -r disk_confirm
[ "$disk_confirm" = "$DISK" ] || die "confirmation didn't match -- aborted, nothing was touched."

confirm "This is the last check. Continue?" || die "aborted, nothing was touched."

# ---------------------------------------------------------------------
# Live-session console setup (doesn't touch the target -- just makes
# the rest of this session's own prompts/output use what was chosen)
# ---------------------------------------------------------------------

loadkeys "$KEYMAP" 2>/dev/null || true
setfont "$CONSOLE_FONT" 2>/dev/null || warn "couldn't set console font $CONSOLE_FONT on this live session -- harmless, the target system gets it regardless"

# ---------------------------------------------------------------------
# Partition, format, mount
# ---------------------------------------------------------------------

info "Wiping old filesystem/partition-table signatures on $DISK..."
# sgdisk --zap-all below only clears GPT structures -- a previously
# used disk (plausible for a live-ISO installer; disks handed to this
# script are rarely factory-fresh) can still have stale MBR boot code
# or old filesystem superblocks that confuse blkid/udev's re-scan even
# after repartitioning, if a new partition happens to overlap an old
# one's signature location. wipefs -a clears all of that first.
wipefs -af "$DISK" >/dev/null

info "Partitioning $DISK..."
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+1GiB -t1:ef00 -c1:"EFI System Partition" "$DISK"
sgdisk -n2:0:0     -t2:8300 -c2:"SPACBR root"          "$DISK"
partprobe "$DISK" 2>/dev/null || true
sleep 2
ok "partitioned"

info "Formatting..."
mkfs.fat -F32 -n EFI "$EFI_PART"
mkfs.btrfs -f -L SPACBR "$ROOT_PART"
ok "formatted"

info "Mounting..."
# No subvolume -- the raw btrfs partition is mounted directly at /,
# matching archinstall's own "default_layout" behavior exactly
# (verified against a real user_configuration.json generated by
# archinstall on this repo's own test machine: its disk_config has an
# empty "btrfs": [] array, meaning no subvolume was created, just
# "compress=zstd" as the only mount option -- no "noatime", no "ssd"
# flag, no compression-level suffix. An earlier version of this script
# added a "@" subvolume and extra mount options as an improvement;
# corrected to match the real reference exactly instead.
mount -o compress=zstd "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot
ok "mounted at /mnt"

# ---------------------------------------------------------------------
# CPU microcode + VM detection -- same logic as install_cpu_microcode
# (packages.sh), inlined since that file doesn't exist here yet.
# Skips in a VM, matching archinstall's own _get_microcode()/
# SysInfo.is_vm() (systemd-detect-virt).
# ---------------------------------------------------------------------

UCODE_PKG=""
if ! { command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt -q; }; then
    CPU_VENDOR="$(awk -F': ' '/vendor_id/{print $2; exit}' /proc/cpuinfo 2>/dev/null)"
    case "$CPU_VENDOR" in
        GenuineIntel) UCODE_PKG="intel-ucode" ;;
        AuthenticAMD) UCODE_PKG="amd-ucode" ;;
        *) warn "unrecognized CPU vendor '$CPU_VENDOR' -- no microcode package" ;;
    esac
else
    ok "running in a VM ($(systemd-detect-virt 2>/dev/null)) -- skipping CPU microcode"
fi

# ---------------------------------------------------------------------
# Mirrors -- HTTPS only, Japan + South Korea specifically (not
# "closest"/"fastest globally" -- a deliberate, narrow choice made
# ahead of time, not something this script second-guesses)
# ---------------------------------------------------------------------

if command -v reflector >/dev/null 2>&1; then
    info "Setting mirrors ($MIRROR_COUNTRIES, HTTPS)..."
    if reflector --country "$MIRROR_COUNTRIES" --protocol https --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null; then
        ok "mirrorlist set to $MIRROR_COUNTRIES"
    else
        warn "reflector couldn't find mirrors for '$MIRROR_COUNTRIES' -- continuing with the ISO's existing mirrorlist"
    fi
else
    warn "reflector not found on this ISO -- continuing with the existing mirrorlist"
fi

# ---------------------------------------------------------------------
# pacstrap -- deliberately minimal beyond what this phase itself
# needs. install/install.sh installs the real package set
# (packages/{base,x11,desktop,hardware}) once booted for real.
# ---------------------------------------------------------------------

info "Installing base system (pacstrap: $KERNELS, limine, plymouth)..."
# shellcheck disable=SC2086
pacstrap -K /mnt base $KERNELS linux-firmware btrfs-progs networkmanager sudo git \
    efibootmgr limine plymouth zram-generator openssh $UCODE_PKG
ok "base system installed"

info "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
ok "fstab written"

# ---------------------------------------------------------------------
# Configure the new system. Plain file edits happen directly against
# /mnt/... from the host side; arch-chroot is reserved for steps that
# genuinely need the target's own tools/context.
# ---------------------------------------------------------------------

info "Setting console keymap/font, timezone ($TIMEZONE), locale ($LOCALE)..."
cat > /mnt/etc/vconsole.conf <<EOF
KEYMAP=$KEYMAP
FONT=$CONSOLE_FONT
EOF
arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
arch-chroot /mnt hwclock --systohc
if ! grep -q "^#\?$LOCALE" /mnt/etc/locale.gen 2>/dev/null; then
    die "locale '$LOCALE' not found in the target's /etc/locale.gen -- this shouldn't happen for en_US.UTF-8 on a stock base install. Stopping before generating a broken locale."
fi
sed -i "s/^#\($LOCALE\)/\1/" /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
printf 'LANG=%s\n' "$LOCALE" > /mnt/etc/locale.conf
ok "keymap, font, timezone, locale set"

info "Setting hostname ($TARGET_HOSTNAME)..."
printf '%s\n' "$TARGET_HOSTNAME" > /mnt/etc/hostname
cat > /mnt/etc/hosts <<EOF
127.0.0.1	localhost
::1		localhost
127.0.1.1	$TARGET_HOSTNAME.localdomain	$TARGET_HOSTNAME
EOF
ok "hostname set"

info "Setting root password..."
printf '%s:%s\n' root "$ROOT_PASSWORD" | arch-chroot /mnt chpasswd
ok "root password set (rescue/emergency access only -- day to day, use $USERNAME + sudo)"

info "Creating user $USERNAME..."
arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$USERNAME"
printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | arch-chroot /mnt chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers
# Verify the sed actually matched -- don't just assume it worked. If
# the shipped /etc/sudoers ever has a differently-formatted commented
# line, this would otherwise silently leave $USERNAME with no sudo
# access at all, while this script still claims success -- and
# install.sh's own require_sudo() would then fail confusingly on
# first Phase 2 run with no clue why, potentially minutes/reboots
# later, far from this actual root cause.
if ! grep -q '^%wheel ALL=(ALL:ALL) ALL' /mnt/etc/sudoers; then
    die "couldn't confirm %wheel is actually uncommented in /mnt/etc/sudoers -- $USERNAME may have NO sudo access. Stopping here rather than claim success: check /mnt/etc/sudoers by hand (EDITOR=nano arch-chroot /mnt visudo) before continuing."
fi
ok "user $USERNAME created with sudo"

# ---------------------------------------------------------------------
# First-login bootstrap -- this is what actually bridges Phase 1 into
# Phase 2 as one continuous experience (boot -> log in -> fully
# configured desktop) instead of two separate manual commands.
#
# Deliberately NOT tty auto-login: that would mean every future boot
# skips authentication entirely, a real standing security tradeoff for
# the whole life of the machine just to save typing one command once.
# This still requires a normal password login -- the automation is in
# what happens *after* that login succeeds, not in skipping login
# itself. Written as .bash_profile (not .zprofile/.zshrc): the user
# useradd'd above has bash as its shell until install.sh's own
# set_default_shell() switches it to zsh, and Arch's stock /etc/skel
# doesn't ship a .bash_profile, so this is guaranteed to be the one
# bash reads. Once the shell switches to zsh, bash (and this file)
# is never read by a normal login again -- naturally inert from then
# on, nothing left to clean up.
# ---------------------------------------------------------------------

info "Writing first-login bootstrap for $USERNAME..."
cat > "/mnt/home/$USERNAME/.bash_profile" <<'PROFILE_EOF'
# SPACBR first-boot bootstrap -- created by install/live-install.sh.
# Runs install/install.sh automatically on first login, then hands off
# to a real zsh login shell (whose own .zshrc has its own tty1
# auto-startx logic, so this chain reaches a running desktop with no
# further manual steps). Marker removed before running, not after --
# deliberately only ever attempts this once automatically; if
# install.sh fails partway (e.g. no network yet), the fix is a manual
# re-run (it's safe/idempotent to re-run, same as every other
# spacbr install/update/repair), not an automatic retry loop on every
# subsequent login that could otherwise hang forever on a persistent
# failure.
if [ -f "$HOME/.spacbr-first-boot" ] && [ -d "$HOME/spacbr" ]; then
    rm -f "$HOME/.spacbr-first-boot"
    printf '\nSPACBR: first login -- running the installer now (this happens once).\n\n'
    ( cd "$HOME/spacbr" && ./install/install.sh )
    printf '\nSPACBR: installer finished. Starting your real shell...\n'
    exec zsh -l
fi
PROFILE_EOF
touch "/mnt/home/$USERNAME/.spacbr-first-boot"
arch-chroot /mnt chown "$USERNAME:$USERNAME" "/home/$USERNAME/.bash_profile" "/home/$USERNAME/.spacbr-first-boot"
sync
# Read the marker back rather than trusting touch's exit status alone --
# found for real that this file went missing on the actual installed
# system despite this section completing without error (same mount,
# same unmount as .bash_profile, which DID persist correctly), root
# cause unconfirmed. Whatever caused it, a silent missing marker means
# .bash_profile's "if" is simply false forever and the user gets a
# bare shell on first login with no indication anything was supposed
# to happen -- so verify it landed and fail loudly here instead.
[ -f "/mnt/home/$USERNAME/.spacbr-first-boot" ] || die "wrote /home/$USERNAME/.spacbr-first-boot but it's not there on read-back -- the first-login bootstrap would silently never fire. Stopping before declaring success."
ok "first-login bootstrap ready"

info "Configuring zram swap..."
mkdir -p /mnt/etc/systemd
cat > /mnt/etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
EOF
ok "zram-generator configured (activates automatically at boot, no separate swap partition)"

info "Enabling NetworkManager, NTP, and sshd (enable only -- can't start a service against a chroot's non-running init)..."
arch-chroot /mnt systemctl enable NetworkManager
arch-chroot /mnt systemctl enable systemd-timesyncd
# sshd: system/nftables/nftables.conf (Phase 2) already allows and
# assumes port 22 is genuinely in use ("SSH is allowed because this
# machine actually runs sshd") -- without this, that assumption was
# never actually true for anything freshly installed by this script.
# Also the only way to reach a machine with no physical/KVM access
# after this reboots, which is the case for this repo's own test
# machine.
arch-chroot /mnt systemctl enable sshd
ok "NetworkManager, systemd-timesyncd, and sshd enabled"

# ---------------------------------------------------------------------
# Plymouth: wire the hook into mkinitcpio, right after the hook that
# sets up the device manager -- the documented Arch wiki position
# (must run before the hooks that produce console output), for
# whichever of the two current mkinitcpio hook families is in play:
# the legacy udev-based set ("base udev ..."), verified against this
# repo's own real test machine's actual shipped HOOKS line ("base udev
# autodetect microcode modconf kms keyboard keymap consolefont block
# filesystems fsck"), or the newer systemd-based set ("base systemd
# ..."), tried second since it wasn't the one confirmed on real
# hardware. Whichever a freshly pacstrapped mkinitcpio actually ships
# by default may not match either exactly -- this is a best-effort
# insertion with a safe fallback (warn and continue, not die), not a
# guarantee.
# ---------------------------------------------------------------------

info "Enabling Plymouth (theme: fade-in)..."
if grep -q '^HOOKS=(base udev ' /mnt/etc/mkinitcpio.conf; then
    sed -i 's/^HOOKS=(base udev /HOOKS=(base udev plymouth /' /mnt/etc/mkinitcpio.conf
    ok "plymouth hook added to mkinitcpio HOOKS (udev-based hook set)"
elif grep -q '^HOOKS=(base systemd ' /mnt/etc/mkinitcpio.conf; then
    sed -i 's/^HOOKS=(base systemd /HOOKS=(base systemd plymouth /' /mnt/etc/mkinitcpio.conf
    ok "plymouth hook added to mkinitcpio HOOKS (systemd-based hook set)"
else
    warn "mkinitcpio.conf's HOOKS line didn't match either expected prefix ('base udev ...' or 'base systemd ...') -- add 'plymouth' to it yourself (right after the device-manager hook) before it'll actually show a splash. Continuing without it; this does not block booting."
fi
# fade-in specifically -- matches the theme selected in the real
# user_configuration.json this script was verified against, not the
# package's own default theme.
if arch-chroot /mnt plymouth-set-default-theme fade-in 2>/dev/null; then
    ok "plymouth theme set to fade-in"
else
    warn "couldn't set plymouth theme to fade-in (plymouth-set-default-theme failed) -- continuing with whatever the package default is"
fi

# ---------------------------------------------------------------------
# Unified Kernel Images. /etc/kernel/cmdline is what mkinitcpio's UKI
# generation reads for the embedded command line (confirmed against
# archinstall's own _config_uki(), which writes exactly this file for
# exactly this reason). "quiet splash" so Plymouth's splash isn't
# fighting kernel boot text for the screen.
# ---------------------------------------------------------------------

ROOT_PARTUUID="$(blkid -s PARTUUID -o value "$ROOT_PART")"
[ -n "$ROOT_PARTUUID" ] || die "couldn't read PARTUUID for $ROOT_PART -- the boot config would be wrong, stopping before writing it."

KERNEL_CMDLINE="root=PARTUUID=$ROOT_PARTUUID rw zswap.enabled=0 quiet splash"
mkdir -p /mnt/etc/kernel
printf '%s\n' "$KERNEL_CMDLINE" > /mnt/etc/kernel/cmdline

info "Configuring UKI generation for: $KERNELS..."
mkdir -p /mnt/boot/EFI/Linux
for kernel in $KERNELS; do
    preset="/mnt/etc/mkinitcpio.d/$kernel.preset"
    if [ ! -f "$preset" ]; then
        warn "$preset not found (expected from the $kernel package) -- skipping its UKI config"
        continue
    fi
    cat > "$preset" <<EOF
# mkinitcpio preset file for '$kernel' (SPACBR: UKI only, no plain initramfs)

ALL_kver="/boot/vmlinuz-$kernel"

PRESETS=('default')

default_uki="/boot/EFI/Linux/arch-$kernel.efi"
EOF
    ok "$kernel.preset configured (UKI -> /boot/EFI/Linux/arch-$kernel.efi)"
done

info "Building Unified Kernel Images (mkinitcpio -P)..."
arch-chroot /mnt mkinitcpio -P
for kernel in $KERNELS; do
    [ -f "/mnt/boot/EFI/Linux/arch-$kernel.efi" ] || die "mkinitcpio finished but /boot/EFI/Linux/arch-$kernel.efi wasn't created -- something's wrong with the $kernel preset. Stopping before declaring success on a system that can't actually boot $kernel."
done
ok "UKIs built for: $KERNELS"

# ---------------------------------------------------------------------
# Limine -- installed to the removable EFI path (EFI/BOOT/BOOTX64.EFI),
# not a machine-specific NVRAM boot entry. Sequence and config format
# follow archinstall's own _add_limine_bootloader() (archlinux/
# archinstall, installer.py) exactly for the removable+UEFI+UKI case.
#
# This runs AFTER the UKIs are built above, not before: limine.conf's
# entries are gated on each arch-$kernel.efi actually existing, and an
# earlier version of this script wrote that config before mkinitcpio
# had run -- every existence check failed, "continue" skipped every
# entry, and the result was a limine.conf with a timeout line and zero
# boot entries. Confirmed for real on the test machine: Limine's own
# boot screen reported "config file contains no valid entries" after a
# clean-looking install run. Keep this block after the UKI build.
# ---------------------------------------------------------------------

info "Installing Limine (removable EFI path)..."
mkdir -p /mnt/boot/EFI/BOOT
cp /mnt/usr/share/limine/BOOTX64.EFI /mnt/boot/EFI/BOOT/
[ -f /mnt/usr/share/limine/BOOTIA32.EFI ] && cp /mnt/usr/share/limine/BOOTIA32.EFI /mnt/boot/EFI/BOOT/

{
    printf 'timeout: 5\n'
    for kernel in $KERNELS; do
        [ -f "/mnt/boot/EFI/Linux/arch-$kernel.efi" ] || continue
        printf '\n/Arch Linux (%s)\n' "$kernel"
        printf '    protocol: efi\n'
        printf '    path: boot():/EFI/Linux/arch-%s.efi\n' "$kernel"
    done
} > /mnt/boot/EFI/BOOT/limine.conf
# UKIs embed their own cmdline (from /etc/kernel/cmdline above) --
# Limine's config doesn't need to repeat it for protocol: efi entries.
if ! grep -q '^/Arch Linux' /mnt/boot/EFI/BOOT/limine.conf; then
    die "limine.conf has no boot entries -- the UKIs above exist but none matched. Stopping before declaring success on a system that can't boot."
fi

# Pacman hook: re-deploy the Limine EFI binaries after every `limine`
# package upgrade, same as archinstall's own generated hook -- without
# this, an upgraded limine package's binaries never reach the ESP
# until this script (or a person) copies them there again by hand.
mkdir -p /mnt/etc/pacman.d/hooks
cat > /mnt/etc/pacman.d/hooks/99-limine.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = limine

[Action]
Description = Deploying Limine after upgrade...
When = PostTransaction
Exec = /bin/sh -c "/usr/bin/cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/ && { [ -f /usr/share/limine/BOOTIA32.EFI ] && /usr/bin/cp /usr/share/limine/BOOTIA32.EFI /boot/EFI/BOOT/ || true; }"
EOF
ok "Limine installed to /boot/EFI/BOOT (removable path)"

# ---------------------------------------------------------------------
# Clone SPACBR into the new user's home -- runuser, not sudo: root
# (this script) doesn't need a password to act as another user.
#
# GIT_TERMINAL_PROMPT=0 -- found for real that a private or not-yet-
# existing repo URL doesn't make `git clone` fail, it makes git prompt
# interactively for a username, then a password, on a plain scripted
# invocation with no way to answer either. That's not a fast failure,
# it's an indefinite hang -- confirmed live: this exact thing happened
# with the default spacbrhq/spacbr URL against this repo's own real
# test machine, and required manually finding and killing the stuck
# git process (ps aux showed it parked on the Username prompt) to
# unblock the rest of the script. GIT_TERMINAL_PROMPT=0 makes git fail
# immediately with a clear "terminal prompts disabled" error instead,
# which the existing else-branch below already handles correctly --
# this was always the intended failure path, it just needed git to
# actually take it.
# ---------------------------------------------------------------------

info "Cloning $SPACBR_REPO_URL..."
if arch-chroot /mnt runuser -u "$USERNAME" -- env GIT_TERMINAL_PROMPT=0 git clone "$SPACBR_REPO_URL" "/home/$USERNAME/spacbr"; then
    ok "SPACBR cloned to /home/$USERNAME/spacbr"
else
    warn "clone failed -- you'll need to clone it yourself after rebooting: git clone $SPACBR_REPO_URL ~/spacbr"
fi

# ---------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------

sync
printf '\n'
ok "Phase 1 complete."
info "Next: reboot, then log in as $USERNAME (normal password login) at the console."
info "install/install.sh runs automatically on that first login, then starts dwm"
info "on its own once it's done -- nothing else to type. See docs/prerequisites.md"
info "or README.md if you ever need to run it by hand instead."

umount -R /mnt
confirm "Unmounted. Reboot now?" && reboot
