/* What IupTabs asks for, and whether asking twice gives the same answer.
 *
 * A container's natural size is what the layout is built from, so it has to be a function of the
 * contents -- children plus the control's own decoration -- and nothing else. The Cocoa driver
 * derived it from the tab view's CURRENT FRAME instead:
 *
 *     final_h = iupMAX(children_naturalheight, [tab_view frame].size.height);
 *
 * which is circular, since that frame came from the previous natural size. Two things followed.
 * The answer drifted -- for a 300pt child it was 494, then 470, then 464 on successive passes --
 * so a dialog sized from one pass had its children laid out from another, and the difference
 * hung off the window. And the tab bar was never added to the children's height at all, so the
 * page was squeezed by exactly the height of the bar.
 *
 * That is what plot.app showed as a plot cut off until the window was resized.
 *
 * The bar's height is asserted against the native control rather than a constant: it is the
 * difference between the controller's view and the tab view inside it, because the segmented
 * control is a sibling of the tab view, not part of it. A hard-coded 30 would pass just as well
 * on this machine and say nothing about any other.
 */
#import <Cocoa/Cocoa.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <iup.h>
#include "iup_object.h"

#define PAGE_W 400
#define PAGE_H 300

static int g_gaps = 0;
static Ihandle *dlg, *tabs, *canvas;

static void chk(int condition, const char* what, const char* detail)
{
  printf("%-4s %-52s %s\n", condition ? "ok  " : "GAP ", what, detail ? detail : "");
  fflush(stdout);
  if (!condition)
    g_gaps++;
}

/* The tab bar, measured the only way it can be: the controller's view holds the segmented
   control and the tab view side by side, so the difference between them is the bar. */
static int native_bar_height(void)
{
  id controller = (id)tabs->handle;
  NSTabView* tab_view;
  NSView* controller_view;

  if (![controller respondsToSelector:@selector(tabView)])
    return -1;

  tab_view = [controller tabView];
  controller_view = [(NSViewController*)controller view];
  [controller_view layoutSubtreeIfNeeded];

  return (int)([controller_view frame].size.height - [tab_view frame].size.height);
}

static int run(Ihandle* timer)
{
  static int running = 0; if (running) return IUP_DEFAULT; running = 1;
  IupSetAttribute(timer, "RUN", "NO");

  char buf[256];
  int bar = native_bar_height();

  /* the bar is added to the page, not taken out of it */
  { int natural_h = tabs->naturalheight;

    snprintf(buf, sizeof buf, "page %d + bar %d = %d, natural height %d",
             PAGE_H, bar, PAGE_H + bar, natural_h);
    chk(bar > 0 && natural_h == PAGE_H + bar,
        "IupTabs adds the tab bar to its page", buf); }

  /* and asking again gives the same answer */
  { int first_w = tabs->naturalwidth,  first_h = tabs->naturalheight;
    int second_w, second_h, third_h;

    IupRefresh(dlg);
    second_w = tabs->naturalwidth; second_h = tabs->naturalheight;
    IupRefresh(dlg);
    third_h = tabs->naturalheight;

    snprintf(buf, sizeof buf, "%dx%d, then %dx%d, then height %d",
             first_w, first_h, second_w, second_h, third_h);
    chk(first_h == second_h && second_h == third_h && first_w == second_w,
        "and answers the same on every layout pass", buf); }

  /* the visible consequence: the page is inside the window, not hanging below it */
  { NSWindow* window = (NSWindow*)dlg->handle;
    NSView* content = [window contentView];
    NSView* page_view = (NSView*)canvas->handle;
    NSRect frame;

    if ([page_view isKindOfClass:[NSScrollView class]])
      page_view = [(NSScrollView*)page_view documentView];

    frame = [page_view convertRect:[page_view bounds] toView:content];

    snprintf(buf, sizeof buf, "page bottom %.0f, top %.0f, window content height %.0f",
             frame.origin.y, frame.origin.y + frame.size.height, [content bounds].size.height);
    chk(frame.origin.y >= -1 && frame.origin.y + frame.size.height <= [content bounds].size.height + 1,
        "the tab page fits inside the window", buf); }

  printf("%d gap(s)\n", g_gaps);
  IupExitLoop();
  return IUP_DEFAULT;
}

int main(int argc, char** argv)
{
  Ihandle *page, *timer;

  setvbuf(stdout, NULL, _IONBF, 0);
  IupOpen(&argc, &argv);

  canvas = IupCanvas(NULL);
  IupSetStrf(canvas, "RASTERSIZE", "%dx%d", PAGE_W, PAGE_H);

  page = IupVbox(canvas, NULL);
  IupSetAttribute(page, "TABTITLE", "One");
  tabs = IupTabs(page, NULL);

  /* No SIZE on the dialog: it must come up at its natural size, which is what is being
     asserted. A forced size would be honoured instead, and prove nothing. */
  dlg = IupDialog(tabs);
  IupSetAttribute(dlg, "TITLE", "tab size");
  IupShowXY(dlg, IUP_CENTER, IUP_CENTER);

  timer = IupTimer();
  IupSetAttribute(timer, "TIME", "800");
  IupSetCallback(timer, "ACTION_CB", (Icallback)run);
  IupSetAttribute(timer, "RUN", "YES");

  IupMainLoop();
  IupClose();
  return g_gaps ? 1 : 0;
}
