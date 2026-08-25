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

        # Import any PGP keys the PKGBUILD's validpgpkeys expects --
        # found for real that this was missing: makepkg checks source
        # signatures against the *building user's own* gpg keyring
        # (~/.gnupg), not pacman's system one, and a fresh user account
        # has nothing imported at all. paru does this automatically for
        # plain AUR packages; this override path calls makepkg directly
        # and needs the same step. Best-effort across two keyservers --
        # if both fail, let makepkg's own error be what's reported
        # rather than fail before even attempting the build.
        for key in $(sed -n '/^validpgpkeys=/,/)/p' "$tmpdir/PKGBUILD" | grep -oE '[A-F0-9]{40}'); do
            gpg --keyserver keyserver.ubuntu.com --recv-keys "$key" >/dev/null 2>&1 || \
            gpg --keyserver keys.openpgp.org --recv-keys "$key" >/dev/null 2>&1 || \
            warn "couldn't fetch PGP key $key for $name from either keyserver -- build may fail signature verification"
        done

        if ( cd "$tmpdir" && makepkg -si --noconfirm ); then
            ok "$name installed (local override)"
        else
            error "failed to build $name (local override)"
        fi
        rm -rf "$tmpdir"
    done
}

# install_cpu_microcode -- detects CPU vendor from /proc/cpuinfo and
# installs the matching official package (intel-ucode/amd-ucode).
# Can't live as a static packages/* line like everything else: which
# one is correct depends on runtime hardware, not a fixed list, and
# installing both unconditionally would be wrong (wastes space, and
# the wrong one's ucode.img just sits unused).
#
# Scope boundary, deliberate: this only installs the package. It does
# NOT touch bootloader configuration (regenerating grub.cfg, editing
# systemd-boot loader entries, rebuilding a UKI) -- SPACBR doesn't
# detect or manage bootloader type anywhere else in this repo, and
# getting boot configuration wrong risks an unbootable system in a way
# that's far harder to recover from remotely than anything else this
# installer touches (contrast with the nftables firewall change, which
# had a safety net precisely because SSH access could be tested and
# recovered from). Verified for real on one machine (systemd-boot +
# UKI/measured boot): `pacman -S intel-ucode` alone was already
# sufficient there -- `journalctl -k | grep microcode` confirmed it
# actually loading at boot with zero manual bootloader step needed, so
# modern kernel-install-based systemd-boot setups appear to wire this
# in automatically. NOT verified: a plain GRUB setup, where the Arch
# wiki's own documentation says `grub-mkconfig` needs a manual re-run
# after installing microcode for the first time -- if `spacbr doctor`'s
# "microcode loaded" check ever fails despite the package being
# installed, that's the first thing to check, not a SPACBR bug.
#
# Skips entirely inside a VM (systemd-detect-virt, already present --
# part of systemd, a hard base dependency, no new package needed).
# Corrected after directly reading archinstall's own installer.py
# (archlinux/archinstall, _get_microcode()): it checks
# `SysInfo.is_vm()` before ever attempting microcode, via exactly this
# same command. A virtual CPU has no real hardware microcode for the
# hypervisor's vCPU to load -- installing intel-ucode/amd-ucode inside
# a VM is pointless, not actively harmful, but pointless is enough
# reason to skip it given this repo's own package philosophy (§39).
install_cpu_microcode() {
    local vendor pkg
    if detect_is_vm; then
        ok "running in a VM ($(systemd-detect-virt 2>/dev/null)) -- skipping CPU microcode"
        return 0
    fi
    vendor="$(awk -F': ' '/vendor_id/{print $2; exit}' /proc/cpuinfo 2>/dev/null)"
    case "$vendor" in
        GenuineIntel) pkg=intel-ucode ;;
        AuthenticAMD) pkg=amd-ucode ;;
        *) warn "unrecognized CPU vendor '$vendor' -- skipping microcode package"; return 0 ;;
    esac
    sudo pacman -S --needed --noconfirm "$pkg"
    ok "$pkg installed"
}

# install_gpu_drivers -- detects GPU vendor(s) via `lspci` (pciutils,
# packages/base) and installs the matching official mesa/Vulkan
# packages. Checks Intel and AMD independently, not a case/either-or
# switch: a hybrid-graphics laptop can genuinely have both, and
# skipping one because the other matched first would silently leave a
# real GPU without a driver. NVIDIA deliberately not handled here --
# not requested, and NVIDIA's own driver situation (proprietary vs.
# nouveau vs. nvidia-open) is enough of a real decision that it
# shouldn't be silently auto-selected the way Intel/AMD's
# unambiguous open-source stack can be.
install_gpu_drivers() {
    local gpu_info pkgs=""
    command -v lspci >/dev/null 2>&1 || { warn "lspci not found (pciutils) -- skipping GPU driver detection"; return 0; }
    gpu_info="$(lspci -k 2>/dev/null | grep -iE 'vga|3d|display')"
    if echo "$gpu_info" | grep -qi intel; then
        pkgs="$pkgs mesa vulkan-intel intel-media-driver"
    fi
    if echo "$gpu_info" | grep -qiE 'advanced micro devices|amd|ati '; then
        pkgs="$pkgs mesa vulkan-radeon libva-mesa-driver"
    fi
    if [ -z "$pkgs" ]; then
        ok "no Intel/AMD GPU detected -- skipping driver install"
        return 0
    fi
    # shellcheck disable=SC2086
    sudo pacman -S --needed --noconfirm $pkgs
    ok "GPU drivers installed for detected hardware"
}

install_all_packages() {
    require_cmd pacman
    for pkgset in base x11 desktop hardware; do
        install_package_set "$pkgset"
    done
    install_cpu_microcode
    install_gpu_drivers

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

    install_claude_code
}

# install_claude_code -- the Claude Code CLI isn't a pacman package
# (npm, from the official @anthropic-ai/claude-code registry entry).
# Installed into a user-owned npm prefix, not npm's own default of
# /usr -- that would need sudo for a global install and would put a
# user tool in a system directory, unlike everything else under
# ~/.local. Non-fatal: a supplementary dev tool, not anything the
# desktop itself depends on to function.
install_claude_code() {
    command -v npm >/dev/null 2>&1 || { warn "npm not found — skipping Claude Code CLI"; return 0; }
    npm config set prefix "$HOME/.local/share/npm"
    if npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code >/dev/null 2>&1; then
        ok "Claude Code CLI installed/updated"
    else
        warn "Claude Code CLI install failed — continuing"
    fi
}
