/* IupMenu / IupItem / IupSubmenu parity probe. Reads native NSMenuItem state. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <iup.h>
#include "iup_object.h"

static int g_gaps=0;
static Ihandle *it_check, *it_img, *it_hide, *sub, *sub_img, *menu;
/* accelerator cases: title -> expected keyEquivalent / modifier mask */
static Ihandle* g_accel[16];
static int accel_cb(Ihandle* ih){ return IUP_DEFAULT; }
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

  /* ---- accelerators ---- */
  {
    struct { const char* title; unichar key; NSEventModifierFlags mask; const char* label; } want[] = {
      {"&Save\tCtrl+S",            's',    NSEventModifierFlagControl,                            "Save"},
      {"Save A&ll\tCtrl+Shift+S",  's',    NSEventModifierFlagControl|NSEventModifierFlagShift,   "Save All"},
      {"Item with Image \tCtrl+M", 'm',    NSEventModifierFlagControl,                            "Item with Image"},
      {"Item && Acc\tCtrl+A",      'a',    NSEventModifierFlagControl,                            "Item & Acc"},
      {"ZoomP\tCtrl++",            '+',    NSEventModifierFlagControl,                            "ZoomP"},
      {"ZoomM\tCtrl+-",            '-',    NSEventModifierFlagControl,                            "ZoomM"},
      {"ZoomQ\tCtrl+'+'",          '+',    NSEventModifierFlagControl,                            "ZoomQ"},
      {"ZoomN\tCtrl_Num /",        '/',    NSEventModifierFlagControl,                            "ZoomN"},
      {"FindNextX\tF3",            0xF706, 0,                                                     "FindNextX"},
      {"ShiftF2X\tShift+F2",       0xF705, NSEventModifierFlagShift,                              "ShiftF2X"},
      {"CloseAllX\tCtrl+Shift+F4", 0xF707, NSEventModifierFlagControl|NSEventModifierFlagShift,   "CloseAllX"},
      {"OpacityX\tCtrl+/Ctrl-",    0,      0,                                                     "OpacityX"},
      {"PauseX\tCtrl+Break",       0,      0,                                                     "PauseX"},
      {"DelX\tDel",                0,      0,                                                     "DelX"},
    };
    int bad=0; char detail[200]=""; 
    for(unsigned i=0;i<sizeof(want)/sizeof(want[0]);i++){
      NSMenuItem* mi=itemOf(g_accel[i]);
      NSString* ke=mi?[mi keyEquivalent]:nil;
      NSEventModifierFlags m=mi?([mi keyEquivalentModifierMask]&NSEventModifierFlagDeviceIndependentFlagsMask):0;
      unichar got = (ke && [ke length]) ? [ke characterAtIndex:0] : 0;
      NSString* lbl = mi?[mi title]:@"";
      /* A fresh NSMenuItem defaults its modifier mask to Command. When there is no key
         equivalent AppKit ignores the mask entirely, so only assert it when a key is expected --
         writing a mask we never use would be pointless and risks touching adopted items. */
      int mask_ok = want[i].key ? (m==want[i].mask) : 1;
      if(got!=want[i].key || !mask_ok || ![lbl isEqualToString:[NSString stringWithUTF8String:want[i].label]]){
        bad++;
        if(!detail[0]) snprintf(detail,sizeof detail,"'%s': key U+%04X mask 0x%lX label '%s'",
          want[i].title,(unsigned)got,(unsigned long)m,[lbl UTF8String]);
      }
    }
    snprintf(buf,sizeof buf,"%d/%lu correct%s%s",(int)(sizeof(want)/sizeof(want[0]))-bad,
             (unsigned long)(sizeof(want)/sizeof(want[0])), bad?" -- first bad: ":"", bad?detail:"");
    chk(bad==0,"accelerators: key equivalent, modifiers and label",buf);
  }

  { /* an item with no ACTION must not claim the keystroke: the menu would consume it ahead of
       the responder chain and the dialog's K_* handler would never run */
    NSMenuItem* mi=itemOf(g_accel[14]);
    snprintf(buf,sizeof buf,"keyEquivalent='%s'",mi?[[mi keyEquivalent] UTF8String]:"?");
    chk(mi && [[mi keyEquivalent] length]==0,"no ACTION callback -> no key equivalent",buf); }

  { /* retitling without a tab must clear the shortcut we installed */
    IupSetAttribute(g_accel[0],"TITLE","SaveX");
    NSMenuItem* mi=itemOf(g_accel[0]);
    snprintf(buf,sizeof buf,"title='%s' keyEquivalent='%s'",[[mi title] UTF8String],
             [[mi keyEquivalent] UTF8String]);
    chk([[mi keyEquivalent] length]==0,"retitling without a tab clears the shortcut",buf); }

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
  {
    const char* titles[] = {
      "&Save\tCtrl+S","Save A&ll\tCtrl+Shift+S","Item with Image \tCtrl+M","Item && Acc\tCtrl+A",
      "ZoomP\tCtrl++","ZoomM\tCtrl+-","ZoomQ\tCtrl+'+'","ZoomN\tCtrl_Num /",
      "FindNextX\tF3","ShiftF2X\tShift+F2","CloseAllX\tCtrl+Shift+F4",
      "OpacityX\tCtrl+/Ctrl-","PauseX\tCtrl+Break","DelX\tDel",
      "NoActX\tCtrl+J",   /* index 14: deliberately no ACTION callback */
    };
    for(unsigned i=0;i<sizeof(titles)/sizeof(titles[0]);i++){
      g_accel[i]=IupItem(titles[i],NULL);
      if(i!=14) IupSetCallback(g_accel[i],"ACTION",(Icallback)accel_cb);
    }
  }
  inner   =IupMenu(it_check,it_img,it_hide,
                   g_accel[0],g_accel[1],g_accel[2],g_accel[3],g_accel[4],g_accel[5],g_accel[6],
                   g_accel[7],g_accel[8],g_accel[9],g_accel[10],g_accel[11],g_accel[12],
                   g_accel[13],g_accel[14],NULL);
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
