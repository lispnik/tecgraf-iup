/* The SIZE="300x" / IupShow / SIZE=NULL idiom that plot.c and ten other samples use.
   Clearing SIZE is deliberate in the shared code (iup_dialog.c zeroes currentwidth/height
   "so the user or the natural size will be used to resize the dialog"), and the getters
   compensate by reading the driver when ih->handle exists. So this asserts the things that
   should hold AFTER the clear: the window must not move or resize, and IUP's reported size
   must still agree with the native window. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <iup.h>
#include "iup_object.h"

static int g_gaps = 0;
static Ihandle *dlg, *canvas;
static NSRect g_before;

static void chk(int c, const char* w, const char* g)
{ printf("%-4s %-52s %s\n", c ? "ok  " : "GAP ", w, g ? g : ""); if (!c) g_gaps++; }

static int run(Ihandle* t)
{
  char buf[240];
  static int running = 0; if (running) return IUP_DEFAULT; running = 1;
  IupSetAttribute(t, "RUN", "NO");
  NSWindow* w = (NSWindow*)dlg->handle;

  /* the clear itself -- everything below is state after it */
  IupSetAttribute(dlg, "SIZE", NULL);
  NSRect after = [w frame];

  snprintf(buf, sizeof buf, "%.0fx%.0f -> %.0fx%.0f",
           g_before.size.width, g_before.size.height, after.size.width, after.size.height);
  chk(after.size.width == g_before.size.width && after.size.height == g_before.size.height,
      "clearing SIZE does not resize the native window", buf);

  snprintf(buf, sizeof buf, "origin %.0f,%.0f -> %.0f,%.0f",
           g_before.origin.x, g_before.origin.y, after.origin.x, after.origin.y);
  chk(after.origin.x == g_before.origin.x && after.origin.y == g_before.origin.y,
      "clearing SIZE does not move the native window", buf);

  /* RASTERSIZE must still report the window, not the zeroed fields. This is what tells us
     whether the shared getters' ih->handle path is working on this driver. */
  { char* rs = IupGetAttribute(dlg, "RASTERSIZE");
    int rw = 0, rh = 0; if (rs) sscanf(rs, "%dx%d", &rw, &rh);
    snprintf(buf, sizeof buf, "RASTERSIZE=%s, window=%.0fx%.0f",
             rs ? rs : "(null)", after.size.width, after.size.height);
    chk(rw == (int)after.size.width && rh == (int)after.size.height,
        "RASTERSIZE still reports the real window after the clear", buf); }

  /* Clearing SIZE drops userwidth, so the next layout falls back to the NATURAL size -- that
     is the documented point of the idiom, not a bug: it lets the user shrink a dialog that
     was opened at a forced width. The canvas asks for 200, so the window must land there. */
  { IupRefresh(dlg);
    NSRect ref = [w frame];
    snprintf(buf, sizeof buf, "%.0fx%.0f -> %.0fx%.0f after IupRefresh (natural width 200)",
             after.size.width, after.size.height, ref.size.width, ref.size.height);
    chk(ref.size.width == 200, "IupRefresh after the clear falls back to natural size", buf); }

  /* the canvas must still fill the client area */
  { NSView* cv = [w contentView];
    NSRect cr = [cv frame];
    snprintf(buf, sizeof buf, "contentView=%.0fx%.0f", cr.size.width, cr.size.height);
    chk(cr.size.width > 0 && cr.size.height > 0, "client area is non-degenerate", buf); }

  /* SIZE is in quarter-character units, so everything sized that way is scaled by the font's
     "average character width" -- and what counts as average differs by platform. Windows uses
     TEXTMETRIC.tmAveCharWidth and GTK uses Pango's approximate_char_width, both lowercase
     weighted and both close to the width of 'x'. Averaging the whole alphabet instead, capitals
     included, made every such dialog about an eighth wider here than on the other platforms.
     Checked as a ratio so it holds for any font: derive the width IUP used from a dialog sized
     in characters, and compare it against the two candidates. */
  { Ihandle* sized = IupDialog(IupCanvas(NULL));
    double used, x_width, mixed_width;
    NSFont* font;
    int w = 0, h = 0;

    IupSetAttribute(sized, "SIZE", "300x");
    IupMap(sized);
    IupGetIntInt(sized, "RASTERSIZE", &w, &h);
    used = w / (300.0 / 4.0);

    font = [NSFont systemFontOfSize:13.0];
    { NSDictionary* attrs = @{NSFontAttributeName: font};
      x_width = [@"x" sizeWithAttributes:attrs].width;
      mixed_width = [@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
                      sizeWithAttributes:attrs].width / 52.0; }

    snprintf(buf, sizeof buf, "SIZE=300x gave %dpx, so charwidth=%.2f ('x' is %.2f, whole "
             "alphabet %.2f)", w, used, x_width, mixed_width);
    chk(used >= x_width - 1.0 && used <= x_width + 1.0,
        "character units are scaled by a lowercase-weighted width", buf);

    IupDestroy(sized); }

  printf("%d gap(s)\n", g_gaps);
  IupExitLoop();
  return IUP_DEFAULT;
}

int main(int argc, char** argv)
{
  IupOpen(&argc, &argv);
  canvas = IupCanvas(NULL);
  IupSetAttribute(canvas, "RASTERSIZE", "200x150");
  dlg = IupDialog(IupVbox(canvas, NULL));
  IupSetAttribute(dlg, "TITLE", "dlgsize");

  IupSetAttribute(dlg, "SIZE", "300x");          /* exactly what plot.c does */
  IupShowXY(dlg, IUP_CENTER, IUP_CENTER);
  g_before = [(NSWindow*)dlg->handle frame];

  Ihandle* t = IupTimer();
  IupSetAttribute(t, "TIME", "600");
  IupSetCallback(t, "ACTION_CB", (Icallback)run);
  IupSetAttribute(t, "RUN", "YES");
  IupMainLoop();
  IupClose();
  return g_gaps ? 1 : 0;
}
