/* The reverse of every other harness here.
 *
 * The others set an attribute through IUP and check the native control changed. This one
 * changes the native control -- the way a click, a drag or a window resize does -- and then
 * asks IUP what it holds. A getter that answers with IUP's own last-set value rather than the
 * control's real state will disagree, and an application polling that attribute is being told
 * something untrue.
 *
 * Two things have to be right for the simulation to be fair, and both cost a wrong answer when
 * they are not:
 *
 *  - AppKit sends a control's action when the user works it. Setting a value programmatically
 *    does not, and the driver syncs IUP's copy from that action, so the action is sent here
 *    too. Without it IupVal reports 0 after the slider moves -- which says nothing about the
 *    driver, only about the shortcut.
 *  - ih->handle is not always the control, or even a view: single-line IupText is an
 *    NSStackView wrapping the field, lists and multiline text are scroll views, and IupTabs
 *    hands back an NSTabViewController. Each is searched for the real control.
 */
#import <Cocoa/Cocoa.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <iup.h>
#include <iupcontrols.h>
#include "iup_object.h"

static int g_gaps = 0;
static Ihandle *dlg, *text, *toggle, *val, *tabs, *list;

static void chk(int condition, const char* what, const char* detail)
{
  printf("%-4s %-52s %s\n", condition ? "ok  " : "GAP ", what, detail ? detail : "");
  fflush(stdout);
  if (!condition)
    g_gaps++;
}

static id find_view(id root, Class wanted)
{
  if (!root)
    return nil;
  if ([root isKindOfClass:wanted])
    return root;

  if ([root isKindOfClass:[NSViewController class]])
    root = [(NSViewController*)root view];

  if ([root isKindOfClass:[NSScrollView class]])
  {
    id document = [(NSScrollView*)root documentView];
    if ([document isKindOfClass:wanted])
      return document;
    root = document;
  }

  if (![root respondsToSelector:@selector(subviews)])
    return nil;

  for (NSView* sub in [(NSView*)root subviews])
  {
    id found = find_view(sub, wanted);
    if (found)
      return found;
  }

  return nil;
}

static id native_of(Ihandle* ih, Class wanted)
{
  return find_view((id)ih->handle, wanted);
}

static int run(Ihandle* timer)
{
  static int running = 0; if (running) return IUP_DEFAULT; running = 1;
  IupSetAttribute(timer, "RUN", "NO");

  char buf[256];

  /* text the user typed */
  { NSTextField* field = native_of(text, [NSTextField class]);
    char* value;
    if (!field) { chk(0, "IupText VALUE follows the field", "no NSTextField found"); }
    else
    {
      [field setStringValue:@"typed by hand"];
      value = IupGetAttribute(text, "VALUE");
      snprintf(buf, sizeof buf, "native=\"%s\" IUP=\"%s\"",
               [[field stringValue] UTF8String], value ? value : "(null)");
      chk(value && 0 == strcmp(value, "typed by hand"), "IupText VALUE follows the field", buf);
    } }

  /* a toggle the user clicked */
  { NSButton* button = native_of(toggle, [NSButton class]);
    char* value;
    if (!button) { chk(0, "IupToggle VALUE follows the button", "no NSButton found"); }
    else
    {
      [button setState:NSControlStateValueOn];
      [button sendAction:[button action] to:[button target]];
      value = IupGetAttribute(toggle, "VALUE");
      snprintf(buf, sizeof buf, "native state=%ld IUP=\"%s\"",
               (long)[button state], value ? value : "(null)");
      chk(value && 0 == strcmp(value, "ON"), "IupToggle VALUE follows the button", buf);
    } }

  /* a slider the user dragged */
  { NSSlider* slider = native_of(val, [NSSlider class]);
    char* value;
    if (!slider) { chk(0, "IupVal VALUE follows the slider", "no NSSlider found"); }
    else
    {
      [slider setDoubleValue:0.75];
      [slider sendAction:[slider action] to:[slider target]];
      value = IupGetAttribute(val, "VALUE");
      snprintf(buf, sizeof buf, "native=%.2f IUP=\"%s\"",
               [slider doubleValue], value ? value : "(null)");
      chk(value && atof(value) > 0.70 && atof(value) < 0.80, "IupVal VALUE follows the slider", buf);
    } }

  /* a tab the user selected */
  { NSTabView* tab_view = native_of(tabs, [NSTabView class]);
    char* value;
    if (!tab_view || [[tab_view tabViewItems] count] < 2)
    { chk(0, "IupTabs VALUEPOS follows the selection", "no NSTabView with two tabs"); }
    else
    {
      [tab_view selectTabViewItemAtIndex:1];   /* its delegate is what tells IUP */
      value = IupGetAttribute(tabs, "VALUEPOS");
      snprintf(buf, sizeof buf, "native index=%ld IUP VALUEPOS=\"%s\"",
               (long)[tab_view indexOfTabViewItem:[tab_view selectedTabViewItem]],
               value ? value : "(null)");
      chk(value && 0 == strcmp(value, "1"), "IupTabs VALUEPOS follows the selection", buf);
    } }

  /* a window the user resized */
  { NSWindow* window = (NSWindow*)dlg->handle;
    NSRect frame = [window frame];
    int width = 0, height = 0;

    frame.size.width += 60;
    frame.size.height += 40;
    [window setFrame:frame display:YES];

    IupGetIntInt(dlg, "RASTERSIZE", &width, &height);
    snprintf(buf, sizeof buf, "window=%.0fx%.0f IUP RASTERSIZE=%dx%d",
             [window frame].size.width, [window frame].size.height, width, height);
    chk(width >= (int)[window frame].size.width - 2, "IupDialog RASTERSIZE follows the window", buf); }

  /* a list row the user clicked */
  { NSTableView* table = native_of(list, [NSTableView class]);
    char* value;
    if (!table) { chk(0, "IupList VALUE follows the selection", "no NSTableView found"); }
    else
    {
      [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
      /* selecting programmatically posts no notification; a click does */
      [[NSNotificationCenter defaultCenter]
        postNotificationName:NSTableViewSelectionDidChangeNotification object:table];
      value = IupGetAttribute(list, "VALUE");
      snprintf(buf, sizeof buf, "native row=%ld IUP VALUE=\"%s\"",
               (long)[table selectedRow], value ? value : "(null)");
      chk(value && 0 == strcmp(value, "2"), "IupList VALUE follows the selection", buf);
    } }

  printf("%d gap(s)\n", g_gaps);
  IupExitLoop();
  return IUP_DEFAULT;
}

int main(int argc, char** argv)
{
  Ihandle *page1, *page2, *timer;

  setvbuf(stdout, NULL, _IONBF, 0);
  IupOpen(&argc, &argv);
  IupControlsOpen();

  text = IupText(NULL);
  IupSetAttribute(text, "VALUE", "set by IUP");

  toggle = IupToggle("toggle", NULL);
  val = IupVal("HORIZONTAL");

  page1 = IupVbox(IupLabel("one"), NULL); IupSetAttribute(page1, "TABTITLE", "One");
  page2 = IupVbox(IupLabel("two"), NULL); IupSetAttribute(page2, "TABTITLE", "Two");
  tabs = IupTabs(page1, page2, NULL);

  list = IupList(NULL);
  IupSetAttribute(list, "1", "alpha");
  IupSetAttribute(list, "2", "beta");
  IupSetAttribute(list, "VISIBLELINES", "3");

  dlg = IupDialog(IupVbox(text, toggle, val, tabs, list, NULL));
  IupSetAttribute(dlg, "TITLE", "native state");
  IupShowXY(dlg, IUP_CENTER, IUP_CENTER);

  timer = IupTimer();
  IupSetAttribute(timer, "TIME", "800");
  IupSetCallback(timer, "ACTION_CB", (Icallback)run);
  IupSetAttribute(timer, "RUN", "YES");

  IupMainLoop();
  IupClose();
  return g_gaps ? 1 : 0;
}
