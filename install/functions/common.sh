# Shared helpers for install/*.sh. Sourced, not executed directly.
#
# SPACBR_HOME resolves dynamically from this file's own location, so
# the exact same scripts work whether they're run straight from a git
# clone (local/dev install) or from the deployed copy under
# $XDG_DATA_HOME/spacbr (via the `spacbr` CLI shim) — see install/README
# for why that matters.

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

SPACBR_HOME="$(cd "$(dirname "$0")/.." && pwd)"
SPACBR_STATE="$XDG_STATE_HOME/spacbr"
SPACBR_MANIFEST="$SPACBR_STATE/manifest"
SPACBR_SELF="$XDG_DATA_HOME/spacbr"

mkdir -p "$SPACBR_STATE"

BACKUP_DIR="$SPACBR_STATE/backups/$(date +%Y%m%d-%H%M%S)"

_color() { [ -t 1 ] && printf '\033[%sm' "$1" || true; }
_reset() { [ -t 1 ] && printf '\033[0m' || true; }

info()  { printf '%s %s\n' "$(_color 36)::$(_reset)" "$*"; }
ok()    { printf '%s %s\n' "$(_color 32)✓$(_reset)" "$*"; }
warn()  { printf '%s %s\n' "$(_color 33)!$(_reset)" "$*" >&2; }
error() { printf '%s %s\n' "$(_color 31)✗$(_reset)" "$*" >&2; }

die() {
    error "$*"
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

confirm() {
    printf '%s [y/N] ' "$1"
    read -r reply
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}
