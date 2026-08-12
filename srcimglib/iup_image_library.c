/** \file
 * \brief IupImgLib
 *
 * See Copyright Notice in iup.h
 */

#include <stdlib.h>

#include "iup.h"
#include "iup_image.h"

#include "iup_imglib.h"

/* __APPLE__ covers both macOS and iOS, but only the macOS build compiles an image set, so
   the two must be told apart before calling into one. */
#ifdef __APPLE__
#include <TargetConditionals.h>
#if defined(TARGET_OS_OSX) && TARGET_OS_OSX
#define IUP_IMGLIB_COCOA 1
#endif
#endif


IUPIMGLIB_API void IupImageLibOpen(void)
{
  if (!IupIsOpened())
    return;

  if (IupGetGlobal("_IUP_IMAGELIB_OPEN"))
    return;

  IupSetGlobal("_IUP_IMAGELIB_OPEN", "1");

  /**************** BaseLib *****************/

#if defined(WIN32)
  /* iupImglibBaseLibWin16x16Open(); */
  iupImglibBaseLibWin32x32Open();
#elif defined(MOTIF)
  iupImglibBaseLibMot16x16Open();
#elif defined(__EMSCRIPTEN__)
#elif defined(IUP_IMGLIB_COCOA)
  /* The "win" sets are plain IupImageRGBA pixel data with no Win32 API in them, unlike the
     GTK ones, which mostly register a NULL creation function plus a gtk- stock id for the
     icon theme to resolve. So they are the only portable choice here. */
  iupImglibBaseLibWin32x32Open();
#elif defined(__APPLE__)
#elif defined(__ANDROID__)
#elif defined(GTK3)
  iupImglibBaseLibGtk324x24Open();
#else
  iupImglibBaseLibGtk24x24Open();
#endif  

  /***************** Logos *****************/

#if defined(MOTIF)
  iupImglibLogosMot32x32Open();
#elif defined(__EMSCRIPTEN__)
#elif defined(IUP_IMGLIB_COCOA)
  iupImglibLogos32x32Open();
#elif defined(__APPLE__)
#elif defined(__ANDROID__)
#else
  iupImglibLogos32x32Open();
#endif

#if defined(MOTIF)
    iupImglibLogosMot48x48Open();
#elif defined(__EMSCRIPTEN__)
#elif defined(IUP_IMGLIB_COCOA)
    iupImglibLogos48x48Open();
#elif defined(__APPLE__)
#elif defined(__ANDROID__)
#else
    iupImglibLogos48x48Open();
#endif

  /***************** Icons *****************/

#ifdef WIN32
  iupImglibIconsWin48x48Open();
#elif defined(MOTIF)
#elif defined(__EMSCRIPTEN__)
#elif defined(IUP_IMGLIB_COCOA)
  iupImglibIconsWin48x48Open();
#elif defined(__APPLE__)
#elif defined(__ANDROID__)
#elif defined(GTK3)
  iupImglibIconsGtk348x48Open();
#else
  iupImglibIconsGtk48x48Open();
#endif  

  iupImglibCircleProgress();
}
