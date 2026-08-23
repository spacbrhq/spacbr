# Architecture

The full, authoritative specification is [`CLAUDE.md`](../CLAUDE.md).
This is a shorter map of the same territory — read it first, then go
to CLAUDE.md for the reasoning behind any specific rule.

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
see CLAUDE.md §7 for the full table. The practical effect: if you're
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
(CLAUDE.md §58 — package sets, Suckless versions/patches,
compatibility). `release/publish.sh` tags, pushes, and creates a
GitHub Release with those three files attached — the one script here
that touches shared/public state, run manually, never automatically.

`spacbr.com/install` redirects to `release/bootstrap.sh` (served raw
from GitHub) — a small, auditable script (CLAUDE.md §54) that detects
the platform, resolves a release, downloads and checksum-verifies it,
then hands off to that release's own `install/install.sh`. See
`release/README.md` for the exact domain-to-GitHub path mapping and
what's still unwired (no release has been tagged yet, no GitHub
remote is configured, spacbr.com's DNS/hosting itself is outside this
repo).

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
