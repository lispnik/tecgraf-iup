/** \file
 * \brief iupgl control for macOS (Cocoa)
 *
 * See Copyright Notice in "iup.h"
 */

#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <memory.h>

#include "iup.h"
#include "iupcbs.h"
#include "iupgl.h"

#include "iup_object.h"
#include "iup_attrib.h"
#include "iup_str.h"
#include "iup_stdcontrols.h"
#include "iup_assert.h"
#include "iup_register.h"

#include "iupcocoa_drv.h"

/* OpenGL is deprecated on macOS but still functional, and it is the only thing IupGLCanvas
   can be built on: the API IUP exposes (IupGLMakeCurrent, IupGLSwapBuffers, and applications
   issuing gl* calls directly) is a context-based model with no Metal equivalent. Silence the
   deprecation warnings here rather than at the project level. */
#pragma clang diagnostic ignored "-Wdeprecated-declarations"


/* Do NOT use _IcontrolData: IupGLCanvas is a base class for other controls (IupGLBackgroundBox,
   and the IupGLControls set), and they need ih->data for their own use. */
typedef struct _IGlControlData
{
	NSOpenGLContext* context;
	NSOpenGLPixelFormat* pixel_format;
	NSView* view;          /* the canvas view the context is attached to, not retained */
	int is_attached;       /* whether -setView: has succeeded yet */
} IGlControlData;


static void cocoaGLCanvasAttachView(Ihandle* ih, IGlControlData* gldata);


static int cocoaGLCanvasDefaultResize(Ihandle *ih, int width, int height)
{
	IupGLMakeCurrent(ih);
	glViewport(0, 0, width, height);
	return IUP_DEFAULT;
}

static int cocoaGLCanvasCreateMethod(Ihandle* ih, void** params)
{
	IGlControlData* gldata;
	(void)params;

	gldata = (IGlControlData*)malloc(sizeof(IGlControlData));
	memset(gldata, 0, sizeof(IGlControlData));
	iupAttribSet(ih, "_IUP_GLCONTROLDATA", (char*)gldata);

	IupSetCallback(ih, "RESIZE_CB", (Icallback)cocoaGLCanvasDefaultResize);

	return IUP_NOERROR;
}

/* Builds the pixel format from the same attributes the GLX and WGL drivers read, so an
   application's IupGLCanvas configuration means the same thing here. */
static NSOpenGLPixelFormat* cocoaGLCanvasCreatePixelFormat(Ihandle* ih)
{
	NSOpenGLPixelFormatAttribute attribute_list[40];
	int n = 0;
	int number;
	char* value;

	attribute_list[n++] = NSOpenGLPFAAccelerated;
	attribute_list[n++] = NSOpenGLPFAClosestPolicy;

	/* CONTEXTPROFILE selects the legacy or a core profile. A core profile is required for
	   GL 3.2+, and on macOS a core profile is strictly core: the fixed-function pipeline that
	   most of IUP's own samples use is unavailable in it, so legacy remains the default. */
	value = iupAttribGetStr(ih, "CONTEXTPROFILE");
	if(value && iupStrEqualNoCase(value, "CORE"))
	{
		int major = 3, minor = 2;
		char* version = iupAttribGetStr(ih, "CONTEXTVERSION");
		if(version)
		{
			iupStrToIntInt(version, &major, &minor, '.');
		}
		attribute_list[n++] = NSOpenGLPFAOpenGLProfile;
		/* 4.1 is the highest macOS ever shipped */
		if((major > 4) || ((4 == major) && (minor >= 1)))
		{
			attribute_list[n++] = NSOpenGLProfileVersion4_1Core;
		}
		else
		{
			attribute_list[n++] = NSOpenGLProfileVersion3_2Core;
		}
	}
	else
	{
		attribute_list[n++] = NSOpenGLPFAOpenGLProfile;
		attribute_list[n++] = NSOpenGLProfileVersionLegacy;
	}

	if(iupStrEqualNoCase(iupAttribGetStr(ih, "BUFFER"), "DOUBLE"))
	{
		attribute_list[n++] = NSOpenGLPFADoubleBuffer;
	}

	if(iupAttribGetBoolean(ih, "STEREO"))
	{
		attribute_list[n++] = NSOpenGLPFAStereo;
	}

	/* COLOR=INDEX has no equivalent: macOS OpenGL has never offered an index-colour pixel
	   format. Applications asking for one get RGBA, and ERROR says so. */
	if(iupStrEqualNoCase(iupAttribGetStr(ih, "COLOR"), "INDEX"))
	{
		iupAttribSet(ih, "ERROR", "Index color mode is not supported on macOS, using RGBA.");
	}

	/* NSOpenGLPFAColorSize is the total of the R+G+B channels, unlike GLX which takes them
	   separately, so add them up when they are given individually. */
	{
		int red = iupAttribGetInt(ih, "RED_SIZE");
		int green = iupAttribGetInt(ih, "GREEN_SIZE");
		int blue = iupAttribGetInt(ih, "BLUE_SIZE");
		int color_size = red + green + blue;
		if(color_size <= 0)
		{
			color_size = iupAttribGetInt(ih, "BUFFER_SIZE");
		}
		if(color_size > 0)
		{
			attribute_list[n++] = NSOpenGLPFAColorSize;
			attribute_list[n++] = (NSOpenGLPixelFormatAttribute)color_size;
		}
	}

	number = iupAttribGetInt(ih, "ALPHA_SIZE");
	if(number > 0)
	{
		attribute_list[n++] = NSOpenGLPFAAlphaSize;
		attribute_list[n++] = (NSOpenGLPixelFormatAttribute)number;
	}

	number = iupAttribGetInt(ih, "DEPTH_SIZE");
	if(number > 0)
	{
		attribute_list[n++] = NSOpenGLPFADepthSize;
		attribute_list[n++] = (NSOpenGLPixelFormatAttribute)number;
	}

	number = iupAttribGetInt(ih, "STENCIL_SIZE");
	if(number > 0)
	{
		attribute_list[n++] = NSOpenGLPFAStencilSize;
		attribute_list[n++] = (NSOpenGLPixelFormatAttribute)number;
	}

	{
		int accum = iupAttribGetInt(ih, "ACCUM_RED_SIZE")
		          + iupAttribGetInt(ih, "ACCUM_GREEN_SIZE")
		          + iupAttribGetInt(ih, "ACCUM_BLUE_SIZE")
		          + iupAttribGetInt(ih, "ACCUM_ALPHA_SIZE");
		if(accum > 0)
		{
			attribute_list[n++] = NSOpenGLPFAAccumSize;
			attribute_list[n++] = (NSOpenGLPixelFormatAttribute)accum;
		}
	}

	attribute_list[n] = 0;

	NSOpenGLPixelFormat* pixel_format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attribute_list];
	if(nil == pixel_format)
	{
		/* NSOpenGLPFAAccelerated is the usual reason a request cannot be satisfied (a headless
		   or software-only configuration), so retry without it before giving up. */
		int i;
		for(i = 0; i < n; i++)
		{
			if(NSOpenGLPFAAccelerated == attribute_list[i])
			{
				memmove(&attribute_list[i], &attribute_list[i + 1],
					sizeof(NSOpenGLPixelFormatAttribute) * (size_t)(n - i));
				n--;
				break;
			}
		}
		pixel_format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attribute_list];
	}

	return pixel_format;
}

/* The context is attached to the IupCanvas view that the base class already created, which is
   what keeps every canvas behaviour -- mouse and key callbacks, tracking areas, drag and drop,
   scrollbars -- working for a GL canvas. It mirrors what the GLX and WGL drivers do with the
   existing native window. */
static void cocoaGLCanvasAttachView(Ihandle* ih, IGlControlData* gldata)
{
	if((nil == gldata->context) || gldata->is_attached)
	{
		return;
	}

	NSView* canvas_view = iupCocoaGetMainView(ih);
	if(nil == canvas_view)
	{
		return;
	}

	/* -setView: silently does nothing useful until the view belongs to a window, so leave it
	   for the first IupGLMakeCurrent if the dialog has not been created yet. */
	if(nil == [canvas_view window])
	{
		return;
	}

	gldata->view = canvas_view;

	/* Keep the GL surface the same size as the canvas IUP reports.

	   AppKit gives a GL surface the window's backing resolution, so on a retina display the
	   drawable is twice the view in each direction -- while RESIZE_CB, DRAWSIZE and every other
	   size IUP hands out are in points, because that is what IUP means by a pixel everywhere
	   else and what the Windows and GTK drivers report. An application doing the ordinary thing,
	   glViewport(0, 0, w, h) with the size RESIZE_CB just gave it, therefore drew into the
	   bottom-left QUARTER of its canvas: glcanvas_cube and mathglsamples both did, and MathGL's
	   plots looked like they refused to fill their windows.

	   Matching the surface to points keeps that code correct, at the cost of the window server
	   scaling the result up on a retina display. The alternative -- a full-resolution surface --
	   cannot be had without every existing application learning a second size, which is not a
	   trade IUP's own contract allows. */
	[canvas_view setWantsBestResolutionOpenGLSurface:NO];

	[gldata->context setView:canvas_view];
	gldata->is_attached = 1;

	/* The surface must be told when the view is resized or moved between screens, otherwise
	   it keeps rendering at the geometry it had when it was attached. */
	[[NSNotificationCenter defaultCenter] addObserver:gldata->context
		selector:@selector(update)
		name:NSViewGlobalFrameDidChangeNotification
		object:canvas_view];
}

static int cocoaGLCanvasMapMethod(Ihandle* ih)
{
	IGlControlData* gldata = (IGlControlData*)iupAttribGet(ih, "_IUP_GLCONTROLDATA");
	NSOpenGLContext* shared_context = nil;
	Ihandle* ih_shared;

	/* the IupCanvas is already mapped (iClassMap runs the parent class first), so this only
	   has to create the OpenGL context and attach it */

	gldata->pixel_format = cocoaGLCanvasCreatePixelFormat(ih);
	if(nil == gldata->pixel_format)
	{
		iupAttribSet(ih, "ERROR", "No appropriate pixel format.");
		return IUP_NOERROR;  /* do not abort mapping */
	}

	ih_shared = IupGetAttributeHandle(ih, "SHAREDCONTEXT");
	if(ih_shared && IupClassMatch(ih_shared, "glcanvas"))  /* must be an IupGLCanvas */
	{
		IGlControlData* shared_gldata = (IGlControlData*)iupAttribGet(ih_shared, "_IUP_GLCONTROLDATA");
		if(shared_gldata)
		{
			shared_context = shared_gldata->context;
		}
	}

	gldata->context = [[NSOpenGLContext alloc] initWithFormat:gldata->pixel_format
	                                            shareContext:shared_context];
	if(nil == gldata->context)
	{
		iupAttribSet(ih, "ERROR", "Could not create a rendering context.");
		return IUP_NOERROR;
	}

	/* Deliberately NOT attaching the context to the view here.
	
	   On GLX and WGL a GL canvas is still an ordinary canvas: creating one takes nothing away,
	   and the GL context only matters once the application calls IupGLMakeCurrent. Attaching
	   an NSOpenGLContext, by contrast, makes the window server composite that surface over the
	   view and hides everything drawn into it by CoreGraphics.
	
	   That is not hypothetical. IupPlot derives from IupGLCanvas so it can offer an OpenGL
	   graphics mode, but its default mode is IUP_PLOT_NATIVE, which draws with CD. Once this
	   driver existed, every IupPlot became a GL canvas and attaching at map time blanked all of
	   them -- empty plots, and uninitialised GL surfaces showing through as flat colour.
	
	   So the takeover waits for the first IupGLMakeCurrent, which is what an application that
	   genuinely renders with OpenGL does before drawing. Until then the canvas behaves exactly
	   as it did before, CPU drawing included. */
	return IUP_NOERROR;
}

static void cocoaGLCanvasUnMapMethod(Ihandle* ih)
{
	IGlControlData* gldata = (IGlControlData*)iupAttribGet(ih, "_IUP_GLCONTROLDATA");
	if(!gldata)
	{
		return;
	}

	if(nil != gldata->context)
	{
		if(gldata->is_attached && (nil != gldata->view))
		{
			[[NSNotificationCenter defaultCenter] removeObserver:gldata->context
				name:NSViewGlobalFrameDidChangeNotification object:gldata->view];
		}
		if([NSOpenGLContext currentContext] == gldata->context)
		{
			[NSOpenGLContext clearCurrentContext];
		}
		[gldata->context clearDrawable];
		[gldata->context release];
		gldata->context = nil;
	}

	if(nil != gldata->pixel_format)
	{
		[gldata->pixel_format release];
		gldata->pixel_format = nil;
	}

	gldata->view = nil;
	gldata->is_attached = 0;
}

static void cocoaGLCanvasDestroy(Ihandle* ih)
{
	IGlControlData* gldata = (IGlControlData*)iupAttribGet(ih, "_IUP_GLCONTROLDATA");
	if(gldata)
	{
		free(gldata);
		iupAttribSet(ih, "_IUP_GLCONTROLDATA", NULL);
	}
}

void iupdrvGlCanvasInitClass(Iclass* ic)
{
	ic->Create = cocoaGLCanvasCreateMethod;
	ic->Destroy = cocoaGLCanvasDestroy;
	ic->Map = cocoaGLCanvasMapMethod;
	ic->UnMap = cocoaGLCanvasUnMapMethod;
}


/******************************************* Exported functions */

/* Every entry point below is called by applications on any handle, so each repeats the same
   guards the GLX driver uses: a live object, an IupGLCanvas, and a context that exists. */
static IGlControlData* cocoaGLCanvasGetData(Ihandle* ih)
{
	IGlControlData* gldata;

	iupASSERT(iupObjectCheck(ih));
	if(!iupObjectCheck(ih))
	{
		return NULL;
	}

	if((ih->iclass->nativetype != IUP_TYPECANVAS) || !IupClassMatch(ih, "glcanvas"))
	{
		return NULL;
	}

	gldata = (IGlControlData*)iupAttribGet(ih, "_IUP_GLCONTROLDATA");
	if(!gldata || (nil == gldata->context))
	{
		return NULL;
	}

	return gldata;
}

int IupGLIsCurrent(Ihandle* ih)
{
	IGlControlData* gldata = cocoaGLCanvasGetData(ih);
	if(!gldata)
	{
		return 0;
	}

	return ([NSOpenGLContext currentContext] == gldata->context) ? 1 : 0;
}

void IupGLMakeCurrent(Ihandle* ih)
{
	IGlControlData* gldata = cocoaGLCanvasGetData(ih);
	if(!gldata)
	{
		return;
	}

	/* First real use of the context: attach it to the view now (see the note in the Map
	   method about why this does not happen at map time), and tell the IupCanvas view to stop
	   maintaining its CPU backing store, which the GL surface would cover anyway. */
	if(!gldata->is_attached)
	{
		cocoaGLCanvasAttachView(ih, gldata);
		if(!gldata->is_attached)
		{
			iupAttribSet(ih, "ERROR", "Failed to set new current context.");
			return;
		}

		iupAttribSet(ih, "_IUPCOCOA_GLCANVAS", "1");
	}

	[gldata->context makeCurrentContext];
	if([NSOpenGLContext currentContext] != gldata->context)
	{
		iupAttribSet(ih, "ERROR", "Failed to set new current context.");
		return;
	}

	iupAttribSet(ih, "ERROR", NULL);

	if(!IupGetGlobal("GL_VERSION"))
	{
		IupSetStrGlobal("GL_VENDOR", (char*)glGetString(GL_VENDOR));
		IupSetStrGlobal("GL_RENDERER", (char*)glGetString(GL_RENDERER));
		IupSetStrGlobal("GL_VERSION", (char*)glGetString(GL_VERSION));
	}
}

void IupGLSwapBuffers(Ihandle* ih)
{
	IGlControlData* gldata = cocoaGLCanvasGetData(ih);
	Icallback cb;

	if(!gldata || !gldata->is_attached)
	{
		return;
	}

	cb = IupGetCallback(ih, "SWAPBUFFERS_CB");
	if(cb)
	{
		cb(ih);
	}

	/* -flushBuffer is a no-op on a single-buffered context, where the drawing is already on
	   screen; glFlush is what actually gets it there. */
	if(iupStrEqualNoCase(iupAttribGetStr(ih, "BUFFER"), "DOUBLE"))
	{
		[gldata->context flushBuffer];
	}
	else
	{
		glFlush();
	}
}

void IupGLPalette(Ihandle* ih, int index, float r, float g, float b)
{
	(void)index; (void)r; (void)g; (void)b;

	iupASSERT(iupObjectCheck(ih));
	if(!iupObjectCheck(ih))
	{
		return;
	}

	/* Index colour mode does not exist in macOS OpenGL, so there is no palette to set. */
	iupAttribSet(ih, "ERROR", "Index color mode is not supported on macOS.");
}

void IupGLUseFont(Ihandle* ih, int first, int count, int list_base)
{
	(void)first; (void)count; (void)list_base;

	iupASSERT(iupObjectCheck(ih));
	if(!iupObjectCheck(ih))
	{
		return;
	}

	/* glXUseXFont/wglUseFontBitmaps built display lists of glyph bitmaps. The macOS analogue
	   was aglUseFont, in the AGL framework Apple removed; nothing replaced it, and display
	   lists do not exist in a core profile at all. Applications that need text on a GL canvas
	   have to draw it themselves (IupGLControls' IupGLDrawText does exactly that). */
	iupAttribSet(ih, "ERROR", "IupGLUseFont is not supported on macOS.");
}

void IupGLWait(int gl)
{
	if(gl)
	{
		glFinish();
	}
	else
	{
		glFlush();
	}
}
