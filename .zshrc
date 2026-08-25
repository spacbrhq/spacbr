source ~/.config/shell/profile
source ~/.config/shell/aliasrc

bindkey -e

# History
HISTFILE="${XDG_CACHE_HOME:-$HOME/.cache}/history"
HISTSIZE=1000
SAVEHIST=1000

# Tweaks
setopt autocd
setopt interactive_comments
stty stop undef

# Colors
autoload -U colors && colors
PS1="[%{$fg[cyan]%}%n%{$fg[white]%}@%{$fg[white]%}%M %{$fg[cyan]%}%1~%{$fg[white]%}]%{$reset_color%}$ "

# Autocomplete
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit
_comp_options+=(globdots)

# Syntax Highlighting
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh 2>/dev/null

# Startup banner — only inside an actual terminal window in the X
# session, never at a bare login shell.
[ -n "$DISPLAY" ] && command -v fastfetch >/dev/null 2>&1 && fastfetch

# First login (system/autologin/ auto-logs the one SPACBR user in on
# tty1 -- no display manager, LUKS2's own passphrase at Plymouth is
# this system's only password): run the installer exactly once, the
# same manifest-file check the welcome notification in
# .config/xinitrc and deploy_dotfiles both already rely on
# ($XDG_STATE_HOME/spacbr/manifest not existing yet means install.sh
# has never completed on this machine). This used to be ly's login_cmd
# hook (system/ly/spacbr-login, removed along with ly -- see
# CHANGELOG.md); on a plain auto-login tty1 shell, this is that funnel
# point now. install/live-install.sh (Phase 1) hand-places this exact
# file (plus .config/shell/profile and aliasrc, which the two lines at
# the top of this file need) before this can ever run for the very
# first time -- install.sh's own deploy_dotfiles re-syncs it moments
# later, a harmless overwrite with identical content at that point.
#
# --yes: every message about this first login, everywhere in this repo
# (live-install.sh's own final confirmation, README, docs/architecture.md),
# promises "one passphrase, nothing else to type" -- install.sh's own
# interactive "This will: ... Continue?" gate (its default with no
# arguments) would otherwise silently break that promise the very first
# time it's reached, asking a second question no other part of this
# design ever mentions. The user already agreed to all of this at
# live-install.sh's own (far more thorough, disk-erasing) confirmation;
# a second gate here is redundant friction, not real safety.
#
# _spacbr_ok guards the exec startx below on install.sh's real exit
# status -- a real regression risk that didn't exist under ly: back
# then, a failed first login just meant landing back at ly's password
# prompt, a natural pause point where a person notices something's
# wrong. With no login screen at all now, a failure here with no guard
# would fall straight through to `exec startx`, which fails too (Xorg
# isn't installed if install.sh never got that far), which ends the
# session, which agetty's autologin just restarts -- the same failure,
# forever, with no prompt ever asking anyone to look at it. Staying at
# a plain interactive shell on failure instead means the actual error
# output is still on screen and reachable.
_spacbr_ok=1
if [ ! -f "${XDG_STATE_HOME:-$HOME/.local/state}/spacbr/manifest" ] && [ -d "$HOME/spacbr" ]; then
	printf '\nSPACBR: first login -- running the installer now (this happens once).\n\n'
	if ( cd "$HOME/spacbr" && ./install/install.sh --yes ); then
		printf '\nSPACBR: installer finished. Continuing...\n'
	else
		_spacbr_ok=0
		printf '\nSPACBR: the installer did not finish -- staying at this shell instead\n'
		printf 'of starting X automatically. Check the output above, then run:\n'
		printf '  cd ~/spacbr && ./install/install.sh\n'
		printf 'yourself once fixed, or just reboot to have this retry automatically.\n\n'
	fi
fi

# Launch Xorg -- tty1 only, only if the first-boot install above didn't
# just fail, and only if X isn't already running (a second shell on
# the same tty, or this running again after install.sh above already
# started one some other way, shouldn't try to start a second X
# server).
#
# clear right before handing off: confirmed for real on actual hardware
# that without this, the raw shell (prompt, this file's own output) is
# visible on tty1 for a beat between agetty spawning the login shell
# and Xorg actually painting over it -- inherent gap in any
# autologin-then-startx flow, not fixable by speeding anything up, but
# a blank screen for that same beat reads as "the system is doing
# something" instead of "a shell leaked through". Only happens on the
# actual handoff path -- never on the failure branch above (that
# output needs to stay on screen) or when this isn't tty1/X is already
# up (nothing being handed off to).
if [ "$_spacbr_ok" = 1 ] && [ "$(tty)" = "/dev/tty1" ] && ! pidof -s Xorg >/dev/null 2>&1; then
	clear
	exec startx "$XINITRC"
fi
unset _spacbr_ok
