/* user and group to drop privileges to */
static const char *user  = "nobody";
static const char *group = "nobody"; /* nogroup if not arch linux */

static const char *colorname[NUMCOLS] = {
	[INIT] =   "#000000",   /* after initialization */
	[INPUT] =  "#282A36",   /* during input */
	[FAILED] = "#FF5555",   /* wrong password */
};

/*
 * Xresources preferences to load at startup
 */
ResourcePref resources[] = {
		{ "color0", STRING, &colorname[INIT] },
		{ "color4", STRING, &colorname[INPUT] },
		{ "color1", STRING, &colorname[FAILED] },
};

/* lock screen opacity */
static const float alpha = 0.6;

/* treat a cleared input like a wrong password (color) */
static const int failonclear = 0;

/* time in seconds before the monitor shuts down */
static const int monitortime = 30;

/* default message */
static const char * message = "Enter password to unlock";

/* text color */
static const char * text_color = "#ffffff";

/* text size (must be a valid size) */
static const char * font_name = "monospace:size=16";

/* Blur the desktop as the lock background via Imlib2 instead of a
 * solid color -- see config.h and slock.c for the full explanation. */
#define BLUR
static const int blurRadius = 5;
//#define PIXELATION
static const int pixelSize = 5;
