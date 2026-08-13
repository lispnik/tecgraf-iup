/* The IupDialog attributes audit_disabled.py found missing: BACKGROUND, HIDETITLEBAR,
   TRAYTIP and the TRAYCLICK_CB wiring, plus CUSTOMFRAME and SHAPEIMAGE as declared-only.

   TRAYCLICK_CB is the interesting one. It was registered inside an #if 0 block, and nothing
   was ever assigned as the status item's target/action -- so the callback could not fire
   however the application registered it. Checking that the callback is "known" would prove
   nothing; this invokes the button's action the way AppKit does and asserts the callback
   actually runs. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <string.h>
#include <iup.h>
#include "iup_object.h"

static int g_gaps = 0;
static int g_tray_clicks = 0;
static Ihandle *dlg, *tray_dlg;

static void chk(int c, const char* w, const char* g)
{ printf("%-4s %-52s %s\n", c ? "ok  " : "GAP ", w, g ? g : ""); fflush(stdout); if (!c) g_gaps++; }

static int tray_click_cb(Ihandle* ih, int button, int pressed, int dclick)
{ (void)ih; (void)button; (void)pressed; (void)dclick; g_tray_clicks++; return IUP_DEFAULT; }

static void rgb_of(NSColor* c, int* r, int* g, int* b)
{
  NSColor* d = [c colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
  if (!d) { *r = *g = *b = -1; return; }
  *r = (int)([d redComponent] * 255 + 0.5);
  *g = (int)([d greenComponent] * 255 + 0.5);
  *b = (int)([d blueComponent] * 255 + 0.5);
}

static int run(Ihandle* t)
{
  char buf[300];
  static int running = 0; if (running) return IUP_DEFAULT; running = 1;
  IupSetAttribute(t, "RUN", "NO");

  NSWindow* w = (NSWindow*)dlg->handle;

  /* ---- HIDETITLEBAR ---- */
  { IupSetAttribute(dlg, "HIDETITLEBAR", "YES");
    BOOL full = ([w styleMask] & NSWindowStyleMaskFullSizeContentView) != 0;
    BOOL transparent = [w titlebarAppearsTransparent];
    BOOL hidden = ([w titleVisibility] == NSWindowTitleHidden);
    snprintf(buf, sizeof buf, "fullSizeContent=%d transparentTitlebar=%d titleHidden=%d",
             full, transparent, hidden);
    chk(full && transparent && hidden, "HIDETITLEBAR=YES frees the title bar", buf); }

  { IupSetAttribute(dlg, "HIDETITLEBAR", "NO");
    BOOL full = ([w styleMask] & NSWindowStyleMaskFullSizeContentView) != 0;
    snprintf(buf, sizeof buf, "fullSizeContent=%d transparentTitlebar=%d titleVisible=%d",
             full, [w titlebarAppearsTransparent],
             [w titleVisibility] == NSWindowTitleVisible);
    chk(!full && ![w titlebarAppearsTransparent]
        && [w titleVisibility] == NSWindowTitleVisible,
        "HIDETITLEBAR=NO restores it", buf); }

  /* ---- BACKGROUND as a colour ---- */
  { IupSetAttribute(dlg, "BACKGROUND", "0 255 0");
    int r, g, b; rgb_of([w backgroundColor], &r, &g, &b);
    snprintf(buf, sizeof buf, "window background=(%d,%d,%d) want (0,255,0)", r, g, b);
    chk(r == 0 && g == 255 && b == 0, "BACKGROUND accepts a colour", buf); }

  /* ---- BACKGROUND as an image: NSColor tiles it as a pattern ---- */
  { unsigned char px[4] = {1, 1, 1, 1};
    Ihandle* img = IupImage(2, 2, px);
    IupSetAttribute(img, "1", "0 0 255");
    IupSetHandle("bgimg", img);
    IupSetAttribute(dlg, "BACKGROUND", "bgimg");
    NSColor* c = [w backgroundColor];
    NSImage* pattern = nil;
    @try { pattern = [c patternImage]; } @catch (NSException* e) { pattern = nil; }
    snprintf(buf, sizeof buf, "patternImage=%s size=%.0fx%.0f",
             pattern ? "set" : "nil",
             pattern ? [pattern size].width : 0, pattern ? [pattern size].height : 0);
    chk(pattern != nil && [pattern size].width == 2,
        "BACKGROUND accepts an image and tiles it", buf); }

  IupSetAttribute(dlg, "BACKGROUND", NULL);

  /* ---- CUSTOMFRAME and SHAPEIMAGE are known attributes ---- */
  { IupSetAttribute(dlg, "CUSTOMFRAME", "NO");
    IupSetAttribute(dlg, "SHAPEIMAGE", "bgimg");   /* must not crash; declared unsupported */
    chk(1, "CUSTOMFRAME and SHAPEIMAGE are accepted", "declared, no crash"); }

  /* ---- tray ----
     On this backend TRAY is a creation-time decision: cocoaDialogMapMethod turns a dialog
     whose TRAY is already set into an NSStatusItem instead of an NSWindow (ih->handle is the
     status item). So the tray checks run against a second dialog that had TRAY set before it
     was shown -- setting it afterwards on a live window is not a supported path. */
  { NSStatusItem* item = (NSStatusItem*)tray_dlg->handle;
    NSStatusBarButton* button = [item isKindOfClass:[NSStatusItem class]] ? [item button] : nil;

    snprintf(buf, sizeof buf, "handle=%s", [(id)item className].UTF8String);
    chk(button != nil, "a TRAY dialog is backed by an NSStatusItem", buf);

    if (button)
    {
      IupSetAttribute(tray_dlg, "TRAYTIP", "hello tray");
      NSString* tip = [button toolTip];
      snprintf(buf, sizeof buf, "button toolTip='%s'", tip ? [tip UTF8String] : "(nil)");
      chk(tip && 0 == strcmp([tip UTF8String], "hello tray"),
          "TRAYTIP reaches the status item's button", buf);

      /* The wiring that was missing entirely: a target and action on the button. */
      snprintf(buf, sizeof buf, "target=%s action=%s",
               [button target] ? "set" : "nil",
               [button action] ? NSStringFromSelector([button action]).UTF8String : "none");
      chk([button target] != nil && [button action] != NULL,
          "the status item has a click target and action", buf);

      /* Fire it the way AppKit would and confirm TRAYCLICK_CB actually runs. Registration
         alone would prove nothing -- before this the callback was declared inside an #if 0
         block and no action was ever assigned, so it could not fire at all. */
      if ([button target] && [button action])
      { g_tray_clicks = 0;
        /* Send straight to the target rather than through -[NSApplication sendAction:to:from:],
           which routes via the responder chain and does not return promptly for a status
           item's button. */
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [[button target] performSelector:[button action] withObject:button];
        #pragma clang diagnostic pop
        snprintf(buf, sizeof buf, "TRAYCLICK_CB invocations=%d", g_tray_clicks);
        chk(g_tray_clicks == 1, "clicking the tray icon calls TRAYCLICK_CB", buf); }
    } }

  printf("%d gap(s)\n", g_gaps);
  IupExitLoop();
  return IUP_DEFAULT;
}

int main(int argc, char** argv)
{
  IupOpen(&argc, &argv);

  dlg = IupDialog(IupVbox(IupLabel("dlgattrib"), NULL));
  IupSetAttribute(dlg, "TITLE", "dlgattrib");
  IupShowXY(dlg, IUP_CENTER, IUP_CENTER);

  /* TRAY must be set before mapping: the map method reads it and builds an NSStatusItem. */
  tray_dlg = IupDialog(NULL);
  IupSetAttribute(tray_dlg, "TRAY", "YES");
  IupSetCallback(tray_dlg, "TRAYCLICK_CB", (Icallback)tray_click_cb);
  IupMap(tray_dlg);

  Ihandle* t = IupTimer();
  IupSetAttribute(t, "TIME", "700");
  IupSetCallback(t, "ACTION_CB", (Icallback)run);
  IupSetAttribute(t, "RUN", "YES");
  IupMainLoop();
  IupClose();
  return g_gaps ? 1 : 0;
}
