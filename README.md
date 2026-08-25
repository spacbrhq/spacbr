# SPACBR

An opinionated personal desktop system for Arch Linux — X11, `dwm`,
and a small set of Suckless tools and native Linux utilities, unified
by one visual language, one interaction model, and one installer.

SPACBR is not a distribution, not a desktop environment, and not a
Wayland compositor. It's an integration layer on top of stock Arch
Linux: Arch remains Arch underneath, and SPACBR can be removed without
breaking it.

Full documentation lives in [`docs/`](docs/): [prerequisites](docs/prerequisites.md),
[architecture](docs/architecture.md), [keybindings](docs/keybindings.md),
[troubleshooting](docs/troubleshooting.md), [development](docs/development.md)
— read `prerequisites.md` first if you're about to install, or
`architecture.md` first if you're changing anything here.

## Philosophy

**Simple at the surface, powerful underneath.** The desktop shows
almost nothing permanently — a status bar with a handful of essential
blocks. Everything else is one keyboard shortcut away, usually through
a `dmenu` prompt:

```
keyboard shortcut → dmenu → action
```

## What's here

| Responsibility | Owner |
|---|---|
| Window management | `dwm` |
| Launcher | `dmenu` |
| Terminal | `st` |
| Status bar | `dwmblocks` |
| Locking | `slock` |
| Notifications | `dunst` |
| Compositor | `picom` |
| Networking | NetworkManager (`nmcli`/`nmtui`) |
| Firewall | `nftables` (`system/nftables/nftables.conf`) |
| Snapshots | `snapper` + `snap-pac` (btrfs only — auto pre/post snapshots around pacman transactions, plus periodic timeline snapshots) |
| Audio | PipeWire + WirePlumber (`wpctl`) |
| Bluetooth | BlueZ (`bluetoothctl`) |
| Brightness | `ddcutil` (DDC/CI — this machine has no backlight device; use `brightnessctl -c backlight` instead on a laptop) |
| Display | `xrandr` |
| Media | `mpv` + `playerctl` |
| Music library | `mpd` + `rmpc` (persistent queue/library, separate need from mpv's play-this-file model) |
| Screen recording | `ffmpeg` (x11grab + pulse) — `.local/bin/record` |
| Documents | `Zathura` |
| Images | `nsxiv` |
| Email | `Geary` |
| Browser | `Firefox` |
| File manager | `PCManFM` |
| Password manager | `pass` |
| Version control | `git` (`.config/git/config`) |
| Default apps | `handlr-regex` |
| Editor | `Neovim` / `Vim` (`Zed` for GUI/mouse-driven work — a documented exception, not a second owner) |

Each of these has exactly one owner, by design — see
[docs/architecture.md](docs/architecture.md#one-owner-per-responsibility)
for the reasoning behind it.

## Visual identity

One palette everywhere — **eightchrome** (by eightharsh): `#2f343f` background,
`#e1e3e7` foreground, `#404552` selection, `#4084d6` accent. `dwm`,
`st`, `slock`, and `nsxiv` read it live from `.config/xresources`;
`dmenu`, GTK, `mpv`, `dunst`, Vim/Neovim, Zathura, and Zed (its own
theme file) carry the same values hardcoded and are checked for drift
by `spacbr doctor` where a mechanical check makes sense. One monospace
face (`Hack`) across the terminal, the bar, the launcher, and GTK
apps — no exceptions. See
[docs/architecture.md](docs/architecture.md#visual-system) for the
full palette table and which components are which.

## Repository layout

```
.config/        XDG configuration (dwm/dmenu/st/slock configs live under .local/src/*)
.local/bin/     user scripts — the dmenu-driven contextual interfaces
.local/src/     Suckless components, built from source (dwm, dmenu, st,
                slock, dwmblocks) with their patches under patches/
packages/       curated pacman package manifests (base, x11, desktop, hardware, aur,
                aur-overrides/ for a vendored PKGBUILD when needed)
install/        the installer (install/update/repair/uninstall) — deployed to end users
release/        maintainer-only: build/publish versioned releases, the web bootstrap script
system/         systemd/X11 integration
docs/           additional documentation
```

## Keybindings (highlights)

`MODKEY` is the Super/Windows key.

| Key | Action |
|---|---|
| `MODKEY+p` | Launcher (dmenu) |
| `MODKEY+t` | Terminal (st) |
| `MODKEY+w` | Browser |
| `MODKEY+e` | File manager |
| `MODKEY+o` | Password menu |
| `MODKEY+c` | Clipboard history |
| `MODKEY+Shift+L` / `XF86 ScreenSaver` | Lock screen |
| `MODKEY+Shift+P` / `XF86 PowerOff` | Power menu (lock/logout/suspend/reboot/shutdown) |
| `MODKEY+Shift+A` | Audio menu (volume %, device selection) |
| `MODKEY+Shift+B` | Brightness menu (contrast auto-follows) |
| `MODKEY+Shift+W` | Wallpaper picker |
| `XF86 Display` | Display management (xrandr) |
| `XF86 Bluetooth` | Bluetooth menu |
| `XF86 AudioPlay`/`AudioNext`/`AudioPrev` | Media transport (`playerctl`) |
| `Print` | Screenshot |
| `MODKEY+1..9` | Switch tag |

Full bindings are in [`.local/src/dwm/config.h`](.local/src/dwm/config.h).

## The `spacbr` CLI

After install, `spacbr` is the management entry point:

```
spacbr install | update | repair | uninstall | doctor | info | version
spacbr network | audio | brightness | bluetooth | display | wallpaper | screenshot | power
```

The first group manages the system itself (see `install/`). The second
group are thin wrappers around the same `~/.local/bin/*` scripts the
dwm keybindings call directly — useful when you'd rather type a
command than remember a chord.

## Installing

**Starting from a blank machine and a live Arch ISO?** Boot the ISO,
connect to the network, then:

```sh
curl -fsSL https://raw.githubusercontent.com/spacbrhq/spacbr/main/install/live-install.sh | sh
```

That partitions the disk (EFI + btrfs, no subvolume — matches a real
`archinstall` reference config, see `docs/architecture.md`), installs
a minimal bootable Arch base — both `linux` and `linux-lts`, Limine as
the bootloader (Unified Kernel Images, installed to the removable EFI
path), Plymouth, NTP, mirrors set to Japan/South Korea over HTTPS —
creates your user with sudo, and clones this repo into it. **Reboot,
log in with your normal password once, and the rest happens on its
own**: a first-login bootstrap runs the real installer below
automatically and starts `dwm` when it's done — no second command to
remember or type. (Not tty auto-login — every boot still needs a real
password; see `docs/architecture.md`'s "Live installer" section for
why that distinction matters and how the handoff actually works.) See
[`install/live-install.sh`](install/live-install.sh)'s own header
comment before running it: it's a genuinely destructive, one-way
operation (it erases the disk you point it at), it only supports a
single-disk UEFI + Limine setup (no LVM/RAID/encryption/GRUB — use
`archinstall` itself for those), and **it has not been run
start-to-finish against real hardware** — built by directly reading
`archinstall`'s own source for the proven patterns, but test it in a
disposable VM before trusting it on a real machine.

**Already have Arch installed** (via `archinstall`, manually, or the
step above)? **Read [`docs/prerequisites.md`](docs/prerequisites.md)
first** — in particular, a genuinely minimal manual Arch install
doesn't have working `sudo` by default, which the installer checks for
and stops on if it's missing.

Once a release is actually published (see `release/README.md` — none
has been cut yet):

```sh
curl -fsSL https://spacbr.com/install | sh
```

That fetches `release/bootstrap.sh`, which resolves a specific,
checksum-verified release and hands off to its `install/install.sh` —
see `release/README.md` for exactly how spacbr.com's four paths map
to GitHub.

Until a release exists, install from a clone:

```sh
git clone https://github.com/spacbrhq/spacbr ~/spacbr
cd ~/spacbr
./install/install.sh
```

See [`install/`](install/) for what the installer actually does, and
[docs/architecture.md](docs/architecture.md#deployment-model) for why
it's structured that way.

## Status

Early, but real-hardware tested. In place and verified live against an
actual Arch machine — not just read from code: the visual system,
Suckless patches, dmenu contextual scripts, package manifests, the
`spacbr` CLI, and the full install/update/repair/doctor pipeline,
including the firewall, `pacman.conf`, CPU microcode, GPU drivers, the
maintenance timers, and NetBird. The release tooling
(`release/build.sh`/`publish.sh`/`bootstrap.sh`) is build-tested
against this repo's own HEAD with output verified, but not used for a
real release yet. `install/live-install.sh` (the from-scratch live-ISO
installer) is the one exception to "verified live" — see its own
header comment and `docs/architecture.md`'s "Live installer" section
for why, and test it in a disposable VM before real hardware.

Not yet done: no release has actually been tagged/published, no GitHub
remote is configured, and spacbr.com's actual DNS/hosting isn't wired
up — see `release/README.md` for the exact remaining steps. Until a
release exists, `spacbr update`/`repair` without an explicit source
directory can't fetch anything newer than what's already deployed —
see the note at the top of `install/update.sh` — and
`live-install.sh`'s default repo URL (`github.com/spacbrhq/spacbr`)
needs overriding at its own prompt if that remote isn't live yet. See
`VERSION` for the current release.

## License

MIT, see [`LICENSE`](LICENSE). Suckless components under `.local/src/`
carry their own upstream licenses.
