# Package installation from packages/*. Sourced, not executed directly.
# Requires common.sh.

# Strip comments/blanks so the manifest files stay human-readable
# (pacman's stdin package list has no comment syntax of its own).
_pkg_list() {
    grep -vE '^\s*#|^\s*$' "$1" || true
}

install_package_set() {
    file="$SPACBR_HOME/packages/$1"
    [ -f "$file" ] || die "no such package manifest: $file"
    list=$(_pkg_list "$file")
    [ -z "$list" ] && { ok "packages/$1 (nothing to install)"; return 0; }
    info "Installing packages/$1"
    # shellcheck disable=SC2086
    printf '%s\n' "$list" | sudo pacman -S --needed --noconfirm -
    ok "packages/$1"
}

install_all_packages() {
    require_cmd pacman
    for pkgset in base x11 desktop hardware; do
        install_package_set "$pkgset"
    done
    if [ -s "$SPACBR_HOME/packages/aur" ] && _pkg_list "$SPACBR_HOME/packages/aur" | grep -q .; then
        require_cmd paru
        info "Installing packages/aur"
        _pkg_list "$SPACBR_HOME/packages/aur" | xargs -r paru -S --needed --noconfirm
        ok "packages/aur"
    fi
}
