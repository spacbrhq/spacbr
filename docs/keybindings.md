# Keybindings

`MODKEY` is the Super/Windows key (`Mod4Mask`). Source of truth is
[`.local/src/dwm/config.h`](../.local/src/dwm/config.h) — if this file
and that one ever disagree, the config wins.

## Applications

| Key | Action |
|---|---|
| `MODKEY+p` | dmenu launcher |
| `MODKEY+t` | Terminal (st) |
| `MODKEY+w` | Browser (Firefox) |
| `MODKEY+e` | File manager (pcmanfm) |
| `MODKEY+o` | Password menu (passmenu) |
| `MODKEY+c` | Clipboard history (clipmenu) |
| `Print` | Screenshot (region select) |

## System (dmenu-driven)

| Key | Action |
|---|---|
| `MODKEY+Shift+L` or `XF86 ScreenSaver` | Lock screen (blurred background — built into `slock` itself) |
| `MODKEY+Shift+P` or `XF86 PowerOff` | Power menu — lock/logout/suspend/reboot/shutdown |
| `MODKEY+Shift+A` | Audio output/input device selection |
| `MODKEY+Shift+W` | Wallpaper picker |
| `XF86 Display` | Display layout menu (xrandr: auto/extend/mirror/external/internal) |
| `XF86 Bluetooth` | Bluetooth menu (power/scan/connect/disconnect/remove) |

Volume, mic mute, and brightness use the standard hardware keys
(`XF86 AudioRaiseVolume`/`LowerVolume`/`Mute`/`MicMute`,
`XF86 MonBrightnessUp`/`Down`) and don't go through dmenu — they're
direct `wpctl`/`brightnessctl` calls.

Every one of the scripts behind these bindings is also reachable as a
plain command: `spacbr audio`, `spacbr bluetooth`, `spacbr display`,
`spacbr wallpaper`, `spacbr power`, `spacbr screenshot`, `spacbr network`.

## Window management

| Key | Action |
|---|---|
| `MODKEY+j` / `MODKEY+k` | Focus next / previous window |
| `MODKEY+Return` | Zoom (swap with master) |
| `MODKEY+i` / `MODKEY+d` | Increase / decrease master count |
| `MODKEY+h` / `MODKEY+l` | Shrink / grow master area |
| `MODKEY+r` / `MODKEY+f` / `MODKEY+m` | Tile / floating / monocle layout |
| `MODKEY+space` | Cycle layout |
| `MODKEY+Shift+space` | Toggle floating |
| `MODKEY+b` | Toggle bar |
| `Alt+F4` | Kill focused client |
| `MODKEY+Tab` | Toggle previous tag |
| `MODKEY+1`..`9` | View tag |
| `MODKEY+Shift+1`..`9` | Move window to tag |
| `MODKEY+Ctrl+1`..`9` | Toggle tag visibility |
| `MODKEY+Ctrl+Shift+1`..`9` | Toggle window's tag |
| `MODKEY+0` | View all tags |
| `MODKEY+Shift+0` | Tag window with all tags |
| `MODKEY+comma` / `period` | Focus previous / next monitor |
| `MODKEY+Shift+comma` / `period` | Move window to previous / next monitor |
| `MODKEY+F5` | Reload colors from Xresources |
| `MODKEY+Shift+q` | Quit dwm |

## Editing conventions

- `MODKEY` alone: launch or view.
- `MODKEY+Shift`: destructive/moving actions (move window, quit, lock).
- `XF86` keys: dedicated hardware buttons map to the one action they're
  physically labeled for — no dual-purpose XF86 bindings.

When adding a new binding, check it against the full `keys[]` array in
`config.h` first — a silently double-bound key (both entries compile,
only the first ever fires) has happened before in this repo.
