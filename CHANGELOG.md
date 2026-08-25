# Changelog

All notable changes to SPACBR are recorded here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); dates are when the
work landed, not necessarily a tagged release (see `VERSION` for the
current release number — nothing has been tagged past `0.1.0` yet, so
everything below is still "unreleased" in that sense).

## [Unreleased]

### First full end-to-end validation of the two-phase system (2026-08-25)

After the fifth real bug's fix (sudo keep-alive) was pushed and pulled
onto the test machine, re-ran `install/install.sh` and it completed
start to finish: `✓ SPACBR installed.` This is the first time
`live-install.sh` (boot → disk → base system → reboot) and
`install.sh` (first login → full desktop) have both actually run to
completion, back to back, against real hardware — not just
individually verified pieces. Confirmed the result is real, not just
the closing message: all five Suckless binaries resolve to the
correct build in a genuine interactive login shell (`dwm`, `dmenu`,
`st`, `dwmblocks` at `~/.local/bin/`; `slock` at `/usr/local/bin/`,
correctly outside `~/.local/bin` since it needs its setuid bit to
survive a `nosuid`-mounted `/home`).

While chasing why the closing `run_all_checks` reported `dwm`/`st`/
`dwmblocks` as failing despite the build log showing all five as
successfully built and installed, found and fixed a real bug in the
checks themselves, not the build: `run_check "dwm" "command -v dwm"`
(and the same pattern for `dmenu`/`st`/`dwmblocks`) is both a false
negative — `install.sh`'s own shell process never re-sources the
profile it just deployed, so `~/.local/bin` isn't on `$PATH` for that
check even when the binary is genuinely there — and, more seriously,
a false *positive* for `dmenu` specifically: `clipmenu` (a real
SPACBR package) depends on the official `dmenu` package, so a bare
`command -v dmenu` happily finds the vanilla, unpatched
`/usr/bin/dmenu` and reports success even if the SPACBR-patched
`~/.local/src/dmenu` build had actually failed. Fixed by checking the
exact `~/.local/bin/<name>` path directly for `dwm`/`dmenu`/`st`/
`dwmblocks`, leaving `slock`'s check as `command -v` since it
deliberately installs elsewhere.

### Fifth real bug: sudo's cached credential expires mid AUR-build (2026-08-25)

Same live-fire run, further along: `install/install.sh` reached
`install_aur_helper()`, bootstrapped `paru` from source successfully
(a genuinely long `cargo build --release` with LTO), then tried to
build the `packages/aur` entries (`localsend`, `netbird`,
`mpdris2-rs`) — `localsend` built and installed fine, but `netbird`
and `mpdris2-rs` (both also sizeable Rust builds) both failed with
`sudo: 3 incorrect password attempts`. `require_sudo()` only calls
`sudo -v` once, at the very start of the script — by the time paru's
internal `sudo pacman -U` ran for these packages, enough wall-clock
time had passed (paru bootstrap + 299 packages + one full AUR build)
that sudo's cached timestamp had expired, and the resulting
mid-build password re-prompt is buried inside `cargo`/`makepkg`
output, easy to miss even watching the terminal — a real user
stepping away during a long install, not just this session's own SSH
automation, could hit the exact same failure. Fixed by having
`require_sudo()` (`detect.sh`, shared by `install.sh`/`update.sh`/
`repair.sh`) start a background `sudo -n true` refresher every 60
seconds, killed via `trap ... EXIT` when the script exits — the
standard pattern for a script that needs sudo for longer than the
default timestamp timeout.

### Fourth real bug: first-login bootstrap marker went missing (2026-08-25)

After fixing the Limine bug above and getting a real boot, `ssh
eightharsh@<host>` landed on a bare bash prompt with no sign the
first-login bootstrap had run — `~/.spacbr-first-boot` simply didn't
exist on disk, while `~/.bash_profile` (written moments earlier in
the same script run, same mount, same `sync` + `umount -R`) was
present and correct. Re-read the exact `touch`/`chown` sequence in
`live-install.sh` and everything after it that touches
`/home/$USERNAME` — nothing in the script explains it; `set -eu`
would have killed the run before its own `ok "first-login bootstrap
ready"` line if `touch` itself had failed, and nothing later in the
script touches that path again. Root cause unconfirmed. Rather than
keep guessing, added a read-back verification right after
`touch`+`chown` (`[ -f ... ] || die ...`, matching the existing
sudoers-verification pattern in the same file) so a repeat of this —
whatever actually causes it — fails loudly at Phase 1 instead of
silently leaving a user at a bare shell with no indication anything
was supposed to happen. Recreating the marker by hand and logging in
again confirmed the *mechanism* itself is correct: `.bash_profile`
fired, consumed the marker, and started `install/install.sh`
automatically, exactly as designed.

### Third real bug: Limine config written before its own UKIs exist (2026-08-25)

Rebooted into the fresh install for the first time this run and hit
Limine's own boot screen reporting "config file contains no valid
entries" — a clean Phase 1 run had produced a genuinely unbootable
disk. Cause: `live-install.sh` wrote `limine.conf` *before* calling
`mkinitcpio -P` to actually build the UKIs it references — each
entry was gated on `[ -f ".../arch-$kernel.efi" ]`, which was false
for every kernel at that point in the script, so the loop's `continue`
skipped every entry and the file ended up as just a `timeout: 5` line
with nothing else. Confirmed on the actual disk: `limine.conf` was
11 bytes, while both UKIs existed fine on the ESP — the UKI *build*
step itself had always worked, only the config referencing it was
wrong. Fixed for the test machine by booting the live ISO again,
mounting the existing partitions (no reinstall needed — the disk was
otherwise fine), and rewriting `limine.conf` by hand once the UKIs
were confirmed present. Fixed in the script by moving the entire
"install Limine, write limine.conf" block to *after* the UKI build +
existence-check block, and added a second guard — `grep -q
'^/Arch Linux' limine.conf || die ...` — so a config with zero
entries can never again be silently written as if it succeeded.

### Second real bug found on the same live-fire run: git clone hangs on credentials (2026-08-25)

Continuing the same actual live run (after fixing the `stty` crash):
Phase 1 got all the way through partitioning, formatting, `pacstrap`
(218 packages, real download), locale/hostname/user setup, zram,
`sshd`/`NetworkManager`/NTP enablement, the Plymouth hook (confirmed
live it landed in the *systemd*-based `HOOKS` set on a freshly
pacstrapped `mkinitcpio.conf` — the fallback added earlier this
session for exactly this uncertainty, not the primary udev-based
pattern verified against the old install), and both kernels' UKIs
building successfully (verified via the script's own post-build
existence check) — then hung indefinitely at the repo-clone step.
`git clone` on a private or not-yet-public repo URL doesn't fail, it
prompts interactively for a GitHub username/password with no way to
answer on a scripted invocation — confirmed live via `ps aux` showing
the real process tree parked on that exact prompt, requiring a manual
`kill` from a separate connection to unblock. Fixed with
`GIT_TERMINAL_PROMPT=0`, which makes git fail immediately instead —
the existing `else` fallback (warn and continue) was always correct,
it just needed git to actually reach it instead of hanging first.

### Real bug found on the actual first live-fire run (2026-08-25)

Booted the test machine into a genuine Arch live ISO and ran
`live-install.sh` for real for the first time this session — and it
crashed immediately at the very first password prompt.
`read_password()`'s `stty -echo` failed ("Inappropriate ioctl for
device" — no real tty allocated on that particular SSH invocation),
and under this script's own `set -eu`, that one failed `stty` call
killed the entire script on the spot, before any disk operation had
even been offered. Confirmed the disk was genuinely untouched
(`wipefs -n` still showed the pre-existing GPT signature) before
fixing anything. Fixed by making both `stty -echo`/`stty echo` calls
tolerate failure (`|| true`) — a session with no real tty degrades to
visible password entry instead of crashing outright, which is the
right fallback for an edge case, not the normal path (a real console
or `ssh -t` still hides input correctly). This is exactly the class of
bug that only actually running the script live, not just linting it,
was ever going to catch.

### `live-install.sh`: added sshd (2026-08-25)

Found while actually preparing to run this script for real against
this repo's own test machine: the pacstrap package list had no SSH
server at all. A machine with no physical/KVM access would be
completely unreachable the moment it rebooted — no way to even reach
the first-login bootstrap that installs the rest of SPACBR. Also,
`system/nftables/nftables.conf` (Phase 2) already allows port 22 on
the explicit assumption "this machine actually runs sshd", which
nothing in Phase 1 had ever made true. Added `openssh` to the pacstrap
list and `systemctl enable sshd` alongside `NetworkManager`/
`systemd-timesyncd`.

### One unified system: bridging Phase 1 into Phase 2 automatically (2026-08-25)

The two-phase live-install model (partition/base-OS, then reboot and
manually run `install.sh`) is now bridged into one continuous
boot-to-desktop experience — CLAUDE.md §82's actual point: Omarchy as
inspiration for a cohesive, easy, unified install experience, never
for its implementation, which this doesn't touch or copy.

`live-install.sh` now writes a `~/.bash_profile` for the new user
(still on `bash` at this point — `set_default_shell()` hasn't run
yet) plus an empty `~/.spacbr-first-boot` marker. On the *next normal
password login* (console or SSH), that profile detects the marker,
removes it, runs `install/install.sh` right there, and hands off to a
real `zsh -l` login shell — whose own pre-existing tty1 `exec startx`
logic (already in `.zshrc`, untouched) then reaches a running desktop
with no new code needed for that part. Net effect: boot the ISO once,
answer Phase 1's prompts once, reboot, log in once, land in a running
desktop — no second manual command.

Deliberately **not** tty auto-login (`agetty --autologin`), which
would trivially achieve the same "nothing to type" effect — that's a
real, standing security tradeoff (unauthenticated shell for anyone
with physical access, for the machine's entire life, not just the
first boot) traded for saving one command, one time. Every login,
including the first, still requires a genuine password; the marker is
removed *before* `install.sh` runs (not after), so a failure partway
means the next login drops to a plain shell rather than silently
retrying forever on a persistent failure.

Also fixed while updating the surrounding docs: `README.md`'s
"Status" section was badly stale — it still said "none of this has
been run against a real Arch machine yet," dramatically out of date
after this entire session's real-hardware testing. Rewritten to
accurately reflect what's actually been verified live versus what
hasn't (`live-install.sh` remains the one real exception, clearly
called out). `README.md` also had a leftover "one subvolume" claim
from before the subvolume was removed entirely earlier this session —
corrected.

Linted clean (`shellcheck -s sh` for the script itself, `shellcheck
-s bash` for the embedded `.bash_profile` heredoc content extracted
and checked separately, since shellcheck doesn't recurse into heredoc
bodies on its own). Standing caveat unchanged: this addition, like the
rest of `live-install.sh`, has not been run start-to-finish against
real hardware or a VM.

### Bug fixes from a full re-read + fresh shellcheck sweep (2026-08-25)

Re-read `live-install.sh` end to end after its several rounds of edits
this session (rather than trust the incremental diffs to have stayed
consistent) and re-ran `shellcheck -s sh` across the whole `install/`
tree. Found and fixed three real issues in `live-install.sh`, plus one
in `install.sh`:

- **No `wipefs` before partitioning.** `sgdisk --zap-all` only clears
  GPT structures — a previously-used disk (plausible for a live-ISO
  installer; disks handed to this script are rarely factory-fresh)
  can keep stale MBR boot code or old filesystem superblocks that
  confuse `blkid`/`udev`'s re-scan if a new partition happens to
  overlap an old signature's location. Added `wipefs -af "$DISK"`
  before partitioning.
- **Sudo setup had no verification.** The `sed` that uncomments
  `%wheel` in the target's `/etc/sudoers` had no check that it
  actually matched — if a future Arch `sudo` package ever ships a
  differently-formatted commented line, the script would have
  silently left the new user with *no* sudo access while still
  claiming "user created with sudo". Now verifies the line is
  actually uncommented afterward and `die`s with clear manual-recovery
  instructions if not, rather than a confusing `require_sudo()`
  failure in Phase 2, disconnected from its real cause, possibly a
  reboot later.
- **Plymouth hook insertion only tried one `mkinitcpio` hook-set
  format** (the udev-based one, verified against the current test
  machine). Added a second attempt for the newer systemd-based hook
  set (`base systemd ...`) as a fallback — a freshly pacstrapped
  `mkinitcpio.conf` isn't guaranteed to match the already-customized
  test machine's own shipped format. Still warns and continues safely
  if neither matches, same as before.
- **`install.sh`'s "This will:" confirmation had drifted out of sync**
  with what it actually does — missing CPU microcode, GPU driver
  installation, and NetBird/Syncthing entirely (both added earlier
  this session, never added to this message). A user reading it before
  confirming was getting an inaccurate picture of what they were about
  to approve. Updated to match the real sequence.

Re-linted clean (`shellcheck -s sh`, exit 0) after all four fixes.

### Live installer: corrected against a real archinstall config (2026-08-25)

Found `/home/eightharsh/user_configuration.json` on this repo's own
test machine — a real config file `archinstall` itself generated,
presumably from an actual reference run — and checked `live-install.sh`
against it directly rather than relying only on reading `archinstall`'s
source. Most of what was already built matched exactly (kernels,
locale/keyboard/console font, `NetworkManager`, NTP, pacman
`Color`/`ParallelDownloads=5`, zram+zstd swap, `Asia/Kolkata` timezone,
Intel GPU driver selection, the 1GiB FAT32 ESP) — real confirmation the
earlier `archinstall`-source-reading work was accurate. Four real gaps
found and fixed:

- **No btrfs subvolume at all**, not even a single `@`. The real
  config's `disk_config` has an empty `"btrfs": []` array —
  `archinstall`'s own `default_layout` mounts the raw partition
  directly at `/`. A `@` subvolume had been added as a deliberate
  improvement over this test machine's own flat layout (still a real,
  documented "Snapshots" limitation); reverted to match the real
  reference exactly instead of keeping an unrequested improvement.
  `snapper`'s own `.snapshots` subvolume (created by `setup_snapper()`
  in Phase 2 regardless) still works fine on a flat root.
- **Mount options were over-specified.** The real config uses exactly
  `compress=zstd` — no `noatime`, no `ssd` flag, no compression-level
  suffix. Corrected to match.
- **Plymouth theme is `fade-in` specifically**, not the package
  default — now set explicitly via `plymouth-set-default-theme`.
- **`noto-fonts-cjk` was missing** from `packages/base`'s font list —
  present in the real config's `fonts_config`, and relevant given the
  Japan/South Korea mirror selection already assumes CJK content isn't
  hypothetical here. Added, installed and confirmed live through the
  real `spacbr repair` pipeline.

`docs/architecture.md`'s "Live installer" section rewritten to match;
kept an honest account of the two-revision history (added a subvolume
split, then reverted it) rather than presenting the current state as
the only one ever considered.

### Live installer: full rewrite to a specific, detailed configuration (2026-08-25)

`install/live-install.sh` rebuilt against a detailed, explicit
specification, replacing the previous systemd-boot-based version
entirely — every choice below was directly requested, not assumed:

- **Bootloader: Limine, not systemd-boot.** Unified Kernel Images,
  installed to the *removable* EFI path (`EFI/BOOT/BOOTX64.EFI`, no
  NVRAM boot entry) rather than a machine-specific one. Install
  sequence, `limine.conf` format, and the pacman upgrade hook all
  follow `archinstall`'s own `_add_limine_bootloader()`
  (`archlinux/archinstall`, `installer.py`), read directly from source
  for the removable+UEFI+UKI case specifically.
- **Two kernels**: `linux` and `linux-lts`, each with its own
  preset/UKI/boot entry.
- **UKI generation**: `/etc/kernel/cmdline` + a from-scratch (not
  regex-edited) `mkinitcpio.d` preset per kernel, `mkinitcpio -P`
  builds them, the script verifies each `.efi` actually exists
  afterward before declaring success.
- **Plymouth** enabled, hook inserted into `mkinitcpio.conf`'s `HOOKS`
  at the position verified against this repo's own real test
  machine's actual shipped `HOOKS` line.
- **Disk layout simplified**: single `@` btrfs subvolume, no separate
  `@home` (a previous version of this script added `@home`/
  `@snapshots` as an improvement over the test machine's flat layout;
  reverted to a single subvolume on explicit request — `snapper`'s own
  `create-config`, already run by Phase 2, creates `.snapshots` itself
  if needed, so nothing here has to pre-create it).
- **Locale** fixed at `en_US.UTF-8` (no prompt), **keyboard layout**
  prompted (default `us`, validated with `loadkeys` before accepting —
  falls back to `us` rather than risk a target that can't type its own
  login password), **console font** fixed at `default8x16`.
- **Mirrors**: `reflector`, HTTPS only, restricted to Japan + South
  Korea specifically (not "closest"/worldwide).
- **NTP**: `systemd-timesyncd` enabled. **Timezone** prompt default
  changed to `Asia/Kolkata`.
- **Root password set, not locked** (unchanged from the previous
  version — CLAUDE.md §88's recovery-path requirement).

New in Phase 2 (`install.sh`, the already-tested side) to match:
`install_gpu_drivers()` (`packages.sh`) — detects Intel/AMD GPU(s) via
`lspci` (new `pciutils` dependency, `packages/base`) independently, not
either-or (a hybrid laptop can have both), installs the matching
official `mesa`/Vulkan packages. NVIDIA deliberately not handled — not
requested, and its proprietary-vs-nouveau-vs-open decision is a real
choice that shouldn't be silently auto-selected the way Intel/AMD's
unambiguous open stack can be. Matching `spacbr doctor` checks added.
Also added: `ttf-liberation`/`ttf-dejavu` (`packages/base`) — the two
other broadly-expected fallback font families alongside the existing
Hack/Noto.

**Still not verified end-to-end** — same standing caveat as before,
now covering more surface area (Limine/UKI is a materially more
complex mechanism than the systemd-boot/BLS version it replaced).
Every technical claim here is sourced either from `archinstall`'s own
installer.py or cross-checked against this repo's real test machine's
actual shipped config (its `linux.preset` was already UKI-enabled by
whatever installed it, and its real `HOOKS` line is what the Plymouth
insertion point was verified against) — not guessed. Syntax-checked
and linted clean (`shellcheck -s sh`) again after the rewrite. Test in
a disposable VM before trusting this against real hardware.

### Live installer (2026-08-25)

- New `install/live-install.sh` — boots from the Arch live ISO,
  partitions a single disk (1GiB EFI + btrfs with `@`/`@home`/
  `@snapshots` subvolumes — a deliberate improvement over this repo's
  own test machine's flat, unsplit btrfs layout, which was already
  documented as an accepted limitation), pacstraps a minimal base
  system, configures timezone/locale/hostname/root password/a
  sudo-capable user, installs `systemd-boot` (following `archinstall`'s
  own proven `bootctl install` + BLS-entry sequence, read directly from
  `archlinux/archinstall`'s `installer.py`), enables NetworkManager,
  sets up `zram` swap (matching both `archinstall`'s own default and
  this repo's actual test machine's real config), and clones this repo
  into the new user's home. Deliberately does not attempt to run
  `install/install.sh` itself inside the live-ISO chroot — a hard
  technical constraint, not a preference: `install.sh` uses `systemctl
  enable --now`, and there's no running systemd instance inside
  `arch-chroot` for `--now` to start anything against. Ends by telling
  the user to reboot and run the real installer, same two-phase
  "tiny bootstrap → real installer" shape `release/bootstrap.sh`
  already uses for releases.
- Deliberately scoped down from `archinstall` itself: one disk, one
  layout, `systemd-boot`/UEFI only — no LVM, RAID, encryption, GRUB, or
  partition-layout menu. Rebuilding all of `archinstall` would violate
  this repo's own "don't reinvent an existing tool" principle for no
  benefit; SPACBR is an opinionated personal system, and this is the
  opinionated personal installer to match. `archinstall` itself (or a
  manual install) remains the answer for anything this script doesn't
  cover.
- **Not verified end-to-end** — the one deliberate exception to this
  session's "verified live" standard for every other change. Disk
  partitioning is irreversible, there's no safety net analogous to the
  firewall change's auto-revert, and testing it against the actual
  test machine would destroy it. Syntax-checked (`sh -n`) and linted
  clean with `shellcheck -s sh` (caught and fixed two real issues in
  the process — `HOSTNAME` as a variable name, which bash treats
  specially, renamed to `TARGET_HOSTNAME`; an `A && B || C` pattern
  that isn't true if/then/else, rewritten as a real `if`). Explicitly
  documented as needing a disposable-VM test before real hardware, in
  both the script's own header and `docs/architecture.md`.
- Same `shellcheck` pass also caught and fixed the identical
  `A && B || C` pattern in two pre-existing files —
  `install/repair.sh`'s final re-check and `services.sh`'s
  `set_default_shell()` — both rewritten as real `if`/`else`. Low
  real-world risk (the `ok`/`warn` helpers being called essentially
  never fail), but the same bug class, so fixed for consistency while
  already looking at it.

### Corrections found by reading archinstall's actual source (2026-08-25)

Directly read `archlinux/archinstall`'s `installer.py`/`hardware.py`
(not blog posts or docs summaries) to validate the CPU
microcode/`fstrim.timer` work from earlier this session against what
the official Arch installer actually does. Found two real gaps in
what had already shipped:

- **`fstrim.timer` is now also skipped on btrfs**, regardless of
  SSD/NVMe. Previously enabled it unconditionally on non-rotational
  storage — including on this repo's own btrfs+NVMe test machine.
  archinstall's `_prepare_fs_type()` explicitly sets
  `self._disable_fstrim = True` for btrfs, traced to [archinstall
  issue #1837](https://github.com/archlinux/archinstall/issues/1837):
  btrfs has had async discard enabled by default since kernel 6.2,
  making periodic `fstrim.timer` redundant there. New shared
  `detect_root_btrfs()` helper (`detect.sh`). `setup_maintenance_timers()`
  now actively *disables* `fstrim.timer` if it finds it enabled on
  btrfs, so re-running `spacbr repair` self-corrects a system that
  picked up the old behavior — confirmed necessary and run for real
  against the test machine, which had exactly this incorrect state.
- **`install_cpu_microcode()` now skips entirely inside a VM**, via a
  new `detect_is_vm()` helper (`systemd-detect-virt -q`, part of
  systemd already). archinstall's `_get_microcode()` checks
  `SysInfo.is_vm()` — using the identical `systemd-detect-virt`
  mechanism — before ever attempting microcode; a virtual CPU has no
  real hardware microcode to load. `spacbr doctor`'s microcode checks
  are skipped in a VM too, for the same reason.

Also confirmed (no code change needed, just validated the existing
docs against ground truth): archinstall always installs `sudo` as part
of its base package set and grants it via a dedicated `/etc/sudoers.d/`
rule file — a different mechanism than the manual `%wheel` uncomment
instructions in `docs/prerequisites.md`, but an equally valid one;
noted there for accuracy. `install_cpu_microcode()`'s own vendor
detection (parsing `/proc/cpuinfo`'s `vendor_id`) already matched
archinstall's `cpu_vendor()` exactly, no change needed there.

### CPU microcode and SSD/NVMe TRIM (2026-08-25)

- New `install_cpu_microcode()`: detects CPU vendor from
  `/proc/cpuinfo` and installs `intel-ucode`/`amd-ucode` accordingly —
  can't be a static `packages/*` entry since the correct choice is
  runtime-dependent. Deliberately does **not** touch bootloader
  config (no `grub-mkconfig`, no systemd-boot loader-entry edits) —
  out of scope on purpose, since a boot-configuration mistake is far
  harder to recover from remotely than anything else this installer
  touches. Verified live on one machine (systemd-boot + UKI): the
  package alone was sufficient, confirmed via `journalctl -k | grep
  microcode` actually showing a load message at boot — but this is
  *not* verified for GRUB setups, which the Arch wiki says need a
  manual `grub-mkconfig` re-run. New `spacbr doctor` checks: "CPU
  microcode package" (vendor-conditional, like the existing
  bluetooth/backlight checks) and "CPU microcode loaded" (checks the
  kernel log for an actual load message, not just that the package is
  installed — this is what would catch the GRUB gap if it ever
  applies).
- `setup_maintenance_timers()` now also enables `fstrim.timer` (ships
  with `util-linux`, no new package) — conditionally, only if root is
  on non-rotational storage (SSD/NVMe), via a new shared
  `detect_root_nonrotational()` helper (`detect.sh`) used by both the
  setup function and its matching doctor check so they can't drift
  apart. A spinning disk gets no benefit from TRIM, so this isn't
  unconditional the way `paccache`/`reflector` are. Verified live: the
  test machine's root is on NVMe with `fstrim.timer` disabled before
  this — a real, actionable gap, not speculative.

### Docs: prerequisites (2026-08-25)

- New `docs/prerequisites.md` — a single, honest checklist of what has
  to be true before running the installer, split into what's actually
  enforced (`require_platform`/`require_sudo`), what's needed just to
  get the repo onto the machine (`git`/`curl`, network), what's worth
  checking even though nothing blocks on it (disk space, brightness
  hardware, btrfs), and what's explicitly *not* required beforehand
  (an AUR helper, a display manager, anything Wayland). Linked from
  `README.md`'s doc index and its Installing section, replacing the
  inline sudo blurb added earlier this session with a pointer to the
  full file instead of duplicating it.

### Fresh-install bootstrapping and maintenance timers (2026-08-25)

- New `require_sudo()` pre-flight check (`detect.sh`), called by
  `install.sh`/`update.sh`/`repair.sh` right after `require_platform`.
  Real gap found by auditing the actual "genuinely minimal Arch install
  → this project" path end to end, not something noticed by accident:
  `sudo` isn't installed by the `base` group at all, and nothing sets
  up a wheel-group user automatically on a fully manual install the way
  `archinstall`'s guided flow does — every install/update/repair step
  runs through `sudo` somewhere, so without this check the first
  failure a new user following the manual-install path would see is a
  raw "sudo: command not found" or "not in the sudoers file" partway
  into package installation, with no guidance. Now fails fast, upfront,
  with the exact remediation commands. Documented in `README.md`'s
  Installing section and a new `docs/troubleshooting.md` entry.
- New `setup_maintenance_timers()`: enables `paccache.timer`
  (pacman-contrib) and `reflector.timer` (reflector) — both packages
  already in `packages/base`, neither timer was ever actually enabled.
  Real gap: `/var/cache/pacman/pkg` had already grown to 2.2GB from a
  single session's package churn with nothing trimming it. Matching
  `spacbr doctor` checks added.
- DPMS aligned with the documented 15-minute idle-lock policy.
  Verified for real: DPMS was enabled but at the Xorg/driver default of
  30/30/30 seconds, not configured by SPACBR at all — the monitor went
  fully dark within ~30s of any pause while the actual lock
  (`xss-lock`/`slock`, via `xset s 900 900`) didn't trigger until 900s
  later. `xinitrc` now sets `xset +dpms; xset dpms 900 900 900` to
  match.

### Email (2026-08-25)

- Added `geary` (`packages/desktop`) as the new, previously-unowned
  "Email" responsibility (§7's table had Documents/Images/Browser but
  nothing for mail). Official (extra), no AUR needed — confirmed live
  via `pacman -Si geary`. Honestly flagged, not glossed over: it pulls
  a real slice of the GNOME stack (`gnome-online-accounts`, `folks`,
  `libhandy`, `webkit2gtk-4.1`, `gtk3`) as hard dependencies; accepted
  since there's no smaller credible GTK/X11-native mail client with
  comparable IMAP/OAuth account support. No dedicated dwm keybinding
  — launched through the dmenu launcher like most apps, not frequent
  enough to earn a hotkey (§73). Installed live via the real
  `spacbr repair` pipeline (not a manual `pacman -S`), confirming
  yesterday's `deploy_self` fix actually works end to end for a plain
  package addition too.

### Investigated: doctor failures reported after the NetBird migration

- Ran a full audit of every check `spacbr doctor` was reporting as
  failed on the test machine. All of them — `dwm`/`st`/`dwmblocks`,
  `~/.local/bin in PATH`, Claude Code CLI, and the firewall/snapper/
  polkit `sudo -n` checks — confirmed to be the same known SSH-testing
  artifacts documented earlier this session (non-interactive/non-login
  shells not sourcing `.zshrc`'s `PATH`, and a `sudo` ticket not
  propagating into a separately-forked script process), not real
  regressions. Verified directly: binaries present with fresh
  timestamps, the Claude CLI symlink intact, and all three sudo-gated
  checks passing cleanly within one continuous interactive session
  (the same `spacbr repair` run that installed NetBird). No actual bug
  found here — noted so this doesn't read as unaddressed.

### Mesh VPN: Tailscale → NetBird (2026-08-25)

- Replaced Tailscale with NetBird throughout — same "one mesh VPN"
  slot (§44), not a second owner alongside it. `tailscale` (official,
  `packages/base`) removed; `netbird` (AUR-only, confirmed not in
  core/extra/multilib) added to `packages/aur` with its usual
  justification comment.
- `setup_tailscale()` → `setup_netbird()` in `services.sh`: enables
  `netbird@main.service` (NetBird's own Arch-packaged systemd template
  unit) but deliberately does not run `netbird up` — same reasoning as
  before, that's an interactive account-linking login only the user
  should trigger. `install.sh`/`repair.sh` and the `spacbr doctor`
  checks updated to match (`netbird`/`netbird enabled`).
- `system/nftables/nftables.conf`: removed the `iifname "tailscale0"
  accept` + `udp dport 41641 accept` rules entirely, replaced with a
  comment explaining why NetBird doesn't need an equivalent — per its
  own docs, the client needs no inbound firewall port in a standard
  NAT'd deployment (outbound-only STUN/relay), and it manages its own
  separate nftables table for `wt0` rather than needing an entry in
  this repo's `table inet filter`. One thing flagged as genuinely
  unverified, not glossed over: whether this file's `flush ruleset`
  could ever race against NetBird's own dynamically-created table —
  neither confirmed safe nor unsafe.
- The real `iif`-vs-`iifname` boot-ordering bug documented for the old
  Tailscale rule (see the "Firewall" write-up from earlier this
  session) is kept in `docs/architecture.md` as a still-useful lesson
  even though the rule itself is gone, with a note pointing that out
  explicitly so a future reader isn't left looking for a rule that no
  longer exists.

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

- Unified the eightchrome palette across `dwm`, `dmenu`, `st`,
  `dwmblocks`, `dunst`, GTK 2/3/4, Vim/Neovim, and `fastfetch`, with a
  `spacbr doctor` check to keep it that way.
- Replaced off-palette colors in Vim/Neovim with real eightchrome
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

- `tmux` (XDG config, true color, vi mode-keys, eightchrome status
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
- `mpd` + `rmpc` (XDG configs, eightchrome theme) with `mpdris2-rs`
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
- (2026-08-25, tested live over SSH against a second real machine) The
  firewall never actually loaded, on every single boot, despite
  `nftables.service` showing "enabled": its Tailscale rule used
  `iif "tailscale0"`, which resolves the interface at ruleset-*load*
  time and fails the *entire* load if it doesn't exist yet —
  `nftables.service` starts before `tailscaled` brings the interface
  up. `sudo nft list ruleset` showed genuinely empty tables the whole
  time. Fixed with `iifname` (matches by name, load-order-independent);
  reapplied live using the documented validate → safety-net → verify →
  cancel sequence, confirmed with a fresh SSH connection before
  cancelling the safety net.

### Brightness (2026-08-25)

- New `.local/bin/brightness` script (`up`/`down`/`get`), replacing the
  raw `ddcutil setvcp 10 +/- 5` calls that used to sit directly inline
  in `dwm/config.h`'s `XF86MonBrightnessUp`/`Down` bindings. Mirrors
  `.local/bin/volume`'s pattern: same problem (a bare hardware-control
  call changes the level correctly but gives zero feedback, reading as
  "the keys don't work"), same fix (`notify-send` with dunst's own
  `x-dunst-stack-tag` hint so repeated presses replace the previous
  popup instead of stacking). `get` prints the current level without
  changing it, for checking/scripting outside of a keypress. Verified
  live: real DDC/CI level change (55% → 60% → 55%) and a real dunst
  notification with the correct content, both confirmed via
  `dunstctl history`, not just read from the code. `dwm` rebuilt
  against the new `config.h`; not yet live-restarted on the test
  machine (restarting `dwm` ends the whole X session there, since
  `xinitrc` execs it directly with no restart loop) — takes effect on
  its next natural start.
- Extended the same session: added `set <pct>` and a `menu` action
  (new `MODKEY+Shift+B` binding) offering Up/Down/"Set percentage",
  each showing the current level live in the label instead of picking
  blind. Brightness changes now also auto-set contrast (VCP 0x12) via
  a bounded linear map of the resulting brightness — a documented,
  explicitly subjective "looks good" default, not a derived value; see
  `docs/architecture.md`'s new "Brightness and contrast" section for
  the full reasoning and the constants. Verified live: the contrast
  formula's output matched exactly at three brightness levels (70% →
  81, 10% → 63, 15% → 64), and the full interactive menu (including the
  two-step "Set percentage" submenu) was driven end to end with
  `xdotool` against a disposable `Xvfb` display — never touching the
  live desktop session.
- `.local/bin/audio` gained the same live-percentage treatment:
  "Volume up"/"Volume down" now show the current level in the label,
  and a new "Set volume percentage" entry opens a preset-list submenu.
  `.local/bin/volume` gained matching `set <pct>` and `get` actions
  (`get` returns a bare number, kept separate from the existing
  `%`-suffixed notification text so it stays parseable the same way
  `brightness get` is). Verified live: `volume set 40` → 40%, `up` →
  45%, `down` → 40%, and the `audio` menu's "Volume down (currently
  65%)" entry correctly dropped it to 60% via the same `Xvfb`/`xdotool`
  method. Both `spacbr` CLI dispatcher and `docs/keybindings.md`/
  `README.md` updated to match.

### Package management

- `pacman.conf` tracked for the first time (`system/pacman/pacman.conf`,
  deployed to `/etc/pacman.conf` by `deploy_pacman_conf()`) — a real
  gap: the live file had drifted from stock with nothing in the repo
  describing or reproducing it. Kept as a copy of Arch's stock file
  (same reasoning as the Suckless `config.h`s staying close to
  `config.def.h`) with `ILoveCandy`/`VerbosePkgLists` and `[multilib]`
  enabled. Validated with `pacman-conf --repo-list` before deploying
  (touches nothing) and re-syncs repo databases automatically if the
  enabled repo list actually changed, so a newly-enabled repo isn't
  left with no local database. `spacbr doctor` gained matching checks
  ("pacman.conf deployed", "multilib enabled"). `/etc/pacman.d/mirrorlist`
  stays deliberately untracked — `spacbr mirrors`/reflector owns it,
  same reasoning as the untracked `libfm.conf`.

### Docs

- `README.md`, `docs/architecture.md`, `docs/keybindings.md`,
  `docs/troubleshooting.md` kept current with all of the above,
  including the "deployment model" reasoning for what gets tracked vs.
  untracked, and write-ups of the two debugging sessions above, plus
  the firewall boot-ordering bug and the new `system/pacman/` directory.
