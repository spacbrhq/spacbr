#!/bin/sh
# Builds a SPACBR release artifact from the current git tree: a
# tarball (via `git archive`, so it's exactly what's committed — no
# stray local files, no need to hand-maintain an exclude list),
# a sha256 checksum sidecar, and a manifest.json describing what's in
# it.
#
# Usage: release/build.sh [git-ref]
#   git-ref defaults to HEAD. For a real release, tag first:
#     git tag v0.1.0 && release/build.sh v0.1.0
#
# Output goes to release/dist/ (gitignored — build output, not source).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REF="${1:-HEAD}"
VERSION="$(cat VERSION)"
TAG="v$VERSION"
OUT="$ROOT/release/dist"
ARCHIVE="spacbr-$TAG.tar.gz"

mkdir -p "$OUT"
rm -f "${OUT:?}/$ARCHIVE" "$OUT/$ARCHIVE.sha256" "$OUT/manifest.json"

echo ":: Building $TAG from $REF"

# --- Archive: exactly what git tracks at $REF, nothing more ---
git archive --format=tar.gz --prefix="spacbr-$TAG/" -o "$OUT/$ARCHIVE" "$REF"
echo "   -> $OUT/$ARCHIVE"

# --- Checksum ---
( cd "$OUT" && sha256sum "$ARCHIVE" > "$ARCHIVE.sha256" )
echo "   -> $OUT/$ARCHIVE.sha256"

# --- Manifest (§58) ---
pkg_json() {
    # turns a packages/<name> file into a JSON string array,
    # stripping comments/blanks the same way install/functions/packages.sh does
    grep -vE '^\s*#|^\s*$' "packages/$1" 2>/dev/null | awk '
        BEGIN { printf "[" }
        { printf "%s\"%s\"", (NR>1 ? ", " : ""), $0 }
        END { printf "]" }
    '
}

aur_overrides_json() {
    # Names of packages/aur-overrides/<name>/ dirs -- built from a
    # vendored local PKGBUILD (install_aur_overrides), not pulled from
    # the AUR directly. Found for real: packages/aur's own list went
    # to [] once arc-gtk-theme moved here, silently dropping a real,
    # required AUR-sourced package from the manifest's package set
    # (§58 requires describing "AUR package set" -- an empty list here
    # while one is actually installed is exactly the omission that
    # requirement exists to prevent).
    dir="packages/aur-overrides"
    [ -d "$dir" ] || { printf '[]'; return; }
    find "$dir" -mindepth 1 -maxdepth 1 -type d | sort | awk -F/ '
        BEGIN { printf "[" }
        { printf "%s\"%s\"", (NR>1 ? ", " : ""), $NF }
        END { printf "]" }
    '
}

suckless_version() {
    grep -m1 '^VERSION' ".local/src/$1/config.mk" 2>/dev/null | sed -E 's/^VERSION[[:space:]]*=[[:space:]]*//'
}

suckless_patches_json() {
    dir=".local/src/$1/patches"
    [ -d "$dir" ] || { printf '[]'; return; }
    find "$dir" -maxdepth 1 -type f -name '*.diff' | sort | awk '
        BEGIN { printf "[" }
        { n=split($0, a, "/"); printf "%s\"%s\"", (NR>1 ? ", " : ""), a[n] }
        END { printf "]" }
    '
}

cat > "$OUT/manifest.json" <<EOF
{
  "spacbr_version": "$VERSION",
  "installer_version": "$VERSION",
  "git_ref": "$REF",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "compatibility": {
    "os": "arch",
    "arch": "x86_64"
  },
  "packages": {
    "base": $(pkg_json base),
    "x11": $(pkg_json x11),
    "desktop": $(pkg_json desktop),
    "hardware": $(pkg_json hardware),
    "aur": $(pkg_json aur),
    "aur_overrides": $(aur_overrides_json)
  },
  "suckless": {
    "dwm": { "version": "$(suckless_version dwm)", "patches": $(suckless_patches_json dwm) },
    "dmenu": { "version": "$(suckless_version dmenu)", "patches": $(suckless_patches_json dmenu) },
    "st": { "version": "$(suckless_version st)", "patches": $(suckless_patches_json st) },
    "slock": { "version": "$(suckless_version slock)", "patches": $(suckless_patches_json slock) },
    "dwmblocks": { "version": null, "patches": [] }
  }
}
EOF
echo "   -> $OUT/manifest.json"

echo ":: Done. Publish with: release/publish.sh $TAG"
