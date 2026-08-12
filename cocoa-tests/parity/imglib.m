/* What IupImageLibOpen() actually gives you on macOS, and whether the IupImage -> NSImage
   path underneath it works at all. Those are separate questions: the library could be empty
   while images themselves render fine, which is what determines whether it is worth wiring
   a stock icon set up to this platform.

   Two things found while writing this that are NOT Cocoa bugs, so nothing asserts them:

   * IUP_Zoom, IUP_FileText, IUP_FontBold, IUP_FontDialog, IUP_FontItalic,
     IUP_WindowsCascade and IUP_WindowsTile sit inside #ifdef IUP_IMGLIB_OLD, which nothing
     in the tree defines. They are unregistered on every platform, not missing here.
   * A button created without an IMAGE cannot be given one later: iupButtonComputeNaturalSize
     fixes ih->data->type at map time, and gtkButtonSetImageAttrib returns 0 for a non-image
     button exactly as the Cocoa driver does. Same on both. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <string.h>
#include <iup.h>
#include "iup_object.h"

static int g_gaps = 0;
static Ihandle *dlg, *btn, *lbl;

static void chk(int c, const char* w, const char* g)
{ printf("%-4s %-52s %s\n", c ? "ok  " : "GAP ", w, g ? g : ""); if (!c) g_gaps++; }

/* names IUP documents for the image library, one per family */
static const char* k_names[] = {
  "IUP_FileOpen", "IUP_FileSave", "IUP_EditCopy", "IUP_EditPaste",
  "IUP_ActionOk", "IUP_ActionCancel", "IUP_NavigateHome", "IUP_Print",
  "IUP_ToolsSettings", "IUP_MessageError", "IUP_MessageInfo",
  "IUP_Tecgraf", "IUP_PUC-Rio", "IUP_BR", "IUP_Lua", "IUP_Petrobras",
  /* CircleProgress is the exception: iupImglibCircleProgress registers its frames with
     IupSetHandle directly, so these ARE in the handle namespace. */
  "IUP_CircleProgress0", "IUP_CircleProgress8",
};
#define NNAMES ((int)(sizeof k_names / sizeof k_names[0]))

static unsigned char k_pixels[4*4] = {  /* 4x4, palette indices */
  1,1,2,2,  1,1,2,2,  2,2,1,1,  2,2,1,1
};

static int run(Ihandle* t)
{
  char buf[400];
  static int running = 0; if (running) return IUP_DEFAULT; running = 1;
  IupSetAttribute(t, "RUN", "NO");

  /* 1. Stock images are NOT in the handle namespace -- iupImageStockSet puts them in a
        private table and they are instantiated lazily, so IupGetHandle("IUP_FileOpen")
        is NULL even on a platform where the library works. Resolve them the way a control
        does: assign the name and see whether a native image comes out the other end. */
  { int found = 0; char missing[300] = "";
    for (int i = 0; i < NNAMES; i++)
    { IupSetAttribute(btn, "IMAGE", k_names[i]);
      NSImage* ni = [(NSButton*)btn->handle image];
      if (ni && [ni size].width > 0) found++;
      else if (strlen(missing) < 200) { strcat(missing, k_names[i]); strcat(missing, " "); } }
    snprintf(buf, sizeof buf, "%d/%d resolve to a native image; missing: %s", found, NNAMES,
             found == NNAMES ? "(none)" : missing);
    chk(found == NNAMES, "the documented stock images load", buf); }

  /* 2. they must be real artwork, not 1x1 placeholders */
  { IupSetAttribute(btn, "IMAGE", "IUP_FileOpen");
    NSImage* ni = [(NSButton*)btn->handle image];
    NSSize sz = ni ? [ni size] : NSMakeSize(0, 0);
    snprintf(buf, sizeof buf, "IUP_FileOpen is %.0fx%.0f", sz.width, sz.height);
    chk(sz.width >= 16 && sz.height >= 16, "stock images are full size", buf); }

  /* 3. a logo, which is registered NoResize and is not square */
  { IupSetAttribute(btn, "IMAGE", "IUP_Tecgraf");
    NSImage* ni = [(NSButton*)btn->handle image];
    NSSize sz = ni ? [ni size] : NSMakeSize(0, 0);
    snprintf(buf, sizeof buf, "IUP_Tecgraf is %.0fx%.0f", sz.width, sz.height);
    chk(sz.width >= 16 && sz.height >= 16, "logos load too", buf);
    IupSetAttribute(btn, "IMAGE", "testimg"); }

  /* 3. does a hand-built IupImage reach the native control at all?  If this passes while
        (1) fails, the gap is purely that no icon set is compiled in for this platform. */
  { NSButton* nb = (NSButton*)btn->handle;
    NSImage* ni = [nb image];
    snprintf(buf, sizeof buf, "NSButton image=%s size=%.0fx%.0f",
             ni ? "set" : "nil", ni ? [ni size].width : 0, ni ? [ni size].height : 0);
    chk(ni != nil && [ni size].width == 4 && [ni size].height == 4,
        "a hand-built IupImage reaches the NSButton", buf); }

  { NSView* lv = (NSView*)lbl->handle;
    NSImage* ni = [lv isKindOfClass:[NSImageView class]] ? [(NSImageView*)lv image] : nil;
    snprintf(buf, sizeof buf, "%s image=%s", [[lv className] UTF8String], ni ? "set" : "nil");
    chk(ni != nil, "a hand-built IupImage reaches the NSImageView label", buf); }

  /* 4. colours must survive the palette -> RGBA conversion, right way up */
  { NSButton* nb = (NSButton*)btn->handle;
    NSImage* ni = [nb image];
    NSBitmapImageRep* rep = nil;
    for (NSImageRep* r in [ni representations])
      if ([r isKindOfClass:[NSBitmapImageRep class]]) { rep = (NSBitmapImageRep*)r; break; }
    if (!rep) { chk(0, "image has a readable bitmap representation", "no NSBitmapImageRep"); }
    else
    { NSColor* tl = [[rep colorAtX:0 y:0] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
      NSColor* tr = [[rep colorAtX:3 y:0] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
      int tl_red = (int)([tl redComponent] * 255 + 0.5), tl_grn = (int)([tl greenComponent] * 255 + 0.5);
      int tr_red = (int)([tr redComponent] * 255 + 0.5), tr_grn = (int)([tr greenComponent] * 255 + 0.5);
      snprintf(buf, sizeof buf, "top-left=(%d,%d,..) want red; top-right=(%d,%d,..) want green",
               tl_red, tl_grn, tr_red, tr_grn);
      /* index 1 = red, index 2 = green; top row is 1,1,2,2 -- and y=0 must be the TOP */
      chk(tl_red > 200 && tl_grn < 60 && tr_grn > 200 && tr_red < 60,
          "palette colours and row order survive the conversion", buf); } }

  printf("%d gap(s)\n", g_gaps);
  IupExitLoop();
  return IUP_DEFAULT;
}

int main(int argc, char** argv)
{
  IupOpen(&argc, &argv);
  IupImageLibOpen();

  Ihandle* img = IupImage(4, 4, k_pixels);
  IupSetAttribute(img, "0", "BGCOLOR");
  IupSetAttribute(img, "1", "255 0 0");
  IupSetAttribute(img, "2", "0 255 0");
  IupSetHandle("testimg", img);

  btn = IupButton(NULL, NULL);
  IupSetAttribute(btn, "IMAGE", "testimg");
  lbl = IupLabel(NULL);
  IupSetAttribute(lbl, "IMAGE", "testimg");

  dlg = IupDialog(IupVbox(btn, lbl, NULL));
  IupSetAttribute(dlg, "TITLE", "imglib");
  IupShowXY(dlg, IUP_CENTER, IUP_CENTER);

  Ihandle* t = IupTimer();
  IupSetAttribute(t, "TIME", "600");
  IupSetCallback(t, "ACTION_CB", (Icallback)run);
  IupSetAttribute(t, "RUN", "YES");
  IupMainLoop();
  IupClose();
  return g_gaps ? 1 : 0;
}
