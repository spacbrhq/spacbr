//Modify this file to change what commands output to your statusbar, and recompile using the make command.
static const Block blocks[] = {
	/*Icon*/	/*Command*/		/*Update Interval*/	/*Update Signal*/

	{"Net: ", "~/.local/bin/net",						10,		4},
	/* .local/bin/volume get already exists (shared with dwm's hardware
	 * volume keys/the audio dmenu menu) and returns the bare percentage
	 * number -- reused here rather than duplicating a wpctl call.
	 * MUTED check mirrors the exact same check that script's own
	 * notify() uses, so the bar and the notification never disagree. */
	{"Vol: ", "wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED && echo Muted || ~/.local/bin/volume get | sed 's/$/%/'",	5,		0},
	{"", "date '+%b %d (%a) %I:%M %p'",					5,		0},
};

//sets delimiter between status commands. NULL character ('\0') means no delimiter.
static char delim[] = " | ";
static unsigned int delimLen = 5;
