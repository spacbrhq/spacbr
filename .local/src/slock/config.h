/* eightharsh's slock config — eightslate */

/* user and group to drop privileges to */
static const char *user  = "nobody";
static const char *group = "nobody"; /* nogroup if not arch linux */

static const char *colorname[NUMCOLS] = {
	[INIT] =   "#2f343f",   /* after initialization */
	[INPUT] =  "#4084d6",   /* during input */
	[FAILED] = "#ed4737",   /* wrong password */
};

/*
 * Xresources preferences to load at startup -- see slock.color0/4/1
 * in ~/.config/xresources for the actual eightslate values
 */
ResourcePref resources[] = {
		{ "color0", STRING, &colorname[INIT] },
		{ "color4", STRING, &colorname[INPUT] },
		{ "color1", STRING, &colorname[FAILED] },
};

/* lock screen opacity */
static const float alpha = 0.9;

/* treat a cleared input like a wrong password (color) */
static const int failonclear = 0;

/* time in seconds before the monitor shuts down */
static const int monitortime = 30;

/* default message */
static const char * message = "Enter password to unlock";

/* text color */
static const char * text_color = "#fafafa";

/* text size (must be a valid size) */
static const char * font_name = "monospace:size=16";
