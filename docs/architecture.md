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

## Locking and idle

`slock` is the only lock mechanism (§7/§18) — `xscreensaver` was
removed early on specifically because a second lock/screensaver
mechanism is exactly what the spec forbids. Everything since builds
*on top of* slock rather than beside it:

```
idle 4 min  → xss-lock's notifier: .local/bin/screensaver (dims via
               brightnessctl, killed by SIGHUP if you move again)
idle 5 min  → xss-lock's locker: .local/bin/lock (blur + slock)
```

`xss-lock` stays the single, event-driven idle daemon (`xset s 240 60`
— 240s to the notifier, one more 60s cycle to the locker) — it just
runs two different commands at two different points in its own cycle,
not two competing mechanisms. If you ever want a real second idle
tool, replace `xss-lock` outright; don't add one alongside it.

`.local/bin/lock` wraps `slock` rather than patching it: the real
Imlib2 blur patch (`tools.suckless.org/slock/patches/blur-pixelated-screen/`)
targets slock 1.4 and fails 5+ hunks against this repo's 1.5 (already
carrying the xresources patch) — hand-merging unverifiable C against
X11/Imlib2 was judged too risky, the same call made earlier about the
dmenu-xresources patch. The wrapper screenshots the desktop, blurs it
with `imagemagick` (already a dependency), sets it as the root
background, calls `slock`, then restores the real wallpaper on
unlock — same visual result, zero new C code or dependencies, at the
cost of a brief (sub-second) window where the real desktop is still
visible before the blur/lock appears, since the capture happens before
`slock` grabs the screen rather than after. Every direct call to
`slock` in dwm's keybindings and `.local/bin/power` goes through this
wrapper now, not the raw binary.

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

`.config/xresources` is the canonical definition. Three components read
it **live, at runtime**, so they can never drift out of sync with it:

- `dwm` — via the applied xrdb patch (`loadxrdb()`, bound to `MODKEY+F5`
  and SIGHUP)
- `st` — via its applied xresources patch
- `slock` — via its `ResourcePref` table

Everything else — `dmenu`, GTK (`gtk-2.0`/`3.0`/`4.0`), `mpv`, `dunst`,
Vim/Neovim, Zathura — has these same hex values **hardcoded** and must
be kept in sync by hand. This is a real gap, not a theoretical one:
this repo has twice shipped actual drift from it — dwm's own compiled-in
fallback colors didn't match the palette at all (meaning `MODKEY+p`,
the single most-used keybinding, rendered `dmenu` in the wrong colors
until this was caught), and GTK apps rendered in `Cantarell` while
every other component used `Hack`. `spacbr doctor`'s "Visual system
consistency" checks now catch both regressions automatically.

There's an unused, already-present patch
(`.local/src/dmenu/patches/dmenu-xresources-4.9.diff`) that would move
`dmenu` into the live-synced group like `dwm`/`st`/`slock`, eliminating
this class of drift for it permanently. It doesn't apply cleanly
against the current `dmenu.c` (already modified by the fuzzy-match
patch — 3 of 6 hunks fail) and hand-resolving a C patch with no way to
compile-test the result on this machine was judged too risky to do
blind. Worth revisiting once there's a real build environment to
verify against.

When you add a new themed component: hardcode the palette values
above, note in a comment that they must track `.config/xresources`,
and add a `spacbr doctor` check for it if drift would be easy to miss.

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
running system points back at it. Every file SPACBR deploys is
recorded in a manifest (`$XDG_STATE_HOME/spacbr/manifest`), which is
what makes `spacbr uninstall` safe: it only ever removes paths that
manifest lists, never packages, never anything it didn't put there
itself.

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

Until a real release exists, `spacbr update`/`repair` without an
explicit source directory can't fetch anything newer than what's
already deployed — see the top of `install/update.sh`.

## Where things live

| Path | What |
|---|---|
| `.config/` | XDG configuration for everything except the Suckless tools (those keep their config in their own source tree, matching upstream convention) |
| `.local/bin/` | User scripts — the dmenu-driven contextual interfaces, plus the `spacbr` CLI |
| `.local/src/` | Suckless components built from source, with patches under each tool's `patches/` |
| `.local/share/` | Backgrounds, gnupg config — user data SPACBR ships defaults for |
| `packages/` | Curated pacman manifests: `base`, `x11`, `desktop`, `hardware`, `aur` |
| `install/` | The installer and its shared `functions/` — deployed to end users |
| `release/` | Maintainer-only: build/publish releases, the web bootstrap script — never deployed |
| `docs/` | This directory |

`system/` (systemd/X11 integration beyond what's already in
`.config/xinitrc` and the packages' own default units) is currently
empty — nothing has needed custom unit files or Xorg drop-ins yet. It
stays in the layout for when something does.
