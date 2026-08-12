/* Do IupLabel mouse callbacks fire? Sends real NSEvents through the window's dispatch. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <iup.h>
#include "iup_object.h"

static int g_button = 0, g_motion = 0, g_enter = 0, g_leave = 0, g_fail = 0;
static int g_last_but = 0, g_last_pressed = -1, g_last_x = -1, g_last_y = -1;
static Ihandle *lbl_text, *lbl_img;

static int button_cb(Ihandle* ih, int but, int pressed, int x, int y, char* status)
{ g_button++; g_last_but=but; g_last_pressed=pressed; g_last_x=x; g_last_y=y; return IUP_DEFAULT; }
static int motion_cb(Ihandle* ih, int x, int y, char* status) { g_motion++; return IUP_DEFAULT; }
static int enter_cb(Ihandle* ih) { g_enter++; return IUP_DEFAULT; }
static int leave_cb(Ihandle* ih) { g_leave++; return IUP_DEFAULT; }

static void ok(int cond, const char* what, const char* got)
{ printf("%-4s %-44s %s\n", cond?"PASS":"FAIL", what, got?got:""); if(!cond) g_fail++; }

static void send_click(NSView* view, NSEventType down, NSEventType up)
{
  NSWindow* win = [view window];
  NSRect f = [view bounds];
  NSPoint mid = [view convertPoint:NSMakePoint(NSMidX(f), NSMidY(f)) toView:nil];
  for (int i = 0; i < 2; i++) {
    NSEvent* e = [NSEvent mouseEventWithType:(i==0?down:up) location:mid
      modifierFlags:0 timestamp:[NSDate timeIntervalSinceReferenceDate]
      windowNumber:[win windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1.0];
    if (e) [win sendEvent:e];
  }
}

static int run(Ihandle* t)
{
  /* One shot: the counters below are cumulative, and a repeating timer would re-run the whole
     suite and report spurious failures on the second pass. */
  static int already_running = 0;
  if (already_running) return IUP_DEFAULT;
  already_running = 1;
  IupSetAttribute(t, "RUN", "NO");
  char buf[160];
  NSView* tv = (NSView*)lbl_text->handle;
  NSView* iv = (NSView*)lbl_img->handle;

  send_click(tv, NSEventTypeLeftMouseDown, NSEventTypeLeftMouseUp);
  snprintf(buf,sizeof buf,"%d calls, last but=%c pressed=%d at %d,%d",
           g_button, (char)g_last_but, g_last_pressed, g_last_x, g_last_y);
  ok(g_button >= 2, "BUTTON_CB fires on a text label (down+up)", buf);
  ok(g_last_pressed == 0, "BUTTON_CB reports the release, not only press", g_last_pressed==0?"got release":"NO release seen");

  g_button = 0;
  send_click(iv, NSEventTypeLeftMouseDown, NSEventTypeLeftMouseUp);
  snprintf(buf,sizeof buf,"%d calls", g_button);
  ok(g_button >= 2, "BUTTON_CB fires on an image label", buf);

  {
    NSRect f = [tv bounds];
    NSPoint mid = [tv convertPoint:NSMakePoint(NSMidX(f), NSMidY(f)) toView:nil];
    NSEvent* e = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged location:mid
      modifierFlags:0 timestamp:[NSDate timeIntervalSinceReferenceDate]
      windowNumber:[[tv window] windowNumber] context:nil eventNumber:0 clickCount:0 pressure:1.0];
    if (e) [[tv window] sendEvent:e];
    snprintf(buf,sizeof buf,"%d calls", g_motion);
    ok(g_motion >= 1, "MOTION_CB fires on drag", buf);
  }

  snprintf(buf,sizeof buf,"%lu area(s)", (unsigned long)[[tv trackingAreas] count]);
  ok([[tv trackingAreas] count] > 0, "tracking area installed for enter/leave", buf);
  {
    /* +mouseEventWithType: raises for enter/exit types; these need the enter/exit constructor. */
    NSEvent* e = [NSEvent enterExitEventWithType:NSEventTypeMouseEntered location:NSZeroPoint
      modifierFlags:0 timestamp:0 windowNumber:[[tv window] windowNumber] context:nil
      eventNumber:0 trackingNumber:0 userData:NULL];
    [tv mouseEntered:e]; [tv mouseExited:e];
    snprintf(buf,sizeof buf,"enter=%d leave=%d", g_enter, g_leave);
    ok(g_enter==1 && g_leave==1, "ENTERWINDOW_CB / LEAVEWINDOW_CB fire", buf);
  }

  printf("\n%d failure(s)\n", g_fail);
  IupExitLoop(); return IUP_DEFAULT;
}

static unsigned char img8[4*4] = {1,1,1,1, 1,2,2,1, 1,2,2,1, 1,1,1,1};

int main(int argc, char** argv)
{
  Ihandle *t, *dlg, *img;
  setvbuf(stdout,NULL,_IONBF,0);
  IupOpen(&argc,&argv);
  img = IupImage(4,4,img8);
  IupSetAttribute(img,"1","255 0 0"); IupSetAttribute(img,"2","0 255 0");
  IupSetHandle("_CB_IMG_", img);

  lbl_text = IupLabel("Click me, I am a reasonably wide label");
  lbl_img  = IupLabel(NULL); IupSetAttribute(lbl_img,"IMAGE","_CB_IMG_");
  IupSetAttribute(lbl_img,"RASTERSIZE","60x40");
  for (int i=0;i<2;i++) {
    Ihandle* l = i? lbl_img : lbl_text;
    IupSetCallback(l,"BUTTON_CB",(Icallback)button_cb);
    IupSetCallback(l,"MOTION_CB",(Icallback)motion_cb);
    IupSetCallback(l,"ENTERWINDOW_CB",(Icallback)enter_cb);
    IupSetCallback(l,"LEAVEWINDOW_CB",(Icallback)leave_cb);
  }
  dlg = IupDialog(IupVbox(lbl_text, lbl_img, NULL));
  IupSetAttribute(dlg,"TITLE","label callbacks");
  IupShow(dlg);
  t=IupTimer(); IupSetAttribute(t,"TIME","700");
  IupSetCallback(t,"ACTION_CB",run); IupSetAttribute(t,"RUN","YES");
  IupMainLoop();
  return g_fail;
}
