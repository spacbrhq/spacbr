# Changelog

All notable changes to SPACBR are recorded here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); dates are when the
work landed, not necessarily a tagged release (see `VERSION` for the
current release number — nothing has been tagged past `0.1.0` yet, so
everything below is still "unreleased" in that sense).

## [Unreleased]

### Suckless components

- Baseline audit and cleanup of `dwm`/`dmenu`/`st`/`dwmblocks`/`slock`
  sources and patches; `PREFIX` for the first four moved to
  `~/.local` (user-owned binaries), `slock` stays under `/usr/local`
  since it needs a setuid-root binary to read shadow auth.
- `dwm`: full keybinding pass — dropped `xscreensaver` (duplicate lock
  mechanism, forbidden by spec) in favor of `slock` on both the XF86
  key and `Mod+Shift+L`; added a `display` dmenu script in place of
  `arandr`; added keybindings for DNS, mirrors, volume, screen
  recording, color picker; wired `playerctl` media keys; fixed a
  keycode-scoping bug in the brightness bindings.
- `slock`: blur baked directly into the lock screen (not a wrapper
  script); a solid highlight box and color-coded auth-state feedback
  behind the message; fixed it silently unlocking itself when DPMS is
  unavailable, and fixed it showing the live desktop through the lock
  in some cases.
- `st`: fixed a crash in `strhandle()`'s DCS/APC/PM path noise, most
  recently silencing the `erresc: unknown str` error systemd's
  `pam_systemd` triggers via its `OSC 3008` session-privilege marker
  on every `sudo`/`su` (see `docs/troubleshooting.md`).
- `dmenu`: fixed a real crash (`free()` on a static string literal).

### Visual system

- Unified the denshichrome palette across `dwm`, `dmenu`, `st`,
  `dwmblocks`, `dunst`, GTK 2/3/4, Vim/Neovim, and `fastfetch`, with a
  `spacbr doctor` check to keep it that way.
- Replaced off-palette colors in Vim/Neovim with real denshichrome
  values; matched Neovim's colors to Vim's; transparent statusline
  background.
- Dropped `arc-gtk-theme` for GTK's own bundled Adwaita dark variant
  (later needed a vendored PKGBUILD fix to restore Arc-Dark, with
  `paru` auto-bootstrapped).
- `dwmblocks`: consistent text labels instead of mixed icon/no-icon
  blocks; battery block hidden entirely on hardware with no battery;
  colored fastfetch info labels to match the accent blue.
- Redesigned `fastfetch`'s module list: more info (disk, GPU, swap,
  local IP, sound, player/media), grouped into readable sections,
  still minimal.

### dmenu-driven utilities (`.local/bin/`)

- `net`, `audio`, `bluetooth`, `wallpaper`, `power`, `display`,
  `idle-lock`, `passmenu`, `screenshot` (full/window/region + color
  picker), `dns`, `mirrors`, `volume`, `record` (screen recording:
  full/region/window, with/without system audio, dmenu-driven
  settings, in-menu stop option).
- `audio`: speaker/headphone toggle over `pactl` (handles both the
  one-sink-two-ports case and genuinely separate sinks, e.g. USB);
  `volume` wrapper gives notification feedback for up/down/mute/
  mic-mute, shared by dwm's hardware keys and the `audio` menu so both
  give identical feedback; fixed already-open streams not moving to a
  newly-selected output device (`pactl move-sink-input`/
  `move-source-output`).
- Fixed `net`/`passmenu`/`screenshot` never being executable since the
  first commit; fixed the Bluetooth script hanging forever with no
  adapter present; fixed the Net status block never detecting
  Wi-Fi-only connectivity; excluded macOS AppleDouble sidecar files
  from the wallpaper picker and from all deploy paths.

### System integration

- Fixed the PipeWire/PulseAudio-compat layer never starting: it's
  socket-activated by the packages' own systemd --user units, and
  starting `pipewire`/`pipewire-pulse`/`wireplumber` again from
  `xinitrc` actively broke it.
- Default-deny `nftables` firewall, with explicit allow rules added
  later for Tailscale and Syncthing.
- `snapper` + `snap-pac` for automatic btrfs snapshots around package
  operations.
- Wired up the polkit agent and `clipmenu`; fixed the power menu's
  Reboot/Suspend/Shutdown (never actually worked) and a false-negative
  in the polkit rule's doctor check.
- `mimeapps.list` + `handlr.toml` (handlr-regex was installed but
  unconfigured); `nsxiv` added as the image viewer.
- Extended Neovim: LSP, treesitter, a real statusline, editing polish
  (after a full rewrite following a persistent startup problem); fixed
  the trim-whitespace autocommand crashing on non-modifiable buffers.
- Added Zed as a deliberate GUI exception to Neovim owning "Editor"
  (mouse/GUI-driven work only, `vim_mode` intentionally off).
- Switched brightness control to `ddcutil` on hardware with no
  backlight device; scoped the brightness keybindings to the backlight
  device class.
- Fixed `TERM` (`st-256color`, not `st`); imported `DISPLAY`/
  `XAUTHORITY` for systemd --user and D-Bus activation.

### New tools (this session)

- `tmux` (XDG config, true color, vi mode-keys, denshichrome status
  bar), `alacritty` (available alternative terminal, `st` stays
  primary), `nnn` (with `n()` cd-on-quit shell function), `fzf` (zsh
  integration).
- `tailscale` and `syncthing`, both enabled as services with matching
  firewall rules.
- `localsend`, built from AUR source.
- Claude Code CLI, installed via a `~/.local/share/npm` prefix (no
  sudo needed for `npm install -g`).
- Git config (`.config/git/config`, XDG path) with `delta` as pager
  and `zdiff3` conflict style; `git-delta` and `restic` (backup,
  package only — destination deliberately not configured yet).
- `mpd` + `rmpc` (XDG configs, denshichrome theme) with `mpdris2-rs`
  bridging mpd to MPRIS so `playerctl` and `fastfetch`'s player/media
  modules actually see it — mpd doesn't expose MPRIS on its own.

### Installer / CLI

- `spacbr` CLI and `spacbr doctor`, covering suckless components,
  services, XDG layout, PATH, fonts, permissions, and (as of this
  session) firewall/snapper/tmux/fzf/nnn/alacritty/tailscale/
  syncthing/localsend/mpdris2-rs/git-delta/restic/Claude Code CLI/mpd.
- Install/update/repair/uninstall flow, with a managed-copy deploy
  model (backs up any live file that differs from the repo before
  overwriting) and idempotent package/service handling.
- Release channel and web bootstrap (curl-pipe-shell architecture:
  tiny bootstrap → versioned release → real installer).
- Fixed a critical bug in the actual public install flow and a
  manifest gap; fixed `spacbr uninstall` destroying wallpapers and the
  suckless source tree; fixed `spacbr repair` reporting "Nothing to
  repair" while ignoring real damage; fixed a download-corruption bug
  in `firefox.sh`; fixed `spacbr info` printing a stray "unknown" line
  on inactive services.

### Notable bugs found and fixed by actually testing

- Established a "fresh `git archive HEAD` → `spacbr repair`" workflow
  as the real reproducibility test (replacing ad-hoc installs
  back-filled into manifests afterward). Running it for real caught:
  `libfm.conf` wrongly tracked despite being autogenerated by libfm
  itself (untracked, documented in `docs/architecture.md`); a drifted
  Zed setting and an aliasrc comment that existed live but never made
  it back into the repo (restored, per "changes made manually to the
  installed system should eventually be represented in the
  repository").
- `x-canonical-private-synchronous` (a notify-osd/Canonical hint)
  silently accepted by dunst but never actually rendered — switched to
  dunst's own `x-dunst-stack-tag`.
- A newly-plugged keyboard-class USB device's key presses not
  reaching `dwm`'s grab because `dwm` had been running since before
  the device appeared (`docs/troubleshooting.md` has the live,
  no-logout fix).

### Docs

- `README.md`, `docs/architecture.md`, `docs/keybindings.md`,
  `docs/troubleshooting.md` kept current with all of the above,
  including the "deployment model" reasoning for what gets tracked vs.
  untracked, and write-ups of the two debugging sessions above.
