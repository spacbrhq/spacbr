#!/bin/sh
# Removes only what SPACBR's manifest says it deployed, plus the
# Suckless binaries via each component's own `make uninstall`.
# Does NOT remove packages (pacman-installed, may be used by other
# software) or user data (backgrounds, gnupg keyrings, documents).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/install/functions/common.sh"

[ -f "$SPACBR_MANIFEST" ] || die "no manifest at $SPACBR_MANIFEST — nothing SPACBR-tracked to remove"

count=$(wc -l < "$SPACBR_MANIFEST")
printf 'This will remove %s SPACBR-deployed file(s) listed in %s,\n' "$count" "$SPACBR_MANIFEST"
printf 'uninstall dwm/dmenu/st/dwmblocks/slock, and remove %s.\n' "$SPACBR_SELF"
printf 'Packages and personal data (backgrounds, gnupg, documents) are left alone.\n\n'
confirm "Continue?" || die "aborted"

while IFS= read -r path; do
    [ -f "$path" ] && rm -f "$path"
done < "$SPACBR_MANIFEST"
ok "removed manifested files"

# Found for real: `2>/dev/null || true` here silently swallowed a
# real failure -- slock's Makefile had been deleted by the manifest
# loop above (fixed separately: .local/src is no longer manifested),
# so `make uninstall` had nothing to work with, failed, and slock's
# setuid binary was left behind while this script still reported
# success. warn instead of swallowing, so a real failure is visible.
for name in dwm dmenu st blocks; do
    dir="$HOME/.local/src/$name"
    if [ -d "$dir" ]; then
        ( cd "$dir" && make uninstall ) || warn "failed to uninstall $name — check $dir/Makefile"
    fi
done
if [ -d "$HOME/.local/src/slock" ]; then
    ( cd "$HOME/.local/src/slock" && sudo make uninstall ) || warn "failed to uninstall slock — check $HOME/.local/src/slock/Makefile"
fi
ok "uninstalled Suckless binaries"

rm -rf "$SPACBR_SELF"
rm -f "$SPACBR_MANIFEST"

ok "SPACBR uninstalled. Arch Linux underneath is untouched."
info "Backups under $XDG_STATE_HOME/spacbr/backups were left in place — remove manually if not needed."
