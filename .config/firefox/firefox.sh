#!/bin/sh

# Fallback matches every other XDG-path default already used elsewhere
# in this repo (.zshrc, .config/xinitrc) -- found for real that running
# this script from a context where XDG_CONFIG_HOME isn't already
# exported (profile.sh sets it, but nothing guarantees every caller
# sourced that first) silently collapsed this to the bogus absolute
# path "/mozilla/firefox", which mkdir/sed then failed against with a
# confusing error instead of just working.
browserdir="${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox"
profilesini="$browserdir/profiles.ini"

firefox --headless >/dev/null 2>&1 &
# Poll for profiles.ini rather than a fixed sleep -- a completely
# fresh Firefox (never run before, no profile yet) can take longer
# than one second to finish first-run profile creation; a fixed sleep
# either wastes time on a machine that already has a profile or races
# ahead of one that doesn't, reading an empty/missing file either way.
for _ in 1 2 3 4 5 6 7 8 9 10; do
	[ -f "$profilesini" ] && break
	sleep 1
done
pdir="$1"
profile="$(sed -n "/Default=.*.default-release/ s/.*=//p" "$profilesini")"
[ -z "$1" ] && pdir="$browserdir/$profile"

overrides="$2"
[ -z "$2" ] && overrides="$HOME/.config/firefox/user-overrides.js"

# Stop Firefox -- -x for an *exact* process-name match. Confirmed for
# real this was a genuine bug, not theoretical: without -x, pkill
# matches by substring against the process name by default, and this
# script's own process name (running as ~/.config/firefox/firefox.sh)
# is "firefox.sh" -- which contains "firefox" as a substring. A bare
# `pkill firefox` killed the script itself via SIGTERM the moment it
# reached this line, every single run, before ever getting to the
# Arkenfox/overrides/extensions steps below.
pkill -x firefox

# Get the Arkenfox user.js and prepare it.
arkenfox="$pdir/arkenfox.js"
curl "https://raw.githubusercontent.com/arkenfox/user.js/master/user.js" > "$arkenfox"
userjs="$pdir/user.js"

# Apply Arkenfox and the overrides
cat "$arkenfox" "$overrides" > "$userjs"

# Chrome-level theming (tabs/toolbar/urlbar) -- see chrome/userChrome.css's
# own header for why GTK_THEME alone can't reach this. Requires
# toolkit.legacyUserProfileCustomizations.stylesheets=true, set in
# user-overrides.js above (already applied to userjs by this point).
chromesrc="$(dirname "$0")/chrome/userChrome.css"
if [ -f "$chromesrc" ]; then
	mkdir -p "$pdir/chrome"
	cp "$chromesrc" "$pdir/chrome/userChrome.css"
fi

# Install extensions
addonlist="ublock-origin decentraleyes istilldontcareaboutcookies new-window-without-toolbar tridactyl-vim"
addontmp="$(mktemp -d)"
trap "rm -fr $addontmp" HUP INT QUIT TERM PWR EXIT
IFS=' '
mkdir -p "$pdir/extensions/"

# Loop through addons and install them
for addon in $addonlist; do
	echo "Downloading $addon"
	addonurl="$(curl --connect-timeout 5 "https://addons.mozilla.org/en-US/firefox/addon/${addon}/" |
		grep -o 'https://addons.mozilla.org/firefox/downloads/file/[^"]*')"
	file="${addonurl##*/}"
	# -O saves to a name derived from the URL in the *current*
	# directory; that's incompatible with also redirecting stdout to
	# a specific path. Verified for real: the old `-LOs ... > path`
	# combination left an empty file at the intended path while the
	# actual ~4-5MB download landed in whatever directory the script
	# happened to be run from. -o names the real output path directly.
	curl -Ls -o "$addontmp/$file" "$addonurl"
	id="$(unzip -p "$addontmp/$file" manifest.json | grep "\"id\"")"
	id="${id%\"*}"
	id="${id##*\"}"
	mv "$addontmp/$file" "$pdir/extensions/$id.xpi"
done
