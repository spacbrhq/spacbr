# Prerequisites

What needs to be true before you run the SPACBR installer — read this
before `./install/install.sh` (or `curl -fsSL spacbr.com/install | sh`
once a release actually exists — see `release/README.md`). Grouped by
what the installer actually enforces itself versus what's worth
knowing going in.

This whole file assumes Arch Linux is **already installed and
booted**. Starting from nothing but a live ISO instead? See
[`install/live-install.sh`](../install/live-install.sh) (also linked
from `README.md`'s Installing section) — it handles disk
partitioning, the base system, and the bootloader, then hands off to
exactly the installer this file is about. Read its own header comment
first: it's genuinely destructive (erases a disk) and has not been
tested start-to-finish against real hardware.

## Checked by the installer — it stops with clear instructions if these aren't true

- **Arch Linux, x86_64.** `require_platform()` checks
  `/etc/arch-release`/`/etc/os-release` and `uname -m` before anything
  else runs. SPACBR doesn't target any other distribution or
  architecture (§2 of `CLAUDE.md`).
- **A regular (non-root) user with working `sudo`.** `require_sudo()`
  checks this immediately after `require_platform()`. This is the one
  most likely to actually trip you up: a fully manual Arch install
  (`pacstrap /mnt base linux linux-firmware` per the Arch wiki, not
  `archinstall`'s guided flow) has neither `sudo` installed nor a
  wheel-group user configured — the `base` group doesn't include
  `sudo` at all. If you hit this, fix it as root first:
  ```sh
  pacman -S sudo
  usermod -aG wheel <user>
  EDITOR=nano visudo   # uncomment: %wheel ALL=(ALL:ALL) ALL
  ```
  then log back in as that user and re-run the installer. Don't run
  the installer as root itself, even to sidestep this — the whole
  deploy model assumes a real user's `$HOME` (`useradd -m -G wheel -s
  /bin/bash <user> && passwd <user>` first). More detail:
  `docs/troubleshooting.md`. (Confirmed directly against archinstall's
  own source — `archinstall/lib/installer.py`'s `enable_sudo()` —
  that its guided flow does grant this automatically, always
  installing `sudo` as part of its base package set and adding the
  user to `wheel`; it does it via a dedicated `/etc/sudoers.d/` rule
  file rather than uncommenting the `%wheel` line, a different
  mechanism than the manual instructions above but an equally valid
  one — `require_sudo()` just checks `sudo -v` works, not how it got
  that way.)

## Needed to get the installer onto the machine (before either of the above ever runs)

- **`git`** — for `git clone https://github.com/spacbrhq/spacbr`, the
  install-from-clone path. Not shipped by the `base` group; install it
  yourself first (`pacman -S git`) if it's not already there.
- **or `curl`** — for the `curl -fsSL spacbr.com/install | sh`
  one-liner, once a release exists. `release/bootstrap.sh` checks for
  `curl`, `tar`, and `sha256sum` itself and dies cleanly with a clear
  message if any are missing, rather than failing partway through a
  download.
- **Network connectivity.** Needed for both of the above, for every
  `pacman -S` the installer runs, and for the AUR builds it does
  (`netbird`, `localsend`, `mpdris2-rs`, `arc-gtk-theme` — see
  `packages/aur`). Not pre-checked by the installer; if it's missing,
  pacman's own connection error during package installation will be
  the first sign.

## Worth checking first, even though nothing blocks on it

- **Free disk space.** No hard minimum is enforced. Budget a few GB:
  the base Suckless+X11+desktop package set, plus AUR builds (`netbird`
  is a full Go build; `geary` alone pulls roughly 30 dependencies), add
  up, and pacman's own package cache grows until `paccache.timer`
  (enabled automatically by the installer — see "Maintenance timers"
  in `docs/architecture.md`) starts trimming it. Verified for real:
  one day of package churn on a test machine grew
  `/var/cache/pacman/pkg` to 2.2GB before that timer existed.
- **Your monitor's brightness hardware.** `dwm/config.h`'s brightness
  keybindings are hardcoded to one approach, not auto-detected per
  machine: `ddcutil` (DDC/CI over the monitor cable) if there's no
  `backlight`-class device at all (a desktop with only an external
  monitor), or `brightnessctl -c backlight` if there is one (a laptop
  panel). After install, check which applies with `brightnessctl -l`;
  if the shipped default doesn't match your hardware, edit
  `.local/src/dwm/config.h`'s `XF86XK_MonBrightnessUp`/`Down` bindings
  and rebuild (`cd .local/src/dwm && make && make install`). See
  `docs/keybindings.md`.
- **Whether root is on btrfs**, if you want the automatic snapshot
  safety net (pre/post snapshots around every pacman transaction).
  `setup_snapper()` only configures anything if `/` actually is btrfs
  — on any other filesystem it's a harmless no-op, not an error, so
  this isn't something you need to arrange, just something worth
  knowing about either way.
- **Existing dotfiles you care about.** The installer never deletes
  anything — any live file that differs from what it's about to deploy
  gets backed up first, under
  `$XDG_STATE_HOME/spacbr/backups/<timestamp>/` — but knowing that
  before you start beats being surprised by a backup directory
  afterward.

## Explicitly NOT required beforehand

- **An AUR helper.** `paru` is bootstrapped automatically from source
  the first time it's needed (`install_aur_helper()` in
  `install/functions/packages.sh`) — don't pre-install one yourself.
  §43 of `CLAUDE.md`: at most one AUR helper, and the installer
  standardizes on it.
- **A display manager / login manager.** SPACBR starts X itself via
  `startx` from `.zshrc`'s tty1 auto-login logic
  (`.config/xinitrc`) — no `gdm`/`sddm`/`lightdm` involved or assumed.
- **Wayland anything.** SPACBR is built around X11/dwm end to end (§2
  of `CLAUDE.md`) — this isn't a partial-Wayland setup with X11
  fallback, it's X11 only.

## See also

- [`docs/troubleshooting.md`](troubleshooting.md) — what to do if a
  check above actually fails.
- [`docs/architecture.md`](architecture.md) — the reasoning behind
  `require_sudo`/`require_platform` and everything else the installer
  does, in depth.
- [`README.md`](../README.md)'s Installing section — the actual
  install commands once everything above is in place.
