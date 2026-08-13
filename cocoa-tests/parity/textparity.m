/* IupText against the native NSTextField / NSTextView.

   IupText was in far better shape than the other controls when this was written: comparing
   live registrations (with #if 0 regions stripped -- grep alone counts the dead copies and
   makes the driver look complete) showed only three of GTK's attributes disabled here,
   OVERWRITE, PADDING and TABSIZE. So most of this harness is verification rather than a list
   of known gaps, which is the point: an attribute with a registered setter can still do
   nothing.

   PASSWORD is deliberately not asserted as a gap: it is registered NULL/NULL on GTK too and
   is handled at map time from the attribute, so the registration proves nothing either way.
   It is checked through the native class instead. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <string.h>
#include <iup.h>
#include "iup_object.h"

static int g_gaps = 0;
static Ihandle *dlg, *single, *multi, *pass, *spin;

static void chk(int c, const char* w, const char* g)
{ printf("%-4s %-52s %s\n", c ? "ok  " : "GAP ", w, g ? g : ""); if (!c) g_gaps++; }

/* ih->handle is the outermost view: a scroll view for multiline, and for a spin the box that
   holds the field and the stepper. */
static NSTextView* textViewOf(Ihandle* ih)
{
  id root = (id)ih->handle;
  if ([root isKindOfClass:[NSTextView class]]) return root;
  if ([root isKindOfClass:[NSScrollView class]])
  { id doc = [(NSScrollView*)root documentView];
    if ([doc isKindOfClass:[NSTextView class]]) return doc; }
  return nil;
}

static NSTextField* fieldOf(Ihandle* ih)
{
  id root = (id)ih->handle;
  if ([root isKindOfClass:[NSTextField class]]) return root;
  for (NSView* sub in [(NSView*)root subviews])
    if ([sub isKindOfClass:[NSTextField class]]) return (NSTextField*)sub;
  return nil;
}

static int run(Ihandle* t)
{
  char buf[300];
  static int running = 0; if (running) return IUP_DEFAULT; running = 1;
  IupSetAttribute(t, "RUN", "NO");

  NSTextField* nf = fieldOf(single);
  NSTextView*  nv = textViewOf(multi);

  chk(nf != nil, "single-line IupText is an NSTextField",
      nf ? [[nf className] UTF8String] : "not found");
  chk(nv != nil, "multiline IupText is an NSTextView",
      nv ? [[nv className] UTF8String] : "not found");
  if (!nf || !nv) { printf("%d gap(s)\n", g_gaps); IupExitLoop(); return IUP_DEFAULT; }

  /* ---- VALUE both ways ---- */
  IupSetAttribute(single, "VALUE", "hello");
  snprintf(buf, sizeof buf, "native='%s'", [[nf stringValue] UTF8String]);
  chk(0 == strcmp([[nf stringValue] UTF8String], "hello"),
      "VALUE reaches the NSTextField", buf);

  [nf setStringValue:@"typed"];
  { char* v = IupGetAttribute(single, "VALUE");
    snprintf(buf, sizeof buf, "IupGetAttribute='%s'", v ? v : "(null)");
    chk(v && 0 == strcmp(v, "typed"), "VALUE reads back from the NSTextField", buf); }

  IupSetAttribute(multi, "VALUE", "line one\nline two\nline three");
  snprintf(buf, sizeof buf, "storage length=%lu", (unsigned long)[[nv textStorage] length]);
  chk(0 == strcmp([[[nv textStorage] string] UTF8String], "line one\nline two\nline three"),
      "VALUE reaches the NSTextView", buf);

  /* ---- line/char counting, which is shared code reading the driver ---- */
  { char* lc = IupGetAttribute(multi, "LINECOUNT");
    snprintf(buf, sizeof buf, "LINECOUNT=%s (want 3)", lc ? lc : "(null)");
    chk(lc && 0 == strcmp(lc, "3"), "LINECOUNT counts the lines", buf); }

  { IupSetAttribute(multi, "CARET", "2,1");
    char* lv = IupGetAttribute(multi, "LINEVALUE");
    snprintf(buf, sizeof buf, "LINEVALUE='%s' (want 'line two')", lv ? lv : "(null)");
    chk(lv && 0 == strcmp(lv, "line two"), "LINEVALUE returns the caret's line", buf); }

  /* ---- selection ---- */
  { IupSetAttribute(multi, "SELECTIONPOS", "0:8");
    NSRange sel = [nv selectedRange];
    snprintf(buf, sizeof buf, "native selection=%lu,%lu (want 0,8)",
             (unsigned long)sel.location, (unsigned long)sel.length);
    chk(sel.location == 0 && sel.length == 8, "SELECTIONPOS moves the native selection", buf); }

  { char* st = IupGetAttribute(multi, "SELECTEDTEXT");
    snprintf(buf, sizeof buf, "SELECTEDTEXT='%s' (want 'line one')", st ? st : "(null)");
    chk(st && 0 == strcmp(st, "line one"), "SELECTEDTEXT returns the selection", buf); }

  /* ---- caret ---- */
  { IupSetAttribute(multi, "CARETPOS", "5");
    NSRange sel = [nv selectedRange];
    snprintf(buf, sizeof buf, "native caret=%lu (want 5)", (unsigned long)sel.location);
    chk(sel.location == 5, "CARETPOS moves the native caret", buf); }

  /* ---- APPEND / INSERT ---- */
  { IupSetAttribute(single, "VALUE", "abc");
    IupSetAttribute(single, "APPEND", "def");
    snprintf(buf, sizeof buf, "native='%s' (want 'abcdef')", [[nf stringValue] UTF8String]);
    chk(0 == strcmp([[nf stringValue] UTF8String], "abcdef"), "APPEND appends", buf); }

  /* ---- READONLY ---- */
  { IupSetAttribute(single, "READONLY", "YES");
    BOOL editable_ro = [nf isEditable];
    IupSetAttribute(single, "READONLY", "NO");
    BOOL editable_rw = [nf isEditable];
    snprintf(buf, sizeof buf, "isEditable %d -> %d", editable_ro, editable_rw);
    chk(!editable_ro && editable_rw, "READONLY controls NSTextField editability", buf); }

  { IupSetAttribute(multi, "READONLY", "YES");
    BOOL ro = [nv isEditable];
    IupSetAttribute(multi, "READONLY", "NO");
    snprintf(buf, sizeof buf, "isEditable=%d then %d", ro, [nv isEditable]);
    chk(!ro && [nv isEditable], "READONLY controls NSTextView editability", buf); }

  /* ---- PASSWORD: proven through the native class, not the registration ---- */
  { NSTextField* pf = fieldOf(pass);
    snprintf(buf, sizeof buf, "class=%s", pf ? [[pf className] UTF8String] : "(none)");
    chk(pf && [pf isKindOfClass:[NSSecureTextField class]],
        "PASSWORD=YES creates an NSSecureTextField", buf); }

  /* ---- ALIGNMENT ---- */
  { IupSetAttribute(single, "ALIGNMENT", "ARIGHT");
    NSTextAlignment right = [nf alignment];
    IupSetAttribute(single, "ALIGNMENT", "ACENTER");
    NSTextAlignment center = [nf alignment];
    IupSetAttribute(single, "ALIGNMENT", "ALEFT");
    snprintf(buf, sizeof buf, "right=%ld center=%ld left=%ld",
             (long)right, (long)center, (long)[nf alignment]);
    chk(right == NSTextAlignmentRight && center == NSTextAlignmentCenter
        && [nf alignment] == NSTextAlignmentLeft,
        "ALIGNMENT reaches the native alignment", buf); }

  /* ---- BGCOLOR / FGCOLOR ---- */
  { IupSetAttribute(single, "BGCOLOR", "255 255 0");
    NSColor* bg = [[nf backgroundColor] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    snprintf(buf, sizeof buf, "backgroundColor=(%.0f,%.0f,%.0f)",
             [bg redComponent]*255, [bg greenComponent]*255, [bg blueComponent]*255);
    chk([bg redComponent] > 0.9 && [bg greenComponent] > 0.9 && [bg blueComponent] < 0.1,
        "BGCOLOR reaches the NSTextField", buf); }

  { IupSetAttribute(multi, "FGCOLOR", "255 0 0");
    NSColor* fg = [[nv textColor] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    snprintf(buf, sizeof buf, "textColor=(%.0f,%.0f,%.0f)",
             [fg redComponent]*255, [fg greenComponent]*255, [fg blueComponent]*255);
    /* -colorUsingColorSpace: converts through the display profile, so pure red arrives as
       roughly (255,38,0); compare which channel leads rather than absolute levels. */
    chk([fg redComponent] > 0.9 && [fg redComponent] > 3 * [fg greenComponent],
        "FGCOLOR reaches the NSTextView", buf); }

  /* ---- CUEBANNER (placeholder) ---- */
  { IupSetAttribute(single, "CUEBANNER", "type here");
    NSString* ph = [[nf cell] placeholderString];
    snprintf(buf, sizeof buf, "placeholderString='%s'", ph ? [ph UTF8String] : "(nil)");
    chk(ph && 0 == strcmp([ph UTF8String], "type here"),
        "CUEBANNER sets the placeholder string", buf); }

  /* ---- MASK and NC ----
     Both are enforced by iupEditCallActionCb inside the driver's edit hook, not by setting
     VALUE, so they can only be checked by driving the field editor the way typing does.
     Asserting on IupSetAttribute(VALUE) would pass even with the edit hook broken. */
  { NSWindow* window = (NSWindow*)dlg->handle;
    [window makeFirstResponder:nf];
    NSTextView* editor = (NSTextView*)[window fieldEditor:YES forObject:nf];

    IupSetAttribute(single, "NC", "0");
    IupSetAttribute(single, "VALUE", "");
    IupSetAttribute(single, "MASK", "/d*");   /* digits only */

    const char* typed[] = { "1", "2", "a", "3", "z" };
    for (int i = 0; i < 5; i++)
    { NSString* key = [NSString stringWithUTF8String:typed[i]];
      NSRange at = [editor selectedRange];
      if ([editor shouldChangeTextInRange:at replacementString:key])
      { [[editor textStorage] replaceCharactersInRange:at withString:key];
        [editor didChangeText]; } }

    snprintf(buf, sizeof buf, "typed 1 2 a 3 z -> '%s' (want '123')", [[editor string] UTF8String]);
    chk(0 == strcmp([[editor string] UTF8String], "123"),
        "MASK rejects characters it does not match", buf);
    IupSetAttribute(single, "MASK", NULL); }

  { NSWindow* window = (NSWindow*)dlg->handle;
    NSTextView* editor = (NSTextView*)[window fieldEditor:YES forObject:nf];
    IupSetAttribute(single, "VALUE", "");
    [editor setString:@""];
    IupSetAttribute(single, "NC", "3");

    for (int i = 0; i < 6; i++)
    { NSString* key = [NSString stringWithFormat:@"%d", i];
      NSRange at = [editor selectedRange];
      if ([editor shouldChangeTextInRange:at replacementString:key])
      { [[editor textStorage] replaceCharactersInRange:at withString:key];
        [editor didChangeText]; } }

    snprintf(buf, sizeof buf, "typed 6 chars with NC=3 -> '%s'", [[editor string] UTF8String]);
    chk(3 == (int)[[editor string] length], "NC limits interactive input", buf);
    IupSetAttribute(single, "NC", "0"); }

  /* ---- the three that were disabled ---- */

  /* TABSIZE: defaultTabInterval only takes effect once the explicit tab stops are cleared */
  { IupSetAttribute(multi, "TABSIZE", "4");
    NSParagraphStyle* ps = [nv defaultParagraphStyle];
    CGFloat interval = ps ? [ps defaultTabInterval] : 0;
    NSUInteger stops = ps ? [[ps tabStops] count] : 999;
    snprintf(buf, sizeof buf, "defaultTabInterval=%.1f tabStops=%lu", interval, (unsigned long)stops);
    chk(ps != nil && interval > 0 && stops == 0, "TABSIZE sets the tab interval", buf); }

  { IupSetAttribute(multi, "TABSIZE", "8");
    CGFloat wide = [[nv defaultParagraphStyle] defaultTabInterval];
    IupSetAttribute(multi, "TABSIZE", "4");
    CGFloat narrow = [[nv defaultParagraphStyle] defaultTabInterval];
    snprintf(buf, sizeof buf, "8 -> %.1f, 4 -> %.1f", wide, narrow);
    chk(wide > narrow * 1.5, "TABSIZE scales with the requested size", buf); }

  /* PADDING: real inner inset on the text view, and the shared natural size grows */
  { int before_w = multi->naturalwidth;
    IupSetAttribute(multi, "PADDING", "7x3");
    NSSize inset = [nv textContainerInset];
    char* pad = IupGetAttribute(multi, "PADDING");
    snprintf(buf, sizeof buf, "inset=%.0fx%.0f PADDING=%s", inset.width, inset.height,
             pad ? pad : "(null)");
    chk(inset.width == 7 && inset.height == 3 && pad && 0 == strcmp(pad, "7x3"),
        "PADDING insets the NSTextView text container", buf);
    (void)before_w; }

  /* The natural size grows by 2*padding (iup_text.c), but only where the natural size is
     actually computed: with an explicit SIZE the user size wins and padding cannot show up
     there. So this uses a separate text with no SIZE set. */
  { Ihandle* sized = IupText(NULL);
    IupSetAttribute(sized, "MULTILINE", "YES");
    Ihandle* box = IupDialog(IupVbox(sized, NULL));
    IupMap(box);
    IupSetAttribute(sized, "PADDING", "0x0");
    IupRefresh(sized);
    int nw = sized->naturalwidth, nh = sized->naturalheight;
    IupSetAttribute(sized, "PADDING", "20x10");
    IupRefresh(sized);
    snprintf(buf, sizeof buf, "natural %dx%d -> %dx%d", nw, nh,
             sized->naturalwidth, sized->naturalheight);
    chk(sized->naturalwidth == nw + 40 && sized->naturalheight == nh + 20,
        "PADDING grows the natural size by 2x on each axis", buf);
    IupDestroy(box); }

  /* OVERWRITE: typing must replace the next character rather than push it along */
  { IupSetAttribute(multi, "PADDING", "0x0");
    IupSetAttribute(multi, "VALUE", "ABCDEF");
    IupSetAttribute(multi, "OVERWRITE", "YES");
    char* ov = IupGetAttribute(multi, "OVERWRITE");
    /* iupStrReturnChecked yields IUP's "ON"/"OFF", which is what the Windows driver returns
       for this attribute too -- not the "YES" that was written in. */
    snprintf(buf, sizeof buf, "OVERWRITE reads back as '%s'", ov ? ov : "(null)");
    chk(ov && 0 == strcmp(ov, "ON"), "OVERWRITE round-trips", buf);

    [nv setSelectedRange:NSMakeRange(2, 0)];
    [nv insertText:@"x" replacementRange:NSMakeRange(NSNotFound, 0)];
    snprintf(buf, sizeof buf, "'%s' (want 'ABxDEF')", [[[nv textStorage] string] UTF8String]);
    chk(0 == strcmp([[[nv textStorage] string] UTF8String], "ABxDEF"),
        "OVERWRITE=YES replaces the next character", buf);

    IupSetAttribute(multi, "OVERWRITE", "NO");
    IupSetAttribute(multi, "VALUE", "ABCDEF");
    [nv setSelectedRange:NSMakeRange(2, 0)];
    [nv insertText:@"x" replacementRange:NSMakeRange(NSNotFound, 0)];
    snprintf(buf, sizeof buf, "'%s' (want 'ABxCDEF')", [[[nv textStorage] string] UTF8String]);
    chk(0 == strcmp([[[nv textStorage] string] UTF8String], "ABxCDEF"),
        "OVERWRITE=NO still inserts", buf); }

  /* a newline must not consume the character after it */
  { IupSetAttribute(multi, "OVERWRITE", "YES");
    IupSetAttribute(multi, "VALUE", "AB\nCD");
    [nv setSelectedRange:NSMakeRange(2, 0)];
    [nv insertText:@"x" replacementRange:NSMakeRange(NSNotFound, 0)];
    snprintf(buf, sizeof buf, "'%s' (want 'ABx\\nCD')",
             [[[[nv textStorage] string] stringByReplacingOccurrencesOfString:@"\n"
                                                                  withString:@"\\n"] UTF8String]);
    chk(0 == strcmp([[[nv textStorage] string] UTF8String], "ABx\nCD"),
        "OVERWRITE does not eat the newline", buf);
    IupSetAttribute(multi, "OVERWRITE", "NO"); }

  /* ---- spin ---- */
  { NSStepper* stepper = nil;
    for (NSView* sub in [(NSView*)spin->handle subviews])
      if ([sub isKindOfClass:[NSStepper class]]) stepper = (NSStepper*)sub;
    IupSetAttribute(spin, "SPINVALUE", "7");
    snprintf(buf, sizeof buf, "stepper=%s value=%.0f", stepper ? "yes" : "no",
             stepper ? [stepper doubleValue] : -1);
    chk(stepper != nil && [stepper doubleValue] == 7,
        "SPIN creates an NSStepper and SPINVALUE reaches it", buf); }

  printf("%d gap(s)\n", g_gaps);
  IupExitLoop();
  return IUP_DEFAULT;
}

int main(int argc, char** argv)
{
  IupOpen(&argc, &argv);

  single = IupText(NULL);
  IupSetAttribute(single, "SIZE", "120x");

  multi = IupText(NULL);
  IupSetAttribute(multi, "MULTILINE", "YES");
  IupSetAttribute(multi, "SIZE", "160x80");

  pass = IupText(NULL);
  IupSetAttribute(pass, "PASSWORD", "YES");

  spin = IupText(NULL);
  IupSetAttribute(spin, "SPIN", "YES");

  dlg = IupDialog(IupVbox(single, multi, pass, spin, NULL));
  IupSetAttribute(dlg, "TITLE", "textparity");
  IupShowXY(dlg, IUP_CENTER, IUP_CENTER);

  Ihandle* t = IupTimer();
  IupSetAttribute(t, "TIME", "700");
  IupSetCallback(t, "ACTION_CB", (Icallback)run);
  IupSetAttribute(t, "RUN", "YES");
  IupMainLoop();
  IupClose();
  return g_gaps ? 1 : 0;
}
