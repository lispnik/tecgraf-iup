#ifndef __IUP_IMGLIB_H 
#define __IUP_IMGLIB_H

#ifdef __cplusplus
extern "C" {
#endif

#ifdef WIN32
void iupImglibBaseLibWin16x16Open(void);     /* Used only by the Win32 driver */
#endif
/* Not Win32-only: the pixel data behind these is plain IupImageRGBA, so the Cocoa driver
   uses them too -- the gtk sets resolve gtk- stock ids and cannot be used off GTK. */
void iupImglibBaseLibWin32x32Open(void);
#ifndef WIN32
void iupImglibBaseLibMot16x16Open(void);    /* Used only by the Motif driver */
#endif

void iupImglibBaseLibGtk24x24Open(void);    /* Used only by the GTK driver */
void iupImglibBaseLibGtk324x24Open(void);    /* Used only by the GTK driver */

#ifndef WIN32
void iupImglibLogosMot32x32Open(void);      /* Used only by the Motif driver */
void iupImglibLogosMot48x48Open(void);      /* Used only by the Motif driver */
#endif

void iupImglibLogos32x32Open(void);
void iupImglibLogos48x48Open(void);

void iupImglibCircleProgress(void);

void iupImglibIconsWin48x48Open(void);      /* likewise portable, see above */
#ifdef WIN32
#elif defined(MOTIF)
#elif defined(GTK3)
void iupImglibIconsGtk348x48Open(void);
#else
void iupImglibIconsGtk48x48Open(void);
#endif

#ifdef __cplusplus
}
#endif

#endif
