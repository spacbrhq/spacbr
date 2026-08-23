#!/bin/sh
# SPACBR bootstrap.
#
# This is the ONLY code that runs directly from:
#   curl -fsSL https://spacbr.com/install | sh
#
# It is deliberately tiny and auditable: it does
# not configure the system itself. It detects the platform, resolves
# a specific versioned release, downloads it, verifies its checksum,
# and hands off to that release's own install/install.sh — which is
# the real installer, reviewable in full before it runs.
#
# Pin a version instead of latest:
#   SPACBR_VERSION=v0.1.0 curl -fsSL https://spacbr.com/install | sh
set -eu

REPO="spacbrhq/spacbr"   # GitHub owner/repo — update if this changes
API="https://api.github.com/repos/$REPO"
VERSION="${SPACBR_VERSION:-latest}"

say()  { printf 'spacbr: %s\n' "$1"; }
die()  { printf 'spacbr: %s\n' "$1" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar  >/dev/null 2>&1 || die "tar is required"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"

[ -f /etc/arch-release ] || die "this installer targets Arch Linux only"
[ "$(uname -m)" = "x86_64" ] || die "this installer targets x86_64 only"

if [ "$VERSION" = "latest" ]; then
    say "resolving latest release..."
    tag=$(curl -fsSL "$API/releases/latest" \
        | grep -m1 '"tag_name"' \
        | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/')
else
    tag="$VERSION"
fi
[ -n "${tag:-}" ] || die "could not determine a release to install"
say "installing $tag"

base="https://github.com/$REPO/releases/download/$tag"
archive="spacbr-$tag.tar.gz"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT INT TERM

say "downloading $archive..."
curl -fsSL -o "$tmpdir/$archive" "$base/$archive" || die "download failed — does release $tag exist?"
curl -fsSL -o "$tmpdir/$archive.sha256" "$base/$archive.sha256" || die "checksum file download failed"

say "verifying checksum..."
( cd "$tmpdir" && sha256sum -c "$archive.sha256" ) >/dev/null || die "checksum verification FAILED — aborting, refusing to run unverified content"

say "extracting..."
tar -xzf "$tmpdir/$archive" -C "$tmpdir"
srcdir=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d -name 'spacbr-*')
[ -d "$srcdir" ] || die "extracted archive has an unexpected layout"

say "handing off to the versioned installer..."
exec sh "$srcdir/install/install.sh"
