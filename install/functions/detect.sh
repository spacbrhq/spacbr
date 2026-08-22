# System detection. Sourced, not executed directly. Requires common.sh.

detect_arch_linux() {
    [ -f /etc/arch-release ] && return 0
    [ -f /etc/os-release ] && grep -q '^ID=arch' /etc/os-release && return 0
    return 1
}

detect_x86_64() {
    [ "$(uname -m)" = "x86_64" ]
}

require_platform() {
    detect_arch_linux || die "SPACBR targets Arch Linux only (see CLAUDE.md §2). /etc/arch-release or /etc/os-release ID=arch not found."
    detect_x86_64 || die "SPACBR targets x86_64 only. Detected: $(uname -m)"
    ok "Arch Linux, x86_64"
}
