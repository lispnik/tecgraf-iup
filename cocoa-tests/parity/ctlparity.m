/* The four controls with no harness at all: IupCanvas, IupVal, IupProgressBar, IupTabs.

   audit_disabled.py can only prove an attribute is registered. IupText showed how little that
   proves -- it registered a live handler for everything GTK does and still had five real
   bugs, including a caret setter parsing its value with the wrong separator so every
   assignment was silently discarded. So this asserts native state: the NSSlider's
   doubleValue, the NSProgressIndicator's indeterminate flag, the NSTabView's item labels.

   Attributes either driver marks IUPAF_NOT_SUPPORTED are not asserted: that flag is a
   declaration of a known absence, and checking it would only re-state the declaration. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <string.h>
#include <iup.h>
#include "iup_object.h"

static int g_gaps = 0;
static Ihandle *dlg, *canvas, *val, *pbar, *marquee_bar, *tabs, *tab1, *tab2;

static void chk(int c, const char* w, const char* g)
{ printf("%-4s %-52s %s\n", c ? "ok  " : "GAP ", w, g ? g : ""); fflush(stdout); if (!c) g_gaps++; }

/* ih->handle is the outermost view; several controls nest their real one inside. */
static id nativeOfClass(Ihandle* ih, Class wanted)
{
  id root = (id)ih->handle;
  if (root == nil) return nil;
  if ([root isKindOfClass:wanted]) return root;
  if ([root isKindOfClass:[NSScrollView class]])
  { id doc = [(NSScrollView*)root documentView];
    if ([doc isKindOfClass:wanted]) return doc; }
  /* ih->handle is not always an NSView -- IupTabs hands back a view controller, and a
     dialog with TRAY is an NSStatusItem -- so -subviews must not be sent blind. */
  if (![root isKindOfClass:[NSView class]])
  {
    if ([root respondsToSelector:@selector(view)])
    { id v = [root performSelector:@selector(view)];
      if ([v isKindOfClass:wanted]) return v;
      root = v; }
    else return nil;
  }
  if (![root isKindOfClass:[NSView class]]) return nil;
  for (NSView* sub in [(NSView*)root subviews])
  { if ([sub isKindOfClass:wanted]) return sub;
    for (NSView* deeper in [sub subviews])
    { if ([deeper isKindOfClass:wanted]) return deeper;
      for (NSView* deepest in [deeper subviews])
        if ([deepest isKindOfClass:wanted]) return deepest; } }
  return nil;
}

static int run(Ihandle* t)
{
  char buf[300];
  static int running = 0; if (running) return IUP_DEFAULT; running = 1;
  IupSetAttribute(t, "RUN", "NO");

  /* ================= IupVal -> NSSlider ================= */
  NSSlider* slider = (NSSlider*)nativeOfClass(val, [NSSlider class]);
  chk(slider != nil, "IupVal is an NSSlider",
      slider ? [[slider className] UTF8String] : "not found");

  if (slider)
  {
    { IupSetAttribute(val, "MIN", "10");
      IupSetAttribute(val, "MAX", "50");
      snprintf(buf, sizeof buf, "native min=%.0f max=%.0f", [slider minValue], [slider maxValue]);
      chk([slider minValue] == 10 && [slider maxValue] == 50,
          "MIN/MAX reach the slider", buf); }

    { IupSetAttribute(val, "VALUE", "25");
      snprintf(buf, sizeof buf, "native doubleValue=%.1f", [slider doubleValue]);
      chk([slider doubleValue] > 24.5 && [slider doubleValue] < 25.5,
          "VALUE reaches the slider", buf); }

    /* iupValGetValueAttrib is shared and returns ih->data->val, the cached value -- both
       backends update it from the setter and from the action callback, not by polling the
       widget. So this asserts the IUP round trip, not that a programmatic poke at the
       NSSlider is visible through IUP, which neither driver promises. */
    { IupSetAttribute(val, "VALUE", "37");
      char* v = IupGetAttribute(val, "VALUE");
      double back = v ? atof(v) : -1;
      snprintf(buf, sizeof buf, "VALUE='%s', native=%.1f", v ? v : "(null)", [slider doubleValue]);
      chk(back > 36.5 && back < 37.5 && [slider doubleValue] > 36.5,
          "VALUE round-trips and matches the slider", buf); }

    { IupSetAttribute(val, "SHOWTICKS", "5");
      NSInteger ticks = [slider numberOfTickMarks];
      snprintf(buf, sizeof buf, "numberOfTickMarks=%ld", (long)ticks);
      chk(ticks == 5, "SHOWTICKS sets the tick marks", buf); }

    { IupSetAttribute(val, "STEPONTICKS", "YES");
      BOOL only = [slider allowsTickMarkValuesOnly];
      IupSetAttribute(val, "STEPONTICKS", "NO");
      snprintf(buf, sizeof buf, "allowsTickMarkValuesOnly %d -> %d",
               only, [slider allowsTickMarkValuesOnly]);
      chk(only && ![slider allowsTickMarkValuesOnly],
          "STEPONTICKS controls tick-only values", buf); }
  }

  /* ============ IupProgressBar -> NSProgressIndicator ============ */
  NSProgressIndicator* pi = (NSProgressIndicator*)nativeOfClass(pbar, [NSProgressIndicator class]);
  chk(pi != nil, "IupProgressBar is an NSProgressIndicator",
      pi ? [[pi className] UTF8String] : "not found");

  if (pi)
  {
    { IupSetAttribute(pbar, "MIN", "0");
      IupSetAttribute(pbar, "MAX", "200");
      IupSetAttribute(pbar, "VALUE", "50");
      snprintf(buf, sizeof buf, "native doubleValue=%.1f (min=%.0f max=%.0f)",
               [pi doubleValue], [pi minValue], [pi maxValue]);
      chk([pi doubleValue] > 49.0 && [pi doubleValue] < 51.0,
          "VALUE reaches the progress indicator", buf); }

    /* MARQUEE is creation-time on both backends -- gtkProgressBarSetMarqueeAttrib and the
       Cocoa setter open with the same "if (!ih->data->marquee) return 0" guard, and the map
       method is what calls -setIndeterminate:. So it has to be set before mapping; asserting
       a post-map switch tests something neither driver claims to do. */
    { NSProgressIndicator* mpi = (NSProgressIndicator*)nativeOfClass(marquee_bar,
                                                                    [NSProgressIndicator class]);
      snprintf(buf, sizeof buf, "isIndeterminate=%d", mpi ? [mpi isIndeterminate] : -1);
      chk(mpi != nil && [mpi isIndeterminate],
          "MARQUEE set before map gives an indeterminate bar", buf); }
  }

  /* ================= IupTabs -> NSTabView ================= */
  NSTabView* tab_view = (NSTabView*)nativeOfClass(tabs, [NSTabView class]);
  chk(tab_view != nil, "IupTabs is an NSTabView",
      tab_view ? [[tab_view className] UTF8String] : "not found");

  if (tab_view)
  {
    { NSInteger count = [tab_view numberOfTabViewItems];
      snprintf(buf, sizeof buf, "numberOfTabViewItems=%ld (want 2)", (long)count);
      chk(count == 2, "each child becomes a tab view item", buf); }

    { IupSetAttributeId(tabs, "TABTITLE", 0, "First");
      IupSetAttributeId(tabs, "TABTITLE", 1, "Second");
      NSString* a = [[tab_view tabViewItemAtIndex:0] label];
      NSString* b = [[tab_view tabViewItemAtIndex:1] label];
      snprintf(buf, sizeof buf, "labels='%s','%s'",
               a ? [a UTF8String] : "(nil)", b ? [b UTF8String] : "(nil)");
      chk(a && b && 0 == strcmp([a UTF8String], "First")
          && 0 == strcmp([b UTF8String], "Second"),
          "TABTITLE reaches the tab view items", buf); }

    /* This backend builds tabs from an NSTabViewController with a segmented control, so the
       strip position is its tabStyle -- the inner NSTabView is deliberately NSNoTabsNoBorder
       and its tabViewType never changes. Asserting tabViewType tests the wrong object. */
    { NSTabViewController* controller = (NSTabViewController*)tabs->handle;
      IupSetAttribute(tabs, "TABTYPE", "BOTTOM");
      NSTabViewControllerTabStyle bottom = [controller tabStyle];
      IupSetAttribute(tabs, "TABTYPE", "TOP");
      NSTabViewControllerTabStyle top = [controller tabStyle];
      snprintf(buf, sizeof buf, "tabStyle bottom=%ld top=%ld",
               (long)bottom, (long)top);
      chk(bottom == NSTabViewControllerTabStyleSegmentedControlOnBottom
          && top == NSTabViewControllerTabStyleSegmentedControlOnTop,
          "TABTYPE moves the segmented control", buf); }

    { IupSetAttribute(tabs, "VALUEPOS", "1");
      NSTabViewItem* selected = [tab_view selectedTabViewItem];
      NSInteger index = selected ? [tab_view indexOfTabViewItem:selected] : -1;
      snprintf(buf, sizeof buf, "selected index=%ld (want 1)", (long)index);
      chk(index == 1, "VALUEPOS selects the tab natively", buf); }

    /* TABTIP is deliberately not asserted. It is implemented only by IupFlatTabs
       (iup_flattabs.c) -- neither the GTK nor the Windows native tabs register it -- so on
       every backend setting it just parks a string in the hash table. This driver has a
       cocoaTabsSetTabTipAttrib written but gated behind "#define IUPCOCOA_ENABLE_TABTIP 0",
       with the author's note that it produced no visible result: NSTabViewItem.toolTip does
       set (verified directly), but the segmented control an NSTabViewController draws does
       not surface it. Testing it would assert a feature no backend claims. */
  }

  /* ================= IupCanvas ================= */
  { NSView* cv = (NSView*)canvas->handle;
    chk(cv != nil, "IupCanvas has a native view",
        cv ? [[cv className] UTF8String] : "not found"); }

  { char* ds = IupGetAttribute(canvas, "DRAWSIZE");
    int w = 0, h = 0; if (ds) sscanf(ds, "%dx%d", &w, &h);
    snprintf(buf, sizeof buf, "DRAWSIZE=%s", ds ? ds : "(null)");
    chk(ds && w > 0 && h > 0, "DRAWSIZE reports the drawable area", buf); }

  /* A scrolled canvas must report the scrollbar it was created with, and DX/DY must reach
     the native scrollers -- iupdrvCanvasInitClass derives SCROLLBAR from ih->data->sb. */
  { char* sb = IupGetAttribute(canvas, "SCROLLBAR");
    snprintf(buf, sizeof buf, "SCROLLBAR=%s", sb ? sb : "(null)");
    chk(sb && (0 == strcmp(sb, "YES") || 0 == strcmp(sb, "Yes")),
        "a scrolled canvas reports its scrollbar", buf); }

  { NSScrollView* sv = [(id)canvas->handle isKindOfClass:[NSScrollView class]]
                       ? (NSScrollView*)canvas->handle : nil;
    snprintf(buf, sizeof buf, "%s, vertical scroller=%s",
             [[(id)canvas->handle className] UTF8String],
             (sv && [sv hasVerticalScroller]) ? "yes" : "no");
    chk(sv != nil && [sv hasVerticalScroller],
        "it is backed by an NSScrollView with real scrollers", buf); }

  { IupSetAttribute(canvas, "XMIN", "0");
    IupSetAttribute(canvas, "XMAX", "1000");
    IupSetAttribute(canvas, "DX", "100");
    char* dx = IupGetAttribute(canvas, "DX");
    snprintf(buf, sizeof buf, "DX reads back as '%s'", dx ? dx : "(null)");
    chk(dx && atof(dx) > 99.0 && atof(dx) < 101.0, "DX round-trips", buf); }

  printf("%d gap(s)\n", g_gaps);
  IupExitLoop();
  return IUP_DEFAULT;
}

int main(int argc, char** argv)
{
  IupOpen(&argc, &argv);

  canvas = IupCanvas(NULL);
  IupSetAttribute(canvas, "SCROLLBAR", "YES");
  IupSetAttribute(canvas, "RASTERSIZE", "150x100");

  val = IupVal("HORIZONTAL");
  pbar = IupProgressBar();

  marquee_bar = IupProgressBar();
  IupSetAttribute(marquee_bar, "MARQUEE", "YES");   /* must precede the map */

  tab1 = IupVbox(IupLabel("one"), NULL);
  tab2 = IupVbox(IupLabel("two"), NULL);
  tabs = IupTabs(tab1, tab2, NULL);
  IupSetAttribute(tabs, "RASTERSIZE", "200x100");

  dlg = IupDialog(IupVbox(canvas, val, pbar, marquee_bar, tabs, NULL));
  IupSetAttribute(dlg, "TITLE", "ctlparity");
  IupShowXY(dlg, IUP_CENTER, IUP_CENTER);

  Ihandle* t = IupTimer();
  IupSetAttribute(t, "TIME", "700");
  IupSetCallback(t, "ACTION_CB", (Icallback)run);
  IupSetAttribute(t, "RUN", "YES");
  IupMainLoop();
  IupClose();
  return g_gaps ? 1 : 0;
}
