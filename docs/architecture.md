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

## Visual system

Everything shares one palette — internally called **denshichrome**:

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
  (`#2d3043`, `#1e2030`) that were never part of denshichrome at all —
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
`.config/zed/themes/denshichrome.json`, since Zed's theme format is a
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

## Deployment model

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
(`i2c-dev` for ddcutil), and `nftables/` (the firewall ruleset), each
deployed by `install/functions/system.sh`, not the regular
`deploy_tree` path. `services/` and `x11/` stay empty until a real need
shows up — see `system/README.md`.
