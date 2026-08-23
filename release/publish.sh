#!/bin/sh
# Tags the current commit, pushes the tag, and creates a GitHub
# Release with the artifacts from release/build.sh attached.
#
# This is the one script in this repo that touches shared/public
# state (pushes a git tag, creates a public release) — run it
# yourself when you're ready, it is never invoked automatically.
#
# Prerequisites:
#   - `gh auth login` already done
#   - a git remote named "origin" pointing at the GitHub repo
#   - release/build.sh already run for this VERSION (or this script
#     runs it for you if release/dist/ is empty)
#
# Usage: release/publish.sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v gh >/dev/null 2>&1 || { echo "publish: gh (GitHub CLI) is required" >&2; exit 1; }
git remote get-url origin >/dev/null 2>&1 || { echo "publish: no 'origin' remote configured" >&2; exit 1; }

VERSION="$(cat VERSION)"
TAG="v$VERSION"

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "publish: tag $TAG already exists locally" >&2
    exit 1
fi

printf 'This will tag HEAD as %s, push it to origin, and create a PUBLIC\n' "$TAG"
printf 'GitHub release with the built artifacts attached. Continue? [y/N] '
read -r reply
case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "aborted"; exit 1 ;;
esac

[ -f "release/dist/spacbr-$TAG.tar.gz" ] || release/build.sh HEAD

git tag -a "$TAG" -m "SPACBR $TAG"
git push origin "$TAG"

gh release create "$TAG" \
    "release/dist/spacbr-$TAG.tar.gz" \
    "release/dist/spacbr-$TAG.tar.gz.sha256" \
    "release/dist/manifest.json" \
    --title "SPACBR $TAG" \
    --notes "See CHANGELOG or commit history for what's in this release."

echo "Published $TAG. Bootstrap URL: https://github.com/$(git remote get-url origin | sed -E 's#.*[:/]([^/]+/[^/.]+)(\.git)?$#\1#')/releases/download/$TAG/spacbr-$TAG.tar.gz"
