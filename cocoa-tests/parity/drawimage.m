/* IupDrawImage: the natural-size contract, and row-stride correctness across widths.

   Both bugs behind IupColorBrowser's blank/sheared colour wheel are pinned here:

   * w/h of -1 mean "the image's own size" (see iupgtk_draw_cairo.c and iupwin_draw_gdi.c,
     which both special-case -1 and 0). Cocoa passed them into NSMakeRect and drew nothing.
   * NSBitmapImageRep pads rows to a 4-byte boundary. The conversion walked the destination
     with a bound derived from that padded stride and never returned to the row start, so
     every row slipped by the padding and the image sheared. Only widths where width*bpp is
     already a multiple of 4 escaped -- which is why most images looked fine and the 181px
     colour browser did not. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <iup.h>
#include <iupdraw.h>
#include "iup_object.h"

static int g_gaps = 0;
static Ihandle *dlg, *canvas;

/* deliberately mixed: 64 and 68 are 4-byte aligned at 24bpp, 65/66/181 are not */
static const int k_widths[] = { 64, 65, 66, 181, 68 };
#define NWIDTHS ((int)(sizeof k_widths / sizeof k_widths[0]))
#define CELL 200   /* each image is drawn into its own CELL-wide column */

static void chk(int c, const char* w, const char* g)
{ printf("%-4s %-52s %s\n", c ? "ok  " : "GAP ", w, g ? g : ""); if (!c) g_gaps++; }

/* Green left half, red right half. The vertical boundary is what makes shear visible: a
   row that slips by the padding moves the boundary sideways, and the slip accumulates, so
   by the last row it is displaced far enough to be unmistakable. A solid field, or a single
   marker pixel, would hide exactly this. */
static void make_image(int i)
{
  int size = k_widths[i];
  unsigned char* data = (unsigned char*)malloc(size * size * 3);
  char name[16];
  int x, y;
  for (y = 0; y < size; y++)
  { for (x = 0; x < size; x++)
    { int k = (y * size + x) * 3;
      int green = x < size / 2;
      data[k] = green ? 0 : 255; data[k+1] = green ? 255 : 0; data[k+2] = 0; } }
  snprintf(name, sizeof name, "stride%d", i);
  IupSetHandle(name, IupImageRGB(size, size, data));
}

/* The capture is colour-managed: pure red comes back as roughly (0.94, 0.29, 0.18) and pure
   green as (0.49, 0.95, 0.31), so neither absolute levels nor a ratio test work. Which
   channel leads, by a clear margin, is the reliable signal. */
static int is_red(NSColor* c)
{ return [c redComponent] > [c greenComponent] + 0.25 && [c redComponent] > [c blueComponent]; }
static int is_green(NSColor* c)
{ return [c greenComponent] > [c redComponent] + 0.25 && [c greenComponent] > [c blueComponent]; }

static int draw_cb(Ihandle* ih)
{
  int i;
  IupDrawBegin(ih);
  IupDrawParentBackground(ih);
  for (i = 0; i < NWIDTHS; i++)
  { char name[16]; snprintf(name, sizeof name, "stride%d", i);
    IupDrawImage(ih, name, i * CELL, 0, -1, -1); }   /* -1 = natural size */
  IupDrawEnd(ih);
  return IUP_DEFAULT;
}

static int run(Ihandle* t)
{
  char buf[240];
  int i;
  static int running = 0; if (running) return IUP_DEFAULT; running = 1;
  IupSetAttribute(t, "RUN", "NO");

  NSView* view = (NSView*)canvas->handle;
  NSBitmapImageRep* rep = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
  [view cacheDisplayInRect:[view bounds] toBitmapImageRep:rep];
  CGFloat scale = [rep pixelsWide] / [view bounds].size.width;   /* Retina backing */
  if (getenv("DRAWIMAGE_DUMP"))
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:[NSString stringWithUTF8String:getenv("DRAWIMAGE_DUMP")] atomically:YES];

  for (i = 0; i < NWIDTHS; i++)
  {
    int size = k_widths[i];
    int base = i * CELL;
    int aligned = ((size * 3) % 4) == 0;
    int half = size / 2;

#define SAMPLE(px, py) [[rep colorAtX:(NSInteger)(((px) * scale) + scale/2) \
                                    y:(NSInteger)(((py) * scale) + scale/2)] \
                         colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]]

    /* (a) drawn at all, at its own size: inside the far corner is red, past it is neither. */
    NSColor* inside = SAMPLE(base + size - 3, size - 3);
    NSColor* beyond = SAMPLE(base + size + 6, size - 3);
    snprintf(buf, sizeof buf, "%dx%d (%s): inside=%s beyond=%s", size, size,
             aligned ? "aligned" : "unaligned",
             is_red(inside) ? "red" : "not-red",
             (is_red(beyond) || is_green(beyond)) ? "image" : "background");
    chk(is_red(inside) && !is_red(beyond) && !is_green(beyond),
        "drawn at its natural size when w/h are -1", buf);

    /* (b) the green/red boundary sits at the same x on the first and last rows. Shear moves
           it by the accumulated padding, which over `size` rows is enormous. */
    NSColor* top_left    = SAMPLE(base + half - 3, 2);
    NSColor* top_right   = SAMPLE(base + half + 3, 2);
    NSColor* bot_left    = SAMPLE(base + half - 3, size - 3);
    NSColor* bot_right   = SAMPLE(base + half + 3, size - 3);
    int top_ok = is_green(top_left) && is_red(top_right);
    int bot_ok = is_green(bot_left) && is_red(bot_right);
    snprintf(buf, sizeof buf, "%dx%d boundary at x=%d: first row %s, last row %s",
             size, size, half, top_ok ? "ok" : "moved", bot_ok ? "ok" : "moved");
    chk(top_ok && bot_ok, "rows are not sheared by the 4-byte row padding", buf);

#undef SAMPLE
  }

  printf("%d gap(s)\n", g_gaps);
  IupExitLoop();
  return IUP_DEFAULT;
}

int main(int argc, char** argv)
{
  int i;
  IupOpen(&argc, &argv);
  for (i = 0; i < NWIDTHS; i++) make_image(i);

  canvas = IupCanvas(NULL);
  IupSetStrf(canvas, "RASTERSIZE", "%dx%d", NWIDTHS * CELL, 200);
  IupSetCallback(canvas, "ACTION", (Icallback)draw_cb);

  dlg = IupDialog(IupVbox(canvas, NULL));
  IupSetAttribute(dlg, "TITLE", "drawimage");
  IupShowXY(dlg, IUP_CENTER, IUP_CENTER);

  Ihandle* t = IupTimer();
  IupSetAttribute(t, "TIME", "700");
  IupSetCallback(t, "ACTION_CB", (Icallback)run);
  IupSetAttribute(t, "RUN", "YES");
  IupMainLoop();
  IupClose();
  return g_gaps ? 1 : 0;
}
