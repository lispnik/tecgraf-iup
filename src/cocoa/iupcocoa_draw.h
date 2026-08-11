#ifndef __IUPCOCOA_DRAWCANVAS_H 
#define __IUPCOCOA_DRAWCANVAS_H

#include <stdbool.h>

@class IupCocoaCanvasView;
@class NSGraphicsContext;

struct _IdrawCanvas
{
	CGContextRef cgContext;
	IupCocoaCanvasView* canvasView;
	NSGraphicsContext* graphicsContext;
	Ihandle* ih;

	CGFloat w, h;
	bool useNativeFocusRing;
	/* True when cgContext is an offscreen bitmap we created because there was no current
	   NSGraphicsContext (drawing requested outside a draw cycle, e.g. during IupMap).
	   iupdrvDrawKillCanvas must release it. */
	bool ownsContext;
	/* True while a clip is active, i.e. we have pushed exactly one graphics state for it. */
	bool clipPushed;
/*
	int draw_focus;
	int focus_x1;
	int focus_y1;
	int focus_x2;
	int focus_y2;
*/
	CGFloat clip_x1;
	CGFloat clip_y1;
	CGFloat clip_x2;
	CGFloat clip_y2;
};

#endif /* __IUPCOCOA_DRAWCANVAS_H */

