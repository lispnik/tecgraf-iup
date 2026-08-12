/* ENTERWINDOW_CB / LEAVEWINDOW_CB are registered by iupBaseRegisterCommonCallbacks for every
   control, so they must work on more than IupLabel. Tracking is installed generically by
   iupCocoaAddToParent, so this drives the tracking area's owner directly. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <iup.h>
#include "iup_object.h"

static int g_gaps=0;
static void chk(int c,const char* w,const char* g)
{ printf("%-4s %-46s %s\n",c?"ok  ":"GAP ",w,g?g:""); if(!c) g_gaps++; }

#define NCTRL 5
static Ihandle* g_ctrl[NCTRL];
static const char* g_name[NCTRL]={"IupButton","IupText","IupCanvas","IupToggle","IupList"};
static int g_enter[NCTRL], g_leave[NCTRL];
static int enter_cb(Ihandle* ih){ for(int i=0;i<NCTRL;i++) if(g_ctrl[i]==ih) g_enter[i]++; return IUP_DEFAULT; }
static int leave_cb(Ihandle* ih){ for(int i=0;i<NCTRL;i++) if(g_ctrl[i]==ih) g_leave[i]++; return IUP_DEFAULT; }

static int run(Ihandle* t)
{
  char buf[220];
  static int running=0; if(running) return IUP_DEFAULT; running=1;
  IupSetAttribute(t,"RUN","NO");

  for(int i=0;i<NCTRL;i++){
    NSView* v=(NSView*)g_ctrl[i]->handle;
    NSArray* areas=[v trackingAreas];
    NSEvent* e=[NSEvent enterExitEventWithType:NSEventTypeMouseEntered location:NSZeroPoint
      modifierFlags:0 timestamp:0 windowNumber:[[v window] windowNumber] context:nil
      eventNumber:0 trackingNumber:0 userData:NULL];
    id owner=[areas count]?[[areas firstObject] owner]:nil;
    if(owner){ [owner mouseEntered:e]; [owner mouseExited:e]; }
    snprintf(buf,sizeof buf,"%lu tracking area(s), enter=%d leave=%d",
             (unsigned long)[areas count],g_enter[i],g_leave[i]);
    chk([areas count]==1 && g_enter[i]==1 && g_leave[i]==1, g_name[i], buf);
  }

  printf("\n%d gap(s)\n",g_gaps);
  IupExitLoop(); return IUP_DEFAULT;
}

int main(int argc,char**argv)
{
  Ihandle *t,*dlg,*box;
  setvbuf(stdout,NULL,_IONBF,0);
  IupOpen(&argc,&argv);
  g_ctrl[0]=IupButton("b",NULL);
  g_ctrl[1]=IupText(NULL);
  g_ctrl[2]=IupCanvas(NULL); IupSetAttribute(g_ctrl[2],"RASTERSIZE","80x40");
  g_ctrl[3]=IupToggle("t",NULL);
  g_ctrl[4]=IupList(NULL); IupSetAttribute(g_ctrl[4],"1","x");
  box=IupVbox(g_ctrl[0],g_ctrl[1],g_ctrl[2],g_ctrl[3],g_ctrl[4],NULL);
  for(int i=0;i<NCTRL;i++){
    IupSetCallback(g_ctrl[i],"ENTERWINDOW_CB",(Icallback)enter_cb);
    IupSetCallback(g_ctrl[i],"LEAVEWINDOW_CB",(Icallback)leave_cb);
  }
  dlg=IupDialog(box); IupSetAttribute(dlg,"TITLE","enter/leave"); IupShow(dlg);
  t=IupTimer(); IupSetAttribute(t,"TIME","700");
  IupSetCallback(t,"ACTION_CB",run); IupSetAttribute(t,"RUN","YES");
  IupMainLoop(); return 0;
}
