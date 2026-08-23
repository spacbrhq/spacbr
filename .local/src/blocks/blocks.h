//Modify this file to change what commands output to your statusbar, and recompile using the make command.
static const Block blocks[] = {
	/*Icon*/	/*Command*/		/*Update Interval*/	/*Update Signal*/

	{"Net: ", "~/.local/bin/net",						10,		4},
	{"LAX ", "TZ='America/Los_Angeles' date '+%I:%M %p'",		5,		0},
	{"DAB ", "TZ='America/New_York' date '+%I:%M %p'",		5,		0},
	{"FCO ", "TZ='Europe/Rome' date '+%I:%M %p'",		5,		0},
	{"DXB ", "TZ='Asia/Dubai' date '+%I:%M %p'",		5,		0},
	{"TPE ", "TZ='Asia/Taipei' date '+%I:%M %p'",		5,		0},
	{"", "date '+%b %d (%a) %I:%M %p'",					5,		0},
	/* Icon lives in the command, not the static field: dwmblocks always
	 * copies the icon first, so a static "Bat: " label would render
	 * forever even with no battery present. Verified for real on
	 * battery-less desktop hardware -- empty icon + empty command
	 * output is the only combination dwmblocks treats as "no block". */
	{"", "for b in /sys/class/power_supply/BAT*/capacity; do [ -f $b ] && printf 'Bat: %s%%' $(cat $b) && break; done",	5,		0},
};

//sets delimiter between status commands. NULL character ('\0') means no delimiter.
static char delim[] = " | ";
static unsigned int delimLen = 5;
