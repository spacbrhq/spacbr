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

# Builds and installs paru (§43: SPACBR's one designated AUR helper)
# from its AUR source package if it isn't already present. Builds from
# source rather than paru-bin: verified for real that the prebuilt
# paru-bin binary was linked against an older libalpm ABI than a
# current pacman ships, and failed outright ("error while loading
# shared libraries: libalpm.so.15"). Building from source compiles
# against whatever libalpm is actually installed, avoiding that skew.
# makepkg verifies the source tarball's checksum and GPG signature
# before building, same trust model as any other AUR package.
install_aur_helper() {
    command -v paru >/dev/null 2>&1 && { ok "paru already installed"; return 0; }
    require_cmd git
    require_cmd makepkg
    info "Building paru (AUR helper)"
    tmpdir=$(mktemp -d)
    if ( cd "$tmpdir" && git clone --depth 1 https://aur.archlinux.org/paru.git \
         && cd paru && makepkg -si --noconfirm ); then
        ok "paru installed"
    else
        rm -rf "$tmpdir"
        error "failed to build paru"
        return 1
    fi
    rm -rf "$tmpdir"
}

# Builds anything under packages/aur-overrides/<name>/ from its
# vendored PKGBUILD instead of pulling <name> from the AUR directly.
# Used when an AUR package needs a build-option change upstream won't
# (or hasn't) taken -- see packages/aur-overrides/arc-gtk-theme for a
# real example: the published AUR PKGBUILD fails to build outright.
# Builds happen in a scratch copy, never in place inside the source
# tree, so makepkg's build artifacts never land in a git-managed
# directory.
install_aur_overrides() {
    [ -d "$SPACBR_HOME/packages/aur-overrides" ] || return 0
    for dir in "$SPACBR_HOME"/packages/aur-overrides/*/; do
        [ -d "$dir" ] || continue
        name="$(basename "$dir")"
        if pacman -Qi "$name" >/dev/null 2>&1; then
            ok "$name already installed (local override)"
            continue
        fi
        info "Building $name from local override"
        tmpdir=$(mktemp -d)
        cp -r "$dir." "$tmpdir/"
        if ( cd "$tmpdir" && makepkg -si --noconfirm ); then
            ok "$name installed (local override)"
        else
            error "failed to build $name (local override)"
        fi
        rm -rf "$tmpdir"
    done
}

install_all_packages() {
    require_cmd pacman
    for pkgset in base x11 desktop hardware; do
        install_package_set "$pkgset"
    done

    # Non-fatal: AUR content is supplementary, never anything the base
    # desktop depends on to function (§43). install_aur_overrides
    # doesn't actually need paru -- it builds straight from a vendored
    # PKGBUILD via makepkg -- so it still runs even if the paru build
    # itself fails.
    install_aur_helper || warn "continuing without paru — plain packages/aur entries (if any) will be skipped"

    if [ -d "$SPACBR_HOME/packages/aur-overrides" ] && [ -n "$(ls -A "$SPACBR_HOME/packages/aur-overrides" 2>/dev/null)" ]; then
        install_aur_overrides
    fi

    if [ -s "$SPACBR_HOME/packages/aur" ] && _pkg_list "$SPACBR_HOME/packages/aur" | grep -q .; then
        if command -v paru >/dev/null 2>&1; then
            info "Installing packages/aur"
            _pkg_list "$SPACBR_HOME/packages/aur" | xargs -r paru -S --needed --noconfirm
            ok "packages/aur"
        else
            warn "paru not available — skipping packages/aur ($(_pkg_list "$SPACBR_HOME/packages/aur" | wc -l) package(s), see the file for what's skipped)"
        fi
    fi
}
