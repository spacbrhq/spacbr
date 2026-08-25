#!/bin/sh
# SPACBR live installer -- run this from the Arch Linux live ISO,
# before anything else exists. Mirrors archinstall's own guided-
# installer UX (answer a handful of questions, confirm once clearly,
# then it does everything) but deliberately does NOT try to be a
# general-purpose installer the way archinstall is -- no LVM, no RAID,
# no partition-layout customization, no profile menu. One disk, one
# layout, one opinionated configuration -- including LUKS2 full-disk
# encryption on root, always on, not a checkbox (see the "Boot &
# authentication" section of docs/architecture.md). SPACBR is
# an opinionated personal system (CLAUDE.md SS1); this is the
# opinionated personal installer to match. If you need something this
# script doesn't do, use archinstall (or a manual install) to get a
# base Arch system running, then pick up at "Getting the installer
# onto the machine" in docs/prerequisites.md.
#
# TWO-PHASE MODEL, same "tiny bootstrap -> real installer" shape this
# repo already uses for release/bootstrap.sh:
#   Phase 1 (this script, live ISO, as root): partition (LUKS2-encrypted
#     root), format, mount, pacstrap a minimal base system, configure
#     just enough to boot and reach a desktop automatically, clone this
#     repo into the new user's home.
#   Phase 2 (install/install.sh, after rebooting into the new system,
#     as that user): everything SPACBR actually is -- packages,
#     dotfiles, Suckless builds, dmenu scripts, services, CPU
#     microcode, GPU drivers, maintenance timers.
#
# Unlike most of this file, disk encryption is NOT "no customization" --
# SPACBR is opinionated about *whether* (always, full-disk LUKS2 root),
# not about LVM/RAID/multi-volume layouts, which stay genuinely out of
# scope the same as the rest of this header already says.
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
#   - Disk: single disk, GPT, 1GiB EFI System Partition (unencrypted,
#     Limine + the UKIs live here) + a LUKS2-encrypted btrfs root for
#     everything else, mounted directly (no subvolume -- matches
#     archinstall's own default_layout exactly, verified against a
#     real user_configuration.json, just with a LUKS2 container between
#     the partition and the filesystem now). No swap partition -- zram
#     instead (zstd compression), matching archinstall's own current
#     default.
#   - Bootloader: Limine, UEFI, Unified Kernel Images, installed to
#     the *removable* EFI path (EFI/BOOT/BOOTX64.EFI) rather than a
#     machine-specific NVRAM boot entry -- more portable, survives a
#     NVRAM reset, no efibootmgr entry to go stale. Limine itself needs
#     zero LUKS-aware configuration: it only ever loads a UKI from the
#     unencrypted ESP by path, decryption is entirely initramfs-side
#     (confirmed against ArchWiki's own UKI page).
#   - Kernels: linux AND linux-lts, each gets its own UKI/boot entry.
#   - Plymouth: enabled, wired into mkinitcpio's HOOKS (with sd-encrypt,
#     not just cosmetically) -- shares Limine's wallpaper, and shows
#     the LUKS2 unlock password prompt itself
#     (system/plymouth/spacbr/spacbr.script's SetDisplayPasswordFunction)
#     instead of a plain console prompt. See CHANGELOG.md for the full
#     history (removed once, brought back, now doing real authentication
#     work, not just a splash).
#   - Login: no display manager, no second password. The LUKS2
#     passphrase (entered once, at Plymouth, during early boot) is the
#     only password this system ever asks for -- systemd auto-logs the
#     one SPACBR user in on tty1 afterward (system/autologin/), whose
#     .zshrc runs install/install.sh on its very first invocation
#     (same "one login, nothing else to type" contract the old
#     .bash_profile-based bootstrap and, later, ly's login_cmd both
#     had -- only the mechanism keeps changing) and then execs startx.
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

# This script's own directory -- used wherever this file reads content
# relative to itself (system/autologin/, .zshrc, system/limine/
# wallpaper.jpg, VERSION) rather than assuming the repo is cloned onto
# the *target* yet (it
# isn't, at this point in Phase 1) or embedding that content inline.
# Works whether this script is run standalone or from a real local
# clone (see docs/prerequisites.md) -- degrades gracefully at each
# individual use site if a given file isn't actually there.
SPACBR_ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------------
# Self-contained helpers (common.sh doesn't exist yet -- this repo
# isn't cloned until Phase 1 finishes)
# ---------------------------------------------------------------------

# True-color eightchrome (by eightharsh) -- kept in sync with
# install/functions/common.sh's copy of these same four color triples
# (and .config/xresources) by hand.
_color() { [ -t 1 ] && printf '\033[38;2;%sm' "$1" || true; }
_reset() { [ -t 1 ] && printf '\033[0m' || true; }
info()   { printf '%s %s\n' "$(_color '64;132;214')::$(_reset)" "$*"; }
ok()     { printf '%s %s\n' "$(_color '155;207;79')✓$(_reset)" "$*"; }
warn()   { printf '%s %s\n' "$(_color '246;209;58')!$(_reset)" "$*" >&2; }
error()  { printf '%s %s\n' "$(_color '237;71;55')✗$(_reset)" "$*" >&2; }
die()    { error "$*"; exit 1; }
banner() { [ -t 1 ] && printf '\n%sSPACBR%s\n\n' "$(_color '64;132;214')" "$(_reset)"; }

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
command -v cryptsetup >/dev/null 2>&1 || die "cryptsetup not found -- this shouldn't happen on the stock Arch ISO (it ships cryptsetup by default for exactly this kind of install). Is this actually the Arch live ISO?"

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

banner
printf '%s\n\n' "SPACBR live installer -- Phase 1 (disk, base system, bootloader)"

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
printf '  - Create: %s (1GiB, EFI System Partition, FAT32, unencrypted), %s (rest of\n' "$EFI_PART" "$ROOT_PART"
printf '    disk, LUKS2-encrypted btrfs)\n'
printf '  - Ask you to set a disk-encryption passphrase (typed twice, hidden) --\n'
printf '    this becomes THE password for this machine: it unlocks the disk at every\n'
printf '    boot, through Plymouth, and nothing else asks for a password afterward\n'
printf '  - btrfs mounted directly at / inside the LUKS2 container (no subvolume,\n'
printf '    matching archinstall default_layout)\n'
printf '  - Install a minimal Arch base (kernels: %s) + Limine (UKI, removable EFI path)\n' "$KERNELS"
printf '  - Locale %s, keymap %s, console font %s, timezone %s\n' "$LOCALE" "$KEYMAP" "$CONSOLE_FONT" "$TIMEZONE"
printf '  - Mirrors: reflector, HTTPS, %s\n' "$MIRROR_COUNTRIES"
printf '  - Hostname "%s", user "%s" with sudo, root password set (rescue access)\n' "$TARGET_HOSTNAME" "$USERNAME"
printf '  - NetworkManager + systemd-timesyncd (NTP) + sshd enabled, zram swap, Plymouth enabled (themed later, in install.sh -- see below)\n'
printf '  - linux also gets a fallback UKI (broader driver support) for the boot menu'\''s "SPACBR (fallback)" entry\n'
printf '  - Clone %s into /home/%s/spacbr\n' "$SPACBR_REPO_URL" "$USERNAME"
printf '  - %s is auto-logged in on tty1 after every successful LUKS2 unlock --\n' "$USERNAME"
printf '    no second password, no display manager. Their FIRST login runs\n'
printf '    install/install.sh automatically, which installs the actual SPACBR\n'
printf '    desktop (packages, dotfiles, Suckless, services, GPU drivers) and starts\n'
printf '    dwm on its own once done. One passphrase, one reboot, nothing else to type.\n\n'

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
sgdisk -n2:0:0     -t2:8309 -c2:"SPACBR root (LUKS)"   "$DISK"
partprobe "$DISK" 2>/dev/null || true
sleep 2
ok "partitioned"

# ---------------------------------------------------------------------
# LUKS2: the root partition is a raw block device until this point --
# everything from here on (mkfs, mount, the eventual kernel cmdline)
# targets the *decrypted* mapping (/dev/mapper/cryptroot), never
# $ROOT_PART directly again. Both cryptsetup calls below prompt
# interactively on the real terminal (cryptsetup's own native
# echo-off/confirm handling, same as read_password's stty dance but
# built into the tool itself) -- the passphrase is never captured into
# a shell variable, printed, or logged anywhere in this script.
# ---------------------------------------------------------------------

info "Setting up disk encryption on $ROOT_PART -- you'll be asked to set a passphrase now (typed twice)..."
cryptsetup luksFormat --type luks2 "$ROOT_PART"
info "Unlocking it once now to format it..."
cryptsetup open "$ROOT_PART" cryptroot
ok "LUKS2 container created and unlocked as /dev/mapper/cryptroot"

info "Formatting..."
mkfs.fat -F32 -n EFI "$EFI_PART"
mkfs.btrfs -f -L SPACBR /dev/mapper/cryptroot
ok "formatted"

info "Mounting..."
# No subvolume -- the raw btrfs filesystem (now living inside the
# LUKS2 container) is mounted directly at /, matching archinstall's
# own "default_layout" behavior exactly (verified against a real
# user_configuration.json generated by archinstall on this repo's own
# test machine: its disk_config has an empty "btrfs": [] array, meaning
# no subvolume was created, just "compress=zstd" as the only mount
# option -- no "noatime", no "ssd" flag, no compression-level suffix.
# An earlier version of this script added a "@" subvolume and extra
# mount options as an improvement; corrected to match the real
# reference exactly instead.
mount -o compress=zstd /dev/mapper/cryptroot /mnt
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

info "Installing base system (pacstrap: $KERNELS, limine, plymouth, cryptsetup, zsh)..."
# shellcheck disable=SC2086
# cryptsetup: needed inside the target itself, not just on the live
# ISO -- mkinitcpio's sd-encrypt hook shells out to it when building
# the initramfs, and it's the tool for any later `cryptsetup
# luksAddKey`/passphrase-change against the now-encrypted root.
#
# zsh is pacstrapped here rather than left to Phase 2's packages/base:
# it has to already be this user's login shell (see the useradd call
# below) for the very *first* auto-login to run this file's first-boot
# bootstrap at all -- a fresh account's default shell would otherwise
# be whatever `useradd` falls back to, which never sources .zshrc.
# Xorg itself (xorg-server etc.) does NOT need to be here too: the
# first-boot bootstrap in .zshrc runs install.sh -- which installs
# Xorg via packages/x11 -- to completion, synchronously, before ever
# exec-ing startx. By the time startx actually runs, Xorg is
# guaranteed to exist.
pacstrap -K /mnt base $KERNELS linux-firmware btrfs-progs networkmanager sudo git \
    efibootmgr limine plymouth cryptsetup zsh zram-generator openssh $UCODE_PKG
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
arch-chroot /mnt useradd -m -G wheel -s /bin/zsh "$USERNAME"
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
# Automatic login (system/autologin/) -- this is what bridges Phase 1
# into Phase 2 as one continuous experience (boot -> unlock -> fully
# configured desktop) instead of two separate manual commands. No
# display manager, no second password: the LUKS2 passphrase already
# entered at Plymouth earlier in this boot is the only authentication
# this machine ever asks for (docs/architecture.md, "Boot &
# authentication"). Real standing security tradeoff, same as it always
# is for any auto-login setup -- accepted deliberately here because
# the disk itself is already the thing being protected, and it's
# already locked behind the LUKS2 passphrase; a second prompt behind
# the same physical-access threat model would be authenticating the
# same fact twice, not adding real protection.
#
# Must run on tty1 specifically -- getty@tty1 is enabled (not
# disabled, the opposite of the old ly setup) with an autologin
# drop-in overriding its ExecStart.
# ---------------------------------------------------------------------

info "Setting up automatic login for $USERNAME on tty1..."
[ -f "$SPACBR_ROOT_DIR/system/autologin/tty1-autologin.conf" ] || die "system/autologin/tty1-autologin.conf not found next to this script -- this repo needs to be a real local clone for autologin to be configured correctly, not just this one file downloaded standalone. See docs/prerequisites.md."
mkdir -p /mnt/etc/systemd/system/getty@tty1.service.d
sed "s/@SPACBR_USERNAME@/$USERNAME/" "$SPACBR_ROOT_DIR/system/autologin/tty1-autologin.conf" \
    > /mnt/etc/systemd/system/getty@tty1.service.d/autologin.conf
arch-chroot /mnt systemctl enable getty@tty1.service
ok "getty@tty1 autologin configured for $USERNAME"

# .zshrc (+ the two files it sources on its first two lines) is what
# actually runs the first-boot install.sh trigger and then execs
# startx -- see that file for the logic itself. Placed here, directly,
# the same way ly's spacbr-login used to be: the very first auto-login
# has no other way to reach a working shell rc, since Phase 2's own
# deploy_dotfiles() hasn't run yet at this point (it's what deploy_dotfiles
# will itself re-sync moments later, on that same first login -- this
# is only bootstrapping that first run, not a permanent parallel copy).
# Load-bearing like the ly files were: a missing .zshrc here means the
# first auto-login drops into a shell with no first-boot trigger and
# no exec-startx, i.e. a machine that boots to a blank prompt forever.
info "Placing first-boot shell configuration for $USERNAME..."
[ -f "$SPACBR_ROOT_DIR/.zshrc" ] || die ".zshrc not found next to this script -- see the autologin message above, same cause."
[ -f "$SPACBR_ROOT_DIR/.config/shell/profile" ] || die ".config/shell/profile not found next to this script -- see the autologin message above, same cause."
[ -f "$SPACBR_ROOT_DIR/.config/shell/aliasrc" ] || die ".config/shell/aliasrc not found next to this script -- see the autologin message above, same cause."
mkdir -p "/mnt/home/$USERNAME/.config/shell"
cp "$SPACBR_ROOT_DIR/.zshrc" "/mnt/home/$USERNAME/.zshrc"
cp "$SPACBR_ROOT_DIR/.config/shell/profile" "/mnt/home/$USERNAME/.config/shell/profile"
cp "$SPACBR_ROOT_DIR/.config/shell/aliasrc" "/mnt/home/$USERNAME/.config/shell/aliasrc"
# Placed as root -- must hand ownership to the real user now, not just
# for correctness but because Phase 2's own deploy_dotfiles (running
# AS that user) needs to be able to overwrite these same paths a few
# minutes later; a root-owned file with the usual 644 mode isn't
# writable by its non-owner, which would make that later `cp -p` fail.
arch-chroot /mnt chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.zshrc" "/home/$USERNAME/.config"
ok "first-boot .zshrc placed for $USERNAME"

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
# mkinitcpio HOOKS -- systemd-based initramfs with sd-encrypt (LUKS2
# root) and plymouth (shows the sd-encrypt password prompt itself,
# instead of a plain systemd-ask-password console agent). One
# deterministic full-line replacement now, not the old two-family
# conditional insertion: sd-encrypt only exists in the systemd hook
# family, so there's no udev-family branch left to support once LUKS2
# is unconditional.
#
# Exact ordering verified against two separately-cited ArchWiki rules,
# not guessed: the dm-crypt page's own systemd+sd-encrypt example line,
# and the Plymouth page's troubleshooting section stating the systemd
# hook must come before plymouth, and plymouth must come before
# encrypt/sd-encrypt.
#
# Known real risk, not resolved here: that same Plymouth troubleshooting
# section documents a password prompt that may not visually *update* on
# a script-module theme (system/plymouth/spacbr/spacbr.script is one)
# specifically when using the systemd hook family -- exactly this
# combination. No fix is clearly documented anywhere found. Only a real
# boot test (not part of this pass -- see docs/architecture.md) can
# confirm whether this affects SPACBR's theme in practice.
#
# Theme itself is NOT set here on purpose -- deferred to install.sh
# (Phase 2) via deploy_plymouth_theme(). The spacbr theme's wordmark
# uses Rajdhani Bold (packages/aur-overrides/ttf-rajdhani), which
# doesn't exist until Phase 2 installs it; setting the theme before
# that font exists would make mkinitcpio's plymouth hook silently
# `fc-match` to some fallback instead. Leaving Plymouth on its packaged
# default for this one first boot (until Phase 2's first-login
# install.sh run finishes) is the same "Phase 1 gets you booted, Phase
# 2 makes it SPACBR" split every other Phase 1/2 boundary in this file
# already uses -- LUKS2 unlock itself still works fine on Plymouth's
# stock theme in the meantime, it just isn't themed yet.
# ---------------------------------------------------------------------

info "Configuring mkinitcpio HOOKS for LUKS2 (sd-encrypt) + Plymouth..."
sed -i 's/^HOOKS=(.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole plymouth block sd-encrypt filesystems fsck)/' /mnt/etc/mkinitcpio.conf
if ! grep -q '^HOOKS=(base systemd .*sd-encrypt' /mnt/etc/mkinitcpio.conf; then
    die "couldn't confirm mkinitcpio.conf's HOOKS line was actually rewritten -- stopping before building a UKI that can't unlock its own root. Check /mnt/etc/mkinitcpio.conf by hand."
fi
ok "mkinitcpio HOOKS set: systemd + sd-vconsole + plymouth + sd-encrypt"

# ---------------------------------------------------------------------
# Unified Kernel Images. /etc/kernel/cmdline is what mkinitcpio's UKI
# generation reads for the embedded command line (confirmed against
# archinstall's own _config_uki(), which writes exactly this file for
# exactly this reason). "quiet splash" so Plymouth's splash isn't
# fighting kernel boot text for the screen.
#
# rd.luks.name=<LUKS-container-UUID>=cryptroot + root=/dev/mapper/cryptroot
# is sd-encrypt's own addressing scheme (verified against ArchWiki's
# dm-crypt page) -- replaces the plain root=PARTUUID=... this file used
# before LUKS2. The UUID is the LUKS *container's* UUID
# (cryptsetup luksUUID), deliberately not the filesystem's -- a
# different value read a different way, easy to get wrong.
# ---------------------------------------------------------------------

LUKS_UUID="$(cryptsetup luksUUID "$ROOT_PART")"
[ -n "$LUKS_UUID" ] || die "couldn't read the LUKS UUID for $ROOT_PART -- the boot config would be wrong, stopping before writing it."

KERNEL_CMDLINE="rd.luks.name=$LUKS_UUID=cryptroot root=/dev/mapper/cryptroot rw zswap.enabled=0 quiet splash"
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
    if [ "$kernel" = "linux" ]; then
        # Primary kernel only gets a real fallback UKI too -- stock
        # mkinitcpio's own convention (a commented-out 'fallback' preset
        # ships in every mkinitcpio.conf), just re-enabled here instead
        # of invented. -S autodetect skips the hook that trims the
        # initramfs down to only the modules THIS install's current
        # hardware needs, so the fallback image carries broader driver
        # support -- a real safety net if autodetect ever guesses wrong
        # (different hardware, a driver regression), not a renamed
        # duplicate of default_uki. linux-lts doesn't get one: two
        # kernels already covers "primary breaks, boot the other one";
        # a fallback of the fallback is real menu clutter for
        # diminishing safety-net value, not a gap.
        cat > "$preset" <<EOF
# mkinitcpio preset file for 'linux' (SPACBR: UKI only, no plain initramfs)

ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default' 'fallback')

default_uki="/boot/EFI/Linux/arch-linux.efi"

fallback_uki="/boot/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
EOF
        ok "linux.preset configured (UKI -> arch-linux.efi, fallback -> arch-linux-fallback.efi)"
    else
        cat > "$preset" <<EOF
# mkinitcpio preset file for '$kernel' (SPACBR: UKI only, no plain initramfs)

ALL_kver="/boot/vmlinuz-$kernel"

PRESETS=('default')

default_uki="/boot/EFI/Linux/arch-$kernel.efi"
EOF
        ok "$kernel.preset configured (UKI -> /boot/EFI/Linux/arch-$kernel.efi)"
    fi
done

info "Building Unified Kernel Images (mkinitcpio -P)..."
arch-chroot /mnt mkinitcpio -P
for kernel in $KERNELS; do
    [ -f "/mnt/boot/EFI/Linux/arch-$kernel.efi" ] || die "mkinitcpio finished but /boot/EFI/Linux/arch-$kernel.efi wasn't created -- something's wrong with the $kernel preset. Stopping before declaring success on a system that can't actually boot $kernel."
done
[ -f /mnt/boot/EFI/Linux/arch-linux-fallback.efi ] || die "mkinitcpio finished but arch-linux-fallback.efi wasn't created -- something's wrong with linux.preset's fallback config. Stopping before declaring success on a system whose fallback entry can't actually boot."
ok "UKIs built for: $KERNELS (plus linux's fallback)"

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

# Wallpaper (system/limine/wallpaper.jpg) and VERSION, read relative to
# this script's own location (see SPACBR_ROOT_DIR at the top of this
# file). Pre-shrunk to 2560px wide (from a 5504x3072 original, sips -Z
# 2560) specifically for boot-time decode speed -- Limine's own image
# decoder runs on UEFI firmware, not a real CPU/GPU, and a fast boot
# was the entire point of the last several rounds of work here;
# shipping the full 5MB original would fight that directly. Falls back
# to the plain-color "Quiet Mono" config (no wallpaper directives at
# all) if the file isn't found, not a broken/missing-image boot screen.
HAVE_WALLPAPER=0
if [ -f "$SPACBR_ROOT_DIR/system/limine/wallpaper.jpg" ]; then
    cp "$SPACBR_ROOT_DIR/system/limine/wallpaper.jpg" /mnt/boot/EFI/BOOT/wallpaper.jpg
    HAVE_WALLPAPER=1
    ok "Limine wallpaper copied to ESP"
else
    warn "system/limine/wallpaper.jpg not found next to this script -- Limine will use a plain eightchrome background instead of the wallpaper"
fi
SPACBR_VERSION="$(cat "$SPACBR_ROOT_DIR/VERSION" 2>/dev/null || echo "0.1.0")"

{
    # timeout: 3 -- was 5. "The bootloader should feel almost
    # invisible during normal use" / "avoid large countdown timers":
    # short enough to feel like a beat, not a wait, still enough time
    # to actually catch and pick the fallback/LTS entry when it matters.
    printf 'timeout: 3\n'
    # eightchrome (by eightharsh) -- keep these values in sync with
    # .config/xresources by hand (same colors as background/foreground/
    # color1/color2/color3/color4 there); Limine's config format has no
    # way to read Xresources. Directive names/format verified against
    # Limine's own CONFIG.md: colors are RRGGBB (no '#'), term_palette
    # is a ';'-separated 8-color array (black;red;green;brown;blue;
    # magenta;cyan;gray), term_background is TTRRGGBB with TT stands
    # for transparency (00 = fully opaque, higher = more of whatever's
    # behind it shows through).
    #
    # Two different term_background values depending on HAVE_WALLPAPER:
    # 002f343f (TT=00, fully opaque -- the documented no-wallpaper
    # default) when there's no image to show through at all, versus
    # 902f343f (TT=90) when there is one.
    #
    # Legibility for this specific photo is handled in two layers, not
    # one -- inspired by a KaOS Limine theme screenshot, which turned
    # out (checked against CONFIG.md: no "panel"/"box" directive exists
    # at all) to bake its own translucent header panel directly into
    # its wallpaper image rather than something Limine renders live:
    #   1. system/limine/wallpaper.jpg itself already has a soft
    #      eightchrome-toned gradient baked into its own top ~46-60%
    #      (smoothstep-faded, not a hard-edged box) -- exactly the
    #      region interface_branding/help text/the menu land in at this
    #      file's term_margin. Generated once, not at install time (see
    #      the comment above HAVE_WALLPAPER).
    #   2. term_background's TT=90 is then a light *global* tint on top
    #      of that -- mostly for overall cohesion with eightchrome, not
    #      doing the legibility work by itself anymore. Confirmed by
    #      sampling: the baked panel alone already brings the photo's
    #      brightest band (top 20%, RGB(178,185,193) in the unpaneled
    #      original) down close to eightchrome-bg tone, so a much
    #      lighter global overlay than the old single-layer TT=50
    #      (which had to do all the darkening by itself) still leaves
    #      that region legible, while the wave texture below the panel
    #      -- which was never a legibility problem, nothing renders
    #      text there -- stays visibly richer than a uniform full-screen
    #      darken would allow.
    #
    # No term_font_scale here on purpose -- an earlier version of this
    # file set 2x2 to give the stock font real presence, but "not
    # oversized" / "avoid large display-style typography" is the
    # opposite ask: the spaciousness below comes from term_margin (a
    # generous 96px, up from the previous 80) working on Limine's own
    # normal-sized font, not from bigger glyphs. Same "negative space,
    # not bigger text" idea CLAUDE.md's own SS75 already states for
    # every other SPACBR surface.
    #
    # Custom term_font (Iosevka / IBM Plex Mono / Hack, in that
    # preference order) was considered and not done: Limine's term_font
    # needs a raw, header-less 256-glyph CP437 bitmap font (8px wide,
    # confirmed by byte-inspecting Neptune3013/fallout-limine-theme's
    # own PHXEGA8.F14 -- exactly 256*14 bytes, no header), not a normal
    # TTF. No trustworthy pre-made conversion of any of the three exists
    # (checked -- Iosevka's own issue tracker has an open, unresolved
    # request for exactly this, "1-bit bitmap version .psf", #1353);
    # hand-converting one needs a FontForge+PSFtools pipeline whose
    # output quality can't be verified without eyes on the physical
    # screen. Limine's stock font stays -- it already reads as clean
    # and compact, which was the actual goal, not a specific typeface.
    #
    # No "UEFI Firmware Settings" entry: that needs Limine's
    # efi_boot_entry protocol, which reboots into a *named* NVRAM boot
    # entry -- checked this repo's own test machine with `efibootmgr
    # -v`, no such entry exists there, and Limine is deliberately
    # installed to the removable EFI path specifically to not depend on
    # NVRAM entries existing at all. Adding a hardcoded guess here would
    # likely be a dead menu item on most real hardware.
    #
    # interface_help_colour/interface_help_colour_bright: Limine's
    # defaults for these are its own stock green/cyan-ish colors
    # (0x00aa00 / derived), independent of interface_branding_colour --
    # left untouched, the on-screen key-bindings hint and countdown
    # digit clash against eightchrome instead of reading as one themed
    # screen. Help text itself renders at the *top* of the screen per
    # Limine's own CONFIG.md -- there's no directive to move it to the
    # bottom the way a from-scratch mockup might lay it out.
    #
    # "Quiet Mono": identity stays neutral, the accent marks the
    # live/selected thing instead -- same principle Plymouth's own
    # progress rule applies (system/plymouth/spacbr/spacbr.script).
    # Branding sits in plain foreground like the help text around it.
    # term_foreground_
    # bright is set to accent here as a real, testable hypothesis, not
    # a confirmed fact: CONFIG.md documents term_foreground_bright's
    # existence but not when Limine actually uses it, and this can't be
    # checked from here -- there's no way to see the rendered menu
    # without eyes on the physical screen. If the highlighted entry
    # actually renders in accent, this is exactly "selected reads as
    # live, everything else stays quiet"; if Limine doesn't use bright
    # this way at all, it's a harmless unused directive, not a breakage.
    #
    # remember_last_entry: yes -- boots whichever entry was picked last
    # time by default instead of always resetting to the first one.
    printf 'remember_last_entry: yes\n'
    # Version number, same "SPACBR <version>" convention checks.sh's
    # own "spacbr version" output already uses -- not a new format
    # invented for this screen.
    printf 'interface_branding: SPACBR %s\n' "$SPACBR_VERSION"
    printf 'interface_branding_colour: e1e3e7\n'
    printf 'interface_help_colour: e1e3e7\n'
    printf 'interface_help_colour_bright: 4084d6\n'
    if [ "$HAVE_WALLPAPER" -eq 1 ]; then
        # boot():/... resolves from the ESP *partition root*, not from
        # limine.conf's own directory (confirmed against CONFIG.md) --
        # same reason the UKI entries below already say
        # boot():/EFI/Linux/arch-*.efi in full, not boot():/arch-*.efi.
        # wallpaper.jpg lives next to limine.conf itself (/EFI/BOOT/),
        # so it needs the same full-path treatment; boot():/wallpaper.jpg
        # silently pointed at a file that doesn't exist at the partition
        # root, which is why the wallpaper never rendered.
        printf 'wallpaper: boot():/EFI/BOOT/wallpaper.jpg\n'
        # stretched, not centered: centered's behavior depends on how
        # the image's native pixel size compares to this machine's
        # actual screen resolution, which isn't known at config-write
        # time and varies by hardware -- stretched fills the exact
        # screen dimensions the same way on any display, at the cost of
        # minor distortion on screens whose aspect ratio isn't close to
        # the photo's own (~1.79:1, close to most 16:9 displays).
        printf 'wallpaper_style: stretched\n'
        printf 'term_background: 902f343f\n'
    else
        printf 'term_background: 002f343f\n'
    fi
    printf 'term_foreground: e1e3e7\n'
    printf 'term_foreground_bright: 4084d6\n'
    printf 'term_palette: 2f343f;ed4737;9bcf4f;f6d13a;4084d6;dab6fc;60e1e0;e1e3e7\n'
    printf 'term_palette_bright: 404552;fda685;94e88c;fff75e;5294e2;ceb3e1;8ddddd;fafafa\n'
    printf 'term_margin: 96\n'
    # Entry names read as menu choices a normal user can act on, not a
    # kernel-package-name dump ("Linux 6.x", "initramfs-linux.img"
    # never appear here) and not a repeat of the "SPACBR" branding line
    # above for every single entry -- "(fallback)"/"(LTS)" is the only
    # thing that needs to vary per entry, so that's the only thing that
    # does. default_entry stays unset: entry order below (linux/default
    # first) already makes the primary kernel Limine's default, and
    # remember_last_entry above overrides that anyway once it's used.
    if [ -f /mnt/boot/EFI/Linux/arch-linux.efi ]; then
        printf '\n/SPACBR\n'
        printf '    protocol: efi\n'
        printf '    path: boot():/EFI/Linux/arch-linux.efi\n'
    fi
    if [ -f /mnt/boot/EFI/Linux/arch-linux-lts.efi ]; then
        printf '\n/SPACBR (LTS)\n'
        printf '    protocol: efi\n'
        printf '    path: boot():/EFI/Linux/arch-linux-lts.efi\n'
    fi
    if [ -f /mnt/boot/EFI/Linux/arch-linux-fallback.efi ]; then
        printf '\n/SPACBR (fallback)\n'
        printf '    protocol: efi\n'
        printf '    path: boot():/EFI/Linux/arch-linux-fallback.efi\n'
    fi
} > /mnt/boot/EFI/BOOT/limine.conf
# UKIs embed their own cmdline (from /etc/kernel/cmdline above) --
# Limine's config doesn't need to repeat it for protocol: efi entries.
if ! grep -q '^/SPACBR' /mnt/boot/EFI/BOOT/limine.conf; then
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
info "Next: reboot, enter the disk-encryption passphrase you set when Plymouth"
info "asks for it -- that's the only password this system asks for. $USERNAME is"
info "then auto-logged in on tty1, install/install.sh runs automatically on that"
info "first login, and dwm starts on its own once it's done -- nothing else to"
info "type. See docs/prerequisites.md or README.md if you ever need to run"
info "install.sh by hand instead."

umount -R /mnt
cryptsetup close cryptroot
confirm "Unmounted and locked. Reboot now?" && reboot
