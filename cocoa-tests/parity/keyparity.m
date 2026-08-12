/* Does MODKEYSTATE work outside an event callback, and how does a Cmd key arrive at K_ANY? */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <iup.h>
#include <iupkey.h>
#include <string.h>
static Ihandle *dlg; static int g_last; static int g_gaps=0;
static void chk(int c,const char* w,const char* g)
{ printf("%-4s %-50s %s\n",c?"ok  ":"GAP ",w,g?g:""); if(!c) g_gaps++; }
static int k_any(Ihandle* ih, int c){ g_last=c;
  return IUP_DEFAULT;
}
static int probe(Ihandle* t){
  static int r=0; if(r) return IUP_DEFAULT; r=1; IupSetAttribute(t,"RUN","NO");
  { char* mk=IupGetGlobal("MODKEYSTATE"); char b[80];
    snprintf(b,sizeof b,"'%s' (4 chars: Shift Ctrl Option Command)",mk?mk:"(null)");
    /* Cannot assert a held modifier without physical input; assert it is well formed and
       queryable outside an event, which is what the old currentEvent version could not do. */
    chk(mk && strlen(mk)==4, "MODKEYSTATE is queryable outside an event callback", b); }
  { NSWindow* w=[NSApp windows][0];
    struct { const char* name; NSEventModifierFlags flag; NSString* chars; int expect; } cases[] = {
      {"Cmd+C",     NSEventModifierFlagCommand, @"c",  K_yC},
      {"Ctrl+C",    NSEventModifierFlagControl, @"c",  K_cC},
      {"Option+C",  NSEventModifierFlagOption,  @"\u00e7", K_mC},  /* macOS composes ç */
      {"plain c",   0,                          @"c",  K_c},
    };
    for(unsigned i=0;i<sizeof(cases)/sizeof(cases[0]);i++){
      g_last=0;
      NSEvent* e=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:cases[i].flag timestamp:[NSDate timeIntervalSinceReferenceDate]
        windowNumber:[w windowNumber] context:nil characters:cases[i].chars
        charactersIgnoringModifiers:@"c" isARepeat:NO keyCode:8];
      if(e) [w sendEvent:e];
      { char b[120]; snprintf(b,sizeof b,"got 0x%08X expected 0x%08X",(unsigned)g_last,(unsigned)cases[i].expect);
        chk(g_last==cases[i].expect, cases[i].name, b); }
    } }
  printf("\n%d gap(s)\n",g_gaps);
  IupExitLoop(); return IUP_DEFAULT;
}
int main(int argc,char**argv){ Ihandle* t; setvbuf(stdout,NULL,_IONBF,0);
  IupOpen(&argc,&argv);
  dlg=IupDialog(IupVbox(IupLabel("modkey"),NULL));
  IupSetCallback(dlg,"K_ANY",(Icallback)k_any);
  IupShow(dlg);
  t=IupTimer(); IupSetAttribute(t,"TIME","600"); IupSetCallback(t,"ACTION_CB",probe);
  IupSetAttribute(t,"RUN","YES"); IupMainLoop(); return 0; }
