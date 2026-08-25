# Architecture

This is the authoritative map of SPACBR's design — read it first if
you're changing anything in this repo.

## What SPACBR is

An integration layer on stock Arch Linux, X11, and dwm — not a
distribution, not a desktop environment, not a Wayland compositor.
Removing SPACBR should leave a working, ordinary Arch install behind.

```
SPACBR
  ├── Configuration   (.config/, .local/)
  ├── Suckless        (.local/src/: dwm, dmenu, st, slock, dwmblocks)
  ├── Scripts         (.local/bin/: the dmenu-driven contextual tools)
  ├── Packages        (packages/: curated pacman manifests)
  ├── Installer       (install/: install, update, repair, uninstall, doctor)
  ├── CLI             (.local/bin/spacbr)
  └── Release         (release/: build, publish, web bootstrap — maintainer-only)
       │
       ▼
   Arch Linux → X11 → dwm → hardware
```

## One owner per responsibility

Every piece of functionality has exactly one tool responsible for it —
see the table in the README. The practical effect: if you're
about to add a second tool that does something an existing owner
already does (a second terminal, a second lock screen, a second
compositor), that's the signal to stop and either use the existing
owner or replace it — never run both. This has already come up once:
Alacritty duplicating `st`, and `xscreensaver` duplicating `slock`,
were both removed for exactly this reason.

The one deliberate exception: Zed, alongside Neovim/Vim as "Editor."
`nvim` stays the terminal/keyboard-driven editor matching this
project's own keyboard → dmenu → action model; Zed exists specifically
for GUI/mouse-driven work, not as a second silent owner of the same
responsibility. `.config/zed/settings.json` keeps `vim_mode` off on
purpose — a GUI editor running modal keybindings would defeat the
reason it exists alongside `nvim` rather than instead of it. The
difference from Alacritty/xscreensaver: those two did the *same* job
as an existing owner and were removed; Zed does a genuinely different
job (GUI-first vs. terminal-first) that the existing owner can't. If
you're ever tempted to add another "exception" like this, that
distinction — different job, not a nicer version of the same job — is
the bar it has to clear. `nvim`'s own config additionally carries
native LSP (`clangd`/`lua_ls`/`bash-language-server`, no plugin — built
into Neovim core) and treesitter (the config's first and only plugin
dependency, via a single `lazy.nvim` git-clone bootstrap, specifically
because parser version management is genuinely painful without it).

## Interaction model

```
keyboard shortcut → dmenu → action
```

Three layers, in order of preference:

1. **Keyboard** — direct dwm keybindings for things used constantly
   (window management, launching apps, volume/brightness).
2. **dmenu** — a contextual menu for anything with more than one
   choice to make (which wifi network, which bluetooth device, which
   power action). See `.local/bin/{audio,bluetooth,display,wallpaper,power}`.
3. **Terminal** — for anything that's genuinely a terminal task
   (`nmtui`, editing a file, running a build).

The permanent UI (the dwmblocks bar) stays minimal on purpose — it
shows state, not controls. Controls live behind the keyboard/dmenu
layers so the desktop stays visually quiet.

## Locking

`slock` is the only lock mechanism (§7/§18) — every lock trigger
(`MODKEY+Shift+L`, `XF86 ScreenSaver`, the power menu's Lock/Suspend,
and `xss-lock`'s idle timeout) spawns the raw binary directly; there's
no wrapper.

`slock` blurs the actual desktop as its lock background, via a
hand-adapted Imlib2 patch (see `.local/src/slock/config.h`'s `BLUR`
block and `slock.c`). The real upstream patch
(`tools.suckless.org/slock/patches/blur-pixelated-screen/`) targets
slock 1.4 and fails 5+ hunks against this repo's 1.5 (already carrying
the xresources patch), so it was reimplemented by hand into the
current source rather than force-applied — and along the way, three
real bugs in the upstream patch itself were caught and fixed rather
than carried forward:

1. Its fallback background color (when screenshot capture fails) used
   `colors[0]` (always the INIT tint) instead of `colors[color]`,
   silently losing the typing/wrong-password color feedback even in
   the no-blur fallback case.
2. `lock->bgmap` was never initialized on a struct allocated with
   `malloc` (not `calloc`) outside the success path, so a failed
   screenshot capture would leave every `if (lock->bgmap)` check
   reading uninitialized memory as if it were a valid Pixmap.
3. `imlib_free_image()` was called inside `lockscreen()`, which runs
   once per X11 screen — freeing the shared image after the first
   screen would leave any second screen (a genuine multi-head setup,
   not RandR/Xinerama multi-monitor) operating on freed memory.

One real, inherent tradeoff of this patch design that's *not* a bug:
once the blurred background is set, the lock window shows that same
static image regardless of auth state — the INIT/INPUT/FAILED color
feedback only ever applies as a fallback when screenshot capture
fails, not layered on top of the blur.

A separate, more serious bug was found in vanilla upstream `slock`
itself, unrelated to the blur patch: `main()` draws the lock screen
and grabs keyboard/pointer input *before* its DPMS setup block runs,
but that block treated any DPMS failure as fatal (`die()` →
`exit(1)`). Closing the X connection on exit makes the X server
release every grab and destroy the lock windows as part of normal
client-death cleanup — so on any X server without full DPMS support
(verified for real on a headless X server with no DPMS extension at
all), the screen would appear to lock and then silently unlock itself
moments later, with zero indication anything went wrong. DPMS only
ever controlled monitor auto-blanking while locked, never the actual
lock/grab, so a missing or broken DPMS extension is now a warning, not
a fatal error — the lock proceeds regardless, verified to actually
stay locked indefinitely under the same conditions that used to defeat
it within moments.

A third bug, found for real rather than by inspection, made the lock
screen show the *live* desktop instead of the static blurred snapshot
under `picom` (running with `detect-client-opacity = true`, needed for
its own reasons — see `.config/picom/picom.conf`): the upstream alpha
patch this config also carried set `_NET_WM_WINDOW_OPACITY` on the lock
window to a configurable `alpha` (`0.9` by default). That patch was
designed for a translucent *solid color* tint over nothing on a plain
VT — it predates this repo's blur patch, which gives the window a real
screenshot as its background instead of a solid color. Combining the
two meant picom kept compositing 10% of the real, still-updating
desktop back on top of the static blurred image for as long as the
screen stayed locked. Proven with a fullscreen `mpv` test pattern:
locking, waiting 3 seconds, and diffing two screenshots showed the
video's motion had continued underneath — the desktop was still
playing, not just weakly blurred. Bumping `alpha` to `1.0` to "fully
opaque" made it *worse*: `xprop` showed the resulting property was
`0` (fully invisible), because `alpha * 0xffffffff` was computed in
32-bit `float` precision (`alpha`'s declared type) and float's 24-bit
mantissa can't represent `0xffffffff` exactly — it rounds up to `2^32`,
one past `unsigned int`'s range, so the cast back to `unsigned int` was
undefined behavior that this compiler resolved to `0`. There is no
value of that expression that reaches genuine full opacity; the fix
was to delete the opacity mechanism outright rather than tune it —
`slock`'s window is a normal, fully opaque X11 window by default once
nothing sets `_NET_WM_WINDOW_OPACITY` on it at all, which is exactly
what a screenshot-backed lock screen needs.

Once that leak was gone, the original `blurRadius = 5` from the
adapted patch turned out to be undersized on its own too — a box blur
only softens edges, so any region wider than the radius (a solid
terminal background, a large flat color) stays essentially untouched
in its interior. `config.h` now blurs at `blurRadius = 16` and layers
a `dimAlpha = 210` (~82%) black overlay on top via
`imlib_image_fill_rectangle` with blending enabled, baked into the
same captured image before it ever becomes the window background.
Verified against real desktop content (a terminal full of `ls -la`
output): fully illegible. Verified against a SMPTE color-bar test
pattern (deliberately adversarial — large, fully-saturated, flat-color
regions are close to a worst case for any blur+darken scheme, since
proportional darkening preserves relative contrast and hue): still
faintly distinguishable at the color-bar boundaries. Real
desktop/video content isn't built from edge-to-edge saturated primary
colors, so this is treated as an accepted, documented limit rather
than tuned further at the cost of a much darker default lock screen.

A fixed-color box behind the message was added at one point to make a
locked screen unmistakable at a glance (see the git history for that
version), but it's now the same `colorname[INIT]`/`[INPUT]`/`[FAILED]`
pixel the window background itself would use if the screenshot capture
had failed — `writemessage()` takes the current color as a parameter
instead of hardcoding one. This gets both properties at once: a solid
box is still always visible against the blur, and its color now
actually shows the auth state (neutral at rest, accent blue while
typing, red on a wrong password) instead of being permanently one
fixed color regardless of what's happening.

DPMS (actual monitor power-down) is a separate mechanism from the
`xset s 900 900` screensaver/blank timeout above that triggers
`xss-lock`/`slock` -- and until now, nothing in `xinitrc` actually
configured it, leaving it at whatever the Xorg/driver default happens
to be. Verified for real on this machine: that default was 30 seconds
across Standby/Suspend/Off, not off entirely -- so the monitor went
fully dark within ~30s of any pause, while the documented 15-minute
idle-lock policy didn't actually lock the session until 900s later.
Not a security gap (it still locks eventually, just later than the
screen goes dark), but a real, unintended mismatch against the
documented policy. `xinitrc` now sets `xset +dpms; xset dpms 900 900
900` to align all three DPMS states with the same 900s used for the
screensaver.

## Firewall

`nftables` owns this, not `ufw` or `firewalld`: it's Arch's native
netfilter backend already (both of those are wrappers generating rules
for the same subsystem), and a static ruleset loaded once at boot by
the stock `nftables.service` (see `system/nftables/nftables.conf`) has
no need for an extra abstraction layer just to be more approachable.
This was a real, previously-unaddressed gap, not a speculative
hardening pass — this machine runs `sshd` and had no firewall at all
before this.

Policy: default-deny inbound (loopback, established/related traffic,
ping, and SSH allowed through), unrestricted outbound. The actual
threat model for a personal desktop is unsolicited inbound connections
-- auditing or whitelisting the machine's own outbound traffic would
break far more than it protects and isn't what solves a real problem
here.

Applying a default-deny firewall remotely over the exact connection
that could get cut off by a mistake in it is a genuine risk, not a
theoretical one -- so it wasn't applied blind. Sequence used: validate
the ruleset syntax only first (`nft -c -f`, applies nothing), arm a
backgrounded safety net (`sleep 90 && nft flush ruleset`, cancellable),
apply the real ruleset, open a *fresh* SSH connection to confirm it
still works, then cancel the safety net -- repeated a second time for
making it persistent (`/etc/nftables.conf` + enabling the service),
since reloading from the file is a second point where a typo could
lock things out. If either step had failed, the SSH session would have
recovered on its own within 90 seconds with no manual intervention
needed.

A real bug found later, on a second real machine: the ruleset's
Tailscale rule originally read `iif "tailscale0" accept`. `iif`
resolves the named interface to a kernel ifindex at ruleset-*load*
time -- if the interface doesn't exist yet, the whole load fails, not
just that one rule. `nftables.service` starts before `tailscaled` has
brought `tailscale0` up, so *every* boot failed the entire ruleset load
with "Interface does not exist", silently leaving that machine with no
firewall at all despite `nftables.service` showing "enabled" -- caught
by noticing `spacbr doctor`'s "firewall ruleset loaded" check failing,
then confirming with `sudo nft list ruleset` showing genuinely empty
tables. Fixed by switching to `iifname "tailscale0"`, which matches by
interface *name* at packet-filter time instead and doesn't care whether
the interface existed when the ruleset loaded. Reapplied using the same
validate/safety-net/verify/cancel sequence above.

Kept here even though the rule itself is gone: Tailscale has since been
replaced by NetBird (see `packages/aur`), and the current
`system/nftables/nftables.conf` has no equivalent rule at all —
NetBird's own docs say the client needs no inbound firewall port in a
standard NAT'd deployment, and it manages its own separate nftables
table for its `wt0` interface rather than needing an entry in this
one. The `iif`-vs-`iifname` lesson above is still real and still
applies to any future interface-based rule added here; it just isn't
currently exercised by anything in the live ruleset.

## Snapshots

`snapper` + `snap-pac` own this, conditional on the root filesystem
actually being btrfs (`setup_snapper()` in `services.sh` no-ops
otherwise). Real gap, not speculative hardening: this machine's root
is btrfs and had zero recovery path if a `pacman -Syu` went wrong.
`snap-pac` creates a pre/post snapshot pair around every pacman
transaction automatically; `snapper-timeline.timer` and
`snapper-cleanup.timer` add periodic snapshots and keep the total
count/space bounded, both confirmed enabled and running.

No vendored config file, unlike the firewall/polkit/modules-load
system files: `snapper create-config`'s own generated defaults (0.5 of
the filesystem, 10 hourly/daily/monthly/yearly timeline snapshots,
automatic cleanup) are already sensible for a personal desktop.
Overriding them would be config for its own sake, not solving a real
problem — `setup_snapper()` only creates the config if one doesn't
already exist, never touches an existing one.

One honest limitation, not glossed over: this machine's btrfs layout
is a flat root subvolume (the top-level subvolume itself, no dedicated
`@`/`@home` split). Snapshots, `snapper diff`, and mounting an old
snapshot to recover individual files all work fully regardless —
verified for real with a manual snapshot and a real pacman transaction
(reinstalling `nftables`), both showing up correctly in `snapper
list`. But a clean one-command boot-time rollback (`grub-btrfs`'s
usual trick) isn't as guaranteed as it would be with a proper subvolume
split, since there's no dedicated subvolume to swap out from under the
running system. Fixing that would mean migrating the filesystem layout
— a much bigger, more invasive step than "add a safety net," and not
something to do as a side effect of setting up snapshots.

## Maintenance timers

`paccache.timer` (pacman-contrib) and `reflector.timer` (reflector)
are enabled by `setup_maintenance_timers()` in `services.sh` — both
packages were already in `packages/base` for other reasons
(`pacman-contrib` for `spacbr mirrors`' underlying tooling, `reflector`
itself for the same script), but neither timer was ever actually
enabled. Real gap, not speculative: found for real that
`/var/cache/pacman/pkg` had already grown to 2.2GB from a single
session's package churn (installing/removing `tailscale`, building
`netbird`, `geary` and its ~30 dependencies) with nothing trimming it —
unbounded growth on a machine that's never rebooted to notice via some
other maintenance path. `reflector.timer` is a smaller, lower-urgency
addition alongside it: mirrors previously only refreshed via the
manual `spacbr mirrors` dmenu entry, never automatically.

`fstrim.timer` (ships with `util-linux`, already in `packages/base` —
no new package) is enabled by the same function, but conditionally:
only if `detect_root_nonrotational()` (`detect.sh`) confirms root's
underlying block device reports non-rotational
(`/sys/block/<disk>/queue/rotational` = `0`) — an SSD or NVMe drive —
**and** `detect_root_btrfs()` says root is *not* btrfs. A spinning
disk gets zero benefit from periodic TRIM, so this isn't enabled
unconditionally the way `paccache`/`reflector` are. The btrfs
exclusion was a real correction, not part of the original design:
this shipped enabling `fstrim.timer` unconditionally on any SSD/NVMe
(including this repo's own btrfs+NVMe test machine) until directly
reading archinstall's own `installer.py`
(`archlinux/archinstall`) surfaced `_prepare_fs_type()`'s `if
fs_type == FilesystemType.BTRFS: self._disable_fstrim = True` —
traced to [archinstall issue
#1837](https://github.com/archlinux/archinstall/issues/1837): btrfs
has had async discard enabled by default since kernel 6.2, making a
separate periodic TRIM pass redundant (not harmful, just pointless —
and this repo's own package philosophy, §39, treats pointless as
reason enough to skip). `setup_maintenance_timers()` now actively
*disables* `fstrim.timer` on btrfs if it finds it enabled, so re-running
`spacbr repair` self-corrects a system that picked up the old
unconditional behavior. Both `detect_root_nonrotational()` and
`detect_root_btrfs()` back both the setup function and their matching
`spacbr doctor` checks, so none of the four can drift apart.
Periodic `fstrim.timer` over a continuous `discard` mount option
(for non-btrfs filesystems) is the current Arch wiki recommendation
(avoids per-delete TRIM latency/security concerns) — not something
reinvented here.

## CPU microcode

`install_cpu_microcode()` (`packages.sh`) detects CPU vendor from
`/proc/cpuinfo`'s `vendor_id` and installs the matching official
package (`intel-ucode`/`amd-ucode`). Can't live as a static
`packages/*` line like everything else — which one is correct depends
on runtime hardware, and installing both unconditionally would be
wrong (wasted space, and the wrong one's `ucode.img` just sits
unused). Called from `install_all_packages()`, right after the static
`packages/{base,x11,desktop,hardware}` loop.

Skips entirely inside a VM, via `detect_is_vm()` (`detect.sh`,
`systemd-detect-virt -q` — part of systemd, no new dependency): a
virtual CPU has no real hardware microcode for the hypervisor's vCPU
to load, so installing `intel-ucode`/`amd-ucode` there is pointless
(not harmful). Added after directly reading archinstall's own
`_get_microcode()` in `installer.py`, which checks `SysInfo.is_vm()`
via the identical `systemd-detect-virt` mechanism before ever
attempting microcode — this wasn't part of the original design here,
it was adopted specifically because archinstall already solved the
same problem the same way. `spacbr doctor`'s microcode checks are
skipped in a VM too, for the same reason.

Deliberate scope boundary: this only installs the package. It does
**not** touch bootloader configuration (regenerating `grub.cfg`,
editing systemd-boot loader entries, rebuilding a UKI) — SPACBR
doesn't detect or manage bootloader type anywhere else in this repo,
and getting boot configuration wrong risks an unbootable system in a
way that's far harder to recover from remotely than anything else this
installer touches (contrast with the nftables firewall change earlier
in this document, which had a safety net precisely *because* SSH
access could be tested and recovered from if something went wrong —
there's no equivalent safety net for a bricked boot chain reachable
only over SSH). Verified for real on one machine (systemd-boot +
UKI/measured boot): `pacman -S intel-ucode` alone was already
sufficient there — `journalctl -k | grep microcode` confirmed it
actually loading at boot with zero manual bootloader step needed, so a
modern kernel-install-based systemd-boot setup appears to wire this in
automatically. **Not verified**: a plain GRUB setup, where the Arch
wiki's own documentation says a manual `grub-mkconfig` re-run is needed
after installing microcode for the first time. `spacbr doctor`'s "CPU
microcode loaded" check exists specifically to catch this gap if it
ever applies — it checks the kernel log for an actual microcode load
message, not just that the package is installed, and its remediation
hint points at the GRUB step. If that check ever fails despite the
package being present, that's expected on GRUB until the manual step
runs, not a SPACBR bug.

## Audio startup

PipeWire, WirePlumber, and the PulseAudio-compat layer are *not*
started from `xinitrc` — a real bug, found for real while wiring up
screen recording (`.local/bin/record`'s audio option needs the
PulseAudio-compat layer for `ffmpeg -f pulse`). `xinitrc` used to start
`pipewire &`/`pipewire-pulse &`/`wireplumber &` as raw background
processes. Their packages already ship socket-activated systemd
--user units, enabled by default — and the user's systemd instance
starts at login, before `xinitrc` ever runs, so `pipewire.socket` is
already listening on `/run/user/$UID/pipewire-0` by the time those
lines executed. Starting `pipewire &` a second time tried to bind that
same socket path again, which failed; that failure cascaded
(`pipewire.socket` → failed, `pipewire.service` → dependency failed,
`pipewire-pulse.socket`/`.service` → dependency failed too) and
systemd rate-limited further retries. Net effect: the native PipeWire
protocol mostly still worked (`wpctl`, since the raw xinitrc-started
process was providing it) but the PulseAudio-compat layer (`pactl`,
and anything built on it) never came up at all — silently, since
nothing was checking for it. Removing those three lines lets the
already-enabled systemd units do this correctly.

## Brightness and contrast

`.local/bin/brightness` (`up`/`down`/`set <pct>`/`get`/`menu`) wraps
`ddcutil` the same way `.local/bin/volume` wraps `wpctl` — a bare
hardware-control call changes the level correctly but gives zero
feedback, which reads as "the keys don't work" even when they do.
Unlike audio (split into `volume`, the hot-key-bound primitive, and
`audio`, the dmenu front-end that shells out to it), brightness keeps
both in one file: its `menu` action isn't doing anything structurally
different from `up`/`down`/`set`, just a dmenu layer on the same
operations, so a second file would just be indirection without a real
seam to justify it.

Every brightness change also sets contrast (VCP 0x12) via a linear map
of the resulting brightness level: a touch more contrast at high
brightness (bright ambient light washes out a low-contrast image), a
touch less at low brightness (high contrast in a dark room looks harsh
and crushes shadow detail on most panels), bounded to a narrow band
(60-90) so it never swings to a genuinely bad-looking extreme. This is
an explicit, subjective "looks good" default, not a derived or
industry-standard value — there's no such thing as a universally
correct brightness/contrast curve, it depends on the panel and the
room. The four constants (`base`, `scale`, `min`, `max`) live inline in
`apply_contrast()` specifically so they're easy to hand-tune for a
different monitor or taste without hunting through the file. Best-effort:
a monitor that doesn't support VCP 0x12 just leaves contrast alone,
same silent-fallback spirit as brightness itself when `ddcutil` fails
outright (no DDC/CI support at all).

Verified live on a second real machine, not just read from the code:
the formula's output matched exactly at three brightness levels (70% →
81 contrast, 10% → 63, 15% → 64), and the full interactive `menu` flow
(including the two-step "Set percentage" submenu) was driven end to
end with `xdotool` against a disposable `Xvfb` display — the same
isolated-display testing method `docs/development.md` already
documents — rather than touching the real desktop session, since a
`dwm` restart would have ended it (`xinitrc` execs `dwm` directly, no
restart loop).

## Visual system

Everything shares one palette — internally called **eightchrome**, by eightharsh:

| Role | Hex |
|---|---|
| Background | `#2f343f` |
| Foreground | `#e1e3e7` |
| Selection / border accent | `#404552` |
| Bright accent (blue) | `#4084d6` |
| Bright white | `#fafafa` |
| Error / urgent | `#ed4737` |

`.config/xresources` is the canonical definition. Four components read
it **live, at runtime**, so they can never drift out of sync with it:

- `dwm` — via the applied xrdb patch (`loadxrdb()`, bound to `MODKEY+F5`
  and SIGHUP)
- `st` — via its applied xresources patch
- `slock` — via its `ResourcePref` table
- `nsxiv` — natively, no patch needed (see `nsxiv(1)`'s CONFIGURATION
  section) — its `Nsxiv.*` keys live right next to `dwm.*` in
  `.config/xresources`

`dmenu` deliberately carries its palette/font hardcoded in its own
`config.h` instead — see the comment at the top of
`.config/xresources` for why (it already reads Xresources for these
exact keys via an applied patch, but the compiled-in fallback is the
one place the values need to live, not two). GTK (`gtk-2.0`/`3.0`/
`4.0`), `mpv`, `dunst`, Vim/Neovim, Zathura all have these same hex
values **hardcoded** and must be kept in sync by hand. This is a real
gap, not a theoretical one — this repo has shipped actual drift from
it more than once, all caught only by testing on real hardware, not by
reading the code:

- dwm's own compiled-in fallback colors didn't match the palette at
  all (meaning `MODKEY+p`, the single most-used keybinding, rendered
  `dmenu` in the wrong colors until this was caught).
- GTK apps rendered in `Cantarell` while every other component used
  `Hack`.
- `dunstrc` used deprecated legacy `height`/`offset` syntax (dunst
  1.12+ warns about this; `width` had already been migrated to the
  current tuple syntax, `height`/`offset` were just missed).
- `nvim`/`vim`'s hand-rolled colorscheme used two colors
  (`#2d3043`, `#1e2030`) that were never part of eightchrome at all —
  close enough to a common third-party colorscheme's tones to suggest
  leftover drift from a template, not a deliberate choice (confirmed
  with the user).

`spacbr doctor`'s "Visual system consistency" checks catch the
mismatches above automatically where a check makes sense; the
deprecated-syntax and off-palette-color classes don't have a
mechanical check (there's no "is this the real palette" test that
wouldn't just be re-implementing the palette table), so those rely on
actually looking.

A related, more severe failure mode: the entire GTK dark theme can
vanish, not just drift. `arc-gtk-theme` (AUR) is the GTK theme every
`gtk-2.0`/`3.0`/`4.0` config and `xinitrc`'s `GTK_THEME` assume, and
its *published* AUR PKGBUILD doesn't build at all (it hardcodes GNOME
Shell 43 theming against a source tarball whose asset layout doesn't
match — verified via a real, reproducible `paru -S` failure). Fixed by
vendoring a patched PKGBUILD (`packages/aur-overrides/arc-gtk-theme/`)
that skips the broken, SPACBR-irrelevant GNOME Shell/Cinnamon build
steps; see "Deployment model" below for how `aur-overrides/` works in
general. The doctor's "GTK theme installed"
check verifies `/usr/share/themes/Arc-Dark` actually exists on disk,
independent of which path installed it, so a future regression here
shows up as an actionable failure instead of a silent fallback to
plain light GTK.

Zed (see "One owner per responsibility" above for its editor-ownership
status) doesn't hardcode palette values inline at all — it has its own
full theme file,
`.config/zed/themes/eightchrome.json`, since Zed's theme format is a
JSON document Zed reads directly rather than a handful of `highlight`/
`hi()` calls. Same palette, different mechanism; keep both in sync by
hand the same way as everything else in the "hardcoded" group above.

There's an unused, already-present patch
(`.local/src/dmenu/patches/dmenu-xresources-4.9.diff`) that would move
`dmenu` fully into the live-synced group. It doesn't apply cleanly
against the current `dmenu.c` (already modified by the fuzzy-match
patch — 3 of 6 hunks fail), and hand-resolving a C patch was
deliberately not done blind. A real build/test environment now exists
(this repo has been built, run, and debugged live on real Arch
hardware repeatedly — see `docs/development.md`), so "no way to
compile-test" is no longer the blocker; this is simply not yet
prioritized, and dmenu's own hardcoded values already match the
palette exactly (verified, and checked by `spacbr doctor`).

When you add a new themed component: hardcode the palette values
above (or give it its own theme file if that's how it's configured,
like Zed), note in a comment that they must track
`.config/xresources`, and add a `spacbr doctor` check for it if drift
would be easy to miss.

### Icons: deliberately none

The dwmblocks bar uses short text labels (`Mem: `, `Net: `, `Bat: `),
not pictographic icons. This was a considered decision, not an
oversight: plain `Hack` only ships Powerline separator/branch/lock
glyphs, not network/volume/battery icons — getting real icons would
mean adding `ttf-hack-nerd` as a new font dependency, which cuts
against CLAUDE.md's repeated "avoid excessive icons" guidance (§4,
§16, §75). If this is ever revisited, it's a deliberate trade-off to
make explicitly, not something to silently "fix" back in.

## Live installer (`install/live-install.sh`)

Boots off the Arch live ISO, ends with a rebootable, SPACBR-clonable
system. Two-phase model, the same "tiny bootstrap → real installer"
shape `release/bootstrap.sh` already uses for the release channel:

```
Phase 1 (live ISO, as root)          Phase 2 (booted system, as the new user)
  install/live-install.sh       -->    install/install.sh
  disk, base OS, bootloader             packages, dotfiles, Suckless,
                                         services, everything SPACBR is
```

Phase 1 cannot become Phase 2, and this is a hard technical
constraint, not a design preference: `install.sh` enables services
with `systemctl enable --now`, and `arch-chroot` gives you the target
filesystem but not a running `systemd` instance to start anything
against inside it — only `enable` (a symlink, no init needed) works
in a chroot. Attempting to run the real installer inside the live-ISO
chroot would either silently skip every `--now` or hang waiting on a
D-Bus/systemd instance that doesn't exist there. So Phase 1 stops at
"reboot and log in," and Phase 2 runs for real, against a genuinely
running system — exactly like the existing manual-install path in
`README.md` already does, just with everything before that step
automated instead of hand-typed from the Arch wiki.

**Deliberately not a general-purpose installer.** `archinstall` itself
already is one — LVM, RAID, disk encryption, GRUB/BIOS, arbitrary
partition layouts, desktop-environment profiles. Rebuilding that would
violate this repo's own "don't reinvent an existing tool" principle
(§80) for no benefit; SPACBR is an opinionated *personal* system
(§1), so the installer matching that is one disk, one layout, one
bootloader, no menu of alternatives. If a machine needs something this
script doesn't do, the right tool is `archinstall` (or a manual
install) to get a base Arch system running, then
`docs/prerequisites.md`'s "already have Arch installed" path picks up
from there — this script is a convenience for the common case, not the
only supported way in.

**Partition layout**: one EFI System Partition (1GiB, FAT32) + one
btrfs partition for everything else, mounted **directly at `/` with no
subvolume at all** (mount option: plain `compress=zstd`, nothing
else). This went through two revisions before landing here, both
driven by real evidence rather than either being an arbitrary
preference: a `@` subvolume was first added as a deliberate
improvement over this repo's own test machine's flat, unsplit btrfs
root (still a real, documented limitation — see "Snapshots" above);
then, once an actual `user_configuration.json` generated by a real
`archinstall` run on that same test machine became available to check
against, it turned out `archinstall`'s own `default_layout` disk
config doesn't create any subvolume either (`disk_config.btrfs_options`
is an empty array) and uses exactly `compress=zstd` as its only mount
option — no `noatime`, no `ssd` flag, no compression-level suffix.
Corrected to match that real, authoritative reference exactly rather
than keep an unrequested improvement. The practical effect: the
no-clean-rollback limitation documented in "Snapshots" isn't fixed by
this installer after all — `snapper`'s own `create-config` (already run
by `install.sh`'s `setup_snapper()` in Phase 2) still creates a
`.snapshots` subvolume on top of the flat root if one doesn't exist,
which is sufficient for `snapper`'s own snapshot/diff/undochange
workflow even without a dedicated `@` split. `zram` (via
`zram-generator`, `min(ram/2, 4096)` MB, zstd) instead of a swap
partition — matches both `archinstall`'s own default (confirmed
against the same real `user_configuration.json`: `swap.algorithm:
"zstd"`, `swap.enabled: true`) and, independently, this repo's actual
test machine's real configuration (confirmed live via `lsblk` showing
a `zram0` swap device).

**CPU microcode and VM detection** reuse the exact same logic as
`install_cpu_microcode()`/`detect_is_vm()` (`packages.sh`/`detect.sh`)
— necessarily duplicated rather than sourced, since this script runs
before the repo is cloned and those files don't exist yet on the live
ISO. Keep the two copies in sync by hand if either changes.

**Locale, keyboard, console font, mirrors**: locale is fixed at
`en_US.UTF-8` (not prompted — a settled choice, not something to
second-guess on every run); keyboard layout (`vconsole` `KEYMAP`) is
prompted, default `us`, validated with `loadkeys` before being
accepted (falls back to `us` if the entered layout doesn't exist
rather than writing a config that would leave the target unable to
type a working password at its own login prompt); console font is
fixed at `default8x16` (`kbd`'s own standard default, not worth a
prompt). Mirrors are set via `reflector`, HTTPS only, restricted to
Japan and South Korea specifically — a deliberate, narrow selection
made ahead of time, not "closest to me" (which a live ISO has no
reliable way to determine anyway) or a broader worldwide list.

**Two kernels**: both `linux` and `linux-lts` are installed, each
gets its own preset/UKI/boot entry — a working fallback kernel if an
update to the primary one ever breaks something, at the cost of one
extra `mkinitcpio -P` build and a second UKI's worth of ESP space.

**Bootloader: Limine, UEFI, Unified Kernel Images, installed to the
*removable* EFI path** (`EFI/BOOT/BOOTX64.EFI`) rather than a
machine-specific NVRAM boot entry (`EFI/arch-limine/...` +
`efibootmgr --create`) — UEFI firmware scans the removable path
automatically with no NVRAM entry required, so this survives an NVRAM
reset and doesn't depend on `efibootmgr` succeeding on firmware that's
awkward about it. Install sequence and `limine.conf` format follow
`archinstall`'s own `_add_limine_bootloader()` (`archlinux/archinstall`,
`installer.py`) for exactly the removable+UEFI+UKI case: copy
`BOOTX64.EFI`/`BOOTIA32.EFI` from `/usr/share/limine/` into
`EFI/BOOT/`, write `limine.conf` next to them with one `protocol: efi`
entry per kernel pointing at its UKI, and install a pacman hook
(`99-limine.hook`) that re-deploys those binaries after every `limine`
package upgrade (without it, an upgraded package's binaries never
reach the ESP again until someone copies them by hand).

UKI generation itself is `mkinitcpio`'s job, following `archinstall`'s
`_config_uki()`: `/etc/kernel/cmdline` holds the kernel command line
(`root=PARTUUID=...`, `rw`, `zswap.enabled=0` —
`archinstall`'s own comment: zswap should be disabled when using zram
— plus `quiet splash` so Plymouth's splash isn't fighting kernel boot
text for the screen), and each kernel's `/etc/mkinitcpio.d/<kernel>.preset`
sets `default_uki=".../arch-<kernel>.efi"` with no `default_image=` at
all (UKI only, no redundant plain initramfs). Rather than
regex-editing the vendor-shipped preset file the way `archinstall`
does (matching its exact commented/uncommented line patterns, which
risks silently doing nothing if a future `mkinitcpio` package version
ships a differently-formatted default), this script overwrites each
preset with a minimal, fully-known-good version instead — verified
against this repo's own real test machine's actual shipped
`linux.preset` (already UKI-enabled by whatever installed it
originally, confirming UKI is a legitimate, working modern default,
not a novel approach). `mkinitcpio -P` (run once, builds every preset)
does the actual build; the script verifies each expected `.efi` file
exists afterward and refuses to declare success otherwise.

**Plymouth**: package installed, its hook inserted into
`mkinitcpio.conf`'s `HOOKS` array immediately after `base udev` — the
Arch-wiki-documented required position (must run before the hooks that
produce their own console output). The exact insertion point was
verified against this repo's own real test machine's actual shipped
`HOOKS` line (`base udev autodetect microcode modconf kms keyboard
keymap consolefont block filesystems fsck`) rather than assumed from a
generic default, so the `sed` pattern matching the real prefix is
known to be correct for at least one real, current Arch install. Theme
is set explicitly to `fade-in` (`plymouth-set-default-theme`), not
left at the package's own default — matches the theme selected in the
same real `user_configuration.json` referenced throughout this
section.

**NTP**: `systemd-timesyncd` enabled (not started — same chroot
constraint as `NetworkManager`).

**`sshd`**: `openssh` installed, `sshd` enabled. Not part of the
original design — added once actually running this script for real
against this repo's own test machine surfaced that the pacstrap list
had no SSH server at all, meaning any machine with no physical/KVM
access would be completely unreachable the moment it rebooted, and
that `system/nftables/nftables.conf` (Phase 2) already allows port 22
on the explicit assumption "this machine actually runs sshd" — an
assumption nothing in Phase 1 had ever actually made true for a
freshly installed system.

**Root password is set, not locked.** Some install flows disable
direct root login entirely once a sudo-capable user exists;
this script doesn't, on purpose — CLAUDE.md §88 requires a recovery
path to always exist ("if X11 fails, the user must still be able to
reach a TTY"), and a root password is the simplest guarantee of that
if the created user's account or sudo access ever ends up broken.

**One unified system, boot to desktop — the actual point of this
script existing at all** (CLAUDE.md §82: Omarchy is fair inspiration
for "cohesive defaults... easy installation... unified system
experience", never for its actual implementation, which this doesn't
touch). Phase 1 can't run Phase 2 itself (the `arch-chroot`/`--now`
constraint explained above), so the two are bridged with a first-login
bootstrap instead: Phase 1 writes `~/.bash_profile` for the new user
(`useradd`'s shell is still `bash` at this point — `install.sh`'s own
`set_default_shell()` hasn't run yet, and Arch's stock `/etc/skel`
ships no `.bash_profile` of its own, so this is guaranteed to be the
one bash actually reads) plus an empty `~/.spacbr-first-boot` marker.
On the *next normal password login* — console or SSH, whichever the
user actually reaches first — that profile detects the marker, removes
it, and runs `install/install.sh` right there before handing off to a
real interactive `zsh -l` login shell. `.zshrc`'s own pre-existing tty1
`exec startx` logic then takes it the rest of the way automatically,
with no new code needed for that part — the user never has to
manually type `cd ~/spacbr && ./install/install.sh` at all. Net
result: boot the ISO once, answer Phase 1's prompts once, reboot, log
in with a normal password once, and land in a running desktop — the
same "one command, one system, done" shape Omarchy is known for, built
entirely from this repo's own already-existing, already-tested pieces
(`install.sh`, `.zshrc`'s startx logic) rather than a new mechanism
copied from anywhere.

Deliberately **not** tty auto-login (`agetty --autologin`), which
would trivially achieve the same "no typing" effect. Auto-login is a
real, standing security tradeoff — anyone with physical access gets an
unauthenticated shell, for the entire life of the machine, not just
the first boot. This design still requires a genuine password login
every time, including the first; the automation lives entirely in
*what happens right after* that login succeeds, which costs nothing
security-wise. The marker is removed *before* `install.sh` runs, not
after, so a failure partway (e.g. no network yet) means the next login
drops to a plain shell rather than silently retrying forever on a
persistent failure — recovering is then the same manual, idempotent
`cd ~/spacbr && ./install/install.sh` re-run any other install failure
already uses, not a new failure mode to design around.

**Not tested end-to-end.** Everything else in this repo's install
path — `install.sh`/`update.sh`/`repair.sh`, the firewall, `pacman.conf`,
NetBird, brightness, the maintenance timers — was verified live against
real hardware or through the actual `spacbr repair` pipeline before
being considered done. This script is the one exception: it performs
irreversible disk operations, there's no safety net analogous to the
firewall change's 90-second auto-revert, and running it against
already-installed hardware to test it would destroy that hardware's
data. It was built by directly reading `archinstall`'s own source for
every proven pattern it follows, syntax-checked (`sh -n`) and linted
clean (`shellcheck -s sh`), but "linted clean" is not the same
standard of confidence as "verified for real" that everything else in
this document earns. Test it in a disposable VM before trusting it
against real hardware.

## Deployment model

Before any of the below runs, `require_sudo()` (`detect.sh`) checks
the installer is running as a regular user with working `sudo`, not
root and not sudo-less — real gap, not speculative: a genuinely
minimal manual Arch install (`pacstrap /mnt base linux linux-firmware`,
not `archinstall`'s guided flow) has neither `sudo` installed nor a
wheel-group user configured, since the `base` group doesn't include
it. Every install/update/repair step below runs through `sudo`
somewhere, so this fails fast with clear remediation instructions
instead of dying confusingly on whichever `sudo` call happens to be
first in a much longer script — see `docs/troubleshooting.md`.

The installer uses **managed copies, not symlinks**. `install/install.sh`
copies `.config`/`.local` into the real `$HOME`, and copies `install/`,
`packages/`, `docs/`, and friends into `$XDG_DATA_HOME/spacbr`. Once
installed, the original git clone can be deleted — nothing on the
running system points back at it.

Deployed files are recorded in a manifest
(`$XDG_STATE_HOME/spacbr/manifest`), which is what `spacbr uninstall`
removes — but **not every deployed file is manifested**, and that's
deliberate, not an oversight. `.local/src/*` (the suckless source —
the user's own live, rebuildable, potentially hand-patched copy, not
disposable config) and `.local/share/backgrounds/*` (wallpapers —
indistinguishable from ones the user added themselves once deployed)
are still copied/updated normally but never tracked for later
deletion. This was found the hard way: uninstall used to delete every
manifested path unconditionally, which meant it deleted every
wallpaper and the entire suckless source tree (`dwm.c`, `config.h`,
the Makefiles) while leaving orphaned `.o` files and already-built
binaries behind — and since slock's Makefile was among the deleted
files, `sudo make uninstall` for slock had nothing to work with and
silently failed, leaving its setuid binary behind while the installer
still reported success. See `_should_not_manifest()` in
`install/functions/configs.sh`.

Two related, smaller deploy-time fixes worth knowing about:

- `_should_skip()` (same file) filters macOS AppleDouble sidecar files
  (`._*`) out of every deploy path. Found for real after `scp`-ing a
  source tree from a Mac: they matched extension filters and sorted
  ahead of real files, so `wallpaper`'s picker offered a `._cars.jpg`
  as a candidate before `cars.jpg` itself, and they turned up inside
  `$XDG_DATA_HOME/spacbr/install` too (`deploy_self`'s `cp -r` doesn't
  go through `_should_skip()` at all, so it gets its own explicit
  post-copy cleanup pass instead).
- `packages/aur-overrides/<name>/` holds a vendored, SPACBR-patched
  PKGBUILD for a package whose published AUR version doesn't build (or
  needs a build-option change upstream won't take) — see
  `arc-gtk-theme` above for why one exists today.
  `install_aur_overrides()` in `install/functions/packages.sh` builds
  these directly via `makepkg` in a scratch copy, independent of
  whether `paru` itself is even installed. `install_aur_helper()` in
  the same file bootstraps `paru` from source automatically (not
  `paru-bin` — verified for real that the prebuilt binary was linked
  against an older `libalpm` ABI than a current `pacman` ships, and
  failed to even run) if a plain `packages/aur` entry or an override
  needs it and it isn't present yet; failures here are non-fatal, same
  as the rest of AUR handling (§43: supplementary, never a hard
  dependency of the base desktop).
- Don't track a file this repo doesn't actually control the content
  of. `.config/libfm/libfm.conf` was tracked from the very first
  baseline commit despite its own first line saying "Autogenerated
  file, don't edit, your changes will be overwritten" -- libfm rewrites
  it as its own version/UI state evolves. Found for real by running
  `spacbr repair` against a fresh archive of the committed source: it
  correctly (per its own backup-before-overwrite design) restored the
  stale 1.3.2-era file over what the actually-installed 1.4.1 had
  since generated live, silently dropping keys libfm itself had added.
  Fixed by untracking it entirely rather than trying to keep a static
  copy in sync with a file that's designed to keep changing itself --
  the same reasoning `.local/state/` already gets wholesale in
  `.gitignore`. A hand-authored config that genuinely drifted with a
  real local change (Zed's `settings.json` picked up a
  `cli_default_open_behavior` setting live that was never ported back)
  is the opposite case: that one got restored *into* the repo, per
  CLAUDE.md's own "changes made manually to the installed system
  should eventually be represented in the repository."

See [`../install/`](../install/) and its inline comments for exactly
how install/update/repair/uninstall work today.

## Release channel

`release/` (maintainer-only — never deployed to end users, deliberately
not in `deploy_self`'s copy list) builds and publishes versioned
releases: `release/build.sh` uses `git archive` to produce a tarball
exactly matching what's tagged, a sha256 checksum, and a manifest.json
(package sets, Suckless versions/patches, compatibility).
`release/publish.sh` tags, pushes, and creates a
GitHub Release with those three files attached — the one script here
that touches shared/public state, run manually, never automatically.

`spacbr.com/install` redirects to `release/bootstrap.sh` (served raw
from GitHub) — a small, auditable script that detects
the platform, resolves a release, downloads and checksum-verifies it,
then hands off to that release's own `install/install.sh`. The repo
itself is live at [github.com/spacbrhq/spacbr](https://github.com/spacbrhq/spacbr);
see `release/README.md` for the exact domain-to-GitHub path mapping
and what's still unwired (no release has been tagged yet, spacbr.com's
DNS/hosting itself is outside this repo).

This whole chain was verified for real end to end — genuine
`curl -fsSL ... | sh` against a locally-served fake release, a real
pseudo-terminal, full package install through to the final
`spacbr doctor` — and it caught a bug that would have broken the
documented one-line install for every single real user: by the time
bootstrap.sh's final `exec sh install.sh` runs, stdin is the curl
pipe, already at EOF, so `install.sh`'s "Continue? [y/N]" `read` got
an empty reply and aborted immediately, every time. Fixed by
reconnecting stdin to the real controlling terminal
(`exec 0</dev/tty`) before the handoff, falling back to `--yes` only
if there genuinely isn't one (piped through another script, no tty at
all).

Until a real release exists, `spacbr update`/`repair` without an
explicit source directory can't fetch anything newer than what's
already deployed — see the top of `install/update.sh`.

## Where things live

| Path | What |
|---|---|
| `.config/` | XDG configuration for everything except the Suckless tools (those keep their config in their own source tree, matching upstream convention). Includes `mimeapps.list` + `handlr/` (default-app associations — PDF → Zathura, http(s)/html → Firefox, audio/video/images → mpv/nsxiv via regex) and `zed/` (the GUI editor exception, see above) |
| `.local/bin/` | User scripts — the dmenu-driven contextual interfaces, plus the `spacbr` CLI |
| `.local/src/` | Suckless components built from source, with patches under each tool's `patches/`. Deployed and updated normally but never manifested for uninstall — see "Deployment model" |
| `.local/share/` | Backgrounds, gnupg config — user data SPACBR ships defaults for. Backgrounds specifically are also never manifested for uninstall, same reasoning |
| `packages/` | Curated pacman manifests: `base`, `x11`, `desktop`, `hardware`, `aur`, plus `aur-overrides/<name>/` for a vendored PKGBUILD when a package's published AUR version needs one — see "Deployment model" |
| `install/` | The installer and its shared `functions/` — deployed to end users |
| `release/` | Maintainer-only: build/publish releases, the web bootstrap script — never deployed |
| `docs/` | This directory |

`system/` holds files that live outside `$HOME` (root-owned, under
`/etc`) — `polkit/` (passwordless power actions), `modules-load.d/`
(`i2c-dev` for ddcutil), `nftables/` (the firewall ruleset), and
`pacman/` (`pacman.conf`), each deployed by `install/functions/system.sh`,
not the regular `deploy_tree` path. `services/` and `x11/` stay empty
until a real need shows up — see `system/README.md`.

## Package management

`pacman.conf` is tracked at `system/pacman/pacman.conf` and deployed to
`/etc/pacman.conf` by `deploy_pacman_conf()` — a real gap until this was
added: the live file diverged from stock (`ParallelDownloads`,
`Color`/`CheckSpace` already set) with nothing in the repo describing
or reproducing that, contradicting §11's "source repository is
authoritative" rule the same way an untracked `nftables.conf` would
have. It's a copy of Arch's own stock file, not a rewrite from
scratch — same reasoning as keeping the Suckless `config.h` files close
to `config.def.h`: deviations stay easy to spot, and everything
`pacman.conf(5)` already documents stays intact instead of being
silently dropped. Deviations, kept in the file's own header comment
too: `ILoveCandy`/`VerbosePkgLists` uncommented (cosmetic/readability,
no functional effect), and `[multilib]` enabled (32-bit repo, for
Steam/Wine/etc — not needed by SPACBR's own package set, a personal
addition kept here so a fresh install reproduces it rather than leaving
it as an unrecorded manual step).

`deploy_pacman_conf()` validates with `pacman-conf --config <src>
--repo-list` before installing the file — syntax/repo-list only,
touches nothing — so a typo can't silently break every subsequent
pacman invocation the way an untracked hand-edit could. If the enabled
repo list actually changed (e.g. `[multilib]` going from disabled to
enabled), it re-syncs databases (`pacman -Sy`) immediately afterward:
a newly enabled repo has no local database yet, and the very next
`pacman -S` for anything in it would otherwise fail with a
"repository not found"-style error until the next unrelated sync.

`/etc/pacman.d/mirrorlist` is deliberately **not** tracked anywhere in
this repo — `spacbr mirrors` (a thin wrapper over `reflector`)
regenerates it, the same "don't track a file this repo doesn't control
the content of" reasoning already applied to
`.config/libfm/libfm.conf` in "Deployment model" above.
