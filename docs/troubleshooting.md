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

## Lock screen isn't blurred

The blur is built into `slock` itself (hand-adapted Imlib2 patch, see
`docs/architecture.md`'s "Locking" section) — there's no wrapper
script to check.

- `slock` needs `imlib2` (`packages/x11`) at build time for
  `Imlib2.h` — if it was built before this was added, `make clean &&
  make && sudo make install` in `.local/src/slock` (needs `sudo` —
  see the setuid note above).
- Screenshot capture happening but the image looking wrong (garbled,
  black, or a stale frame) usually means Imlib2 is reading the root
  window before the previous frame (e.g. the desktop right after
  waking) has actually painted — this is inherent to grabbing the
  root window's current contents, not something the lock logic
  controls.
- If capture fails outright (e.g. `imlib_create_image` returns NULL),
  `slock` falls back to the plain solid-color background exactly as
  before this feature existed — silently, by design, not an error you
  need to chase.
- To disable the blur without removing it, comment out `#define BLUR`
  in `.local/src/slock/config.h` and rebuild.

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
- The block detects connectivity by finding whichever interface
  carries the default route (`ip route show default`), not by
  guessing from interface names. It used to match names against
  `/^e/` ("ethernet"), which silently never matched WiFi interfaces
  (`wlan0`, `wlp2s0`, ...) — a WiFi-only machine would have shown
  "no eth" forever regardless of actual connectivity. If this ever
  regresses, check `ip route show default` directly first.

## Bluetooth menu hangs forever

If there's no Bluetooth adapter, `bluetoothctl` has no `org.bluez`
D-Bus service to talk to (systemd itself refuses to even start
`bluetoothd` — `ConditionPathIsDirectory=/sys/class/bluetooth` fails)
and blocks indefinitely instead of failing. `.local/bin/bluetooth`
checks `/sys/class/bluetooth` exists before doing anything else and
exits with a notification if not — same test `spacbr doctor`'s
"bluetooth service active" check already uses. If this ever hangs
again despite that check, something's wrong with the check itself, not
just missing hardware.

## Bluetooth/display/wallpaper/power menus show nothing or error

These are dmenu front-ends over `bluetoothctl`/`xrandr`/`hsetroot`/
`loginctl`. If the menu itself doesn't appear, `dmenu` isn't the
problem — check the underlying tool works standalone first
(`bluetoothctl show`, `xrandr --query`, etc.) before assuming the
script is broken.

## Opening a file (PDF, image, link) doesn't launch the app you expect

Default-app associations go through `handlr-regex`, configured in
`.config/mimeapps.list`. A regex catch-all like `^image/.*=nsxiv.desktop;`
only wins when *no* installed `.desktop` file has a real, exact
declared association for that specific mimetype — it's not a priority
override. This was found for real: `zathura-pdf-mupdf.desktop` also
declares `image/jpeg`/`png`/`bmp`/`tiff`/`svg+xml` (mupdf renders
standalone images too) and Firefox declares `image/gif`/`webp` (inline
image handling), so a plain `^image/.*` catch-all silently lost to
both of them for exactly the formats you'd actually hit day to day.
Check what's actually configured with `handlr get <mimetype>`
(e.g. `handlr get image/jpeg`); if it's wrong, add an *exact* entry
for that mimetype in `mimeapps.list` rather than assuming the regex
line covers it — exact entries are what mimeapps.list actually gives
override priority to.

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
- `spacbr repair` always re-syncs dotfiles from a real source directory
  now, regardless of what `spacbr doctor`'s checks find. It didn't
  used to: repair only attempted anything if some check had failed,
  but none of the checks verify individual `.local/bin` scripts exist
  (`wallpaper`, `audio`, `bluetooth`, ...) — deleting one and running
  `spacbr repair ~/spacbr` reported "Nothing to repair" while doing
  nothing, contradicting repair's own documented ability to restore
  missing `.local/bin` content. If `spacbr repair` without a source
  argument reports nothing to fix, that's real (nothing it can check
  found anything wrong) — point it at a source directory if you
  suspect a specific file went missing instead.

## Uninstalling didn't remove everything I expected

By design — `spacbr uninstall` only removes what's in
`$XDG_STATE_HOME/spacbr/manifest` (files it deployed) plus the built
Suckless binaries. It never removes pacman packages (something else on
your system might depend on them) or personal data (backgrounds,
gnupg keyrings, documents). Remove those yourself if you actually want
them gone.

## A service/app that needs an inbound connection stopped working after install

`nftables` (see `system/nftables/nftables.conf`) denies all inbound
connections except SSH and ping by default — this is expected for
anything that needs to *accept* incoming connections (a local web
server, a sync tool, game hosting, etc.), not something that's broken.
Add a rule for the port you need, e.g. `sudo nft add rule inet filter
input tcp dport <port> accept`, then make it permanent by adding the
same line to `system/nftables/nftables.conf` and re-running `spacbr
repair` (or edit `/etc/nftables.conf` directly and `sudo systemctl
restart nftables`, but that won't survive the next `spacbr
install`/`update` overwriting the file from source). Outbound
connections (browsing, updates, etc.) are never affected — only
unsolicited *inbound* ones are.

If you ever lock yourself out over SSH while editing this file
remotely, the same safety-net pattern used when this was first set up
works: `nft -c -f <file>` validates syntax without applying anything,
and applying changes with a backgrounded `sleep 90 && nft flush
ruleset` armed (cancel it once you've confirmed a fresh connection
still works) means a mistake recovers on its own within 90 seconds
instead of requiring physical access.

## A system update broke something and I want to go back

If root is btrfs, `snapper -c root list` shows every automatic
snapshot — `snap-pac` takes a pre/post pair around every pacman
transaction, so there's very likely one from right before whatever
broke. `snapper -c root status <pre>..<post>` shows exactly what that
transaction changed; `snapper -c root undochange <pre>..<post>`
reverts just those file changes without a full rollback. For
individual files, mount the old snapshot directly (it's a normal
read-only subvolume under `/.snapshots/<number>/snapshot`) and copy
what you need back out.

This machine's btrfs layout doesn't have a dedicated root subvolume to
swap out from under the running system (see "Snapshots" in
`docs/architecture.md`), so a full one-command boot-time rollback
isn't available the way it would be with `grub-btrfs` on a proper
`@`/`@home` layout — `undochange` or manual file recovery from a
snapshot are the paths that actually work here. `snapper list-configs`
returning nothing, or `spacbr doctor`'s "snapper" checks failing, means
either root isn't btrfs (nothing to do) or setup never ran — `spacbr
repair` fixes the latter.
