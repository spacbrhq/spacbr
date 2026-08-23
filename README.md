# SPACBR

An opinionated personal desktop system for Arch Linux — X11, `dwm`,
and a small set of Suckless tools and native Linux utilities, unified
by one visual language, one interaction model, and one installer.

SPACBR is not a distribution, not a desktop environment, and not a
Wayland compositor. It's an integration layer on top of stock Arch
Linux: Arch remains Arch underneath, and SPACBR can be removed without
breaking it.

Full architecture and design rules live in [`CLAUDE.md`](CLAUDE.md) —
read that first if you're changing anything here. Shorter, task-focused
docs live in [`docs/`](docs/): [architecture](docs/architecture.md),
[keybindings](docs/keybindings.md), [troubleshooting](docs/troubleshooting.md),
[development](docs/development.md).

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
| Audio | PipeWire + WirePlumber (`wpctl`) |
| Bluetooth | BlueZ (`bluetoothctl`) |
| Brightness | `brightnessctl` |
| Display | `xrandr` |

Each of these has exactly one owner — see CLAUDE.md §7 for the full
responsibility model and the reasoning behind it.

## Repository layout

```
.config/        XDG configuration (dwm/dmenu/st/slock configs live under .local/src/*)
.local/bin/     user scripts — the dmenu-driven contextual interfaces
.local/src/     Suckless components, built from source (dwm, dmenu, st,
                slock, dwmblocks) with their patches under patches/
packages/       curated pacman package manifests (base, x11, desktop, hardware, aur)
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
| `MODKEY+Shift+A` | Audio device selection |
| `MODKEY+Shift+W` | Wallpaper picker |
| `XF86 Display` | Display management (xrandr) |
| `XF86 Bluetooth` | Bluetooth menu |
| `Print` | Screenshot |
| `MODKEY+1..9` | Switch tag |

Full bindings are in [`.local/src/dwm/config.h`](.local/src/dwm/config.h).

## The `spacbr` CLI

After install, `spacbr` is the management entry point:

```
spacbr install | update | repair | uninstall | doctor | info | version
spacbr network | audio | bluetooth | display | wallpaper | screenshot | power
```

The first group manages the system itself (see `install/`). The second
group are thin wrappers around the same `~/.local/bin/*` scripts the
dwm keybindings call directly — useful when you'd rather type a
command than remember a chord.

## Installing

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
git clone https://github.com/eightharsh/spacbr ~/spacbr
cd ~/spacbr
./install/install.sh
```

See [`install/`](install/) for what the installer actually does, and
CLAUDE.md §53-72 for why it's structured that way.

## Status

Early. In place: the visual system, Suckless patches, dmenu contextual
scripts, package manifests, the installer (install/update/repair/
uninstall/doctor), the `spacbr` CLI, and the release tooling
(`release/build.sh`/`publish.sh`/`bootstrap.sh` — build-tested against
this repo's own HEAD, output verified). Not yet done: no release has
actually been tagged/published, no GitHub remote is configured, and
spacbr.com's actual DNS/hosting isn't wired up — see `release/README.md`
for the exact remaining steps. Until a release exists, `spacbr update`/
`repair` without an explicit source directory can't fetch anything
newer than what's already deployed — see the note at the top of
`install/update.sh`. None of this has been run against a real Arch
machine yet. See `VERSION` for the current release.

## License

MIT, see [`LICENSE`](LICENSE). Suckless components under `.local/src/`
carry their own upstream licenses.
