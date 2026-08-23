# system/

Systemd unit and X11 integration files that are genuinely SPACBR's own
— as opposed to the default units already shipped by packages
(NetworkManager, bluetooth, pipewire, wireplumber all provide their
own, enabled by `install/functions/services.sh` or activated from
`xinitrc`).

- `services/` — for a custom systemd unit, if one is ever needed
  (e.g. a user service SPACBR itself owns, not just enables). Empty
  today: nothing needs one yet.
- `x11/` — for Xorg config drop-ins (e.g. `/etc/X11/xorg.conf.d/`
  snippets for input/libinput tuning), separate from the session
  startup logic that already lives in `.config/xinitrc`. Empty today:
  no hardware-specific Xorg tuning has been needed yet.

Don't add a file here speculatively. If a real
need shows up (a specific device needing an Xorg quirk, a service
SPACBR needs to own rather than just enable), it goes here with a
comment explaining what problem it solves — the same bar every other
component in this repo has to clear.
