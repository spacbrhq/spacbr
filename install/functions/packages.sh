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
        if command -v paru >/dev/null 2>&1; then
            info "Installing packages/aur"
            _pkg_list "$SPACBR_HOME/packages/aur" | xargs -r paru -S --needed --noconfirm
            ok "packages/aur"
        else
            # §43: the core installer must work without an AUR helper.
            # AUR entries are supplementary (themes, etc.), never
            # anything the base desktop depends on to function --
            # skip them with a clear warning instead of dying and
            # losing the Suckless builds/services/validation that
            # haven't run yet. Deliberately not auto-bootstrapping
            # paru here: that means building and trusting an AUR
            # PKGBUILD unattended inside an automated installer, which
            # is a real supply-chain step a human should decide on,
            # not something to do blindly on their behalf.
            warn "paru not found — skipping packages/aur ($(_pkg_list "$SPACBR_HOME/packages/aur" | wc -l) package(s), see the file for what's skipped)"
            warn "install an AUR helper yourself and re-run 'spacbr install' (or install those packages manually) if you want them"
        fi
    fi
}
