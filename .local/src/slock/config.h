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

/* There used to be a lock-screen "alpha" opacity knob here (the
 * upstream alpha patch's setting for a translucent *solid color* over
 * nothing, on a plain VT with no captured backdrop). Removed entirely
 * -- it doesn't make sense once the window's background is a real
 * screenshot (see BLUR/PIXELATION/dimAlpha above), and it was actively
 * dangerous in that role. Verified for real, two distinct bugs:
 *
 * 1. Any value below 1.0 sets _NET_WM_WINDOW_OPACITY on slock's
 *    window, and picom's detect-client-opacity=true honors it --
 *    compositing that percentage of the REAL, still-updating desktop
 *    on top of the static blurred snapshot for as long as the screen
 *    stayed locked. At 0.9, two screenshots taken 3 seconds apart
 *    while locked showed the background video's motion had continued
 *    -- the real desktop was still visibly playing through, not just
 *    weakly blurred.
 *
 * 2. Trying to "fix" that by setting alpha to 1.0 (fully opaque)
 *    instead produced an even worse result: `xprop` on the lock
 *    window showed _NET_WM_WINDOW_OPACITY = 0 (fully invisible).
 *    Cause: `alpha * 0xffffffff` was computed in 32-bit float
 *    precision (alpha's declared type), and float's 24-bit mantissa
 *    can't represent 0xffffffff (4294967295) exactly -- it rounds up
 *    to exactly 2^32, one past unsigned int's range, so the cast to
 *    unsigned int was undefined behavior that resolved to 0 on this
 *    compiler. There is no in-range value of this expression that
 *    reaches true full opacity; the mechanism itself is broken.
 */

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

/*
 * Blur the actual desktop as the lock window's background (via
 * Imlib2), instead of a solid color. Adapted by hand from
 * tools.suckless.org/slock/patches/blur-pixelated-screen/ (targets
 * slock 1.4, doesn't apply cleanly against 1.5 + the xresources patch
 * already in this tree) — see slock.c for where each piece landed.
 *
 * Known tradeoff, inherent to this patch design, not a bug: once the
 * blurred background is set, the window always shows that same static
 * image — the INIT/INPUT/FAILED color feedback (background tint while
 * typing, red flash on a wrong password) only applies as a fallback
 * if the screenshot capture fails, not on top of the blur.
 *
 * blurRadius alone is not enough for real content: Imlib2's blur is a
 * box blur, so any region *wider* than the radius stays essentially
 * unblurred in its interior — only its edges soften. Verified for
 * real: locking over a fullscreen video left every color band and an
 * on-screen text marker fully legible at blurRadius 5, because each
 * band was much wider than 5px. Static wallpapers looked fine only
 * because most wallpapers don't have that kind of large-scale, sharp,
 * high-contrast structure. dimAlpha darkens the already-blurred image
 * afterwards (0 = no darkening, 255 = solid black) specifically to
 * cover that gap — it destroys color/brightness information blur
 * can't reach, without needing a blur radius large enough to be slow.
 */
#define BLUR
static const int blurRadius = 16;
static const int dimAlpha = 210;
/* PIXELATION is the patch's alternative to BLUR — mosaic effect
 * instead of a Gaussian-style blur. Off by default; enable at most
 * one of the two. */
//#define PIXELATION
static const int pixelSize = 5;
