/* IupFileDlg's result attributes.
 *
 * A modal file panel cannot be driven from a test without putting one on the user's screen and
 * synthesising keystrokes into it, so what is asserted here is the part that was actually
 * wrong: the shape of VALUE and the MULTIVALUE family for a given selection. The driver builds
 * those in iupCocoaFileDlgSetMultiValue, which this calls directly with a synthetic selection.
 *
 * IUP documents the format exactly (html/en/dlg/iupfiledlg.html):
 *
 *   "/tecgraf/iup/test|a.txt|b.txt|"   MULTIPLEFILES and more than one file selected
 *   "/tecgraf/iup/test/a.txt"          only one file selected -- no separator at all
 *
 * The Cocoa driver used to return full paths joined by '|' in both cases, so an application
 * parsing it the documented way read the first path as the directory and then found no file
 * names. ImLab's File>Open silently opened nothing, which is how this was found.
 */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <string.h>
#include <iup.h>
#include "iup_object.h"
#include "iup_attrib.h"
#include "iupcocoa_drv.h"

static int g_gaps = 0;
static void chk(int c, const char* w, const char* g)
{ printf("%-4s %-56s %s\n", c ? "ok  " : "GAP ", w, g ? g : ""); fflush(stdout); if (!c) g_gaps++; }

/* Accepts whatever save panel is on screen, which is what its Save button amounts to: the
   panel runs through -runModal, and -ok: is not implemented on modern AppKit. */
static void accept_save_panel(void)
{
  for (NSWindow* w in [NSApp windows])
    if ([w isKindOfClass:[NSSavePanel class]])
    {
      [NSApp stopModalWithCode:NSModalResponseOK];
      return;
    }
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

static NSArray* urls(NSArray* paths)
{
  NSMutableArray* a = [NSMutableArray array];
  for (NSString* p in paths) [a addObject:[NSURL fileURLWithPath:p]];
  return a;
}

int main(int argc, char** argv)
{
  char buf[512];
  Ihandle* dlg;

  IupOpen(&argc, &argv);

  dlg = IupFileDlg();
  IupSetAttribute(dlg, "MULTIPLEFILES", "YES");

  /* ---- exactly one file: a bare full path ---- */
  iupCocoaFileDlgSetMultiValue(dlg, urls(@[@"/tmp/iup test/a.txt"]));
  { char* value = IupGetAttribute(dlg, "VALUE");
    snprintf(buf, sizeof buf, "VALUE=\"%s\"", value ? value : "(null)");
    chk(value && 0 == strcmp(value, "/tmp/iup test/a.txt"),
        "one file gives the full path with no separator", buf); }

  { char* dir = IupGetAttribute(dlg, "DIRECTORY");
    snprintf(buf, sizeof buf, "DIRECTORY=\"%s\"", dir ? dir : "(null)");
    chk(dir && 0 == strcmp(dir, "/tmp/iup test"), "DIRECTORY is the containing folder", buf); }

  { int count = IupGetInt(dlg, "MULTIVALUECOUNT");
    snprintf(buf, sizeof buf, "MULTIVALUECOUNT=%d (want 2: the path counts)", count);
    chk(count == 2, "MULTIVALUECOUNT includes the path", buf); }

  { char* v0 = IupGetAttributeId(dlg, "MULTIVALUE", 0);
    char* v1 = IupGetAttributeId(dlg, "MULTIVALUE", 1);
    snprintf(buf, sizeof buf, "MULTIVALUE0=\"%s\" MULTIVALUE1=\"%s\"",
             v0 ? v0 : "(null)", v1 ? v1 : "(null)");
    chk(v0 && v1 && 0 == strcmp(v0, "/tmp/iup test") && 0 == strcmp(v1, "a.txt"),
        "MULTIVALUE0 is the path and MULTIVALUE1 the file name", buf); }

  /* ---- more than one: directory, then bare names, terminated by '|' ---- */
  iupCocoaFileDlgSetMultiValue(dlg, urls(@[@"/tmp/iup test/a.txt",
                                           @"/tmp/iup test/b.txt",
                                           @"/tmp/iup test/c.txt"]));
  { char* value = IupGetAttribute(dlg, "VALUE");
    snprintf(buf, sizeof buf, "VALUE=\"%s\"", value ? value : "(null)");
    chk(value && 0 == strcmp(value, "/tmp/iup test|a.txt|b.txt|c.txt|"),
        "several files give the directory then bare names", buf); }

  { int count = IupGetInt(dlg, "MULTIVALUECOUNT");
    snprintf(buf, sizeof buf, "MULTIVALUECOUNT=%d (want 4)", count);
    chk(count == 4, "MULTIVALUECOUNT counts the path plus each file", buf); }

  /* ---- MULTIVALUEPATH asks for full paths instead of names ---- */
  IupSetAttribute(dlg, "MULTIVALUEPATH", "YES");
  iupCocoaFileDlgSetMultiValue(dlg, urls(@[@"/tmp/one/a.txt", @"/tmp/two/b.txt"]));
  { char* value = IupGetAttribute(dlg, "VALUE");
    snprintf(buf, sizeof buf, "VALUE=\"%s\"", value ? value : "(null)");
    chk(value && NULL != strstr(value, "/tmp/two/b.txt"),
        "MULTIVALUEPATH keeps full paths, for selections spanning folders", buf); }
  IupSetAttribute(dlg, "MULTIVALUEPATH", NULL);

  /* ---- an empty selection must not produce a value ---- */
  iupCocoaFileDlgSetMultiValue(dlg, @[]);
  { char* value = IupGetAttribute(dlg, "VALUE");
    snprintf(buf, sizeof buf, "VALUE=%s", value ? value : "(null)");
    chk(value == NULL, "an empty selection leaves no VALUE behind", buf); }

  /* ---- a save dialog has to actually appear ----
     The SAVE branch of the driver used to set the dialog type and nothing else, leaving the
     panel nil. Messages to nil do nothing and return zero, so no panel was shown, -runModal
     "returned" 0, and the driver reported a cancel -- every Save As in every application
     silently did nothing, which is how this was found in ImLab. */
  { Ihandle* save = IupFileDlg();
    const char* wanted = "/tmp/iup_filedlg_harness_save.png";

    remove(wanted);
    IupSetAttribute(save, "DIALOGTYPE", "SAVE");
    IupSetAttribute(save, "TITLE", "harness save");
    IupSetAttribute(save, "FILE", "iup_filedlg_harness_save.png");
    IupSetAttribute(save, "DIRECTORY", "/tmp");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ accept_save_panel(); });

    IupPopup(save, IUP_CENTER, IUP_CENTER);

    { char* value = IupGetAttribute(save, "VALUE");
      snprintf(buf, sizeof buf, "VALUE=%s", value ? value : "(null)");
      chk(value != NULL, "a SAVE dialog returns a name rather than reporting a cancel", buf);
      chk(value && NULL != strstr(value, "iup_filedlg_harness_save.png"),
          "...the name that was asked for", buf); }

    { int status = IupGetInt(save, "STATUS");
      snprintf(buf, sizeof buf, "STATUS=%d (1 = new file)", status);
      chk(status == 1, "STATUS says whether the file already existed", buf); }

    /* DIRECTORY is a filesystem path, and setting it used to go through URLWithString, which
       silently produced nothing usable -- so the panel ignored where it was told to open. */
    { char* dir = IupGetAttribute(save, "DIRECTORY");
      snprintf(buf, sizeof buf, "DIRECTORY=%s", dir ? dir : "(null)");
      chk(dir && NULL != strstr(dir, "tmp"), "DIRECTORY reaches the panel", buf); }

    IupDestroy(save); }

  /* ---- the attribute set the application reads is registered ---- */
  { IupSetAttribute(dlg, "DIALOGTYPE", "OPEN");
    chk(NULL != IupGetAttribute(dlg, "DIALOGTYPE"), "DIALOGTYPE round-trips", NULL); }

  IupDestroy(dlg);

  printf("%d gap(s)\n", g_gaps);
  IupClose();
  return g_gaps ? 1 : 0;
}
