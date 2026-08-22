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

for name in dwm dmenu st blocks; do
    dir="$HOME/.local/src/$name"
    [ -d "$dir" ] && ( cd "$dir" && make uninstall ) 2>/dev/null || true
done
[ -d "$HOME/.local/src/slock" ] && ( cd "$HOME/.local/src/slock" && sudo make uninstall ) 2>/dev/null || true
ok "uninstalled Suckless binaries"

rm -rf "$SPACBR_SELF"
rm -f "$SPACBR_MANIFEST"

ok "SPACBR uninstalled. Arch Linux underneath is untouched."
info "Backups under $XDG_STATE_HOME/spacbr/backups were left in place — remove manually if not needed."
