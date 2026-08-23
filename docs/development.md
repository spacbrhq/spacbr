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
Don't add a patch because it's popular — CLAUDE.md §13 covers this in
detail. When adding one, apply it against a clean checkout of that
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

There's no CI and no real Arch machine in this environment — every
install script here has been syntax-checked (`sh -n`) and manually
traced for these `set -e` interactions, but not executed end-to-end.
Treat that as the standing caveat until someone runs it for real.

## Testing without wrecking your real system

There isn't a sandboxed test harness for the installer yet. Until
there is, the safest way to iterate is a disposable Arch VM or
container — never run `install.sh`/`update.sh`/`repair.sh` against a
machine you're not prepared to have modified, and always read the
confirmation prompt `install.sh` prints before answering yes.
