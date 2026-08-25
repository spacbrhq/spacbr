# Deploys system/ (files that live outside the user's home directory,
# under /etc) — separate from configs.sh's deploy_tree, which only
# ever writes into $HOME. Sourced, not executed directly. Requires
# common.sh.

# deploy_autologin [SOURCE_DIR] -- renders
# system/autologin/tty1-autologin.conf (the @SPACBR_USERNAME@
# placeholder substituted with $USER) to
# /etc/systemd/system/getty@tty1.service.d/autologin.conf, then makes
# sure getty@tty1 (autologin, no display manager) is enabled.
#
# This system has exactly one password: the LUKS2 passphrase entered
# at Plymouth during early boot (docs/architecture.md, "Boot &
# authentication"). No display manager, no second login prompt.
#
# live-install.sh already does the equivalent of this directly during
# Phase 1 -- it has to, autologin needs to be working *before* Phase 2
# (this) is ever reached, since the first auto-login on tty1 is what
# runs install.sh in the first place. This function exists for two
# other real cases: a standalone `spacbr install` against a plain Arch
# box (no live-install.sh, so none of this happened yet), and `spacbr
# update`/`repair` re-syncing the drop-in if the template or $USER
# changes later.
#
# Idempotent like deploy_nftables: renders the template to a temp file
# first and cmp's that against what's deployed, so a username that
# hasn't changed doesn't get re-copied (and the enable/restart) skipped
# on every run.
deploy_autologin() {
    local src="${1:-$SPACBR_HOME}/system/autologin/tty1-autologin.conf"
    local dest="/etc/systemd/system/getty@tty1.service.d/autologin.conf"
    local rendered

    [ -f "$src" ] || return 0

    rendered="$(mktemp)"
    sed "s/@SPACBR_USERNAME@/$USER/" "$src" > "$rendered"

    if [ -f "$dest" ] && cmp -s "$rendered" "$dest"; then
        ok "autologin already up to date"
    else
        sudo install -D -m 644 "$rendered" "$dest"
        ok "autologin configured for $USER"
    fi
    rm -f "$rendered"

    # Always re-assert this, even with no file changes -- cheap
    # (systemctl enable on an already-enabled unit is a no-op) and it's
    # the actual functional requirement, not the file copy.
    sudo systemctl enable getty@tty1.service >/dev/null 2>&1
    ok "getty@tty1 enabled"
}

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

# deploy_plymouth_theme [SOURCE_DIR] -- copies system/plymouth/spacbr/
# to /usr/share/plymouth/themes/spacbr/, sets it as the default theme,
# and rebuilds the initramfs so it actually takes effect.
#
# Deliberately NOT done in live-install.sh (Phase 1): the theme's
# wordmark uses Rajdhani Bold (packages/aur-overrides/ttf-rajdhani),
# which doesn't exist until install_aur_overrides has run -- i.e. not
# until Phase 2, here. Setting the theme before the font exists would
# make mkinitcpio's plymouth hook silently `fc-match` to whatever
# fallback it could find instead of Rajdhani.
#
# No-ops cleanly on a machine with no Plymouth at all (plymouth isn't
# in any packages/* manifest -- only live-install.sh's pacstrap
# installs it) and on one where the plymouth hook was never added to
# HOOKS -- both real cases, not hypothetical: `spacbr install` run
# directly against a plain Arch install (no live-install.sh) never
# gets Plymouth at all. Idempotent like deploy_nftables: skips the
# `mkinitcpio -P` rebuild (the expensive part) unless the theme files
# actually changed or "spacbr" wasn't already the active theme.
deploy_plymouth_theme() {
    local src="${1:-$SPACBR_HOME}/system/plymouth/spacbr"
    local dest="/usr/share/plymouth/themes/spacbr"
    local changed=0
    local name

    command -v plymouth-set-default-theme >/dev/null 2>&1 || return 0
    [ -d "$src" ] || return 0
    # Anchored to the actual HOOKS= line, not a whole-file grep -- a
    # whole-file match could false-positive on "plymouth" appearing in
    # an unrelated comment (mkinitcpio.conf ships with a large
    # commented-out HOOKS example block).
    grep -qE '^HOOKS=\(.*\bplymouth\b' /etc/mkinitcpio.conf 2>/dev/null || {
        ok "plymouth hook not in mkinitcpio HOOKS -- skipping theme (no splash to theme)"
        return 0
    }

    for name in spacbr.plymouth spacbr.script wallpaper.jpg; do
        if [ ! -f "$dest/$name" ] || ! cmp -s "$src/$name" "$dest/$name"; then
            sudo install -D -m 644 "$src/$name" "$dest/$name"
            changed=1
        fi
    done

    if [ "$(plymouth-set-default-theme 2>/dev/null)" != "spacbr" ]; then
        changed=1
    fi

    if [ "$changed" -eq 0 ]; then
        ok "spacbr Plymouth theme already up to date"
        return 0
    fi

    sudo plymouth-set-default-theme spacbr
    info "Rebuilding initramfs for the spacbr Plymouth theme (mkinitcpio -P)..."
    if sudo mkinitcpio -P; then
        ok "spacbr Plymouth theme deployed and baked into the initramfs"
    else
        error "mkinitcpio -P failed after setting the spacbr Plymouth theme -- boot may still show the previous theme until this is re-run"
        return 1
    fi
}

# deploy_pacman_conf [SOURCE_DIR] -- copies system/pacman/pacman.conf to
# /etc/pacman.conf. Validated with `pacman-conf` before it's put in
# place (syntax/repo-list only, doesn't touch anything) so a typo here
# can't break every future pacman invocation. Re-syncs repo databases
# afterward if the repo list actually changed (e.g. multilib newly
# enabled) -- otherwise a freshly enabled repo has no local database
# yet and the very next `pacman -S` for anything in it fails.
deploy_pacman_conf() {
    local src="${1:-$SPACBR_HOME}/system/pacman/pacman.conf"
    local dest="/etc/pacman.conf"
    [ -f "$src" ] || return 0
    if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
        ok "pacman.conf already up to date"
        return 0
    fi
    if ! pacman-conf --config "$src" --repo-list >/dev/null 2>&1; then
        error "system/pacman/pacman.conf failed validation -- not deploying"
        return 1
    fi
    local repos_before repos_after
    repos_before="$(pacman-conf --repo-list 2>/dev/null || true)"
    sudo install -D -m 644 "$src" "$dest"
    repos_after="$(pacman-conf --repo-list 2>/dev/null || true)"
    if [ "$repos_before" != "$repos_after" ]; then
        sudo pacman -Sy
    fi
    ok "pacman.conf deployed"
}
