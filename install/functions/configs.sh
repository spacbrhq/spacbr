# Managed-copy deployment: SPACBR_HOME -> $HOME, with backup + a
# manifest of everything SPACBR owns. Never symlinks — the source tree
# (a git clone, or the deployed copy under $XDG_DATA_HOME/spacbr) can
# be deleted afterwards without breaking the installed system.
# Sourced, not executed directly. Requires common.sh.

_should_skip() {
    case "$1" in
        *.o|*.orig|*.gch|*/.DS_Store) return 0 ;;
        */.local/src/dwm/dwm|*/.local/src/dmenu/dmenu|*/.local/src/st/st) return 0 ;;
        */.local/src/slock/slock|*/.local/src/blocks/dwmblocks) return 0 ;;
        *) return 1 ;;
    esac
}

_manifest_add() {
    mkdir -p "$(dirname "$SPACBR_MANIFEST")"
    grep -qxF "$1" "$SPACBR_MANIFEST" 2>/dev/null || printf '%s\n' "$1" >> "$SPACBR_MANIFEST"
}

# deploy_tree SRC_DIR DEST_DIR — copies every file under SRC_DIR into
# the matching path under DEST_DIR. Differing existing files are
# backed up first; identical files are left untouched.
deploy_tree() {
    src="$1"
    dest="$2"
    [ -d "$src" ] || return 0
    find "$src" -type f | while IFS= read -r file; do
        _should_skip "$file" && continue
        rel="${file#"$src"/}"
        target="$dest/$rel"
        if [ -f "$target" ] && ! cmp -s "$file" "$target"; then
            mkdir -p "$(dirname "$BACKUP_DIR/$rel")"
            cp -p "$target" "$BACKUP_DIR/$rel"
            warn "backed up modified $target -> $BACKUP_DIR/$rel"
        fi
        mkdir -p "$(dirname "$target")"
        cp -p "$file" "$target"
        _manifest_add "$target"
    done
}

# deploy_dotfiles [SOURCE_DIR] — SOURCE_DIR defaults to SPACBR_HOME.
# Pass it explicitly when updating from a freshly pulled clone that
# isn't SPACBR_HOME (e.g. spacbr update was invoked from the deployed
# copy, which never holds .config/.local — see deploy_self).
deploy_dotfiles() {
    src="${1:-$SPACBR_HOME}"
    info "Deploying .config, .local/bin, .local/share, .local/src from $src"
    deploy_tree "$src/.config" "$HOME/.config"
    deploy_tree "$src/.local/bin" "$HOME/.local/bin"
    deploy_tree "$src/.local/share" "$HOME/.local/share"
    deploy_tree "$src/.local/src" "$HOME/.local/src"
    for f in .zshrc .vimrc; do
        if [ -f "$src/$f" ]; then
            target="$HOME/$f"
            if [ -f "$target" ] && ! cmp -s "$src/$f" "$target"; then
                mkdir -p "$BACKUP_DIR"
                cp -p "$target" "$BACKUP_DIR/$f"
                warn "backed up modified $target -> $BACKUP_DIR/$f"
            fi
            cp -p "$src/$f" "$target"
            _manifest_add "$target"
        fi
    done
    chmod 755 "$HOME"/.local/bin/* 2>/dev/null || true
    ok "dotfiles deployed"
}

# deploy_self [SOURCE_DIR] — copies SPACBR's own support files
# (installer, package manifests, docs) into $XDG_DATA_HOME/spacbr so
# the `spacbr` CLI and update/repair/doctor keep working after the
# original clone is gone. No-ops when SOURCE_DIR already *is*
# SPACBR_SELF (running update from the deployed copy with nothing new
# to copy from).
deploy_self() {
    src="${1:-$SPACBR_HOME}"
    if [ "$src" = "$SPACBR_SELF" ]; then
        ok "SPACBR support files already in place ($SPACBR_SELF)"
        return 0
    fi
    info "Deploying SPACBR support files to $SPACBR_SELF"
    mkdir -p "$SPACBR_SELF"
    for item in install packages system docs VERSION README.md LICENSE CLAUDE.md; do
        [ -e "$src/$item" ] || continue
        rm -rf "${SPACBR_SELF:?}/$item"
        cp -r "$src/$item" "$SPACBR_SELF/"
    done
    ok "SPACBR support files deployed"
}
