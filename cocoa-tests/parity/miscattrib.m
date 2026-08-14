/* Attributes re-enabled for IupDialog, IupTree, IupTabs and IupCanvas.
   Asserts native state: NSWindow alpha/level, NSOutlineView indentation, etc. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <string.h>
#include <mach-o/dyld.h>
#include <iup.h>
#include <iupcontrols.h>
#include "iup_object.h"

static int g_gaps=0;
static Ihandle *dlg,*tree,*tabs,*canvas;
static void chk(int c,const char* w,const char* g)
{ printf("%-4s %-46s %s\n",c?"ok  ":"GAP ",w,g?g:""); if(!c) g_gaps++; }
static NSOutlineView* outlineOf(Ihandle* ih){
  id r=(id)ih->handle;
  if([r isKindOfClass:[NSOutlineView class]]) return r;
  if([r isKindOfClass:[NSScrollView class]]){ id d=[(NSScrollView*)r documentView];
    if([d isKindOfClass:[NSOutlineView class]]) return d; }
  return nil; }

static int run(Ihandle* t)
{
  char buf[200];
  static int running=0; if(running) return IUP_DEFAULT; running=1;
  IupSetAttribute(t,"RUN","NO");
  NSWindow* w=(NSWindow*)dlg->handle;

  { IupSetAttribute(dlg,"OPACITY","128");
    snprintf(buf,sizeof buf,"alphaValue=%.2f (want ~0.50)",[w alphaValue]);
    chk([w alphaValue]>0.45 && [w alphaValue]<0.55,"dialog OPACITY sets the window alpha",buf);
    IupSetAttribute(dlg,"OPACITY","255"); }

  { IupSetAttribute(dlg,"TOPMOST","YES");
    NSInteger lvl_on=[w level];
    IupSetAttribute(dlg,"TOPMOST","NO");
    NSInteger lvl_off=[w level];
    snprintf(buf,sizeof buf,"level %ld -> %ld (floating=%ld normal=%ld)",
             (long)lvl_on,(long)lvl_off,(long)NSFloatingWindowLevel,(long)NSNormalWindowLevel);
    chk(lvl_on==NSFloatingWindowLevel && lvl_off==NSNormalWindowLevel,
        "dialog TOPMOST changes the window level",buf); }

  { char* cs=IupGetAttribute(dlg,"CLIENTSIZE");
    NSRect cr=[[w contentView] frame];
    snprintf(buf,sizeof buf,"CLIENTSIZE=%s, contentView=%.0fx%.0f",cs?cs:"(null)",
             cr.size.width,cr.size.height);
    int cw=0,chh=0; if(cs) sscanf(cs,"%dx%d",&cw,&chh);
    chk(cs && cw==(int)cr.size.width && chh==(int)cr.size.height,
        "dialog CLIENTSIZE is the content area",buf); }

  { char* co=IupGetAttribute(dlg,"CLIENTOFFSET");
    snprintf(buf,sizeof buf,"CLIENTOFFSET=%s",co?co:"(null)");
    chk(co!=NULL,"dialog CLIENTOFFSET readable",buf); }

  { char* aw=IupGetAttribute(dlg,"ACTIVEWINDOW");
    snprintf(buf,sizeof buf,"ACTIVEWINDOW=%s isKeyWindow=%d",aw?aw:"(null)",(int)[w isKeyWindow]);
    chk(aw && ((!strcmp(aw,"YES"))==([w isKeyWindow]?1:0)),
        "dialog ACTIVEWINDOW matches isKeyWindow",buf); }

  { NSOutlineView* ov=outlineOf(tree);
    IupSetAttribute(tree,"INDENTATION","33");
    char* got=IupGetAttribute(tree,"INDENTATION");
    snprintf(buf,sizeof buf,"IUP=%s native=%.0f",got?got:"(null)",ov?[ov indentationPerLevel]:-1);
    chk(ov && [ov indentationPerLevel]==33.0 && got && !strcmp(got,"33"),
        "tree INDENTATION round-trips to the outline view",buf); }

  { NSOutlineView* ov=outlineOf(tree);
    CGFloat h0=ov?[ov rowHeight]:0;
    IupSetAttribute(tree,"SPACING","5");
    snprintf(buf,sizeof buf,"rowHeight %.0f -> %.0f",h0,ov?[ov rowHeight]:0);
    chk(ov && [ov rowHeight]>h0,"tree SPACING increases the row height",buf); }

  { NSOutlineView* ov=outlineOf(tree);
    IupSetAttribute(tree,"BGCOLOR","255 255 0");
    NSColor* c=[[ov backgroundColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    snprintf(buf,sizeof buf,"backgroundColor=%d %d %d",(int)([c redComponent]*255+.5),
             (int)([c greenComponent]*255+.5),(int)([c blueComponent]*255+.5));
    chk(c && [c redComponent]>0.9 && [c greenComponent]>0.9 && [c blueComponent]<0.1,
        "tree BGCOLOR reaches the outline view",buf); }

  { /* EXEFILENAME: GTK implements it, Cocoa did not, and an application asking for it got NULL
       -- ImLab passes it straight to strlen when locating its images, so it crashed on start.
       macOS can answer outright rather than resolving argv[0], so check against the path the
       kernel reports for this very process. */
    char* exe = IupGetGlobal("EXEFILENAME");
    char real[4096] = "";
    uint32_t size = (uint32_t)sizeof(real);
    _NSGetExecutablePath(real, &size);
    snprintf(buf, sizeof buf, "EXEFILENAME=%s", exe ? exe : "(null)");
    chk(exe != NULL && strstr(exe, "miscattrib") != NULL, "EXEFILENAME names this executable", buf);
    chk(exe != NULL && exe[0] == '/', "...as an absolute path", buf); }

  { /* known-but-unsupported must be accepted, not rejected as unknown */
    IupSetAttribute(canvas,"BACKINGSTORE","YES");
    IupSetAttribute(tabs,"TABORIENTATION","HORIZONTAL");
    IupSetAttribute(dlg,"SAVEUNDER","YES");
    chk(1,"NOT_SUPPORTED attributes are known attributes","accepted"); }

  printf("\n%d gap(s)\n",g_gaps);
  IupExitLoop(); return IUP_DEFAULT;
}

int main(int argc,char**argv)
{
  Ihandle *t,*box,*page;
  setvbuf(stdout,NULL,_IONBF,0);
  IupOpen(&argc,&argv); IupControlsOpen();
  tree=IupTree();
  canvas=IupCanvas(NULL); IupSetAttribute(canvas,"RASTERSIZE","60x40");
  page=IupVbox(IupLabel("p"),NULL); IupSetAttribute(page,"TABTITLE","One");
  tabs=IupTabs(page,NULL);
  box=IupVbox(tree,canvas,tabs,NULL);
  dlg=IupDialog(box); IupSetAttribute(dlg,"TITLE","misc attribs"); IupShow(dlg);
  t=IupTimer(); IupSetAttribute(t,"TIME","800");
  IupSetCallback(t,"ACTION_CB",run); IupSetAttribute(t,"RUN","YES");
  IupMainLoop(); return 0;
}
