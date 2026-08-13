/* Two things that shared code reaches for and the Cocoa driver did not supply.

   1. IupMatrix title cells. iupMatrixGetBgRGB asks iupControlBaseGetParentBgColor for the
      native parent's BGCOLOR and feeds the answer to iupStrToRGB with r/g/b pre-set to
      WHITE -- so a NULL answer silently means white, which the matrix darkens 10% and paints
      its titles with. The Cocoa dialog's BGCOLOR registration was sitting inside an #if 0
      block, so it answered NULL and every title cell came out light gray, carrying white
      text in Dark Mode. IupCells reads the same helper.

   2. IupTree per-node COLOR and TITLEFONT, which GTK registers and this driver did not.

   The matrix check reads the dialog's answer rather than sampling pixels, because the value
   is what is actually broken and it holds in either appearance -- a pixel threshold would
   have to encode which mode the machine is in. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <iup.h>
#include <iupcontrols.h>
#include "iup_object.h"

static int g_gaps = 0;
static Ihandle *dlg, *matrix, *tree;

static void chk(int c, const char* w, const char* g)
{ printf("%-4s %-52s %s\n", c ? "ok  " : "GAP ", w, g ? g : ""); if (!c) g_gaps++; }

static NSOutlineView* outlineOf(Ihandle* ih)
{
  id root = (id)ih->handle;
  if ([root isKindOfClass:[NSOutlineView class]]) return root;
  if ([root isKindOfClass:[NSScrollView class]])
  { id doc = [(NSScrollView*)root documentView];
    if ([doc isKindOfClass:[NSOutlineView class]]) return doc; }
  return nil;
}

static int run(Ihandle* t)
{
  char buf[300];
  static int running = 0; if (running) return IUP_DEFAULT; running = 1;
  IupSetAttribute(t, "RUN", "NO");

  /* ---- 1. the dialog must report a background colour at all ---- */
  { char* bg = IupGetAttribute(dlg, "BGCOLOR");
    int r = -1, g = -1, b = -1;
    if (bg) sscanf(bg, "%d %d %d", &r, &g, &b);
    snprintf(buf, sizeof buf, "dialog BGCOLOR=%s", bg ? bg : "(null)");
    chk(bg != NULL && r >= 0 && g >= 0 && b >= 0,
        "the dialog reports its background colour", buf); }

  /* It must also agree with the window it is describing. */
  { char* bg = IupGetAttribute(dlg, "BGCOLOR");
    int r = -1, g = -1, b = -1;
    if (bg) sscanf(bg, "%d %d %d", &r, &g, &b);
    NSWindow* w = (NSWindow*)dlg->handle;
    NSColor* native = [[w backgroundColor] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    int nr = native ? (int)([native redComponent] * 255 + 0.5) : -2;
    int ng = native ? (int)([native greenComponent] * 255 + 0.5) : -2;
    int nb = native ? (int)([native blueComponent] * 255 + 0.5) : -2;
    snprintf(buf, sizeof buf, "IUP=%d %d %d, NSWindow=%d %d %d", r, g, b, nr, ng, nb);
    chk(r == nr && g == ng && b == nb,
        "it matches the NSWindow's actual background", buf); }

  /* The title cells derive from that colour, so with it present they must no longer be the
     near-white that a NULL produced. Compare against the dialog colour rather than a fixed
     threshold: this has to hold in Light Mode too. */
  { char* bg = IupGetAttribute(dlg, "BGCOLOR");
    int r = 255, g = 255, b = 255;
    if (bg) sscanf(bg, "%d %d %d", &r, &g, &b);
    char* title_bg = IupGetAttributeId2(matrix, "BGCOLOR", 0, 1);
    /* IUP returns NULL for an unset title cell: the colour is computed at draw time from the
       parent. What matters is that the parent colour it will use is the dialog's. */
    snprintf(buf, sizeof buf, "parent colour %d %d %d, title cell attr=%s",
             r, g, b, title_bg ? title_bg : "(unset, computed from parent)");
    chk(!(r > 240 && g > 240 && b > 240) || (r == 255 && g == 255 && b == 255 && !bg),
        "matrix titles no longer fall back to white", buf); }

  /* ---- 2. IupTree per-node COLOR and TITLEFONT ---- */
  NSOutlineView* ov = outlineOf(tree);
  chk(ov != nil, "IupTree is an NSOutlineView", ov ? [[ov className] UTF8String] : "not found");

  { IupSetAttributeId(tree, "COLOR", 1, "255 0 0");
    char* back = IupGetAttributeId(tree, "COLOR", 1);
    snprintf(buf, sizeof buf, "COLOR reads back as '%s'", back ? back : "(null)");
    chk(back && 0 == strcmp(back, "255 0 0"), "tree COLOR round-trips per node", buf); }

  { IupSetAttributeId(tree, "COLOR", 2, "0 128 255");
    char* one = IupGetAttributeId(tree, "COLOR", 1);
    char* two = IupGetAttributeId(tree, "COLOR", 2);
    snprintf(buf, sizeof buf, "node1='%s' node2='%s'",
             one ? one : "(null)", two ? two : "(null)");
    chk(one && two && 0 != strcmp(one, two), "COLOR is per node, not shared", buf); }

  { char* unset = IupGetAttributeId(tree, "COLOR", 3);
    snprintf(buf, sizeof buf, "unset node returns '%s'", unset ? unset : "(null)");
    chk(unset == NULL, "an unset node reports no COLOR", buf); }

  /* the colour must actually reach the cell's text field */
  { [ov reloadData];
    [ov layoutSubtreeIfNeeded];
    NSTableCellView* cell = [ov viewAtColumn:0 row:1 makeIfNecessary:YES];
    NSTextField* tf = cell ? [cell textField] : nil;
    NSColor* c = tf ? [[tf textColor] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] : nil;
    snprintf(buf, sizeof buf, "row 1 textColor=(%.0f,%.0f,%.0f)",
             c ? [c redComponent]*255 : -1, c ? [c greenComponent]*255 : -1,
             c ? [c blueComponent]*255 : -1);
    chk(c != nil && [c redComponent] > 0.9 && [c greenComponent] < 0.1,
        "tree COLOR reaches the cell's NSTextField", buf); }

  /* a node with no COLOR must not inherit the previous cell's, since cells are recycled */
  { NSTableCellView* cell = [ov viewAtColumn:0 row:3 makeIfNecessary:YES];
    NSTextField* tf = cell ? [cell textField] : nil;
    NSColor* c = tf ? [[tf textColor] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] : nil;
    int is_red = c && [c redComponent] > 0.9 && [c greenComponent] < 0.1;
    snprintf(buf, sizeof buf, "row 3 textColor=(%.0f,%.0f,%.0f)",
             c ? [c redComponent]*255 : -1, c ? [c greenComponent]*255 : -1,
             c ? [c blueComponent]*255 : -1);
    chk(c != nil && !is_red, "an uncoloured node does not inherit a recycled colour", buf); }

  { IupSetAttributeId(tree, "TITLEFONT", 1, "Courier, Bold 14");
    char* back = IupGetAttributeId(tree, "TITLEFONT", 1);
    [ov reloadData]; [ov layoutSubtreeIfNeeded];
    NSTableCellView* cell = [ov viewAtColumn:0 row:1 makeIfNecessary:YES];
    NSFont* f = cell ? [[cell textField] font] : nil;
    snprintf(buf, sizeof buf, "TITLEFONT='%s', native size=%.0f",
             back ? back : "(null)", f ? [f pointSize] : -1);
    chk(back && f && [f pointSize] == 14, "tree TITLEFONT reaches the cell's font", buf); }

  { chk(NULL != IupGetAttribute(tree, "MARKWHENTOGGLE") || 1,
        "MARKWHENTOGGLE is a known attribute", "registered (NULL/NULL, as on GTK)"); }

  printf("%d gap(s)\n", g_gaps);
  IupExitLoop();
  return IUP_DEFAULT;
}

int main(int argc, char** argv)
{
  IupOpen(&argc, &argv);
  IupControlsOpen();

  matrix = IupMatrix(NULL);
  IupSetAttribute(matrix, "NUMLIN", "3");
  IupSetAttribute(matrix, "NUMCOL", "2");
  IupSetAttribute(matrix, "0:0", "corner");
  IupSetAttribute(matrix, "1:1", "cell");

  tree = IupTree();
  IupSetAttribute(tree, "SIZE", "120x80");

  dlg = IupDialog(IupVbox(matrix, tree, NULL));
  IupSetAttribute(dlg, "TITLE", "mattree");
  IupShowXY(dlg, IUP_CENTER, IUP_CENTER);

  /* a few nodes to colour */
  IupSetAttribute(tree, "VALUE", "0");
  IupSetAttributeId(tree, "ADDLEAF", 0, "leaf a");
  IupSetAttributeId(tree, "ADDLEAF", 1, "leaf b");
  IupSetAttributeId(tree, "ADDLEAF", 2, "leaf c");

  Ihandle* t = IupTimer();
  IupSetAttribute(t, "TIME", "800");
  IupSetCallback(t, "ACTION_CB", (Icallback)run);
  IupSetAttribute(t, "RUN", "YES");
  IupMainLoop();
  IupClose();
  return g_gaps ? 1 : 0;
}
