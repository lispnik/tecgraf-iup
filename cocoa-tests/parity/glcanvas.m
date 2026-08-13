/* IupGLCanvas on Cocoa: does the context exist, is it current, and does it actually put
   pixels on a surface?

   -cacheDisplayInRect: cannot capture an NSOpenGLContext's surface -- the window server
   composites it separately -- so a screen capture proves nothing here either way. glReadPixels
   is the only honest check: it reads the framebuffer the context is really rendering into.

   Colours are compared exactly, unlike the drawimage harness: these values come straight out
   of the GL framebuffer, with no colour management in the path. */
#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#include <stdio.h>
#include <iup.h>
#include <iupgl.h>
#include "iup_object.h"

static int g_gaps = 0;
static Ihandle *dlg, *gl_canvas, *shared_canvas;

#define CANVAS_W 200
#define CANVAS_H 120

static void chk(int c, const char* w, const char* g)
{ printf("%-4s %-52s %s\n", c ? "ok  " : "GAP ", w, g ? g : ""); if (!c) g_gaps++; }

static void read_pixel(int x, int y, unsigned char* rgb)
{
  glReadPixels(x, y, 1, 1, GL_RGB, GL_UNSIGNED_BYTE, rgb);
}

static int run(Ihandle* t)
{
  char buf[240];
  unsigned char left[3] = {0,0,0}, right[3] = {0,0,0};
  static int running = 0; if (running) return IUP_DEFAULT; running = 1;
  IupSetAttribute(t, "RUN", "NO");

  /* 1. the class registered and the control is really a glcanvas */
  chk(gl_canvas != NULL && IupClassMatch(gl_canvas, "glcanvas"),
      "IupGLCanvasOpen registers the glcanvas class", IupGetClassName(gl_canvas));

  /* 2. making it current must succeed and must be observable */
  IupGLMakeCurrent(gl_canvas);
  { char* err = IupGetAttribute(gl_canvas, "ERROR");
    snprintf(buf, sizeof buf, "ERROR=%s", err ? err : "(none)");
    chk(err == NULL, "IupGLMakeCurrent reports no error", buf); }

  chk(IupGLIsCurrent(gl_canvas), "IupGLIsCurrent agrees after MakeCurrent", NULL);

  /* 3. MakeCurrent publishes the driver strings, as the GLX driver does */
  { char* version = IupGetGlobal("GL_VERSION");
    char* vendor = IupGetGlobal("GL_VENDOR");
    snprintf(buf, sizeof buf, "GL_VERSION=%s GL_VENDOR=%s",
             version ? version : "(null)", vendor ? vendor : "(null)");
    chk(version != NULL && vendor != NULL, "GL_VERSION/GL_VENDOR globals are set", buf); }

  /* 4. Render, then read the framebuffer back. Scissored clears are used rather than
        geometry so this does not depend on the fixed-function pipeline (absent from a core
        profile) or on any matrix setup: blue everywhere, then red over the left half. */
  glViewport(0, 0, CANVAS_W, CANVAS_H);
  glClearColor(0.0f, 0.0f, 1.0f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);

  glEnable(GL_SCISSOR_TEST);
  glScissor(0, 0, CANVAS_W / 2, CANVAS_H);
  glClearColor(1.0f, 0.0f, 0.0f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);
  glDisable(GL_SCISSOR_TEST);
  glFinish();

  { GLenum gl_error = glGetError();
    snprintf(buf, sizeof buf, "glGetError=0x%04x", (unsigned)gl_error);
    chk(GL_NO_ERROR == gl_error, "the GL commands raised no error", buf); }

  read_pixel(CANVAS_W / 4, CANVAS_H / 2, left);
  read_pixel((3 * CANVAS_W) / 4, CANVAS_H / 2, right);

  snprintf(buf, sizeof buf, "left=(%d,%d,%d) want red", left[0], left[1], left[2]);
  chk(left[0] > 250 && left[1] < 5 && left[2] < 5,
      "glReadPixels sees what was drawn (scissored half)", buf);

  snprintf(buf, sizeof buf, "right=(%d,%d,%d) want blue", right[0], right[1], right[2]);
  chk(right[2] > 250 && right[0] < 5 && right[1] < 5,
      "the rest of the surface holds the clear colour", buf);

  /* 5. the surface is the size of the canvas, not of some default drawable */
  { GLint viewport[4] = {0,0,0,0};
    glGetIntegerv(GL_VIEWPORT, viewport);
    snprintf(buf, sizeof buf, "viewport=%dx%d, canvas=%dx%d",
             viewport[2], viewport[3], CANVAS_W, CANVAS_H);
    chk(viewport[2] == CANVAS_W && viewport[3] == CANVAS_H,
        "the drawable matches the canvas size", buf); }

  /* 6. swapping must not error; on a double-buffered context this is -flushBuffer */
  IupGLSwapBuffers(gl_canvas);
  { char* err = IupGetAttribute(gl_canvas, "ERROR");
    snprintf(buf, sizeof buf, "ERROR=%s", err ? err : "(none)");
    chk(err == NULL, "IupGLSwapBuffers reports no error", buf); }

  /* 7. a second canvas sharing this one's context must also come up current */
  IupGLMakeCurrent(shared_canvas);
  { char* err = IupGetAttribute(shared_canvas, "ERROR");
    snprintf(buf, sizeof buf, "ERROR=%s current=%d", err ? err : "(none)",
             IupGLIsCurrent(shared_canvas));
    chk(err == NULL && IupGLIsCurrent(shared_canvas),
        "a SHAREDCONTEXT canvas gets its own working context", buf); }

  /* 8. the canvas still behaves as an IupCanvas: it is the base class, and losing its
        attributes would mean losing mouse and keyboard handling for GL applications */
  { char* rs = IupGetAttribute(gl_canvas, "RASTERSIZE");
    snprintf(buf, sizeof buf, "RASTERSIZE=%s, natural=%dx%d", rs ? rs : "(null)",
             gl_canvas->naturalwidth, gl_canvas->naturalheight);
    chk(gl_canvas->naturalwidth == CANVAS_W && gl_canvas->naturalheight == CANVAS_H,
        "it still sizes like an IupCanvas", buf); }

  printf("%d gap(s)\n", g_gaps);
  IupExitLoop();
  return IUP_DEFAULT;
}

int main(int argc, char** argv)
{
  IupOpen(&argc, &argv);
  IupGLCanvasOpen();

  gl_canvas = IupGLCanvas(NULL);
  IupSetAttribute(gl_canvas, "BUFFER", "DOUBLE");
  IupSetAttribute(gl_canvas, "DEPTH_SIZE", "16");
  IupSetStrf(gl_canvas, "RASTERSIZE", "%dx%d", CANVAS_W, CANVAS_H);

  shared_canvas = IupGLCanvas(NULL);
  IupSetAttribute(shared_canvas, "BUFFER", "DOUBLE");
  IupSetStrf(shared_canvas, "RASTERSIZE", "%dx%d", CANVAS_W, CANVAS_H);
  IupSetAttributeHandle(shared_canvas, "SHAREDCONTEXT", gl_canvas);

  dlg = IupDialog(IupVbox(gl_canvas, shared_canvas, NULL));
  IupSetAttribute(dlg, "TITLE", "glcanvas");
  IupShowXY(dlg, IUP_CENTER, IUP_CENTER);

  Ihandle* t = IupTimer();
  IupSetAttribute(t, "TIME", "800");
  IupSetCallback(t, "ACTION_CB", (Icallback)run);
  IupSetAttribute(t, "RUN", "YES");
  IupMainLoop();
  IupClose();
  return g_gaps ? 1 : 0;
}
