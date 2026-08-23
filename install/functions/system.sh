# Deploys system/ (files that live outside the user's home directory,
# under /etc) — separate from configs.sh's deploy_tree, which only
# ever writes into $HOME. Sourced, not executed directly. Requires
# common.sh.

# deploy_polkit_rules [SOURCE_DIR] — copies system/polkit/*.rules to
# /etc/polkit-1/rules.d/. Idempotent: skips the copy (and the reload)
# entirely when the deployed file already matches, so a repeat
# install/update doesn't restart polkit for no reason.
deploy_polkit_rules() {
    local src="${1:-$SPACBR_HOME}/system/polkit"
    local dest="/etc/polkit-1/rules.d"
    local file name changed=0
    [ -d "$src" ] || return 0
    for file in "$src"/*.rules; do
        [ -f "$file" ] || continue
        name="$(basename "$file")"
        if [ -f "$dest/$name" ] && cmp -s "$file" "$dest/$name"; then
            continue
        fi
        sudo install -D -m 644 "$file" "$dest/$name"
        changed=1
    done
    if [ "$changed" -eq 1 ]; then
        sudo systemctl restart polkit
        ok "polkit rules deployed"
    else
        ok "polkit rules already up to date"
    fi
}
