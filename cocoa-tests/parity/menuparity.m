/* IupMenu / IupItem / IupSubmenu parity probe. Reads native NSMenuItem state. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <iup.h>
#include "iup_object.h"

static int g_gaps=0;
static Ihandle *it_check, *it_img, *it_hide, *sub, *sub_img, *menu;
static void chk(int c,const char* w,const char* g)
{ printf("%-4s %-50s %s\n",c?"ok  ":"GAP ",w,g?g:""); if(!c) g_gaps++; }

/* ih->handle for an item/submenu is the NSMenuItem */
static NSMenuItem* itemOf(Ihandle* ih){
  id h=(id)ih->handle;
  if([h isKindOfClass:[NSMenuItem class]]) return (NSMenuItem*)h;
  return nil;
}
static NSMenuItem* submenuItemOf(Ihandle* ih){
  id h=(id)ih->handle;
  if([h isKindOfClass:[NSMenuItem class]]) return (NSMenuItem*)h;
  if([h isKindOfClass:[NSMenu class]]) {
    /* find the item in the parent menu whose submenu is this NSMenu */
    for(NSMenuItem* mi in [[NSApp mainMenu] itemArray])
      if([mi submenu] == (NSMenu*)h) return mi;
  }
  return nil;
}
static unsigned char imgdata[4*4]={1,1,1,1,1,2,2,1,1,2,2,1,1,1,1,1};

static int run(Ihandle* t)
{
  char buf[220];
  static int running=0; if(running) return IUP_DEFAULT; running=1;
  IupSetAttribute(t,"RUN","NO");

  { NSMenuItem* mi=itemOf(it_check);
    id raw=(id)it_check->handle;
    snprintf(buf,sizeof buf,"handle=%s",raw?[NSStringFromClass([raw class]) UTF8String]:"NULL");
    chk(mi!=nil,"dialog MENU maps: item is an NSMenuItem",buf); }

  { NSMenuItem* mi=itemOf(it_check);
    char* v0=IupGetAttribute(it_check,"VALUE");
    IupSetAttribute(it_check,"VALUE","ON");
    char* v1=IupGetAttribute(it_check,"VALUE");
    NSInteger st=mi?[mi state]:-99;
    IupSetAttribute(it_check,"VALUE","OFF");
    char* v2=IupGetAttribute(it_check,"VALUE");
    snprintf(buf,sizeof buf,"start=%s ON->%s (native state=%ld) OFF->%s",
             v0?v0:"(null)",v1?v1:"(null)",(long)st,v2?v2:"(null)");
    chk(v1&&!strcmp(v1,"ON")&&st==NSControlStateValueOn&&v2&&!strcmp(v2,"OFF"),
        "item VALUE toggles the native checkmark",buf); }

  { NSMenuItem* mi=itemOf(it_img);
    IupSetAttribute(it_img,"IMAGE","_MENU_IMG_");
    snprintf(buf,sizeof buf,"native image=%s",(mi&&[mi image])?"set":"none");
    chk(mi&&[mi image]!=nil,"item IMAGE reaches the NSMenuItem",buf); }

  { NSMenuItem* mi=itemOf(it_hide);
    IupSetAttribute(it_hide,"VALUE","ON");
    IupSetAttribute(it_hide,"HIDEMARK","YES");
    snprintf(buf,sizeof buf,"state=%ld onStateImage=%s",mi?(long)[mi state]:-99,
             (mi&&[mi onStateImage])?"present":"suppressed");
    chk(mi&&[mi onStateImage]==nil,"item HIDEMARK suppresses the checkmark",buf); }

  { NSMenuItem* mi=submenuItemOf(sub);
    IupSetAttribute(sub,"ACTIVE","NO");
    BOOL off=mi?[mi isEnabled]:YES;
    IupSetAttribute(sub,"ACTIVE","YES");
    BOOL on=mi?[mi isEnabled]:NO;
    snprintf(buf,sizeof buf,"disabled->enabled=%d, enabled->enabled=%d",(int)off,(int)on);
    chk(mi&&!off&&on,"submenu ACTIVE enables/disables it",buf); }

  { NSMenuItem* mi=submenuItemOf(sub_img);
    IupSetAttribute(sub_img,"IMAGE","_MENU_IMG_");
    snprintf(buf,sizeof buf,"native image=%s",(mi&&[mi image])?"set":"none");
    chk(mi&&[mi image]!=nil,"submenu IMAGE reaches the NSMenuItem",buf); }

  { NSMenuItem* mi=itemOf(it_check);
    IupSetAttribute(it_check,"TITLE","Renamed");
    snprintf(buf,sizeof buf,"native title='%s'",mi?[[mi title] UTF8String]:"?");
    chk(mi&&[[mi title] isEqualToString:@"Renamed"],"item TITLE round-trips (baseline)",buf); }

  { /* An application that supplies a menu bar should get ITS menus, not its menus plus the
       placeholder File/Edit/Format/View/Window/Help that IupOpen installs. Index 0 is the
       application menu, which macOS requires and IUP cannot express. */
    NSMenu* bar=[NSApp mainMenu];
    NSMutableString* titles=[NSMutableString string];
    for(NSInteger i=0;i<[bar numberOfItems];i++)
      [titles appendFormat:@"%@%@",i?@" ":@"",[[bar itemAtIndex:i] title]];
    snprintf(buf,sizeof buf,"bar = %s",[titles UTF8String]);
    chk([bar numberOfItems]==3, "menu bar is the app menu plus only the IUP menus", buf); }

  printf("\n%d gap(s)\n",g_gaps);
  IupExitLoop(); return IUP_DEFAULT;
}

int main(int argc,char**argv)
{
  Ihandle *t,*dlg,*im,*inner;
  setvbuf(stdout,NULL,_IONBF,0);
  IupOpen(&argc,&argv);
  im=IupImage(4,4,imgdata); IupSetAttribute(im,"1","255 0 0"); IupSetAttribute(im,"2","0 0 255");
  IupSetHandle("_MENU_IMG_",im);

  /* A macOS menu bar contains only submenus, so the items under test live inside one -- which is
     how a real menu is built on every platform anyway. */
  it_check=IupItem("Checkable",NULL);
  it_img  =IupItem("WithImage",NULL);
  it_hide =IupItem("HideMark",NULL);
  inner   =IupMenu(it_check,it_img,it_hide,NULL);
  sub     =IupSubmenu("Sub",inner);
  sub_img =IupSubmenu("SubImg",IupMenu(IupItem("Inner2",NULL),NULL));
  menu=IupMenu(sub,sub_img,NULL);
  IupSetHandle("_MENU_",menu);

  dlg=IupDialog(IupVbox(IupLabel("menu parity"),NULL));
  IupSetAttribute(dlg,"TITLE","menu parity");
  IupSetAttribute(dlg,"MENU","_MENU_");
  IupShow(dlg);
  t=IupTimer(); IupSetAttribute(t,"TIME","700");
  IupSetCallback(t,"ACTION_CB",run); IupSetAttribute(t,"RUN","YES");
  IupMainLoop(); return 0;
}
