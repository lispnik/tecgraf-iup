/** \file
 * \brief Button Control
 *
 * See Copyright Notice in "iup.h"
 */

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <memory.h>
#include <stdarg.h>

#include "iup.h"
#include "iupcbs.h"

#include "iup_object.h"
#include "iup_layout.h"
#include "iup_attrib.h"
#include "iup_str.h"
#include "iup_image.h"
#include "iup_button.h"
#include "iup_drv.h"
#include "iup_drvfont.h"
#include "iup_image.h"
#include "iup_key.h"

#include "iupcocoa_drv.h"

static const CGFloat kIupCocoaDefaultWidthNSButton = 1.0;
static const CGFloat kIupCocoaDefaultHeightNSButton = 32.0;

// the point of this is we have a unique memory address for an identifier
static const void* IUP_COCOA_BUTTON_RECEIVER_OBJ_KEY = "IUP_COCOA_BUTTON_RECEIVER_OBJ_KEY";


@interface IupCocoaButtonReceiver : NSObject
- (IBAction) myButtonClickAction:(id)the_sender;
@end

@implementation IupCocoaButtonReceiver

/*
- (void) dealloc
{
	[super dealloc];
}
*/


- (IBAction) myButtonClickAction:(id)the_sender;
{
	Icallback callback_function;
	Ihandle* ih = (Ihandle*)objc_getAssociatedObject(the_sender, IHANDLE_ASSOCIATED_OBJ_KEY);

	// CONFLICT: Cocoa buttons don't normally do anything for non-primary click. (Second click is supposed to trigger the contextual menu.)
	// Also Cocoa doesn't normall give callbacks for both down and up
	/*
	callback_function = IupGetCallback(ih, "BUTTON_CB");
	if(callback_function)
	{
		if(callback_function(ih) == IUP_CLOSE)
		{
			IupExitLoop();
		}
		
	}
	 */
	
	callback_function = IupGetCallback(ih, "ACTION");
	if(callback_function)
	{
		if(callback_function(ih) == IUP_CLOSE)
		{
			IupExitLoop();
		}
	}
}

@end



void iupdrvButtonAddBorders(Ihandle* ih, int *x, int *y)
{
//	NSLog(@"iupdrvButtonAddBorders in <%d, %d>", *x, *y);
	
	
	if(*y < (int)kIupCocoaDefaultHeightNSButton)
	{
		*y = (int)kIupCocoaDefaultHeightNSButton;
//		*y = (int)22;

	}
//	*x += 4; // a regular label seems to get 2 padding on each size
//	*x += 36; // the difference between a label and push button is 36 in Interface Builder

	*x += 27;
	
	/*
	NSView* the_view = (NSView*)ih->handle;
	NSRect view_frame = [the_view frame];
	*x = view_frame.size.width;
	*y = view_frame.size.height;
	
	*/
//	NSLog(@"iupdrvButtonAddBorders frame <%d, %d>", *x, *y);

}

/* defined further down, next to the map method */
static void cocoaButtonApplyTitleColor(Ihandle* ih);
static NSCellImagePosition cocoaButtonCellImagePosition(int iup_img_position);

static int cocoaButtonSetTitleAttrib(Ihandle* ih, const char* value)
{
	id the_button = ih->handle;

	if (ih->data->type & IUP_BUTTON_TEXT)  /* text or both */
	{
		if(value && *value!=0)
		{
			char* stripped_str = iupStrProcessMnemonic(value, NULL, 0);   /* remove & */
			
			// This will return nil if the string can't be converted.
			NSString* ns_string = iupCocoaStringFromCStr(stripped_str);
			
			if(stripped_str && stripped_str != value)
			{
				free(stripped_str);
			}
			
			[the_button setTitle:ns_string];
			cocoaButtonApplyTitleColor(ih);
			
			if(ih->data->type & IUP_BUTTON_IMAGE)
			{
				[the_button setImagePosition:cocoaButtonCellImagePosition(ih->data->img_position)];
			}
			else
			{
				//			[the_button setImagePosition:NSNoImage];
				
			}
			
			return 1;
		}
	}
	
	return 0;
}


// The reason we need a custom layout is because the button is being positioned too high compared to other widgets.
// I think the reason is because the NSButton has both a lot of invisible padding (officially 32 high, but only about 22 visible)
// and I think some of that padding is not completely centered.
// So when putting a button next to a label or textfield, the button looks too high up compared to standard Cocoa/IB layout.
void cocoaButtonLayoutUpdateMethod(Ihandle *ih)
{
	
	NSView* parent_view = nil;
	NSView* child_view = nil;
	
	parent_view = iupCocoaCommonBaseLayoutGetParentView(ih);
	child_view = iupCocoaCommonBaseLayoutGetChildView(ih);
	
	NSRect parent_rect = [parent_view frame];
	
	NSRect child_rect = iupCocoaCommonBaseLayoutComputeChildFrameRectFromParentRect(ih, parent_rect);

	
	// Experimentally, it looks like I just need to shift 1 pixel down to make it look right.
	child_rect.origin.y = child_rect.origin.y - 1.0;
	
	
	[child_view setFrame:child_rect];
	
	
	
}


/* IupButton must deliver BUTTON_CB (iup_button.c registers it for every platform); gtk connects
   it to button-press/release-event and Windows handles WM_*BUTTONDOWN/UP. The Cocoa backend had
   the code for it commented out in IupCocoaButtonReceiver with a note that Cocoa buttons do not
   normally report press/release pairs -- true of the target/action mechanism, but the events are
   right there in the responder chain.

   NSButton is not like the label: -mouseDown: runs the cell's tracking loop, which sends the
   target/action (IUP's ACTION callback) and normally swallows the matching mouse-up. So super
   must still be called, and the release is reported once it returns. IUP documents both
   BUTTON_CB calls as occurring before ACTION; here the release necessarily lands after it,
   because that is when the platform tells us the button was let go. The press ordering is
   correct, and _iupSentRelease keeps the release from being reported twice if a future macOS
   does deliver -mouseUp: separately. */
@interface IupCocoaButton : NSButton
{
	BOOL _iupSentRelease;
}
@end

static void cocoaButtonHandleMouseButton(NSView* the_view, NSEvent* the_event, bool is_pressed)
{
	Ihandle* ih = (Ihandle*)objc_getAssociatedObject(the_view, IHANDLE_ASSOCIATED_OBJ_KEY);
	if(NULL == ih)
	{
		return;
	}
	(void)iupCocoaCommonBaseHandleMouseButtonCallback(ih, the_event, the_view, is_pressed);
}

@implementation IupCocoaButton

- (void) mouseDown:(NSEvent*)the_event
{
	if(![self isEnabled])
	{
		[super mouseDown:the_event];
		return;
	}

	_iupSentRelease = NO;
	cocoaButtonHandleMouseButton(self, the_event, true);

	[super mouseDown:the_event];   /* tracks the mouse and fires ACTION */

	if(!_iupSentRelease)
	{
		/* super consumed the mouse-up; use the event that ended the tracking loop so the
		   reported coordinates are the release point rather than the press point. */
		NSEvent* release_event = [NSApp currentEvent];
		if((nil == release_event) || ([release_event type] != NSEventTypeLeftMouseUp))
		{
			release_event = the_event;
		}
		cocoaButtonHandleMouseButton(self, release_event, false);
	}
}

- (void) mouseUp:(NSEvent*)the_event
{
	if([self isEnabled])
	{
		_iupSentRelease = YES;
		cocoaButtonHandleMouseButton(self, the_event, false);
	}
	[super mouseUp:the_event];
}

- (void) rightMouseDown:(NSEvent*)the_event
{
	if([self isEnabled])
	{
		cocoaButtonHandleMouseButton(self, the_event, true);
	}
	/* NSView's implementation is what pops up the CONTEXTMENU */
	[super rightMouseDown:the_event];
}

- (void) rightMouseUp:(NSEvent*)the_event
{
	if([self isEnabled])
	{
		cocoaButtonHandleMouseButton(self, the_event, false);
	}
	[super rightMouseUp:the_event];
}

- (void) otherMouseDown:(NSEvent*)the_event
{
	if([self isEnabled])
	{
		cocoaButtonHandleMouseButton(self, the_event, true);
	}
	[super otherMouseDown:the_event];
}

- (void) otherMouseUp:(NSEvent*)the_event
{
	if([self isEnabled])
	{
		cocoaButtonHandleMouseButton(self, the_event, false);
	}
	[super otherMouseUp:the_event];
}

@end


static NSButton* cocoaButtonGetButton(Ihandle* ih)
{
	NSView* root_view = (NSView*)ih->handle;
	if(![root_view isKindOfClass:[NSButton class]])
	{
		return nil;
	}
	return (NSButton*)root_view;
}

/* IUP's IMAGEPOSITION says where the image sits relative to the text. */
static NSCellImagePosition cocoaButtonCellImagePosition(int iup_img_position)
{
	switch(iup_img_position)
	{
		case IUP_IMGPOS_RIGHT:  return NSImageRight;
		case IUP_IMGPOS_TOP:    return NSImageAbove;
		case IUP_IMGPOS_BOTTOM: return NSImageBelow;
		case IUP_IMGPOS_LEFT:
		default:                return NSImageLeft;
	}
}

/* Single place that resolves which image the button shows, transcribed from iupwin_button.c.
   The map method used to do `if (IMINACTIVE is set) make_inactive = 1;` and then apply that to
   IMAGE regardless of whether the button was actually inactive -- so merely defining IMINACTIVE
   greyed out an enabled button, and the IMINACTIVE image itself was never loaded at all. */
static void cocoaButtonApplyImage(Ihandle* ih, int is_active)
{
	NSButton* the_button = cocoaButtonGetButton(ih);
	const char* image_name = iupAttribGet(ih, "IMAGE");
	const char* name;
	int make_inactive = 0;

	if((nil == the_button) || !(ih->data->type & IUP_BUTTON_IMAGE))
	{
		return;
	}

	if(is_active)
	{
		name = image_name;
	}
	else
	{
		name = iupAttribGet(ih, "IMINACTIVE");
		if(!name)
		{
			name = image_name;
			make_inactive = 1;
		}
	}

	[the_button setImage:name ? iupImageGetImage(name, ih, make_inactive, NULL) : nil];

	{
		const char* press_name = iupAttribGet(ih, "IMPRESS");
		if(press_name && *press_name != 0)
		{
			[the_button setAlternateImage:iupImageGetImage(press_name, ih, 0, NULL)];
		}
	}

	if(ih->data->type & IUP_BUTTON_TEXT)
	{
		[the_button setImagePosition:cocoaButtonCellImagePosition(ih->data->img_position)];
	}
}

/* FGCOLOR on an NSButton has to go through the attributed title -- there is no setTextColor:.
   Setting a plain title resets any attributed one, so this is also how the colour is removed. */
static void cocoaButtonApplyTitleColor(Ihandle* ih)
{
	NSButton* the_button = cocoaButtonGetButton(ih);
	const char* fg_value;
	unsigned char r;
	unsigned char g;
	unsigned char b;

	if((nil == the_button) || !(ih->data->type & IUP_BUTTON_TEXT))
	{
		return;
	}

	fg_value = iupAttribGet(ih, "FGCOLOR");
	if(fg_value && iupStrToRGB(fg_value, &r, &g, &b))
	{
		NSColor* the_color = [NSColor colorWithCalibratedRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
		NSMutableParagraphStyle* paragraph_style = [[NSMutableParagraphStyle alloc] init];
		NSDictionary* attributes;
		NSAttributedString* attributed_title;

		[paragraph_style setAlignment:[the_button alignment]];
		attributes = [NSDictionary dictionaryWithObjectsAndKeys:
			the_color, NSForegroundColorAttributeName,
			paragraph_style, NSParagraphStyleAttributeName,
			[the_button font], NSFontAttributeName,
			nil];
		attributed_title = [[NSAttributedString alloc] initWithString:[the_button title] attributes:attributes];
		[the_button setAttributedTitle:attributed_title];
		[attributed_title release];
		[paragraph_style release];
	}
	else
	{
		/* Back to the system colour, which is dynamic and follows Dark Mode. */
		[the_button setTitle:[the_button title]];
	}
}


static int cocoaButtonSetFgColorAttrib(Ihandle* ih, const char* value)
{
	/* IUP has not stored the new value yet, so put it in place first and let the funnel read it. */
	iupAttribSetStr(ih, "FGCOLOR", value);
	cocoaButtonApplyTitleColor(ih);
	return 1;
}

static int cocoaButtonSetBgColorAttrib(Ihandle* ih, const char* value)
{
	NSButton* the_button = cocoaButtonGetButton(ih);
	unsigned char r;
	unsigned char g;
	unsigned char b;

	if(nil == the_button)
	{
		return 1;
	}
	/* -setBezelColor: tints the standard push-button bezel (10.12.2+). Windows and GTK3 both
	   ignore BGCOLOR once a title or image is set, so tinting here is no worse than parity. */
	if([the_button respondsToSelector:@selector(setBezelColor:)])
	{
		if(value && iupStrToRGB(value, &r, &g, &b))
		{
			[the_button setBezelColor:[NSColor colorWithCalibratedRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0]];
		}
		else
		{
			[the_button setBezelColor:nil];
		}
	}
	return 1;
}

static int cocoaButtonSetImageAttrib(Ihandle* ih, const char* value)
{
	if(ih->data->type & IUP_BUTTON_IMAGE)
	{
		iupAttribSetStr(ih, "IMAGE", value);
		cocoaButtonApplyImage(ih, iupdrvIsActive(ih));
		return 1;
	}
	return 1;
}

static int cocoaButtonSetImInactiveAttrib(Ihandle* ih, const char* value)
{
	iupAttribSetStr(ih, "IMINACTIVE", value);
	cocoaButtonApplyImage(ih, iupdrvIsActive(ih));
	return 1;
}

static int cocoaButtonSetImPressAttrib(Ihandle* ih, const char* value)
{
	iupAttribSetStr(ih, "IMPRESS", value);
	cocoaButtonApplyImage(ih, iupdrvIsActive(ih));
	return 1;
}

static int cocoaButtonSetAlignmentAttrib(Ihandle* ih, const char* value)
{
	NSButton* the_button = cocoaButtonGetButton(ih);
	char value1[30];
	char value2[30];

	iupStrToStrStr(value, value1, value2, ':');

	if(iupStrEqualNoCase(value1, "ARIGHT"))
	{
		ih->data->horiz_alignment = IUP_ALIGN_ARIGHT;
	}
	else if(iupStrEqualNoCase(value1, "ALEFT"))
	{
		ih->data->horiz_alignment = IUP_ALIGN_ALEFT;
	}
	else
	{
		ih->data->horiz_alignment = IUP_ALIGN_ACENTER;
	}

	if(iupStrEqualNoCase(value2, "ATOP"))
	{
		ih->data->vert_alignment = IUP_ALIGN_ATOP;
	}
	else if(iupStrEqualNoCase(value2, "ABOTTOM"))
	{
		ih->data->vert_alignment = IUP_ALIGN_ABOTTOM;
	}
	else
	{
		ih->data->vert_alignment = IUP_ALIGN_ACENTER;
	}

	if(nil != the_button)
	{
		switch(ih->data->horiz_alignment)
		{
			case IUP_ALIGN_ARIGHT: [the_button setAlignment:NSTextAlignmentRight];  break;
			case IUP_ALIGN_ALEFT:  [the_button setAlignment:NSTextAlignmentLeft];   break;
			default:               [the_button setAlignment:NSTextAlignmentCenter]; break;
		}
		/* the attributed title carries its own paragraph style, so rebuild it */
		cocoaButtonApplyTitleColor(ih);
	}
	/* Vertical alignment is not settable on an NSButton title; Motif has the same restriction. */
	return 0;
}

static char* cocoaButtonGetAlignmentAttrib(Ihandle* ih)
{
	char* horiz_align2str[3] = {"ALEFT", "ACENTER", "ARIGHT"};
	char* vert_align2str[3] = {"ATOP", "ACENTER", "ABOTTOM"};
	return iupStrReturnStrf("%s:%s", horiz_align2str[ih->data->horiz_alignment],
		vert_align2str[ih->data->vert_alignment]);
}

static int cocoaButtonSetPaddingAttrib(Ihandle* ih, const char* value)
{
	iupStrToIntInt(value, &ih->data->horiz_padding, &ih->data->vert_padding, 'x');
	if(ih->handle)
	{
		/* the common ComputeNaturalSize adds 2*padding, so the button has to be re-laid out */
		IupRefresh(ih);
	}
	/* Return 1: iupAttribUpdate() drops any attribute whose setter returns 0, which would discard
	   padding set before map. */
	return 1;
}

static int cocoaButtonSetActiveAttrib(Ihandle* ih, const char* value)
{
	int is_active = iupStrBoolean(value);

	/* gtk and win both swap in the inactive image; previously nothing happened at all. */
	cocoaButtonApplyImage(ih, is_active);

	return iupBaseSetActiveAttrib(ih, value);
}


static int cocoaButtonMapMethod(Ihandle* ih)
{
	char* value;

	/*
	static int woffset = 0;
	static int hoffset = 0;
	
	woffset += 30;
	hoffset += 30;
//	ih->data->type = 0;
	
	 NSButton* the_button = [[NSButton alloc] initWithFrame:NSMakeRect(woffset, hoffset, 0, 0)];
	*/
	NSButton* the_button = [[IupCocoaButton alloc] initWithFrame:NSZeroRect];
	// I seem to be getting a default "Button" title for image button.
	[the_button setTitle:@""];
	

	value = iupAttribGet(ih, "IMAGE");
	if(value)
	{
		ih->data->type = IUP_BUTTON_IMAGE;
		
		const char* title = iupAttribGet(ih, "TITLE");
		if (title && *title!=0)
		{
			ih->data->type |= IUP_BUTTON_TEXT;
			
			
			char* stripped_str = iupStrProcessMnemonic(title, NULL, 0);   /* remove & */
			
			// This will return nil if the string can't be converted.
			NSString* ns_string = iupCocoaStringFromCStr(stripped_str);
			
			if(stripped_str && stripped_str != title)
			{
				free(stripped_str);
			}
			
			[the_button setTitle:ns_string];

			[the_button setImagePosition:cocoaButtonCellImagePosition(ih->data->img_position)];
		}
		else
		{
			// Explicitly set to NSImageOnly, otherwise expanding the image button does it in a off-centered way.
			[the_button setImagePosition:NSImageOnly];
		}
		
		
		[the_button setButtonType:NSMomentaryChangeButton];

		// I don't know what the style should be for images
		// https://mackuba.eu/2014/10/06/a-guide-to-nsbutton-styles/
//		[the_button setBezelStyle:NSRoundedBezelStyle];
		[the_button setBezelStyle:NSThickSquareBezelStyle];
//		[the_button setBezelStyle:NSShadowlessSquareBezelStyle];
//		[the_button setBezelStyle:NSTexturedSquareBezelStyle];
//		[the_button setBezelStyle:NSThickerSquareBezelStyle];

		
		/* the image itself is applied after ih->handle is set, by cocoaButtonApplyImage */
	}
	else
	{
		[the_button setButtonType:NSMomentaryLightButton];
		[the_button setBezelStyle:NSRoundedBezelStyle];
		
		ih->data->type = IUP_BUTTON_TEXT;

		

	}
	
	// Interface builder defaults to 13pt, but programmatic is smaller (12?). Setting the font fixes that difference.
	[the_button setFont:[NSFont systemFontOfSize:0]];

//	[the_button setButtonType:NSMomentaryLightButton];


	
//	[the_button sizeToFit];
	
	
	
	ih->handle = the_button;
	iupCocoaSetAssociatedViews(ih, the_button, the_button);

	// I'm using objc_setAssociatedObject/objc_getAssociatedObject because it allows me to avoid making subclasses just to hold ivars.
	objc_setAssociatedObject(the_button, IHANDLE_ASSOCIATED_OBJ_KEY, (id)ih, OBJC_ASSOCIATION_ASSIGN);
	// I also need to track the memory of the buttion action receiver.
	// I prefer to keep the Ihandle the actual NSView instead of the receiver because it makes the rest of the implementation easier if the handle is always an NSView (or very small set of things, e.g. NSWindow, NSView, CALayer).
	// So with only one pointer to deal with, this means we need our button to hold a reference to the receiver object.
	// This is generally not good Cocoa as buttons don't retain their receivers, but this seems like the best option.
	// Be careful of retain cycles.
	IupCocoaButtonReceiver* button_receiver = [[IupCocoaButtonReceiver alloc] init];
	[the_button setTarget:button_receiver];
	[the_button setAction:@selector(myButtonClickAction:)];
	// I *think* is we use RETAIN, the object will be released automatically when the button is freed.
	// However, the fact that this is tricky and I had to look up the rules (not to mention worrying about retain cycles)
	// makes me think I should just explicitly manage the memory so everybody is aware of what's going on.
	objc_setAssociatedObject(the_button, IUP_COCOA_BUTTON_RECEIVER_OBJ_KEY, (id)button_receiver, OBJC_ASSOCIATION_ASSIGN);

	
	/* Both need ih->handle, so they run after it is assigned. */
	cocoaButtonApplyImage(ih, iupdrvIsActive(ih));
	cocoaButtonApplyTitleColor(ih);

	// All Cocoa views shoud call this to add the new view to the parent view.
	iupCocoaAddToParent(ih);

	
	
	

	
	
//	gtk_widget_realize(ih->handle);
	
	/* update a mnemonic in a label if necessary */
//	iupgtkUpdateMnemonic(ih);
	
	return IUP_NOERROR;
}

static void cocoaButtonUnMapMethod(Ihandle* ih)
{
	id the_button = ih->handle;

	// Destroy the context menu ih it exists
	{
		Ihandle* context_menu_ih = (Ihandle*)iupCocoaCommonBaseGetContextMenuAttrib(ih);
		if(NULL != context_menu_ih)
		{
			IupDestroy(context_menu_ih);
		}
		iupCocoaCommonBaseSetContextMenuAttrib(ih, NULL);
	}
	
	id butten_receiver = objc_getAssociatedObject(the_button, IUP_COCOA_BUTTON_RECEIVER_OBJ_KEY);
	objc_setAssociatedObject(the_button, IUP_COCOA_BUTTON_RECEIVER_OBJ_KEY, nil, OBJC_ASSOCIATION_ASSIGN);
	[butten_receiver release];
	
	iupCocoaRemoveFromParent(ih);
	iupCocoaSetAssociatedViews(ih, nil, nil);

	[the_button release];
	ih->handle = NULL;
	
}


void iupdrvButtonInitClass(Iclass* ic)
{
	/* Driver Dependent Class functions */
	ic->Map = cocoaButtonMapMethod;
	ic->UnMap = cocoaButtonUnMapMethod;
	

	ic->LayoutUpdate = cocoaButtonLayoutUpdateMethod;
	/* Overwrite Visual */
	iupClassRegisterAttribute(ic, "ACTIVE", iupBaseGetActiveAttrib, cocoaButtonSetActiveAttrib, IUPAF_SAMEASSYSTEM, "YES", IUPAF_DEFAULT);

	/* Visual */
	iupClassRegisterAttribute(ic, "BGCOLOR", iupBaseNativeParentGetBgColorAttrib, cocoaButtonSetBgColorAttrib, IUPAF_SAMEASSYSTEM, "DLGBGCOLOR", IUPAF_NO_SAVE);

	/* Special */
	iupClassRegisterAttribute(ic, "FGCOLOR", NULL, cocoaButtonSetFgColorAttrib, IUPAF_SAMEASSYSTEM, "DLGFGCOLOR", IUPAF_DEFAULT);

	iupClassRegisterAttribute(ic, "TITLE", NULL, cocoaButtonSetTitleAttrib, NULL, NULL, IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);

	/* IupButton only */
	iupClassRegisterAttribute(ic, "ALIGNMENT", cocoaButtonGetAlignmentAttrib, cocoaButtonSetAlignmentAttrib, IUPAF_SAMEASSYSTEM, "ACENTER:ACENTER", IUPAF_NO_INHERIT);
	iupClassRegisterAttribute(ic, "IMAGE", NULL, cocoaButtonSetImageAttrib, NULL, NULL, IUPAF_IHANDLENAME|IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
	iupClassRegisterAttribute(ic, "IMINACTIVE", NULL, cocoaButtonSetImInactiveAttrib, NULL, NULL, IUPAF_IHANDLENAME|IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
	iupClassRegisterAttribute(ic, "IMPRESS", NULL, cocoaButtonSetImPressAttrib, NULL, NULL, IUPAF_IHANDLENAME|IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);

	iupClassRegisterAttribute(ic, "PADDING", iupButtonGetPaddingAttrib, cocoaButtonSetPaddingAttrib, IUPAF_SAMEASSYSTEM, "0x0", IUPAF_NOT_MAPPED);

	/* GTK only -- pango markup has no Cocoa equivalent; register it as Windows does so it is a
	   known-but-unsupported attribute rather than an unknown one. */
	iupClassRegisterAttribute(ic, "MARKUP", NULL, NULL, NULL, NULL, IUPAF_NOT_SUPPORTED|IUPAF_NO_INHERIT);

	/* New API for view specific contextual menus (Mac only) */
	iupClassRegisterAttribute(ic, "CONTEXTMENU", iupCocoaCommonBaseGetContextMenuAttrib, iupCocoaCommonBaseSetContextMenuAttrib, NULL, NULL, IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
	iupClassRegisterAttribute(ic, "LAYERBACKED", iupCocoaCommonBaseGetLayerBackedAttrib, iupCocoaCommonBaseSetLayerBackedAttrib, NULL, NULL, IUPAF_NO_DEFAULTVALUE);

}
