/* macOS ships OpenGL as a framework, so there is no GL/gl.h. IUP's samples use the header
   path every other platform has; this forwards it. Only the samples are built against this
   shim -- the iupgl driver itself includes <OpenGL/gl.h> directly. */
#ifndef IUP_COCOA_GL_SHIM_GL_H
#define IUP_COCOA_GL_SHIM_GL_H
#define GL_SILENCE_DEPRECATION 1
#include <OpenGL/gl.h>
#endif
