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

# deploy_modules_load [SOURCE_DIR] -- copies system/modules-load.d/*.conf
# to /etc/modules-load.d/ and loads any new one immediately via
# modprobe, so a fresh install doesn't need a reboot before ddcutil (or
# whatever else needs the module) works. Idempotent like
# deploy_polkit_rules: skips a file that already matches.
deploy_modules_load() {
    local src="${1:-$SPACBR_HOME}/system/modules-load.d"
    local dest="/etc/modules-load.d"
    local file name mod
    [ -d "$src" ] || return 0
    for file in "$src"/*.conf; do
        [ -f "$file" ] || continue
        name="$(basename "$file")"
        if [ -f "$dest/$name" ] && cmp -s "$file" "$dest/$name"; then
            continue
        fi
        sudo install -D -m 644 "$file" "$dest/$name"
        while read -r mod; do
            case "$mod" in ''|'#'*) continue ;; esac
            sudo modprobe "$mod" 2>/dev/null
        done < "$file"
        ok "loaded kernel module(s) from $name"
    done
}

# deploy_nftables [SOURCE_DIR] -- copies system/nftables/nftables.conf
# to /etc/nftables.conf and reloads the ruleset if it changed. The
# nftables package already ships nftables.service to load this file at
# boot; SPACBR doesn't need its own unit, just the file and the
# service enabled (see enable_system_services).
deploy_nftables() {
    local src="${1:-$SPACBR_HOME}/system/nftables/nftables.conf"
    local dest="/etc/nftables.conf"
    [ -f "$src" ] || return 0
    if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
        ok "nftables ruleset already up to date"
        return 0
    fi
    sudo install -D -m 644 "$src" "$dest"
    sudo systemctl reload-or-restart nftables 2>/dev/null || sudo systemctl restart nftables
    ok "nftables ruleset deployed"
}
