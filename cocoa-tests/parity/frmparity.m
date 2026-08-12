/* IupFrame parity probe: reads native NSBox state. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <iup.h>
#include "iup_object.h"

static int g_gaps=0;
static Ihandle *f_titled, *f_plain, *f_bg;
static void chk(int c,const char* w,const char* g)
{ printf("%-4s %-48s %s\n",c?"ok  ":"GAP ",w,g?g:""); if(!c) g_gaps++; }
static NSString* cdesc(NSColor* c){
  if(!c) return @"(nil)";
  c=[c colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if(!c) return @"(unconvertible)";
  return [NSString stringWithFormat:@"%d %d %d",(int)([c redComponent]*255+.5),
          (int)([c greenComponent]*255+.5),(int)([c blueComponent]*255+.5)];
}

static int run(Ihandle* t)
{
  char buf[200];
  static int running=0; if(running) return IUP_DEFAULT; running=1;
  IupSetAttribute(t,"RUN","NO");
  NSBox* box=(NSBox*)f_titled->handle;

  { char* v=IupGetAttribute(f_titled,"TITLE");
    snprintf(buf,sizeof buf,"IUP='%s' native='%s'",v?v:"(null)",[[box title] UTF8String]);
    chk(v&&!strcmp(v,"Group"),"TITLE round-trips",buf); }

  { IupSetAttribute(f_titled,"FGCOLOR","0 0 255");
    NSCell* tc=[box titleCell];
    NSColor* col=[tc respondsToSelector:@selector(textColor)]?[(NSTextFieldCell*)tc textColor]:nil;
    snprintf(buf,sizeof buf,"title colour=%s",[cdesc(col) UTF8String]);
    chk(col&&[cdesc(col) isEqualToString:@"0 0 255"],"FGCOLOR changes the frame title colour",buf); }

  { char* v=IupGetAttribute(f_titled,"BGCOLOR");
    chk(v!=NULL,"BGCOLOR readable on a titled frame",v?v:"(null)"); }

  { /* a titleless frame created with BGCOLOR must honour it (gtk/win: _IUPFRAME_HAS_BGCOLOR) */
    NSBox* bb=(NSBox*)f_bg->handle;
    char* v=IupGetAttribute(f_bg,"BGCOLOR");
    snprintf(buf,sizeof buf,"IUP='%s' native fill=%s",v?v:"(null)",[cdesc([bb fillColor]) UTF8String]);
    /* check the NATIVE fill: IupGetAttribute alone just echoes the stored string, so it passed
       even when nothing had been applied to the NSBox. */
    chk(v&&!strcmp(v,"255 0 0")&&[cdesc([bb fillColor]) isEqualToString:@"255 0 0"],
        "BGCOLOR honoured on a titleless frame",buf); }

  { /* SUNKEN only applies when there is no title, matching gtk */
    NSBox* pb=(NSBox*)f_plain->handle;
    NSBorderType before=[pb borderType]; NSBoxType bt_before=[pb boxType];
    IupSetAttribute(f_plain,"SUNKEN","YES");
    snprintf(buf,sizeof buf,"borderType %ld->%ld boxType %ld->%ld",(long)before,(long)[pb borderType],
             (long)bt_before,(long)[pb boxType]);
    chk(([pb borderType]!=before)||([pb boxType]!=bt_before),"SUNKEN changes the frame border",buf); }

  printf("\n%d gap(s)\n",g_gaps);
  IupExitLoop(); return IUP_DEFAULT;
}

int main(int argc,char**argv)
{
  Ihandle *t,*dlg;
  setvbuf(stdout,NULL,_IONBF,0);
  IupOpen(&argc,&argv);
  f_titled=IupFrame(IupLabel("inside")); IupSetAttribute(f_titled,"TITLE","Group");
  f_plain =IupFrame(IupLabel("plain"));
  f_bg    =IupFrame(IupLabel("bg"));  IupSetAttribute(f_bg,"BGCOLOR","255 0 0");
  dlg=IupDialog(IupVbox(f_titled,f_plain,f_bg,NULL));
  IupSetAttribute(dlg,"TITLE","frame parity");
  IupShow(dlg);
  t=IupTimer(); IupSetAttribute(t,"TIME","700");
  IupSetCallback(t,"ACTION_CB",run); IupSetAttribute(t,"RUN","YES");
  IupMainLoop(); return 0;
}
