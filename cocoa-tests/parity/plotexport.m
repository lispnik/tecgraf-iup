/* IupPlot's file export on Cocoa.
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
#include <cdps.h>
#include <cdcgm.h>
#include <cdirgb.h>

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
      chk(menu_has_item(nsmenu, @"EPS...") && menu_has_item(nsmenu, @"SVG...") &&
          menu_has_item(nsmenu, @"CGM..."),
          "...alongside SVG, EPS and CGM", NULL);
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

/* ------------------------------------------------- the other formats ---- */

static char* slurp(const char* path, long* size)
{
  FILE* f = fopen(path, "rb");
  char* buf;
  long n;
  *size = 0;
  if (!f) return NULL;
  fseek(f, 0, SEEK_END); n = ftell(f); fseek(f, 0, SEEK_SET);
  if (n <= 0) { fclose(f); return NULL; }
  buf = (char*)malloc((size_t)n + 1);
  if (fread(buf, 1, (size_t)n, f) != (size_t)n) { free(buf); fclose(f); return NULL; }
  buf[n] = 0; fclose(f); *size = n;
  return buf;
}

/* EPS and CGM export were dead on this platform for a different reason than PDF: cdps.c and
   cdcgm.c are portable C sitting in CD's source tree, but were in no CMake source list, so the
   library exported no cdContextPS or cdContextCGM and these menu items produced nothing. */
static void export_eps(void)
{
  char data[1024], buf[256];
  const char* path = "/tmp/iup_plotexport_harness.eps";
  int dpi = IupGetInt(NULL, "SCREENDPI");
  cdCanvas* cnv;
  char* text;
  long size;

  remove(path);
  sprintf(data, "%s -e -s%d", path, dpi);      /* the string iPlotExportEPS_CB builds */
  cnv = cdCreateCanvas(CD_PS, data);
  chk(cnv != NULL, "CD has a PostScript driver (src/drv/cdps.c is in the build)", NULL);
  if (!cnv) return;

  IupPlotPaintTo(plot, cnv);
  cdKillCanvas(cnv);

  text = slurp(path, &size);
  chk(text != NULL, "the EPS export wrote a file", NULL);
  if (!text) return;

  snprintf(buf, sizeof buf, "%ld bytes, starts \"%.14s\"", size, text);
  chk(strncmp(text, "%!PS-Adobe", 10) == 0, "it carries the PostScript signature", buf);
  chk(strstr(text, "%%BoundingBox") != NULL, "EPS declares a bounding box, so it can be embedded", NULL);
  chk(strstr(text, "moveto") != NULL && strstr(text, "lineto") != NULL,
      "the plot was drawn as PostScript paths", NULL);
  free(text);
}

/* CGM gets the strongest check available: CD replays the file it just wrote. */
static void export_cgm(void)
{
  char data[1024], buf[256];
  const char* path = "/tmp/iup_plotexport_harness.cgm";
  const int side = 300;
  cdCanvas* cnv;
  cdCanvas* bitmap;
  unsigned char *r, *g, *b;
  int i, ink = 0, played;

  remove(path);
  /* Exactly what iPlotExportCGM_CB builds. CGM does NOT take the -w/-h/-s options the other
     drivers use: its grammar is "filename [w_mmxh_mm] [resolution]", and passing the wrong one
     leaves the canvas at its INT_MAX x INT_MAX default -- whereupon IupPlot dutifully draws
     axis ticks across two billion pixels and appears to hang. */
  { int w = 0, h = 0;
    double res, w_mm, h_mm;
    IupGetIntInt(plot, "DRAWSIZE", &w, &h);
    res = (double)IupGetInt(NULL, "SCREENDPI") / 25.4;
    w_mm = w / res; h_mm = h / res;
    sprintf(data, "%s %gx%g %g", path, w_mm, h_mm, res); }
  cnv = cdCreateCanvas(CD_CGM, data);
  chk(cnv != NULL, "CD has a CGM driver (src/drv/cdcgm.c is in the build)", NULL);
  if (!cnv) return;

  IupPlotPaintTo(plot, cnv);
  cdKillCanvas(cnv);

  r = (unsigned char*)malloc((size_t)side * side);
  g = (unsigned char*)malloc((size_t)side * side);
  b = (unsigned char*)malloc((size_t)side * side);
  memset(r, 255, (size_t)side * side);
  memset(g, 255, (size_t)side * side);
  memset(b, 255, (size_t)side * side);

  sprintf(data, "%dx%d %p %p %p", side, side, r, g, b);
  bitmap = cdCreateCanvas(CD_IMAGERGB, data);
  played = bitmap ? cdCanvasPlay(bitmap, CD_CGM, 0, 0, 0, 0, (void*)path) : CD_ERROR;
  chk(played == CD_OK, "CD can replay the CGM it just wrote", NULL);

  for (i = 0; i < side * side; i++)
    if (r[i] != 255 || g[i] != 255 || b[i] != 255) ink++;

  snprintf(buf, sizeof buf, "%d non-white pixels after playback", ink);
  chk(ink > 100, "the replayed plot puts ink on the page", buf);

  if (bitmap) cdKillCanvas(bitmap);
  free(r); free(g); free(b);
}

/* ----------------------------------------------------------------- run ---- */

static int run(Ihandle* t)
{
  static int running = 0; if (running) return IUP_DEFAULT; running = 1;
  IupSetAttribute(t, "RUN", "NO");

  export_and_check();
  export_eps();
  export_cgm();

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
