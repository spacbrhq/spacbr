/* See LICENSE file for license details. */
#define _XOPEN_SOURCE 500
#if HAVE_SHADOW_H
#include <shadow.h>
#endif

#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <grp.h>
#include <pwd.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <X11/extensions/Xrandr.h>
#include <X11/extensions/dpms.h>
#include <fontconfig/fontconfig.h>
#include <X11/extensions/Xinerama.h>
#include <X11/Xft/Xft.h>
#include <X11/keysym.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/Xresource.h>
#include <Imlib2.h>

#include "arg.h"
#include "util.h"

char *argv0;

/* global count to prevent repeated error messages */
int count_error = 0;

enum {
	INIT,
	INPUT,
	FAILED,
	NUMCOLS
};

struct lock {
	int screen;
	Window root, win;
	Pixmap pmap;
	Pixmap bgmap;
	unsigned long colors[NUMCOLS];
};

struct xrandr {
	int active;
	int evbase;
	int errbase;
};

/* Xresources preferences */
enum resource_type {
	STRING = 0,
	INTEGER = 1,
	FLOAT = 2
};

typedef struct {
	char *name;
	enum resource_type type;
	void *dst;
} ResourcePref;

#include "config.h"

/* holds the blurred/pixelated screenshot used as the lock background */
static Imlib_Image image;

static void
die(const char *errstr, ...)
{
	va_list ap;

	va_start(ap, errstr);
	vfprintf(stderr, errstr, ap);
	va_end(ap);
	exit(1);
}

#ifdef __linux__
#include <fcntl.h>
#include <linux/oom.h>

static void
dontkillme(void)
{
	FILE *f;
	const char oomfile[] = "/proc/self/oom_score_adj";

	if (!(f = fopen(oomfile, "w"))) {
		if (errno == ENOENT)
			return;
		die("slock: fopen %s: %s\n", oomfile, strerror(errno));
	}
	fprintf(f, "%d", OOM_SCORE_ADJ_MIN);
	if (fclose(f)) {
		if (errno == EACCES)
			die("slock: unable to disable OOM killer. "
			    "Make sure to suid or sgid slock.\n");
		else
			die("slock: fclose %s: %s\n", oomfile, strerror(errno));
	}
}
#endif

static void
writemessage(Display *dpy, Window win, int screen, unsigned long boxpixel)
{
	int len, line_len, width, height, s_width, s_height, i, j, k, tab_replace, tab_size;
        XftFont *fontinfo;
        XftColor xftcolor;
        XftDraw *xftdraw;
        XGlyphInfo ext_msg, ext_space;
	XineramaScreenInfo *xsi;
	xftdraw = XftDrawCreate(dpy, win, DefaultVisual(dpy, screen), DefaultColormap(dpy, screen));
	fontinfo = XftFontOpenName(dpy, screen, font_name);
	XftColorAllocName(dpy, DefaultVisual(dpy, screen), DefaultColormap(dpy, screen), text_color, &xftcolor);

	if (fontinfo == NULL) {
		if (count_error == 0) {
			fprintf(stderr, "slock: Unable to load font \"%s\"\n", font_name);
			fprintf(stderr, "slock: Try listing fonts with 'slock -f'\n");
			count_error++;
		}
		return;
	}

	XftTextExtentsUtf8(dpy, fontinfo, (XftChar8 *) " ", 1, &ext_space);
	tab_size = 8 * ext_space.width;

	/*  To prevent "Uninitialized" warnings. */
	xsi = NULL;

	/*
	 * Start formatting and drawing text
	 */

	len = strlen(message);

	/* Max max line length (cut at '\n') */
	line_len = 0;
	k = 0;
	for (i = j = 0; i < len; i++) {
		if (message[i] == '\n') {
			if (i - j > line_len)
				line_len = i - j;
			k++;
			i++;
			j = i;
		}
	}
	/* If there is only one line */
	if (line_len == 0)
		line_len = len;

	if (XineramaIsActive(dpy)) {
		xsi = XineramaQueryScreens(dpy, &i);
		s_width = xsi[0].width;
		s_height = xsi[0].height;
	} else {
		s_width = DisplayWidth(dpy, screen);
		s_height = DisplayHeight(dpy, screen);
	}

	XftTextExtentsUtf8(dpy, fontinfo, (XftChar8 *)message, line_len, &ext_msg);
	height = s_height*3/7 - (k*20)/3;
	width  = (s_width - ext_msg.width)/2;

	/* Solid highlight box behind the message, drawn before the text
	 * itself, in whichever of colorname[INIT]/[INPUT]/[FAILED] the
	 * caller passes in for the current auth state -- not a fixed
	 * color. This is what actually shows the INPUT/FAILED feedback
	 * against the heavy blur+darken this config applies to the
	 * captured background (see config.h's dimAlpha): a fixed-color box
	 * made a locked screen unmistakable at a glance, but couldn't tell
	 * "typing" from "wrong password" the way the box's own color now
	 * does. */
	{
		GC boxgc;
		int box_pad_x = 24, box_pad_y = 16;
		int box_x = width - box_pad_x;
		int box_y = height - fontinfo->ascent - box_pad_y;
		int box_w = ext_msg.width + 2*box_pad_x;
		int box_h = fontinfo->ascent + fontinfo->descent + 20*k + 2*box_pad_y;
		boxgc = XCreateGC(dpy, win, 0, NULL);
		XSetForeground(dpy, boxgc, boxpixel);
		XFillRectangle(dpy, win, boxgc, box_x, box_y, box_w, box_h);
		XFreeGC(dpy, boxgc);
	}

	/* Look for '\n' and print the text between them. */
	for (i = j = k = 0; i <= len; i++) {
		/* i == len is the special case for the last line */
		if (i == len || message[i] == '\n') {
			tab_replace = 0;
			while (message[j] == '\t' && j < i) {
				tab_replace++;
				j++;
			}

			XftDrawStringUtf8(xftdraw, &xftcolor, fontinfo, width + tab_size*tab_replace, height + 20*k, (XftChar8 *)(message + j), i - j);
			while (i < len && message[i] == '\n') {
				i++;
				j = i;
				k++;
			}
		}
	}

	/* xsi should not be NULL anyway if Xinerama is active, but to be safe */
	if (XineramaIsActive(dpy) && xsi != NULL)
			XFree(xsi);

	XftFontClose(dpy, fontinfo);
	XftColorFree(dpy, DefaultVisual(dpy, screen), DefaultColormap(dpy, screen), &xftcolor);
	XftDrawDestroy(xftdraw);
}



static const char *
gethash(void)
{
	const char *hash;
	struct passwd *pw;

	/* Check if the current user has a password entry */
	errno = 0;
	if (!(pw = getpwuid(getuid()))) {
		if (errno)
			die("slock: getpwuid: %s\n", strerror(errno));
		else
			die("slock: cannot retrieve password entry\n");
	}
	hash = pw->pw_passwd;

#if HAVE_SHADOW_H
	if (!strcmp(hash, "x")) {
		struct spwd *sp;
		if (!(sp = getspnam(pw->pw_name)))
			die("slock: getspnam: cannot retrieve shadow entry. "
			    "Make sure to suid or sgid slock.\n");
		hash = sp->sp_pwdp;
	}
#else
	if (!strcmp(hash, "*")) {
#ifdef __OpenBSD__
		if (!(pw = getpwuid_shadow(getuid())))
			die("slock: getpwnam_shadow: cannot retrieve shadow entry. "
			    "Make sure to suid or sgid slock.\n");
		hash = pw->pw_passwd;
#else
		die("slock: getpwuid: cannot retrieve shadow entry. "
		    "Make sure to suid or sgid slock.\n");
#endif /* __OpenBSD__ */
	}
#endif /* HAVE_SHADOW_H */

	return hash;
}

static void
readpw(Display *dpy, struct xrandr *rr, struct lock **locks, int nscreens,
       const char *hash)
{
	XRRScreenChangeNotifyEvent *rre;
	char buf[32], passwd[256], *inputhash;
	int num, screen, running, failure, oldc;
	unsigned int len, color;
	KeySym ksym;
	XEvent ev;

	len = 0;
	running = 1;
	failure = 0;
	oldc = INIT;

	while (running && !XNextEvent(dpy, &ev)) {
		if (ev.type == KeyPress) {
			explicit_bzero(&buf, sizeof(buf));
			num = XLookupString(&ev.xkey, buf, sizeof(buf), &ksym, 0);
			if (IsKeypadKey(ksym)) {
				if (ksym == XK_KP_Enter)
					ksym = XK_Return;
				else if (ksym >= XK_KP_0 && ksym <= XK_KP_9)
					ksym = (ksym - XK_KP_0) + XK_0;
			}
			if (IsFunctionKey(ksym) ||
			    IsKeypadKey(ksym) ||
			    IsMiscFunctionKey(ksym) ||
			    IsPFKey(ksym) ||
			    IsPrivateKeypadKey(ksym))
				continue;
			switch (ksym) {
			case XK_Return:
				passwd[len] = '\0';
				errno = 0;
				if (!(inputhash = crypt(passwd, hash)))
					fprintf(stderr, "slock: crypt: %s\n", strerror(errno));
				else
					running = !!strcmp(inputhash, hash);
				if (running) {
					XBell(dpy, 100);
					failure = 1;
				}
				explicit_bzero(&passwd, sizeof(passwd));
				len = 0;
				break;
			case XK_Escape:
				explicit_bzero(&passwd, sizeof(passwd));
				len = 0;
				break;
			case XK_BackSpace:
				if (len)
					passwd[--len] = '\0';
				break;
			default:
				if (num && !iscntrl((int)buf[0]) &&
				    (len + num < sizeof(passwd))) {
					memcpy(passwd + len, buf, num);
					len += num;
				}
				break;
			}
			color = len ? INPUT : ((failure || failonclear) ? FAILED : INIT);
			if (running && oldc != color) {
				for (screen = 0; screen < nscreens; screen++) {
					/* Once a blurred background is set, it stays as
					 * the static background regardless of auth state
					 * -- that's inherent to this patch, not a bug.
					 * The colors[color] (not colors[0], unlike the
					 * upstream patch this was adapted from) fallback
					 * only applies as the actual window background if
					 * the screenshot capture failed. When it didn't
					 * (the normal case), writemessage's message-box
					 * still gets colors[color] every redraw, which is
					 * what actually shows typing/wrong-password
					 * feedback against a static blurred backdrop. */
					if (locks[screen]->bgmap)
						XSetWindowBackgroundPixmap(dpy,
						                           locks[screen]->win,
						                           locks[screen]->bgmap);
					else
						XSetWindowBackground(dpy,
						                     locks[screen]->win,
						                     locks[screen]->colors[color]);
					XClearWindow(dpy, locks[screen]->win);
					writemessage(dpy, locks[screen]->win, screen, locks[screen]->colors[color]);
				}
				oldc = color;
			}
		} else if (rr->active && ev.type == rr->evbase + RRScreenChangeNotify) {
			rre = (XRRScreenChangeNotifyEvent*)&ev;
			for (screen = 0; screen < nscreens; screen++) {
				if (locks[screen]->win == rre->window) {
					if (rre->rotation == RR_Rotate_90 ||
					    rre->rotation == RR_Rotate_270)
						XResizeWindow(dpy, locks[screen]->win,
						              rre->height, rre->width);
					else
						XResizeWindow(dpy, locks[screen]->win,
						              rre->width, rre->height);
					XClearWindow(dpy, locks[screen]->win);
					break;
				}
			}
		} else {
			for (screen = 0; screen < nscreens; screen++)
				XRaiseWindow(dpy, locks[screen]->win);
		}
	}
}

static struct lock *
lockscreen(Display *dpy, struct xrandr *rr, int screen)
{
	char curs[] = {0, 0, 0, 0, 0, 0, 0, 0};
	int i, ptgrab, kbgrab;
	struct lock *lock;
	XColor color, dummy;
	XSetWindowAttributes wa;
	Cursor invisible;

	if (dpy == NULL || screen < 0 || !(lock = malloc(sizeof(struct lock))))
		return NULL;

	lock->screen = screen;
	lock->root = RootWindow(dpy, lock->screen);

	/* lock is malloc'd, not calloc'd -- bgmap must be explicitly
	 * initialized to None (0), or every `if (lock->bgmap)` check below
	 * and in readpw() would read uninitialized garbage as if it were
	 * a valid Pixmap whenever image capture fails. This is a real bug
	 * present in the upstream patch this was adapted from; fixed here. */
	lock->bgmap = None;

	/* render the (already blurred/pixelated, see main()) screenshot
	 * into a pixmap sized for this screen, used as the lock window's
	 * background below instead of a solid color.
	 *
	 * Deliberately NOT calling imlib_free_image() here, unlike the
	 * upstream patch this was adapted from: lockscreen() runs once
	 * per X11 screen (nscreens in main()), so freeing image after the
	 * first screen would leave every subsequent call operating on
	 * freed memory on any genuine multi-head setup. slock's process
	 * lifetime is short and exits on unlock, so leaving this one
	 * screenshot-sized image allocated for that duration is a
	 * non-issue. */
	if (image) {
		lock->bgmap = XCreatePixmap(dpy, lock->root,
		                           DisplayWidth(dpy, lock->screen),
		                           DisplayHeight(dpy, lock->screen),
		                           DefaultDepth(dpy, lock->screen));
		imlib_context_set_image(image);
		imlib_context_set_display(dpy);
		imlib_context_set_visual(DefaultVisual(dpy, lock->screen));
		imlib_context_set_colormap(DefaultColormap(dpy, lock->screen));
		imlib_context_set_drawable(lock->bgmap);
		imlib_render_image_on_drawable(0, 0);
	}

	for (i = 0; i < NUMCOLS; i++) {
		XAllocNamedColor(dpy, DefaultColormap(dpy, lock->screen),
		                 colorname[i], &color, &dummy);
		lock->colors[i] = color.pixel;
	}

	/* init */
	wa.override_redirect = 1;
	wa.background_pixel = lock->colors[INIT];
	lock->win = XCreateWindow(dpy, lock->root, 0, 0,
	                          DisplayWidth(dpy, lock->screen),
	                          DisplayHeight(dpy, lock->screen),
	                          0, DefaultDepth(dpy, lock->screen),
	                          CopyFromParent,
	                          DefaultVisual(dpy, lock->screen),
	                          CWOverrideRedirect | CWBackPixel, &wa);
	if (lock->bgmap)
		XSetWindowBackgroundPixmap(dpy, lock->win, lock->bgmap);
	lock->pmap = XCreateBitmapFromData(dpy, lock->win, curs, 8, 8);
	invisible = XCreatePixmapCursor(dpy, lock->pmap, lock->pmap,
	                                &color, &color, 0, 0);
	XDefineCursor(dpy, lock->win, invisible);

	/* Try to grab mouse pointer *and* keyboard for 600ms, else fail the lock */
	for (i = 0, ptgrab = kbgrab = -1; i < 6; i++) {
		if (ptgrab != GrabSuccess) {
			ptgrab = XGrabPointer(dpy, lock->root, False,
			                      ButtonPressMask | ButtonReleaseMask |
			                      PointerMotionMask, GrabModeAsync,
			                      GrabModeAsync, None, invisible, CurrentTime);
		}
		if (kbgrab != GrabSuccess) {
			kbgrab = XGrabKeyboard(dpy, lock->root, True,
			                       GrabModeAsync, GrabModeAsync, CurrentTime);
		}

		/* input is grabbed: we can lock the screen */
		if (ptgrab == GrabSuccess && kbgrab == GrabSuccess) {
			XMapRaised(dpy, lock->win);
			if (rr->active)
				XRRSelectInput(dpy, lock->win, RRScreenChangeNotifyMask);

			XSelectInput(dpy, lock->root, SubstructureNotifyMask);
			XSync(dpy, False);
			return lock;
		}

		/* retry on AlreadyGrabbed but fail on other errors */
		if ((ptgrab != AlreadyGrabbed && ptgrab != GrabSuccess) ||
		    (kbgrab != AlreadyGrabbed && kbgrab != GrabSuccess))
			break;

		usleep(100000);
	}

	/* we couldn't grab all input: fail out */
	if (ptgrab != GrabSuccess)
		fprintf(stderr, "slock: unable to grab mouse pointer for screen %d\n",
		        screen);
	if (kbgrab != GrabSuccess)
		fprintf(stderr, "slock: unable to grab keyboard for screen %d\n",
		        screen);
	return NULL;
}

int
resource_load(XrmDatabase db, char *name, enum resource_type rtype, void *dst)
{
	char **sdst = dst;
	int *idst = dst;
	float *fdst = dst;

	char fullname[256];
	char fullclass[256];
	char *type;
	XrmValue ret;

	snprintf(fullname, sizeof(fullname), "%s.%s", "slock", name);
	snprintf(fullclass, sizeof(fullclass), "%s.%s", "Slock", name);
	fullname[sizeof(fullname) - 1] = fullclass[sizeof(fullclass) - 1] = '\0';

	XrmGetResource(db, fullname, fullclass, &type, &ret);
	if (ret.addr == NULL || strncmp("String", type, 64))
		return 1;

	switch (rtype) {
	case STRING:
		*sdst = ret.addr;
		break;
	case INTEGER:
		*idst = strtoul(ret.addr, NULL, 10);
		break;
	case FLOAT:
		*fdst = strtof(ret.addr, NULL);
		break;
	}
	return 0;
}

void
config_init(Display *dpy)
{
	char *resm;
	XrmDatabase db;
	ResourcePref *p;

	XrmInitialize();
	resm = XResourceManagerString(dpy);
	if (!resm)
		return;

	db = XrmGetStringDatabase(resm);
	for (p = resources; p < resources + LEN(resources); p++)
		resource_load(db, p->name, p->type, p->dst);
}

static void
usage(void)
{
	die("usage: slock [-v] [-m message] [cmd [arg ...]]\n");
}

int
main(int argc, char **argv) {
	struct xrandr rr;
	struct lock **locks;
	struct passwd *pwd;
	struct group *grp;
	uid_t duid;
	gid_t dgid;
	const char *hash;
	Display *dpy;
	int s, nlocks, nscreens, dpms_ok = 0;
	CARD16 standby = 0, suspend = 0, off = 0;

	ARGBEGIN {
	case 'v':
		fprintf(stderr, "slock-"VERSION"\n");
		return 0;
	case 'm':
		message = EARGF(usage());
		break;
	default:
		usage();
	} ARGEND

	/* validate drop-user and -group */
	errno = 0;
	if (!(pwd = getpwnam(user)))
		die("slock: getpwnam %s: %s\n", user,
		    errno ? strerror(errno) : "user entry not found");
	duid = pwd->pw_uid;
	errno = 0;
	if (!(grp = getgrnam(group)))
		die("slock: getgrnam %s: %s\n", group,
		    errno ? strerror(errno) : "group entry not found");
	dgid = grp->gr_gid;

#ifdef __linux__
	dontkillme();
#endif

	hash = gethash();
	errno = 0;
	if (!crypt("", hash))
		die("slock: crypt: %s\n", strerror(errno));

	if (!(dpy = XOpenDisplay(NULL)))
		die("slock: cannot open display\n");

	/* drop privileges */
	if (setgroups(0, NULL) < 0)
		die("slock: setgroups: %s\n", strerror(errno));
	if (setgid(dgid) < 0)
		die("slock: setgid: %s\n", strerror(errno));
	if (setuid(duid) < 0)
		die("slock: setuid: %s\n", strerror(errno));

	config_init(dpy);

	/* Screenshot the desktop and blur/pixelate it for use as the lock
	 * background (see config.h's BLUR/PIXELATION/blurRadius/pixelSize).
	 * image stays NULL (and every lock falls back to a solid color,
	 * see lockscreen()/readpw()) if this capture fails for any reason. */
	{
		Screen *scr = ScreenOfDisplay(dpy, DefaultScreen(dpy));
		image = imlib_create_image(scr->width, scr->height);
		if (image) {
			imlib_context_set_image(image);
			imlib_context_set_display(dpy);
			imlib_context_set_visual(DefaultVisual(dpy, 0));
			imlib_context_set_drawable(RootWindow(dpy, XScreenNumberOfScreen(scr)));
			imlib_copy_drawable_to_image(0, 0, 0, scr->width, scr->height, 0, 0, 1);

#ifdef BLUR
			imlib_image_blur(blurRadius);
#endif
#ifdef PIXELATION
			{
				int width = scr->width, height = scr->height;
				int x, y, i, j;
				for (y = 0; y < height; y += pixelSize) {
					for (x = 0; x < width; x += pixelSize) {
						long red = 0, green = 0, blue = 0, n = 0;
						Imlib_Color pixel;
						for (j = 0; j < pixelSize && y + j < height; j++) {
							for (i = 0; i < pixelSize && x + i < width; i++) {
								imlib_image_query_pixel(x + i, y + j, &pixel);
								red += pixel.red;
								green += pixel.green;
								blue += pixel.blue;
								n++;
							}
						}
						if (n > 0) {
							imlib_context_set_color((int)(red / n), (int)(green / n), (int)(blue / n), 255);
							imlib_image_fill_rectangle(x, y, pixelSize, pixelSize);
						}
					}
				}
			}
#endif

			/* Darken on top of the blur/pixelation (see config.h's
			 * dimAlpha for why blur alone isn't sufficient). Blend
			 * mode is required for the alpha channel of the fill
			 * color to actually mix with the image instead of
			 * replacing it outright. */
			if (dimAlpha > 0) {
				imlib_context_set_blend(1);
				imlib_context_set_color(0, 0, 0, dimAlpha);
				imlib_image_fill_rectangle(0, 0, scr->width, scr->height);
			}
		}
	}

	/* check for Xrandr support */
	rr.active = XRRQueryExtension(dpy, &rr.evbase, &rr.errbase);

	/* get number of screens in display "dpy" and blank them */
	nscreens = ScreenCount(dpy);
	if (!(locks = calloc(nscreens, sizeof(struct lock *))))
		die("slock: out of memory\n");
	for (nlocks = 0, s = 0; s < nscreens; s++) {
		if ((locks[s] = lockscreen(dpy, &rr, s)) != NULL) {
			writemessage(dpy, locks[s]->win, s, locks[s]->colors[INIT]);
			nlocks++;
		} else {
			break;
		}
	}
	XSync(dpy, 0);

	/* did we manage to lock everything? */
	if (nlocks != nscreens)
		return 1;

	/* DPMS magic to disable the monitor -- treated as optional. The
	 * screen is already locked and grabbed above (lockscreen()); DPMS
	 * only controls whether the monitor auto-blanks while locked.
	 * Verified for real on an X server with no DPMS extension at all
	 * (Xvfb): die()'ing here closes the display connection, and the X
	 * server releases every grab and destroys the lock windows as part
	 * of normal client-death cleanup -- silently unlocking the screen
	 * seconds after it appeared to lock. A monitor power-saving nicety
	 * must never be able to defeat the actual lock. */
	if (!DPMSCapable(dpy))
		fprintf(stderr, "slock: DPMSCapable failed, monitor will not auto-blank\n");
	else if (!DPMSEnable(dpy))
		fprintf(stderr, "slock: DPMSEnable failed, monitor will not auto-blank\n");
	else if (!DPMSGetTimeouts(dpy, &standby, &suspend, &off))
		fprintf(stderr, "slock: DPMSGetTimeouts failed, monitor will not auto-blank\n");
	else if (!standby || !suspend || !off)
		fprintf(stderr, "slock: at least one DPMS variable is zero, monitor will not auto-blank\n");
	else if (!DPMSSetTimeouts(dpy, monitortime, monitortime, monitortime))
		fprintf(stderr, "slock: DPMSSetTimeouts failed, monitor will not auto-blank\n");
	else
		dpms_ok = 1;

	XSync(dpy, 0);

	/* run post-lock command */
	if (argc > 0) {
		switch (fork()) {
		case -1:
			die("slock: fork failed: %s\n", strerror(errno));
		case 0:
			if (close(ConnectionNumber(dpy)) < 0)
				die("slock: close: %s\n", strerror(errno));
			execvp(argv[0], argv);
			fprintf(stderr, "slock: execvp %s: %s\n", argv[0], strerror(errno));
			_exit(1);
		}
	}

	/* everything is now blank. Wait for the correct password */
	readpw(dpy, &rr, locks, nscreens, hash);

	/* reset DPMS values to inital ones */
	if (dpms_ok)
		DPMSSetTimeouts(dpy, standby, suspend, off);
	XSync(dpy, 0);

	return 0;
}
