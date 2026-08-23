# Troubleshooting

Start with `spacbr doctor` — every failure it reports prints a
remediation hint (`-> ...`) with the exact command to run. This file
covers the failures that need more context than one line.

## X11 won't start / dwm doesn't appear

- Check you're actually on tty1: `.zshrc` only runs `startx` when
  `$(tty)` is `/dev/tty1`. Logging in on another tty won't launch X.
- Check for a stale X lock: if a previous session crashed,
  `/tmp/.X0-lock` can block a new one from starting. Remove it only if
  you're sure no X server is actually running (`pidof Xorg`).
- Check `~/.local/share/xorg/Xorg.0.log` (or `journalctl -b -u
  display-manager` equivalent, though SPACBR doesn't use a display
  manager) for the actual Xorg error.
- `spacbr doctor` — if "Xorg present" or "dwm" fail, that's your
  answer: something didn't get installed/built.

## dwm/dmenu/st/dwmblocks not found after install

These install to `~/.local/bin` (see `packages/`'s note on why, and
the audit reasoning in git history for the PREFIX change from
`/usr/local`). If `command -v dwm` fails:

1. Confirm `~/.local/bin` is actually in `$PATH` —
   `spacbr doctor`'s "~/.local/bin in PATH" check covers this. It's
   exported from `.config/shell/profile`; if you're not using zsh with
   that profile sourced, add it yourself.
2. Rebuild directly: `cd ~/.local/src/dwm && make && make install`
   (same pattern for `dmenu`, `st`, `blocks`).

## slock doesn't lock, or asks for a password that never works

`slock` must be setuid-root to read shadow authentication —
`spacbr doctor`'s "slock is setuid" check verifies this. If it's
missing: `sudo chmod u+s $(command -v slock)`. This is also why slock
alone installs to `/usr/local` instead of `~/.local/bin` — a
user-writable, sometimes `nosuid`-mounted home directory can't safely
host a setuid-root binary. Don't try to move it there.

## Lock screen isn't blurred, or the screen doesn't dim before locking

Locking goes through `.local/bin/lock` (blur wrapper around `slock`)
and idle-triggered locking goes through `.local/bin/screensaver`
(the dim stage) — see `docs/architecture.md`'s "Locking and idle"
section for the full sequence. If either is missing:

- Check `MODKEY+Shift+L` and the power menu both point at
  `~/.local/bin/lock`, not raw `slock` — `dwm/config.h`'s `LOCKSCREEN`
  macro. If dwm was built before this changed, rebuild it.
- The blur needs `import` and `magick` (both from `imagemagick`,
  already a dependency) — it fails silently to a plain-color lock
  screen if either is missing, rather than erroring, so check
  `command -v import magick` if the blur never appears.
- The dim needs `brightnessctl` and an actual backlight device —
  desktops with no laptop panel have nothing to dim, and the script
  exits quietly in that case. This is expected, not a bug: the lock
  itself still happens on schedule regardless.
- The brief moment of visible desktop before the blur/lock appears
  (screenshot + blur takes a beat) is a known, accepted tradeoff of
  doing this in a wrapper script instead of patching `slock` itself —
  not a bug to chase.

## No sound / audio device missing

- `spacbr doctor` checks PipeWire/WirePlumber are *installed*, not
  that they're *running*. Audio is started from `xinitrc`
  (`pipewire &`, `pipewire-pulse &`, `wireplumber &`), not systemd —
  check they actually launched: `pgrep -fl pipewire`.
- `spacbr audio` lets you pick a specific output/input device once the
  daemons are up. If the device you want isn't listed, check
  `wpctl status` directly — the picker parses that output, and an
  unusual `wpctl status` layout could mean the parser misses an entry
  (see `.local/bin/audio`'s `list_section` function).

## "Toggle speaker/headphones" says it can't find both

Most jack-sensing hardware already auto-switches on plug/unplug via
WirePlumber itself, with no action needed — the toggle in
`spacbr audio` is a manual override for when that isn't enough or
isn't happening. It tries two hardware shapes in order:

1. One sink with separate "Speakers"/"Headphones" **ports** (typical
   onboard/laptop codecs) — switched via `pactl set-sink-port`.
2. Two genuinely separate **sinks** (e.g. a USB headset shows up as
   its own device) — switched via `pactl set-default-sink`.

If your hardware exposes neither (an unusual port/sink naming scheme,
or a headphone jack that isn't exposed as a port/sink at all), the
toggle will correctly report it can't find both and do nothing. Check
`pactl list sinks` yourself to see how your hardware actually names
things, and adjust `.local/bin/audio`'s `speaker_port`/`headphone_port`
matching (currently `speaker`/`headphone`/`headset`, case-insensitive)
if needed. This logic is verified against realistic sample `pactl`
output, not against real hardware — the exact port/sink names on your
machine may differ from what's assumed here.

## Network block in the bar stuck on "offline" or blank

- `.local/bin/net` caches its probe result in
  `/tmp/netstatus_cache_$USER` for 30 seconds and only re-probes async
  in the background — the first read after a network change can be
  stale for up to that long.
- Clicking the block launches `nmtui` via `$TERMINAL`. If nothing
  happens, check `$TERMINAL` is actually exported (`echo $TERMINAL`
  should print `st`) — this was a real bug fixed early in the repo's
  history (see git log).

## Bluetooth/display/wallpaper/power menus show nothing or error

These are dmenu front-ends over `bluetoothctl`/`xrandr`/`hsetroot`/
`loginctl`. If the menu itself doesn't appear, `dmenu` isn't the
problem — check the underlying tool works standalone first
(`bluetoothctl show`, `xrandr --query`, etc.) before assuming the
script is broken.

## Installer/update/repair fails partway through

- Nothing is destructive by default: `deploy_tree` (in
  `install/functions/configs.sh`) backs up any existing file it's
  about to overwrite to `$XDG_STATE_HOME/spacbr/backups/<timestamp>/`
  before touching it. Check there first if something looks wrong after
  a run.
- All of install/update/repair are safe to re-run — packages are
  `--needed` (skip if present), file copies are content-diffed, Suckless
  builds are cheap. If a run fails partway, just run it again.
- `spacbr update`/`spacbr repair` run with no arguments, from the
  deployed copy, can't refresh dotfile *content* — see the note at the
  top of `install/update.sh`. Point them at an updated clone instead:
  `spacbr update ~/spacbr`.

## Uninstalling didn't remove everything I expected

By design — `spacbr uninstall` only removes what's in
`$XDG_STATE_HOME/spacbr/manifest` (files it deployed) plus the built
Suckless binaries. It never removes pacman packages (something else on
your system might depend on them) or personal data (backgrounds,
gnupg keyrings, documents). Remove those yourself if you actually want
them gone.
