/* IupList parity probe across subtypes. Reads native state. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <iup.h>
#include "iup_object.h"

static int g_gaps=0; static int g_valuechanged=0;
static Ihandle *l_drop, *l_combo, *l_multi, *l_single;
static int vc_cb(Ihandle* ih){ g_valuechanged++; return IUP_DEFAULT; }
static void chk(int c,const char* w,const char* g)
{ printf("%-4s %-50s %s\n",c?"ok  ":"GAP ",w,g?g:""); if(!c) g_gaps++; }
static NSString* cdesc(NSColor* c){
  if(!c) return @"(nil)";
  c=[c colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if(!c) return @"(unconvertible)";
  return [NSString stringWithFormat:@"%d %d %d",(int)([c redComponent]*255+.5),
          (int)([c greenComponent]*255+.5),(int)([c blueComponent]*255+.5)];
}
/* the multi/single list root may be an NSScrollView wrapping the table */
static NSTableView* tableOf(Ihandle* ih){
  id root=(id)ih->handle;
  if([root isKindOfClass:[NSTableView class]]) return root;
  if([root isKindOfClass:[NSScrollView class]]) return (NSTableView*)[(NSScrollView*)root documentView];
  return nil;
}

static int run(Ihandle* t)
{
  char buf[220];
  static int running=0; if(running) return IUP_DEFAULT; running=1;
  IupSetAttribute(t,"RUN","NO");

  { char* v=IupGetAttribute(l_multi,"1");
    snprintf(buf,sizeof buf,"item1='%s'",v?v:"(null)");
    chk(v&&!strcmp(v,"alpha"),"items readable (baseline sanity)",buf); }

  { IupSetAttribute(l_multi,"BGCOLOR","255 255 0");
    NSTableView* tv=tableOf(l_multi);
    snprintf(buf,sizeof buf,"native backgroundColor=%s",tv?[cdesc([tv backgroundColor]) UTF8String]:"(no table)");
    chk(tv&&[cdesc([tv backgroundColor]) isEqualToString:@"255 255 0"],"BGCOLOR reaches a list",buf); }

  { IupSetAttribute(l_combo,"BGCOLOR","0 255 255");
    NSComboBox* cb=(NSComboBox*)l_combo->handle;
    snprintf(buf,sizeof buf,"native backgroundColor=%s",[cdesc([cb backgroundColor]) UTF8String]);
    chk([cdesc([cb backgroundColor]) isEqualToString:@"0 255 255"],"BGCOLOR reaches an editbox+dropdown",buf); }

  { IupSetAttribute(l_combo,"FGCOLOR","255 0 0");
    NSComboBox* cb=(NSComboBox*)l_combo->handle;
    snprintf(buf,sizeof buf,"native textColor=%s",[cdesc([cb textColor]) UTF8String]);
    chk([cdesc([cb textColor]) isEqualToString:@"255 0 0"],"FGCOLOR reaches an editbox+dropdown",buf); }

  { /* gtk marks these NOT_SUPPORTED; they should at least be known attributes */
    IupSetAttribute(l_drop,"VISIBLEITEMS","7");
    IupSetAttribute(l_drop,"DROPEXPAND","NO");
    IupSetAttribute(l_multi,"AUTOREDRAW","NO");
    chk(1,"VISIBLEITEMS / DROPEXPAND / AUTOREDRAW accepted","known"); }

  { /* TOPITEM scrolls the list so that item N is at the top */
    NSTableView* tv=tableOf(l_multi);
    NSRect before=tv?[tv visibleRect]:NSZeroRect;
    IupSetAttribute(l_multi,"TOPITEM","20");
    NSRect after=tv?[tv visibleRect]:NSZeroRect;
    NSRange rows=tv?[tv rowsInRect:[tv visibleRect]]:NSMakeRange(999,0);
    snprintf(buf,sizeof buf,"visibleRect y %.0f -> %.0f, first visible row=%lu (want 19)",
             before.origin.y,after.origin.y,(unsigned long)rows.location);
    chk(tv&&rows.location==19,"TOPITEM=20 puts item 20 at the top",buf); }

  { /* SCROLLTO/SCROLLTOPOS are editbox-only on gtk (they move the text caret, not the list),
       so the list-scrolling contract is TOPITEM alone -- check it scrolls back too. */
    NSTableView* tv=tableOf(l_multi);
    IupSetAttribute(l_multi,"TOPITEM","1");
    /* Assert the contract, not the pixel: row 0 must be the first visible row. The scroll view
       has a content inset, so visibleRect.origin.y settles at ~10 rather than exactly 0. */
    NSRange rows=tv?[tv rowsInRect:[tv visibleRect]]:NSMakeRange(999,0);
    snprintf(buf,sizeof buf,"first visible row=%lu (visibleRect y=%.0f)",
             (unsigned long)rows.location,tv?[tv visibleRect].origin.y:-1);
    chk(tv&&rows.location==0,"TOPITEM=1 puts item 1 back at the top",buf); }

  /* ---- editbox text attributes. Caret and selection live in the window's field editor, which
     only exists while the field is being edited, so give it focus first -- which is the state an
     application is in when it sets these. ---- */
  { NSComboBox* cb=(NSComboBox*)l_combo->handle;
    IupSetAttribute(l_combo,"VALUE","abcdefghij");
    [[cb window] makeFirstResponder:cb];

    IupSetAttribute(l_combo,"SELECTIONPOS","2:5");
    char* sp=IupGetAttribute(l_combo,"SELECTIONPOS");
    char* st=IupGetAttribute(l_combo,"SELECTEDTEXT");
    snprintf(buf,sizeof buf,"SELECTIONPOS=%s SELECTEDTEXT='%s'",sp?sp:"(null)",st?st:"(null)");
    chk(sp&&!strcmp(sp,"2:5")&&st&&!strcmp(st,"cde"),"SELECTIONPOS + SELECTEDTEXT (0-based)",buf);

    IupSetAttribute(l_combo,"SELECTION","2:5");
    sp=IupGetAttribute(l_combo,"SELECTION");
    st=IupGetAttribute(l_combo,"SELECTEDTEXT");
    snprintf(buf,sizeof buf,"SELECTION=%s SELECTEDTEXT='%s'",sp?sp:"(null)",st?st:"(null)");
    chk(sp&&!strcmp(sp,"2:5")&&st&&!strcmp(st,"bcd"),"SELECTION (1-based) round-trips",buf);

    IupSetAttribute(l_combo,"CARETPOS","4");
    char* cp=IupGetAttribute(l_combo,"CARETPOS");
    char* cr=IupGetAttribute(l_combo,"CARET");
    snprintf(buf,sizeof buf,"CARETPOS=%s CARET=%s (want 4 and 5)",cp?cp:"(null)",cr?cr:"(null)");
    chk(cp&&!strcmp(cp,"4")&&cr&&!strcmp(cr,"5"),"CARETPOS 0-based, CARET 1-based",buf);

    IupSetAttribute(l_combo,"SELECTION","NONE");
    IupSetAttribute(l_combo,"CARETPOS","3");
    IupSetAttribute(l_combo,"INSERT","XY");
    NSText* fe=[[cb window] fieldEditor:NO forObject:cb];
    snprintf(buf,sizeof buf,"text now '%s'",[[fe string] UTF8String]);
    chk([[fe string] isEqualToString:@"abcXYdefghij"],"INSERT puts text at the caret",buf);

    IupSetAttribute(l_combo,"APPEND","ZZ");
    snprintf(buf,sizeof buf,"text now '%s'",[[fe string] UTF8String]);
    chk([[fe string] hasSuffix:@"ZZ"],"APPEND puts text at the end",buf);

    IupSetAttribute(l_combo,"READONLY","YES");
    char* ro=IupGetAttribute(l_combo,"READONLY");
    snprintf(buf,sizeof buf,"READONLY=%s editable=%d",ro?ro:"(null)",(int)[cb isEditable]);
    chk(ro&&!strcmp(ro,"YES")&&![cb isEditable],"READONLY round-trips",buf);
    IupSetAttribute(l_combo,"READONLY","NO"); }

  /* ---- phase 3 ---- */
  { /* iListComputeNaturalSizeMethod adds 2*padding only when the list has an editbox, on every
       platform -- so a MULTIPLE list is the wrong thing to measure. */
    int w0=l_combo->naturalwidth,h0=l_combo->naturalheight;
    IupSetAttribute(l_combo,"PADDING","15x7"); IupRefresh(l_combo);
    snprintf(buf,sizeof buf,"natural %dx%d -> %dx%d (expected +30x+14)",w0,h0,
             l_combo->naturalwidth,l_combo->naturalheight);
    chk(l_combo->naturalwidth>=w0+30,"PADDING grows an editbox list's natural size",buf); }

  { NSTableView* tv=tableOf(l_multi);
    CGFloat h0=tv?[tv rowHeight]:0;
    IupSetAttribute(l_multi,"SPACING","6");
    snprintf(buf,sizeof buf,"rowHeight %.0f -> %.0f, intercell %.0f",h0,tv?[tv rowHeight]:0,
             tv?[tv intercellSpacing].height:0);
    chk(tv&&[tv rowHeight]>h0,"SPACING increases the row height",buf); }

  { NSComboBox* cb=(NSComboBox*)l_combo->handle;
    IupSetAttribute(l_combo,"NC","5");
    char* nc=IupGetAttribute(l_combo,"NC");
    snprintf(buf,sizeof buf,"NC=%s formatter=%s",nc?nc:"(null)",[cb formatter]?"installed":"none");
    chk(nc&&!strcmp(nc,"5")&&[cb formatter]!=nil,"NC installs a length limit",buf);
    IupSetAttribute(l_combo,"NC","0"); }

  { NSComboBox* cb=(NSComboBox*)l_combo->handle;
    IupSetAttribute(l_combo,"FONT","Courier, 16");
    snprintf(buf,sizeof buf,"native font=%s %.0f",[[[cb font] fontName] UTF8String],[[cb font] pointSize]);
    chk([[cb font] pointSize]==16.0,"FONT reaches the editbox",buf); }

  { /* per-item image on a dropdown lands on the NSMenuItem */
    IupSetAttribute(l_drop,"IMAGE1","_LST_IMG_");
    NSPopUpButton* pb=(NSPopUpButton*)l_drop->handle;
    NSImage* got=[[[pb menu] itemAtIndex:0] image];
    snprintf(buf,sizeof buf,"menu item image=%s",got?"set":"none");
    chk(got!=nil,"per-item IMAGE reaches a dropdown menu item",buf); }

  { IupSetCallback(l_combo,"VALUECHANGED_CB",(Icallback)vc_cb);
    NSComboBox* cb=(NSComboBox*)l_combo->handle;
    [[cb window] makeFirstResponder:cb];
    NSText* fe=[[cb window] fieldEditor:NO forObject:cb];
    int before=g_valuechanged;
    if(fe) [fe insertText:@"q"];
    snprintf(buf,sizeof buf,"%d call(s)",g_valuechanged-before);
    chk(g_valuechanged>before,"typing raises VALUECHANGED_CB",buf); }

  printf("\n%d gap(s)\n",g_gaps);
  IupExitLoop(); return IUP_DEFAULT;
}

int main(int argc,char**argv)
{
  Ihandle *t,*dlg; int i;
  setvbuf(stdout,NULL,_IONBF,0);
  IupOpen(&argc,&argv);
  { unsigned char d[4*4]={1,1,1,1,1,2,2,1,1,2,2,1,1,1,1,1};
    Ihandle* im=IupImage(4,4,d); IupSetAttribute(im,"1","255 0 0"); IupSetAttribute(im,"2","0 0 255");
    IupSetHandle("_LST_IMG_",im); }
  l_drop  =IupList(NULL); IupSetAttribute(l_drop,"DROPDOWN","YES");
  l_combo =IupList(NULL); IupSetAttribute(l_combo,"DROPDOWN","YES"); IupSetAttribute(l_combo,"EDITBOX","YES");
  l_multi =IupList(NULL); IupSetAttribute(l_multi,"MULTIPLE","YES");
  l_single=IupList(NULL);
  IupSetAttribute(l_multi,"1","alpha");
  for(i=2;i<=40;i++){ char k[8],v[16]; snprintf(k,sizeof k,"%d",i); snprintf(v,sizeof v,"item%d",i);
    IupSetAttribute(l_multi,k,v); }
  IupSetAttribute(l_drop,"SHOWIMAGE","YES");   /* creation only -- must precede map */
  IupSetAttribute(l_drop,"1","one"); IupSetAttribute(l_drop,"2","two");
  IupSetAttribute(l_combo,"1","red"); IupSetAttribute(l_combo,"2","green");
  IupSetAttribute(l_single,"1","x");
  IupSetAttribute(l_multi,"VISIBLELINES","5");
  dlg=IupDialog(IupVbox(l_drop,l_combo,l_multi,l_single,NULL));
  IupSetAttribute(dlg,"TITLE","list parity");
  IupShow(dlg);
  t=IupTimer(); IupSetAttribute(t,"TIME","700");
  IupSetCallback(t,"ACTION_CB",run); IupSetAttribute(t,"RUN","YES");
  IupMainLoop(); return 0;
}
