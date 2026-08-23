# Development

## Working on a Suckless component

Each of `dwm`, `dmenu`, `st`, `slock`, `blocks` (dwmblocks) under
`.local/src/` is independently buildable:

```sh
cd .local/src/dwm
make clean && make    # compiles against your local X11 headers/libs
```

You need real X11 development headers to build these — this repo has
been developed and edited without them (see the caveats in git history
for `dwm/config.h`'s `XF86XK_Bluetooth`/`XF86XK_PowerOff` bindings),
so **build and smoke-test on an actual Arch/X11 machine before trusting
any Suckless change**, not just `sh -n`/syntax-level checks.

To install a rebuilt component without running the full installer:

```sh
make install          # dwm/dmenu/st/blocks -> ~/.local (no sudo)
sudo make install      # slock only -> /usr/local (setuid-root)
```

Config lives in each tool's `config.h` (the personal, tracked file —
`config.def.h` is the untouched upstream default, kept for reference
and for diffing against when rebasing a patch). `blocks` is the one
exception: its actually-compiled file is `blocks.h`, not
`blocks.def.h` — see the comment at the top of `dwmblocks.c`'s
`#include` line if this trips you up again.

### Patches

Every patch under a tool's `patches/` directory should be something
you can explain: what it changes, why, what it costs to maintain.
Don't add a patch because it's popular. When adding one, apply it against a clean checkout of that
tool's upstream source, verify it still applies cleanly, and note in
the commit message what problem it solves.

## Adding a new dmenu script

Follow the shape of the existing ones (`.local/bin/{audio,bluetooth,
display,wallpaper,power}`):

- POSIX `sh`, not bash, unless you need an actual bash feature
  (§38 — prefer POSIX sh when possible).
- One responsibility. If the menu is doing two unrelated things,
  that's two scripts.
- A single top-level dmenu prompt listing actions in plain English,
  `case` on the choice, one function per action.
- Use `notify-send` for background feedback (nothing else visibly
  confirms a dmenu action happened), but don't spam notifications for
  routine success — reserve them for state changes worth confirming.
- Exit cleanly (`exit 0`) on an empty/cancelled dmenu selection rather
  than falling through to an error.

Then:
1. `chmod 755` it.
2. Wire it into `dwm/config.h` if it deserves a keybinding — check the
   full `keys[]` array for collisions first (a double-bound key has
   happened before in this repo and compiles silently).
3. Add it to the `spacbr` CLI dispatcher if it's a general capability
   rather than something purely bar/keybinding-triggered.
4. Document the binding in `docs/keybindings.md`.

## Working on the installer

`install/functions/*.sh` are sourced libraries, not standalone
scripts — they assume `common.sh` has already run (`SPACBR_HOME`,
logging helpers, `$SPACBR_STATE` etc. are set there). Every entry
point (`install.sh`, `update.sh`, ...) follows the same header:

```sh
#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/install/functions/common.sh"
...
```

`set -eu` means every function that can legitimately fail needs its
failure handled explicitly — a bare command that fails will abort the
whole script. Watch specifically for:

- `var=$(cmd)` — if `cmd` can return non-zero on a valid "nothing
  found" outcome (e.g. `grep` matching zero lines), guard it
  (`cmd || true`) or the assignment itself aborts the script.
- Anything run in a subshell for `cd` isolation
  (`( cd "$dir" && make clean; make )`) — a `;` between two commands in
  that subshell means the first one failing under inherited `set -e`
  skips the second entirely. Use `{ cmd || true; }` for a step whose
  failure shouldn't be fatal.
- A bare call to a function that returns non-zero for a normal,
  expected case (like `run_all_checks` returning failure when checks
  fail) needs to be in an `if`/`&&`/`||` context, not called bare — an
  unguarded bare call aborts before you get to look at the result.

There's no CI. There has, however, been extensive real testing on
actual Arch hardware (not a VM — a real machine, reinstalled clean
specifically for this) covering install, update, repair, uninstall,
every dmenu script, the release/bootstrap flow, and more. That testing
is what actually caught most of the real bugs fixed in this repo's
history — syntax-checking and manual `set -e` tracing alone would have
missed all of them:

- A dmenu crash from `free()`-ing a static string literal (only
  reproduced via a real X session, `gdb` backtrace pinpointed it).
- `install/functions/configs.sh`'s `deploy_tree`/`deploy_dotfiles`
  clobbering their own `src` variable across calls (only visible from
  actual corrupted deployed paths, not from reading the code).
- `spacbr uninstall` deleting every wallpaper and the entire suckless
  source tree because manifested paths are deleted unconditionally
  (only found by actually running uninstall and checking what
  survived).
- `slock` silently unlocking itself on any X server without full DPMS
  support, because `die()`-ing after the lock window was already
  mapped tore down the X connection and released the grab (only
  reproducible on a real headless X server missing that extension).
- `release/bootstrap.sh`'s `curl | sh` flow aborting on its own
  confirmation prompt every single time, because stdin is already
  consumed by the pipe by the time `install.sh` tries to read from it
  (only reproducible by actually piping the real script through `sh`
  with a real pseudo-terminal).

None of these are the kind of thing `sh -n` or a code read reliably
catches. Treat "I traced the logic and it looks right" as necessary,
not sufficient, for anything touching install/update/repair/uninstall,
a Suckless component, or the release/bootstrap chain.

## Testing without wrecking your real system

The established approach: a dedicated Arch machine (real hardware or a
VM) you're prepared to have modified — not your daily driver. A
disposable Xvfb-based virtual display (`Xvfb :1 -screen 0
1280x800x24`, `xrdb -merge`, then `dwmblocks`/`dwm`) on that machine
lets you drive real dmenu scripts and take real screenshots
(`import -window root`) without needing physical access to a monitor.
`xdotool` can simulate keypresses/clicks into that display for
end-to-end verification of anything interactive.

A few sharp edges specific to remote/scripted testing, not to SPACBR
itself:

- Non-interactive SSH shells don't source `.zshrc`/the profile, so
  `~/.local/bin` isn't on `$PATH` and XDG vars aren't set — either
  source `~/.config/shell/profile` first or use full paths.
- A backgrounded daemon (`cmd &`) still holds an SSH session open
  because the child inherits the parent's stdout fd — use
  `nohup cmd >/log 2>&1 </dev/null & disown`.
- `pgrep`/`pkill` without `-x` match substrings against the whole
  command line, not just the process name — `pgrep -la st` matches
  `systemd`, `kworker/R-kstrp`, and anything else with "st" anywhere
  in it. Use `-x` (exact name) or `-af`/`-la` and read the actual
  output before concluding a process isn't running.
- Some GUI apps (Zed among them) ship a thin CLI wrapper as one binary
  name and the real, long-running process under a different one (e.g.
  `/usr/bin/zeditor` hands off to `/usr/lib/zed/zed-editor`, which
  keeps running via its own IPC socket) — `pkill -f <wrapper-name>`
  silently does nothing to the real process. Check `ps aux` for what's
  actually still alive before assuming a kill worked.

Never run `install.sh`/`update.sh`/`repair.sh`/`uninstall.sh` against a
machine you're not prepared to have modified, and always read the
confirmation prompt before answering yes.
