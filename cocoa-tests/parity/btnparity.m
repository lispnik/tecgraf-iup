/* IupButton parity probe: what actually works on the Cocoa backend today? */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <iup.h>
#include "iup_object.h"

static int g_action = 0, g_button = 0;
static Ihandle *b_text, *b_img, *b_both, *b_imin;

static int action_cb(Ihandle* ih) { g_action++; return IUP_DEFAULT; }
static int button_cb(Ihandle* ih,int b,int p,int x,int y,char* s) { g_button++; return IUP_DEFAULT; }

static int g_gaps = 0;
static void chk(int cond, const char* what, const char* got)
{ printf("%-4s %-46s %s\n", cond?"ok  ":"GAP ", what, got?got:""); if(!cond) g_gaps++; }

static NSString* fgOf(NSButton* b) {
  NSAttributedString* a = [b attributedTitle];
  if (!a || [a length]==0) return @"(no title)";
  NSColor* c = [a attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
  if (!c) return @"(no colour attr)";
  c = [c colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  return [NSString stringWithFormat:@"%d %d %d",(int)([c redComponent]*255+.5),
          (int)([c greenComponent]*255+.5),(int)([c blueComponent]*255+.5)];
}
static unsigned char imgA[4*4] = {1,1,1,1, 1,2,2,1, 1,2,2,1, 1,1,1,1};
static unsigned char imgB[4*4] = {2,2,2,2, 2,1,1,2, 2,1,1,2, 2,2,2,2};

static int run(Ihandle* t)
{
  char buf[200];
  /* NSButton's -mouseDown: runs a nested tracking loop that pumps the run loop, which re-enters
     this timer callback. Guard against that or the test runs twice and exits early. */
  static int already_running = 0;
  if (already_running) return IUP_DEFAULT;
  already_running = 1;
  IupSetAttribute(t, "RUN", "NO");
  NSButton* nb = (NSButton*)b_text->handle;

  printf("--- attributes ---\n");
  IupSetAttribute(b_text,"FGCOLOR","0 0 255");
  chk([fgOf(nb) isEqualToString:@"0 0 255"], "FGCOLOR changes the button text colour", [fgOf(nb) UTF8String]);

  { char* v = IupGetAttribute(b_text,"BGCOLOR");
    chk(v!=NULL, "BGCOLOR readable", v?v:"(null)"); }

  { /* IMAGE set before map (map reads it) */
    NSButton* ib = (NSButton*)b_img->handle;
    chk([ib image]!=nil, "IMAGE set BEFORE map shows an image", [ib image]?"has image":"none"); }

  { /* IMAGE changed after map */
    NSButton* ib = (NSButton*)b_img->handle;
    NSData* before = [[ib image] TIFFRepresentation];
    IupSetAttribute(b_img,"IMAGE","_BTN_B_");
    NSData* after = [[ib image] TIFFRepresentation];
    chk(before && after && ![before isEqualToData:after],
        "IMAGE changed AFTER map updates the button", NULL); }

  { /* ACTIVE greying of the image */
    NSButton* ib = (NSButton*)b_img->handle;
    NSData* before = [[ib image] TIFFRepresentation];
    IupSetAttribute(b_img,"ACTIVE","NO");
    NSData* after = [[ib image] TIFFRepresentation];
    chk(before && after && ![before isEqualToData:after], "ACTIVE=NO greys the image", NULL);
    IupSetAttribute(b_img,"ACTIVE","YES"); }

  { IupSetAttribute(b_text,"ALIGNMENT","ARIGHT:ATOP");
    char* v = IupGetAttribute(b_text,"ALIGNMENT");
    snprintf(buf,sizeof buf,"set ARIGHT:ATOP, native alignment=%ld, read back=%s",
             (long)[nb alignment], v?v:"(null)");
    chk([nb alignment]==NSTextAlignmentRight, "ALIGNMENT reaches the native button", buf); }

  { int w0 = b_text->naturalwidth, h0 = b_text->naturalheight;
    IupSetAttribute(b_text,"PADDING","20x10");
    IupRefresh(b_text);
    snprintf(buf,sizeof buf,"natural %dx%d -> %dx%d (expected +40x+20)",
             w0,h0,b_text->naturalwidth,b_text->naturalheight);
    chk(b_text->naturalwidth >= w0+40, "PADDING grows the natural size", buf); }

  { char* v = IupGetAttribute(b_both,"TITLE");
    NSButton* bb = (NSButton*)b_both->handle;
    snprintf(buf,sizeof buf,"title='%s' image=%s", v?v:"", [bb image]?"yes":"no");
    chk(v && *v && [bb image]!=nil, "TITLE + IMAGE both present", buf); }

  { /* IMINACTIVE on an ACTIVE button must not grey it, and must not be ignored */
    NSButton* plain = (NSButton*)b_both->handle;
    NSButton* imin  = (NSButton*)b_imin->handle;
    NSData* a = [[plain image] TIFFRepresentation];
    NSData* b = [[imin  image] TIFFRepresentation];
    chk(a && b && [a isEqualToData:b],
        "IMINACTIVE does not grey an ACTIVE button", (a&&b&&[a isEqualToData:b])?"same image":"DIFFERENT - greyed while active"); }

  printf("--- callbacks ---\n");
  { NSButton* bb = (NSButton*)b_text->handle;
    [bb performClick:nil];
    snprintf(buf,sizeof buf,"%d call(s)", g_action);
    chk(g_action>=1, "ACTION fires on click", buf); }
  { NSWindow* w = [nb window]; NSRect f=[nb bounds];
    NSPoint mid=[nb convertPoint:NSMakePoint(NSMidX(f),NSMidY(f)) toView:nil];
    /* NSButton's -mouseDown: enters the cell tracking loop and blocks until it can dequeue the
       matching mouse-up, so the release has to already be in the queue before the press is
       dispatched -- otherwise this deadlocks. */
    NSEvent* up=[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
      location:mid modifierFlags:0 timestamp:[NSDate timeIntervalSinceReferenceDate]
      windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1.0];
    if(up) [NSApp postEvent:up atStart:NO];
    NSEvent* down=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
      location:mid modifierFlags:0 timestamp:[NSDate timeIntervalSinceReferenceDate]
      windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1.0];
    if(down) [w sendEvent:down];
    snprintf(buf,sizeof buf,"%d call(s) (press+release expected)", g_button);
    chk(g_button>=2, "BUTTON_CB fires for press and release", buf); }

  printf("\n%d gap(s)\n", g_gaps);
  IupExitLoop(); return IUP_DEFAULT;
}

int main(int argc,char**argv)
{
  Ihandle *t,*dlg,*ia,*ib;
  setvbuf(stdout,NULL,_IONBF,0);
  IupOpen(&argc,&argv);
  ia=IupImage(4,4,imgA); IupSetAttribute(ia,"1","255 0 0"); IupSetAttribute(ia,"2","0 255 0");
  IupSetHandle("_BTN_A_",ia);
  ib=IupImage(4,4,imgB); IupSetAttribute(ib,"1","0 0 255"); IupSetAttribute(ib,"2","255 255 0");
  IupSetHandle("_BTN_B_",ib);

  b_text=IupButton("Press","");
  IupSetCallback(b_text,"ACTION",(Icallback)action_cb);
  IupSetCallback(b_text,"BUTTON_CB",(Icallback)button_cb);
  b_img=IupButton(NULL,""); IupSetAttribute(b_img,"IMAGE","_BTN_A_");
  b_both=IupButton("Both",""); IupSetAttribute(b_both,"IMAGE","_BTN_A_");
  b_imin=IupButton("Both",""); IupSetAttribute(b_imin,"IMAGE","_BTN_A_");
  IupSetAttribute(b_imin,"IMINACTIVE","_BTN_B_");   /* button stays ACTIVE */

  dlg=IupDialog(IupVbox(b_text,b_img,b_both,b_imin,NULL));
  IupSetAttribute(dlg,"TITLE","button parity");
  IupShow(dlg);
  t=IupTimer(); IupSetAttribute(t,"TIME","700");
  IupSetCallback(t,"ACTION_CB",run); IupSetAttribute(t,"RUN","YES");
  IupMainLoop(); return 0;
}
