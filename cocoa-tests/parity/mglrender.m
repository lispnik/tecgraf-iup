/* IupMglPlot in OpenGL mode: every frame that reaches the screen must have been rendered.
 *
 * A GL canvas keeps its picture in the back buffer, and swapping makes those contents
 * undefined -- there is nothing to show a second time. iMglPlotRepaint used to skip the render
 * when nothing had changed and swap anyway, which put whichever buffer came round on screen:
 * the frame before last, or nothing at all. Clicking through a tab set full of plots blanked
 * them and brought them back, one buffer at a time.
 *
 * There is no native control to interrogate here -- what MathGL produces is pixels in a GL
 * surface -- but there is an event that says a render happened: POSTDRAW_CB fires from
 * iMglPlotDrawPlot, once per actual render and never for a bare swap. Counting it across
 * repeated exposes with nothing changed in between is exactly the distinction that was wrong.
 *
 * The other half of the same investigation, MathGL's geometry being clipped away by a z range
 * its own projection never widened, is not asserted here: it needs the plots the sample builds
 * and could not be reproduced with a synthetic one, so it is measured against the sample itself
 * in cocoa-tests/run_mglsample.sh.
 */
#import <Cocoa/Cocoa.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <iup.h>
#include <iupgl.h>
#include <iup_mglplot.h>

static int g_gaps = 0;
static int g_renders = 0;
static Ihandle *dlg, *plot;

static void chk(int condition, const char* what, const char* detail)
{
  printf("%-4s %-52s %s\n", condition ? "ok  " : "GAP ", what, detail ? detail : "");
  fflush(stdout);
  if (!condition)
    g_gaps++;
}

static int postdraw_cb(Ihandle* ih)
{
  (void)ih;
  g_renders++;
  return IUP_DEFAULT;
}

static int run(Ihandle* timer)
{
  static int running = 0; if (running) return IUP_DEFAULT; running = 1;
  IupSetAttribute(timer, "RUN", "NO");

  char buf[256];
  int first, second;

  g_renders = 0;
  IupRedraw(plot, 0);
  first = g_renders;

  /* Nothing has changed in between, which is the whole point: this is the expose that used to
     be answered with a swap and no render. */
  g_renders = 0;
  IupRedraw(plot, 0);
  second = g_renders;

  snprintf(buf, sizeof buf, "renders: first expose %d, second %d", first, second);
  chk(first >= 1 && second >= 1, "a GL plot renders on every expose", buf);

  printf("%d gap(s)\n", g_gaps);
  IupExitLoop();
  return IUP_DEFAULT;
}

int main(int argc, char** argv)
{
  Ihandle* timer;
  int i;

  setvbuf(stdout, NULL, _IONBF, 0);
  IupOpen(&argc, &argv);
  IupMglPlotOpen();

  plot = IupMglPlot();
  IupSetAttribute(plot, "OPENGL", "YES");
  IupSetAttribute(plot, "RASTERSIZE", "300x240");
  IupSetCallback(plot, "POSTDRAW_CB", (Icallback)postdraw_cb);

  IupMglPlotBegin(plot, 1);
  for (i = 0; i < 40; i++)
    IupMglPlotAdd1D(plot, NULL, (double)i * (double)i);
  IupMglPlotEnd(plot);
  IupSetAttribute(plot, "DS_COLOR", "255 0 0");

  dlg = IupDialog(plot);
  IupSetAttribute(dlg, "TITLE", "mglplot render");
  IupShowXY(dlg, IUP_CENTER, IUP_CENTER);

  timer = IupTimer();
  IupSetAttribute(timer, "TIME", "1200");
  IupSetCallback(timer, "ACTION_CB", (Icallback)run);
  IupSetAttribute(timer, "RUN", "YES");

  IupMainLoop();
  IupClose();
  return g_gaps ? 1 : 0;
}
