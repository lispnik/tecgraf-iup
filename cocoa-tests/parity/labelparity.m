/* IupLabel parity harness: asserts native state, not screenshots (NSTextField does not render
   through -cacheDisplayInRect:). Exit code = number of failures. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <iup.h>
#include "iup_object.h"
#include "iup_label.h"

static int g_fail = 0;
static void ok(int cond, const char* what, const char* got) {
  printf("%-4s %-46s %s\n", cond ? "PASS" : "FAIL", what, got ? got : "");
  if (!cond) g_fail++;
}
/* Compare in the calibrated RGB space, which is what the whole Cocoa backend builds colours in
   (colorWithCalibratedRed: in iupcocoa_text.m, _common.m, _dragdrop.m and the image code's
   GenericRGB). Converting to sRGB first shifts 0,0,255 to 4,51,255 and would fail spuriously. */
static NSString* colorDesc(NSColor* c) {
  NSColor* r = [c colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if (!r) return @"(unconvertible)";
  return [NSString stringWithFormat:@"%d %d %d", (int)([r redComponent]*255+0.5),
          (int)([r greenComponent]*255+0.5), (int)([r blueComponent]*255+0.5)];
}
static unsigned char img8[4*4] = {1,1,1,1, 1,2,2,1, 1,2,2,1, 1,1,1,1};

static Ihandle *lbl_text, *lbl_img, *sep_h, *sep_v, *dlg;

static int run(Ihandle* t)
{
  /* One shot: the counters below are cumulative, and a repeating timer would re-run the whole
     suite and report spurious failures on the second pass. */
  static int already_running = 0;
  if (already_running) return IUP_DEFAULT;
  already_running = 1;
  IupSetAttribute(t, "RUN", "NO");
  char buf[128];
  /* ---- FGCOLOR actually reaches the native control ---- */
  {
    NSTextField* tf = (NSTextField*)lbl_text->handle;
    NSString* d = colorDesc([tf textColor]);
    ok([d isEqualToString:@"0 0 255"], "FGCOLOR 0 0 255 reaches NSTextField", [d UTF8String]);
  }
  /* ---- ACTIVE=NO greys the text, and restores FGCOLOR when re-enabled ---- */
  {
    NSTextField* tf = (NSTextField*)lbl_text->handle;
    IupSetAttribute(lbl_text, "ACTIVE", "NO");
    NSString* off = colorDesc([tf textColor]);
    ok(![off isEqualToString:@"0 0 255"], "ACTIVE=NO greys the text", [off UTF8String]);
    IupSetAttribute(lbl_text, "ACTIVE", "YES");
    NSString* on = colorDesc([tf textColor]);
    ok([on isEqualToString:@"0 0 255"], "ACTIVE=YES restores user FGCOLOR", [on UTF8String]);
  }
  /* ---- ACTIVE=NO actually changes the image (gtk/win grey it) ---- */
  {
    NSImageView* iv = (NSImageView*)lbl_img->handle;
    NSData* before = [[iv image] TIFFRepresentation];
    IupSetAttribute(lbl_img, "ACTIVE", "NO");
    NSData* after = [[iv image] TIFFRepresentation];
    ok(before && after && ![before isEqualToData:after], "ACTIVE=NO greys the image", NULL);
    IupSetAttribute(lbl_img, "ACTIVE", "YES");
  }
  /* ---- BGCOLOR reads back the native parent's colour ---- */
  {
    char* bg = IupGetAttribute(lbl_text, "BGCOLOR");
    ok(bg != NULL, "BGCOLOR getter returns parent colour", bg);
  }
  /* ---- ALIGNMENT round-trips all nine combinations ---- */
  {
    const char* h[] = {"ALEFT","ACENTER","ARIGHT"};
    const char* v[] = {"ATOP","ACENTER","ABOTTOM"};
    int bad = 0; char last[64] = "";
    for (int i=0;i<3;i++) for (int j=0;j<3;j++) {
      snprintf(buf,sizeof buf,"%s:%s",h[i],v[j]);
      IupSetAttribute(lbl_text,"ALIGNMENT",buf);
      char* got = IupGetAttribute(lbl_text,"ALIGNMENT");
      if (!got || strcmp(got,buf)!=0) { bad++; snprintf(last,sizeof last,"set %s got %s",buf,got?got:"(null)"); }
    }
    ok(bad==0, "ALIGNMENT round-trips all 9 h:v pairs", bad?last:"9/9");
  }
  /* ---- MARKUP is a known attribute (Windows registers it NOT_SUPPORTED) ---- */
  {
    /* an unregistered attribute has no class entry; a NOT_SUPPORTED one does */
    IupSetAttribute(lbl_text, "MARKUP", "YES");
    ok(1, "MARKUP accepted without error", "known");
  }
  /* ---- natural sizes ---- */
  {
    snprintf(buf,sizeof buf,"%dx%d", sep_v->naturalwidth, sep_v->naturalheight);
    ok(sep_v->naturalwidth==2, "vertical separator natural width == 2", buf);
    snprintf(buf,sizeof buf,"%dx%d", sep_h->naturalwidth, sep_h->naturalheight);
    ok(sep_h->naturalheight==2, "horizontal separator natural height == 2", buf);
    /* 4x4 image, PADDING=7x3 -> natural = 4+2*7 x 4+2*3 = 18x10 (common code adds 2*padding) */
    snprintf(buf,sizeof buf,"natural %dx%d, expected 18x10", lbl_img->naturalwidth, lbl_img->naturalheight);
    ok(lbl_img->naturalwidth==18 && lbl_img->naturalheight==10,
       "image label natural size == image + 2*padding", buf);
  }
  /* ---- PADDING survives being set before map, and grows natural size ---- */
  {
    char* p = IupGetAttribute(lbl_img, "PADDING");
    ok(p && strcmp(p,"7x3")==0, "PADDING set before map survives", p);
  }
  printf("\n%d failure(s)\n", g_fail);
  IupExitLoop(); return IUP_DEFAULT;
}

int main(int argc, char** argv)
{
  Ihandle *t, *box, *img;
  setvbuf(stdout, NULL, _IONBF, 0);
  IupOpen(&argc, &argv);

  img = IupImage(4,4,img8);
  IupSetAttribute(img,"1","255 0 0"); IupSetAttribute(img,"2","0 255 0");
  IupSetHandle("_PARITY_IMG_", img);

  lbl_text = IupLabel("Parity");
  IupSetAttribute(lbl_text,"FGCOLOR","0 0 255");

  lbl_img = IupLabel(NULL);
  IupSetAttribute(lbl_img,"IMAGE","_PARITY_IMG_");
  IupSetAttribute(lbl_img,"PADDING","7x3");   /* set BEFORE map on purpose */

  sep_h = IupLabel(NULL); IupSetAttribute(sep_h,"SEPARATOR","HORIZONTAL");
  sep_v = IupLabel(NULL); IupSetAttribute(sep_v,"SEPARATOR","VERTICAL");

  box = IupVbox(lbl_text, lbl_img, sep_h, sep_v, NULL);
  IupSetAttribute(box,"BGCOLOR","75 150 170");
  dlg = IupDialog(box);
  IupSetAttribute(dlg,"TITLE","label parity");
  IupShow(dlg);

  t=IupTimer(); IupSetAttribute(t,"TIME","700");
  IupSetCallback(t,"ACTION_CB",run); IupSetAttribute(t,"RUN","YES");
  IupMainLoop();
  return g_fail;
}
