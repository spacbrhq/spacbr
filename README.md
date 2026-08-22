# SPACBR

An opinionated personal desktop system for Arch Linux — X11, `dwm`,
and a small set of Suckless tools and native Linux utilities, unified
by one visual language, one interaction model, and one installer.

SPACBR is not a distribution, not a desktop environment, and not a
Wayland compositor. It's an integration layer on top of stock Arch
Linux: Arch remains Arch underneath, and SPACBR can be removed without
breaking it.

Full architecture and design rules live in [`CLAUDE.md`](CLAUDE.md) —
read that first if you're changing anything here.

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
install/        the installer (install/update/repair/uninstall)
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
| `MODKEY+Shift+L` / `XF86 ScreenSaver` | Lock screen |
| `MODKEY+Shift+P` / `XF86 PowerOff` | Power menu (lock/logout/suspend/reboot/shutdown) |
| `MODKEY+Shift+A` | Audio device selection |
| `MODKEY+Shift+W` | Wallpaper picker |
| `XF86 Display` | Display management (xrandr) |
| `XF86 Bluetooth` | Bluetooth menu |
| `Print` | Screenshot |
| `MODKEY+1..9` | Switch tag |

Full bindings are in [`.local/src/dwm/config.h`](.local/src/dwm/config.h).

## Installing

Not yet published. Once released:

```sh
curl -fsSL https://<domain>/install | sh
```

Until then, install from a clone:

```sh
git clone <this-repo> ~/spacbr
cd ~/spacbr
./install/install.sh
```

See [`install/`](install/) for what the installer actually does, and
CLAUDE.md §53-72 for why it's structured that way.

## Status

Early — the visual system, Suckless patches, and dmenu contextual
scripts are in place; the installer and `spacbr` CLI are still being
built out. See `VERSION` for the current release.

## License

MIT, see [`LICENSE`](LICENSE). Suckless components under `.local/src/`
carry their own upstream licenses.
