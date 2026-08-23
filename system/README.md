# system/

Systemd unit, polkit rule, and X11 integration files that are
genuinely SPACBR's own — as opposed to the default units already
shipped by packages (NetworkManager, bluetooth, pipewire, wireplumber
all provide their own, enabled by `install/functions/services.sh` or
activated from `xinitrc`). Everything here is deployed *outside* the
user's home directory (`/etc/...`), so it needs root and is installed
by `install/functions/system.sh`, not the regular `deploy_tree` path
that handles `.config`/`.local`.

- `services/` — for a custom systemd unit, if one is ever needed
  (e.g. a user service SPACBR itself owns, not just enables). Empty
  today: nothing needs one yet.
- `x11/` — for Xorg config drop-ins (e.g. `/etc/X11/xorg.conf.d/`
  snippets for input/libinput tuning), separate from the session
  startup logic that already lives in `.config/xinitrc`. Empty today:
  no hardware-specific Xorg tuning has been needed yet.
- `modules-load.d/` — `spacbr-ddcutil.conf` loads `i2c-dev` at boot so
  `ddcutil` can talk to the monitor over DDC/CI, deployed to
  `/etc/modules-load.d/`. Verified for real this is actually needed:
  this machine has zero `backlight`-class devices (a desktop with an
  external monitor, not a laptop panel), so `brightnessctl` had
  nothing to control -- `XF86MonBrightnessUp/Down` now call `ddcutil`
  against the monitor's real VCP brightness feature instead, which
  needs `i2c-dev` loaded before `/dev/i2c-*` exists at all.
- `polkit/` — `10-spacbr-power.rules` grants wheel-group users
  passwordless reboot/suspend/poweroff, deployed to
  `/etc/polkit-1/rules.d/`. Verified for real this is actually needed,
  not speculative: `.local/bin/power`'s Reboot/Suspend/Shutdown
  actions call `systemctl` directly, and polkit's default
  `allow_active=yes` policy for those actions depends on correctly
  recognizing the calling session as "active" — which a bare X11
  session started via plain `startx` (no display-manager/session-
  manager registering it as graphical) doesn't reliably get. Without
  this rule, every one of those three actions fails outright when
  triggered from dwm's power menu. See the rule file's own comment for
  the full story.
- `nftables/` — `nftables.conf` deployed to `/etc/nftables.conf`, the
  file the stock `nftables.service` loads at boot (no SPACBR-owned unit
  needed — the package already ships one). Default-deny inbound
  (loopback, established/related, ping, and SSH allowed; unrestricted
  outbound), the real gap for a machine that runs sshd and had no
  firewall at all. Applied and verified live with a background
  auto-revert safety net (flush the ruleset after 90s unless cancelled)
  so a mistake couldn't have caused a permanent SSH lockout.

Don't add a file here speculatively. If a real
need shows up (a specific device needing an Xorg quirk, a service
SPACBR needs to own rather than just enable), it goes here with a
comment explaining what problem it solves — the same bar every other
component in this repo has to clear.
