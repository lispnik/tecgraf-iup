/* IupToggle parity probe. Reads native NSButton state; no screenshots. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <iup.h>
#include "iup_object.h"

static int g_gaps = 0;
static Ihandle *t_text, *t_img, *t_imin, *r1, *r2;

static void chk(int cond, const char* what, const char* got)
{ printf("%-4s %-46s %s\n", cond?"ok  ":"GAP ", what, got?got:""); if(!cond) g_gaps++; }

static NSString* fgOf(NSButton* b){
  NSAttributedString* a=[b attributedTitle];
  if(!a||[a length]==0) return @"(no title)";
  NSColor* c=[a attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
  if(!c) return @"(no colour attr)";
  c=[c colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  return [NSString stringWithFormat:@"%d %d %d",(int)([c redComponent]*255+.5),
          (int)([c greenComponent]*255+.5),(int)([c blueComponent]*255+.5)];
}
static NSData* refCellImage(NSButtonType t){
  NSButton* b=[[NSButton alloc] initWithFrame:NSMakeRect(0,0,100,24)];
  [b setTitle:@"x"]; [b setButtonType:t];
  return [[(NSButtonCell*)[b cell] image] TIFFRepresentation];
}
static unsigned char imgA[4*4]={1,1,1,1,1,2,2,1,1,2,2,1,1,1,1,1};
static unsigned char imgB[4*4]={2,2,2,2,2,1,1,2,2,1,1,2,2,2,2,2};

static int run(Ihandle* t)
{
  char buf[220];
  static int running=0; if(running) return IUP_DEFAULT; running=1;
  IupSetAttribute(t,"RUN","NO");
  NSButton* nb=(NSButton*)t_text->handle;

  IupSetAttribute(t_text,"FGCOLOR","0 0 255");
  chk([fgOf(nb) isEqualToString:@"0 0 255"], "FGCOLOR changes the toggle text colour", [fgOf(nb) UTF8String]);

  { char* v=IupGetAttribute(t_text,"BGCOLOR"); chk(v!=NULL,"BGCOLOR readable",v?v:"(null)"); }

  { IupSetAttribute(t_text,"VALUE","ON");  char* on=IupGetAttribute(t_text,"VALUE");
    IupSetAttribute(t_text,"VALUE","OFF"); char* off=IupGetAttribute(t_text,"VALUE");
    snprintf(buf,sizeof buf,"ON->%s OFF->%s",on?on:"?",off?off:"?");
    chk(on&&off&&!strcmp(on,"ON")&&!strcmp(off,"OFF"),"VALUE round-trips",buf); }

  { /* a toggle inside an IupRadio must render as a radio, not a checkbox */
    NSButton* rb=(NSButton*)r1->handle;
    NSData* cell=[[(NSButtonCell*)[rb cell] image] TIFFRepresentation];
    int is_radio=cell && [cell isEqualToData:refCellImage(NSButtonTypeRadio)];
    int is_switch=cell && [cell isEqualToData:refCellImage(NSButtonTypeSwitch)];
    snprintf(buf,sizeof buf,"RADIO attr=%s, native=%s",
      IupGetAttribute(r1,"RADIO")?IupGetAttribute(r1,"RADIO"):"?",
      is_radio?"radio":(is_switch?"CHECKBOX":"unknown"));
    chk(is_radio,"toggle in IupRadio renders as a radio button",buf); }

  { NSButton* ib=(NSButton*)t_img->handle;
    chk([ib image]!=nil,"IMAGE set BEFORE map shows an image",[ib image]?"has image":"none");
    NSData* before=[[ib image] TIFFRepresentation];
    IupSetAttribute(t_img,"IMAGE","_TG_B_");
    NSData* after=[[ib image] TIFFRepresentation];
    chk(before&&after&&![before isEqualToData:after],"IMAGE changed AFTER map updates the toggle",NULL); }

  { NSButton* ib=(NSButton*)t_img->handle;
    NSData* before=[[ib image] TIFFRepresentation];
    IupSetAttribute(t_img,"ACTIVE","NO");
    NSData* after=[[ib image] TIFFRepresentation];
    chk(before&&after&&![before isEqualToData:after],"ACTIVE=NO greys the image",NULL);
    IupSetAttribute(t_img,"ACTIVE","YES"); }

  { /* restore t_img's image first: the IMAGE test above changed it to _TG_B_ */
    IupSetAttribute(t_img,"IMAGE","_TG_A_");
    NSButton* plain=(NSButton*)t_img->handle; NSButton* imin=(NSButton*)t_imin->handle;
    NSData* a=[[plain image] TIFFRepresentation]; NSData* b=[[imin image] TIFFRepresentation];
    chk(a&&b&&[a isEqualToData:b],"IMINACTIVE does not grey an ACTIVE toggle",
        (a&&b&&[a isEqualToData:b])?"same image":"DIFFERENT - greyed while active"); }

  { IupSetAttribute(t_text,"ALIGNMENT","ARIGHT:ACENTER");
    snprintf(buf,sizeof buf,"native alignment=%ld (Right=%ld), read back=%s",
      (long)[nb alignment],(long)NSTextAlignmentRight,
      IupGetAttribute(t_text,"ALIGNMENT")?IupGetAttribute(t_text,"ALIGNMENT"):"(null)");
    chk([nb alignment]==NSTextAlignmentRight,"ALIGNMENT reaches the native toggle",buf); }

  { /* iToggleComputeNaturalSizeMethod adds 2*padding only for IMAGE toggles -- a text toggle is
       sized by iupdrvToggleAddCheckBox instead, on every platform. So test the image one. */
    int w0=t_img->naturalwidth,h0=t_img->naturalheight;
    IupSetAttribute(t_img,"PADDING","20x10"); IupRefresh(t_img);
    snprintf(buf,sizeof buf,"%dx%d -> %dx%d (expected +40x+20)",w0,h0,t_img->naturalwidth,t_img->naturalheight);
    chk(t_img->naturalwidth>=w0+40,"PADDING grows an image toggle's natural size",buf); }

  { /* selecting one radio must clear the other; Cocoa only auto-clears siblings that share a
       superview and an action, and never for a programmatic change. */
    IupSetAttribute(r1,"VALUE","ON");
    IupSetAttribute(r2,"VALUE","ON");
    char* v1=IupGetAttribute(r1,"VALUE"); char* v2=IupGetAttribute(r2,"VALUE");
    snprintf(buf,sizeof buf,"after r2=ON: r1=%s r2=%s",v1?v1:"?",v2?v2:"?");
    chk(v1&&v2&&!strcmp(v1,"OFF")&&!strcmp(v2,"ON"),"radio selection is mutually exclusive",buf);
    IupSetAttribute(r1,"VALUE","ON");
    v1=IupGetAttribute(r1,"VALUE"); v2=IupGetAttribute(r2,"VALUE");
    snprintf(buf,sizeof buf,"after r1=ON: r1=%s r2=%s",v1?v1:"?",v2?v2:"?");
    chk(v1&&v2&&!strcmp(v1,"ON")&&!strcmp(v2,"OFF"),"radio exclusivity works both ways",buf); }

  printf("\n%d gap(s)\n",g_gaps);
  IupExitLoop(); return IUP_DEFAULT;
}

int main(int argc,char**argv)
{
  Ihandle *t,*dlg,*ia,*ib,*radio;
  setvbuf(stdout,NULL,_IONBF,0);
  IupOpen(&argc,&argv);
  ia=IupImage(4,4,imgA); IupSetAttribute(ia,"1","255 0 0"); IupSetAttribute(ia,"2","0 255 0");
  IupSetHandle("_TG_A_",ia);
  ib=IupImage(4,4,imgB); IupSetAttribute(ib,"1","0 0 255"); IupSetAttribute(ib,"2","255 255 0");
  IupSetHandle("_TG_B_",ib);

  t_text=IupToggle("Check me",NULL);
  t_img =IupToggle(NULL,NULL); IupSetAttribute(t_img,"IMAGE","_TG_A_");
  t_imin=IupToggle(NULL,NULL); IupSetAttribute(t_imin,"IMAGE","_TG_A_");
  IupSetAttribute(t_imin,"IMINACTIVE","_TG_B_");
  r1=IupToggle("One",NULL); r2=IupToggle("Two",NULL);
  radio=IupRadio(IupVbox(r1,r2,NULL));

  dlg=IupDialog(IupVbox(t_text,t_img,t_imin,radio,NULL));
  IupSetAttribute(dlg,"TITLE","toggle parity");
  IupShow(dlg);
  t=IupTimer(); IupSetAttribute(t,"TIME","700");
  IupSetCallback(t,"ACTION_CB",run); IupSetAttribute(t,"RUN","YES");
  IupMainLoop(); return 0;
}
