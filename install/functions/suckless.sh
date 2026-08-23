# Build and install the Suckless components from the deployed source
# under $HOME/.local/src. Sourced, not executed directly. Requires
# common.sh.
#
# dwm/dmenu/st/dwmblocks install to $HOME/.local (PREFIX set in their
# own config.mk/Makefile) — no root needed. slock installs to
# /usr/local and must be setuid-root to read shadow auth (it needs
# elevated privilege to verify a password against the shadow file),
# which is why it alone needs sudo and can't move to ~/.local/bin like
# the others — a user-writable, often nosuid-mounted home directory
# can't safely host a setuid-root binary.

build_suckless_component() {
    dir="$HOME/.local/src/$1"
    [ -d "$dir" ] || { warn "missing source: $dir (skipping)"; return 1; }
    info "Building $1"
    ( cd "$dir" && { make clean >/dev/null 2>&1 || true; }; make ) || { error "build failed: $1"; return 1; }
    ok "built $1"
}

install_suckless_component() {
    name="$1"
    dir="$HOME/.local/src/$name"
    [ -d "$dir" ] || return 1
    if [ "$name" = "slock" ]; then
        ( cd "$dir" && sudo make install ) || { error "install failed: $name"; return 1; }
    else
        ( cd "$dir" && make install ) || { error "install failed: $name"; return 1; }
    fi
    ok "installed $name"
}

build_and_install_suckless() {
    for name in dwm dmenu st slock blocks; do
        build_suckless_component "$name" && install_suckless_component "$name"
    done
}
