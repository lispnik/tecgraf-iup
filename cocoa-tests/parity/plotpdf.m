/* IupPlot's PDF export on Cocoa.
 *
 * Two things are asserted, and neither is "IupGetAttribute agreed with itself":
 *
 *  1. the context menu the user actually sees contains a PDF entry -- read off the NSMenu that
 *     AppKit put on screen, not off the Ihandle tree that produced it;
 *  2. exporting really produces a PDF, with the proportions of the plot, containing vector
 *     drawing and *text as text*.
 *
 * (2) is worth more than "a file appeared" because CoreGraphics is itself a PDF parser: the
 * output is re-opened and interrogated. The font check is the interesting one -- CD's other
 * route to PDF would be its FreeType simulation, which rasterises glyphs; a page whose
 * resources carry fonts and no image XObject is proof that CoreText embedded them and that the
 * axis labels are selectable rather than a picture of themselves.
 */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <math.h>
#include <iup.h>
#include <iup_plot.h>
#include "iup_object.h"   /* ih->handle: the native NSMenu behind the Ihandle */
#include <cd.h>
#include <cdpdf.h>

static int g_gaps = 0;
static Ihandle *dlg, *plot;
static const char* PDF_FILE = "/tmp/iup_plotpdf_harness.pdf";

static void chk(int c, const char* w, const char* g)
{ printf("%-4s %-58s %s\n", c ? "ok  " : "GAP ", w, g ? g : ""); fflush(stdout); if (!c) g_gaps++; }

/* ---------------------------------------------------------------- menu ---- */

static NSMenu* g_tracked = nil;

static int menu_has_item(NSMenu* menu, NSString* title)
{
  for (NSMenuItem* item in [menu itemArray])
  {
    if ([[item title] isEqualToString:title])
      return 1;
    if ([item hasSubmenu] && menu_has_item([item submenu], title))
      return 1;
  }
  return 0;
}

static NSString* menu_titles(NSMenu* menu)
{
  NSMutableArray* names = [NSMutableArray array];
  for (NSMenuItem* item in [menu itemArray])
  {
    if ([item hasSubmenu])
      [names addObject:[NSString stringWithFormat:@"%@[%@]", [item title], menu_titles([item submenu])]];
    else if ([[item title] length])
      [names addObject:[item title]];
  }
  return [names componentsJoinedByString:@","];
}

/* Fires just before IupPopup maps the menu, so the native NSMenu does not exist yet. Look at it
   once tracking has started, then cancel that tracking -- IupPopup runs a nested AppKit event
   loop and would otherwise never return. */
static int menucontext_cb(Ihandle* ih, Ihandle* menu, int x, int y)
{
  (void)ih; (void)x; (void)y;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    NSMenu* nsmenu = (NSMenu*)menu->handle;
    if (nsmenu)
    {
      char buf[512];
      snprintf(buf, sizeof buf, "items=%s", [menu_titles(nsmenu) UTF8String]);
      chk(menu_has_item(nsmenu, @"PDF..."), "the plot context menu offers PDF export", buf);
      chk(menu_has_item(nsmenu, @"EPS..."), "...alongside the formats that were already there", NULL);
      g_tracked = nsmenu;
      [nsmenu cancelTracking];
    }
    else
      chk(0, "the plot context menu was mapped", "menu->handle is NULL");
  });
  return IUP_DEFAULT;
}

/* ----------------------------------------------------------------- pdf ---- */

static CGPDFDocumentRef open_pdf(const char* path)
{
  CFStringRef s = CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8);
  CFURLRef url = CFURLCreateWithFileSystemPath(NULL, s, kCFURLPOSIXPathStyle, false);
  CGPDFDocumentRef doc = CGPDFDocumentCreateWithURL(url);
  CFRelease(s); CFRelease(url);
  return doc;
}

static int page_ink(CGPDFPageRef page, CGRect box)
{
  int w = (int)box.size.width, h = (int)box.size.height, i, ink = 0;
  unsigned char* buf = (unsigned char*)calloc((size_t)w * h * 4, 1);
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef bmp = CGBitmapContextCreate(buf, w, h, 8, (size_t)w * 4, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
  CGColorSpaceRelease(cs);
  CGContextSetRGBFillColor(bmp, 1, 1, 1, 1);
  CGContextFillRect(bmp, CGRectMake(0, 0, w, h));
  CGContextDrawPDFPage(bmp, page);
  for (i = 0; i < w * h; i++)
  { unsigned char* px = buf + i * 4;
    if (px[0] < 250 || px[1] < 250 || px[2] < 250) ink++; }
  CGContextRelease(bmp); free(buf);
  return ink;
}

/* Counts entries in a page resource sub-dictionary (/Font, /XObject, ...). */
static int resource_count(CGPDFPageRef page, const char* key)
{
  CGPDFDictionaryRef page_dict = CGPDFPageGetDictionary(page), resources, sub;
  if (!CGPDFDictionaryGetDictionary(page_dict, "Resources", &resources))
    return -1;
  if (!CGPDFDictionaryGetDictionary(resources, key, &sub))
    return 0;
  return (int)CGPDFDictionaryGetCount(sub);
}

static void export_and_check(void)
{
  char data[1024], buf[256];
  int w = 0, h = 0, dpi = IupGetInt(NULL, "SCREENDPI");
  CGPDFDocumentRef doc;
  CGPDFPageRef page;
  CGRect box;
  double want_aspect, got_aspect;
  cdCanvas* cnv;

  IupGetIntInt(plot, "DRAWSIZE", &w, &h);
  chk(w > 0 && h > 0 && dpi > 0, "the plot reports a draw size to scale the page from", NULL);

  /* the string iPlotExportPDF_CB builds */
  sprintf(data, "%s -w%g -h%g -s%d", PDF_FILE, (25.4 * w) / dpi, (25.4 * h) / dpi, dpi);

  remove(PDF_FILE);
  cnv = cdCreateCanvas(CD_PDF, data);
  snprintf(buf, sizeof buf, "CD_PDF=%p data=\"%s\"", (void*)CD_PDF, data);
  chk(cnv != NULL, "CD has a PDF driver at all (no PDFlib on this platform)", buf);
  if (!cnv)
    return;

  IupPlotPaintTo(plot, cnv);
  cdKillCanvas(cnv);

  doc = open_pdf(PDF_FILE);
  chk(doc != NULL, "the export is a PDF CoreGraphics can re-open", NULL);
  if (!doc)
    return;

  chk(CGPDFDocumentGetNumberOfPages(doc) == 1, "one plot is one page", NULL);

  page = CGPDFDocumentGetPage(doc, 1);
  box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);

  want_aspect = (double)w / (double)h;
  got_aspect = box.size.width / box.size.height;
  snprintf(buf, sizeof buf, "page=%.1fx%.1f pt (%.3f), canvas=%dx%d px (%.3f)",
           box.size.width, box.size.height, got_aspect, w, h, want_aspect);
  chk(fabs(got_aspect - want_aspect) < 0.02, "the page has the proportions of the plot", buf);

  { int ink = page_ink(page, box);
    snprintf(buf, sizeof buf, "%d non-white pixels", ink);
    chk(ink > 1000, "the plot was actually drawn onto the page", buf); }

  { int fonts = resource_count(page, "Font");
    int images = resource_count(page, "XObject");
    snprintf(buf, sizeof buf, "/Font=%d /XObject=%d", fonts, images);
    chk(fonts > 0, "the axis labels are text, not glyph outlines or pixels", buf);
    chk(images == 0, "nothing was rasterised into an image", buf); }

  CGPDFDocumentRelease(doc);
}

/* ----------------------------------------------------------------- run ---- */

static int run(Ihandle* t)
{
  static int running = 0; if (running) return IUP_DEFAULT; running = 1;
  IupSetAttribute(t, "RUN", "NO");

  export_and_check();

  /* Now the menu. Driving BUTTON_CB is what the canvas itself does on a right click, so this
     goes through iupPlotShowMenuContext exactly as a user would. */
  { typedef int (*IbuttonCB)(Ihandle*, int, int, int, int, char*);
    IbuttonCB cb = (IbuttonCB)IupGetCallback(plot, "BUTTON_CB");
    chk(cb != NULL, "the plot installs a button handler for the context menu", NULL);
    if (cb)
      cb(plot, IUP_BUTTON3, 1, 40, 40, (char*)"");
  }

  printf("%d gap(s)\n", g_gaps);
  IupExitLoop();
  return IUP_DEFAULT;
}

int main(int argc, char** argv)
{
  int i;
  IupOpen(&argc, &argv);
  IupPlotOpen();

  plot = IupPlot();
  IupSetAttribute(plot, "RASTERSIZE", "400x300");
  IupSetAttribute(plot, "TITLE", "PDF export");
  IupSetAttribute(plot, "AXS_XLABEL", "x");
  IupSetAttribute(plot, "AXS_YLABEL", "sin x");
  IupSetAttribute(plot, "MENUCONTEXT", "Yes");
  IupSetCallback(plot, "MENUCONTEXT_CB", (Icallback)menucontext_cb);

  IupPlotBegin(plot, 0);
  for (i = 0; i < 100; i++)
    IupPlotAdd(plot, i / 10.0, sin(i / 10.0));
  IupPlotEnd(plot);

  dlg = IupDialog(plot);
  IupSetAttribute(dlg, "TITLE", "plotpdf");
  IupShowXY(dlg, IUP_CENTER, IUP_CENTER);

  Ihandle* t = IupTimer();
  IupSetAttribute(t, "TIME", "800");
  IupSetCallback(t, "ACTION_CB", (Icallback)run);
  IupSetAttribute(t, "RUN", "YES");
  IupMainLoop();
  IupClose();
  return g_gaps ? 1 : 0;
}
