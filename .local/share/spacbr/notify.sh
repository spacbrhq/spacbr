# spacbr_notify -- shared notify-send wrapper for SPACBR dmenu scripts.
# Sourced (not executed) from each one, e.g.:
#   . "$HOME/.local/share/spacbr/notify.sh"
#
# Always best-effort: does nothing if notify-send isn't installed,
# consistent with this project's "supplementary feedback, never a hard
# dependency" convention -- screenshot used to be the one exception (a
# hard requirement that made it refuse to even take a screenshot on a
# machine without dunst) until that turned out to be a real, reported
# inconsistency against every sibling script.
#
# This exists because every script re-implementing the same 2-3 line
# wrapper by hand is exactly what let two near-identical scripts drift
# apart in practice: audio and volume covered the same kind of
# feedback (an adjustable level changing) but used different
# notify-send flags for a while before anyone noticed and unified them
# by hand. One shared definition can't drift from itself the same way.
#
# Usage:
#   spacbr_notify "Title" "message"
#       Plain notification, default duration, stacks normally -- for
#       one-shot action confirmations (connected, saved, failed).
#   spacbr_notify -i /path/to/icon "Title" "message"
#       Same, with an icon.
#   spacbr_notify -o TAG "Title" "message"
#       OSD-style: 1.5s, replaces the previous notification tagged TAG
#       instead of stacking -- for rapid-fire adjustable actions
#       (volume/brightness level changing), where each new value
#       should replace the last, not pile up. TAG should be unique per
#       subsystem (e.g. spacbr-volume) so unrelated notifications never
#       cancel each other out. Uses dunst's own x-dunst-stack-tag hint,
#       not the more commonly-copied x-canonical-private-synchronous
#       (a notify-osd/Canonical convention) -- verified for real
#       against this project's actual dunst (1.13.2) that the
#       Canonical hint is silently *accepted* but never actually
#       rendered (dunstctl reported it as "currently displayed" while
#       nothing appeared on screen); dunst's own hint renders correctly
#       with the exact same call otherwise unchanged.
#   spacbr_notify -i /path/to/icon -o TAG "Title" "message"
#       Both together.
spacbr_notify() {
    icon=""
    tag=""
    while :; do
        case "$1" in
            -i) icon="$2"; shift 2 ;;
            -o) tag="$2"; shift 2 ;;
            *) break ;;
        esac
    done

    command -v notify-send >/dev/null 2>&1 || return 0

    # Always returns 0, regardless of notify-send's own exit status
    # (shellcheck SC2015 flagged this correctly, repeatedly, across
    # every caller: `cmd && notify "ok" || notify "failed"` is not
    # if-then-else -- if notify-send itself hiccups on the success
    # branch, "failed" fires right after, misreporting a real success.
    # A notification's own delivery outcome should never be able to
    # flip what a caller believes happened; fixed once here instead of
    # patching every individual call site.
    if [ -n "$icon" ] && [ -n "$tag" ]; then
        notify-send -i "$icon" -t 1500 -h "string:x-dunst-stack-tag:$tag" "$1" "$2"
    elif [ -n "$icon" ]; then
        notify-send -i "$icon" "$1" "$2"
    elif [ -n "$tag" ]; then
        notify-send -t 1500 -h "string:x-dunst-stack-tag:$tag" "$1" "$2"
    else
        notify-send "$1" "$2"
    fi
    return 0
}
