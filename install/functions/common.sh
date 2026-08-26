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

# shellcheck disable=SC2034 # used by sibling install/functions/*.sh files that source this one, not within this file itself
SPACBR_HOME="$(cd "$(dirname "$0")/.." && pwd)"
SPACBR_STATE="$XDG_STATE_HOME/spacbr"
# shellcheck disable=SC2034
SPACBR_MANIFEST="$SPACBR_STATE/manifest"
# shellcheck disable=SC2034
SPACBR_SELF="$XDG_DATA_HOME/spacbr"

mkdir -p "$SPACBR_STATE"

# shellcheck disable=SC2034
BACKUP_DIR="$SPACBR_STATE/backups/$(date +%Y%m%d-%H%M%S)"

# True-color eightchrome (by eightharsh), not generic 16-color ANSI --
# same "38;2;R;G;B" truecolor sequence .config/fastfetch/config.jsonc
# already uses for this exact palette. accent #4084d6 (info), green
# color2 #9bcf4f (ok), yellow color3 #f6d13a (warn), red color1 #ed4737
# == the "Error / urgent" role in docs/architecture.md's palette table
# (error/die). Keep these four triples in sync with .config/xresources
# by hand.
_color() { [ -t 1 ] && printf '\033[38;2;%sm' "$1" || true; }
_reset() { [ -t 1 ] && printf '\033[0m' || true; }

info()  { printf '%s %s\n' "$(_color '64;132;214')::$(_reset)" "$*"; }
ok()    { printf '%s %s\n' "$(_color '155;207;79')✓$(_reset)" "$*"; }
warn()  { printf '%s %s\n' "$(_color '246;209;58')!$(_reset)" "$*" >&2; }
error() { printf '%s %s\n' "$(_color '237;71;55')✗$(_reset)" "$*" >&2; }

# banner -- small text wordmark, no ASCII art (CLAUDE.md SS81: "not
# from giant logos, excessive branding"). Same accent color as the
# fastfetch "SPACBR" module and dwm/dmenu/st's own accent.
banner() { [ -t 1 ] && printf '\n%sSPACBR%s\n\n' "$(_color '64;132;214')" "$(_reset)"; }

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
