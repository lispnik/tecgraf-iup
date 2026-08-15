/* Measures what IupMglPlot really renders, from inside the mglplot sample.
 *
 * The sample is what this has to run against. MathGL's OpenGL canvas was losing most of its
 * geometry to a clip volume its own projection never widened -- a bar chart drew nothing at
 * all, and a line plot kept only its legend -- but a plot built by hand for a harness does not
 * reproduce it: the plots that failed are the ones the sample builds, and every synthetic
 * stand-in tried (line, bars, crossed origin, tall canvas, inside tabs) rendered fine either
 * way. So the sample's own plots are the specimen, and this is injected into it.
 *
 * The measurement is taken where the frame certainly exists: MathGL ends a render with
 * glFinish(), so the back buffer is read there, before the swap and before the window server
 * has any say in whether the surface is composited. Reading the front buffer afterwards
 * measures the compositor as much as the plot, and reading at the view's size rather than the
 * viewport's samples a corner of it on a retina display -- both of which have produced
 * confident nonsense here before.
 *
 *   usage: injected by run_mglsample.sh; every tab is selected in turn and its ink reported.
 */
#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <iup.h>
#include "iup_object.h"

/* Ink measured before and after the clip fix, per tab of the sample, on a 149366-pixel canvas:
 *
 *      tab      0      1        2      3       4      5
 *      before   600    149366   1872   0       1092   359
 *      after    5359   149366   2731   33712   8327   9345
 *
 * Tab 1 is the sample's cyan-background plot, so it fills the canvas either way and says
 * nothing. The threshold is a fraction of the canvas rather than a count, because the canvas
 * size follows the window: one percent clears every "after" figure by at least 1.8x and catches
 * four of the five "before" ones outright. Tab 2 is a sparse plot whose ink barely moved and is
 * not a strong signal either way; the tabs that went blank -- 0, 3 and 5 -- are. */
#define MIN_INK_FRACTION 0.01

static int g_failures = 0;
static int g_tab = -1;
static int g_measured = 0;

static void chk(int condition, const char* what, const char* detail)
{
  printf("%-4s %-52s %s\n", condition ? "ok" : "FAIL", what, detail ? detail : "");
  fflush(stdout);
  if (!condition)
    g_failures++;
}

/* MathGL's render ends here. */
static void my_glFinish(void)
{
  GLint viewport[4] = {0, 0, 0, 0};
  unsigned char* pixels;
  int width, height, i, ink = 0;
  char what[64], detail[128];

  glFinish();

  if (g_tab < 0 || g_measured)
    return;

  glGetIntegerv(GL_VIEWPORT, viewport);
  width = viewport[2];
  height = viewport[3];
  if (width <= 0 || height <= 0)
    return;

  pixels = (unsigned char*)malloc((size_t)width * height * 3);
  glReadBuffer(GL_BACK);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadPixels(0, 0, width, height, GL_RGB, GL_UNSIGNED_BYTE, pixels);

  for (i = 0; i < width * height; i++)
  {
    unsigned char r = pixels[i*3], g = pixels[i*3+1], b = pixels[i*3+2];
    if (!(r > 245 && g > 245 && b > 245))
      ink++;
  }
  free(pixels);

  {
    int minimum = (int)(width * height * MIN_INK_FRACTION);

    snprintf(what, sizeof what, "tab %d renders its plot", g_tab);
    snprintf(detail, sizeof detail, "ink=%d of %d, threshold %d", ink, width * height, minimum);
    chk(ink >= minimum, what, detail);
  }

  g_measured = 1;
}

__attribute__((used)) static struct { const void* replacement; const void* replacee; }
  interposers[] __attribute__((section("__DATA,__interpose"))) = {
    { (const void*)(unsigned long)&my_glFinish, (const void*)(unsigned long)&glFinish } };

extern Ihandle* iupDlgListFirst(void);
extern Ihandle* iupDlgListNext(void);

#define MAX_PLOTS 16
static Ihandle* g_plots[MAX_PLOTS];
static int g_plot_count = 0;

/* In tab order: the plots are collected by walking the dialog, and each tab page holds one. */
static void collect_plots(Ihandle* ih)
{
  Ihandle* child;

  if (!ih)
    return;
  if (0 == strcmp(IupGetClassName(ih), "mglplot") && g_plot_count < MAX_PLOTS)
    g_plots[g_plot_count++] = ih;

  for (child = IupGetNextChild(ih, NULL); child; child = IupGetNextChild(ih, child))
    collect_plots(child);
}

static Ihandle* find_class(Ihandle* ih, const char* class_name)
{
  Ihandle* child;

  if (!ih)
    return NULL;
  if (0 == strcmp(IupGetClassName(ih), class_name))
    return ih;

  for (child = IupGetNextChild(ih, NULL); child; child = IupGetNextChild(ih, child))
  {
    Ihandle* found = find_class(child, class_name);
    if (found)
      return found;
  }
  return NULL;
}

/* IupTabs hands back an NSTabViewController, so the tab view is one step further in. Selecting
   through it is what a click does; setting VALUEPOS would test IUP talking to itself. */
static NSTabView* tab_view_of(Ihandle* tabs)
{
  id root = (id)tabs->handle;

  if ([root isKindOfClass:[NSViewController class]])
    root = [(NSViewController*)root view];
  if ([root isKindOfClass:[NSTabView class]])
    return root;

  for (NSView* sub in [(NSView*)root subviews])
    if ([sub isKindOfClass:[NSTabView class]])
      return (NSTabView*)sub;

  return nil;
}

__attribute__((constructor)) static void mgl_probe_init(void)
{
  if (!getenv("MGL_TEST"))
    return;

  /* let the sample build its plots and show its dialog */
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    Ihandle *dialog, *tabs = NULL;
    NSTabView* tab_view;
    NSUInteger count, i;

    for (dialog = iupDlgListFirst(); dialog && !tabs; dialog = iupDlgListNext())
    {
      tabs = find_class(dialog, "tabs");
      if (tabs)
        collect_plots(dialog);
    }

    if (!tabs || !(tab_view = tab_view_of(tabs)))
    {
      chk(0, "the sample's tabs were found", NULL);
      printf("%d failure(s)\n", g_failures);
      exit(g_failures ? g_failures : 1);
    }

    count = [[tab_view tabViewItems] count];
    for (i = 0; i < count; i++)
    {
      g_tab = (int)i;
      g_measured = 0;
      [tab_view selectTabViewItemAtIndex:i];

      /* Ask for the repaint rather than relying on the selection to produce one: the tab the
         sample opens on is already selected, and selecting it again is not an expose. */
      if ((int)i < g_plot_count)
        IupRedraw(g_plots[i], 0);

      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.6]];

      if (!g_measured)
      {
        char what[64];
        snprintf(what, sizeof what, "tab %d renders its plot", (int)i);
        chk(0, what, "no render happened at all");
      }
    }

    printf("%d failure(s)\n", g_failures);
    fflush(stdout);
    exit(g_failures);
  });
}
