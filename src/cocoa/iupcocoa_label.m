/** \file
 * \brief Label Control
 *
 * See Copyright Notice in "iup.h"
 */

#include <Cocoa/Cocoa.h>

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
#include "iup_label.h"
#include "iup_drv.h"
#include "iup_image.h"
#include "iup_focus.h"

#include "iup_childtree.h"

#include "iupcocoa_drv.h"

#import "IUPCocoaVerticalAlignmentTextFieldCell.h"



/* IupLabel must deliver BUTTON_CB, MOTION_CB, ENTERWINDOW_CB and LEAVEWINDOW_CB -- iup_label.c
   registers them for every platform. GTK gets them by wrapping every label in a GtkEventBox;
   Windows subclasses the static control with winLabelMsgProc. A stock NSTextField/NSImageView
   delivers none of them, so subclass the two view types the label actually uses.

   No NSBox subclass: Windows installs its message proc only for non-separator labels, and a 2px
   separator is not a usable mouse target.

   A category on NSTextField/NSImageView would have hijacked every such view in the process
   (IupText's field, list and tree cell views); a GTK-style wrapper view would have changed what
   ih->handle is, which the font, active, tips, background and layout code all key off. */

static void cocoaLabelHandleMouseButton(NSView* the_view, Ihandle* ih, NSEvent* the_event, bool is_pressed)
{
	if(NULL == ih)
	{
		return;
	}
	(void)iupCocoaCommonBaseHandleMouseButtonCallback(ih, the_event, the_view, is_pressed);
}

static void cocoaLabelHandleMouseMotion(NSView* the_view, Ihandle* ih, NSEvent* the_event)
{
	if(NULL == ih)
	{
		return;
	}
	(void)iupCocoaCommonBaseHandleMouseMotionCallback(ih, the_event, the_view);
}

/* NSTrackingInVisibleRect makes AppKit maintain the region itself, so the constant frame changes
   IUP's layout performs need no bookkeeping here. The returned area is owned by the caller. */
static NSTrackingArea* cocoaLabelReplaceTrackingArea(NSView* the_view, NSTrackingArea* existing_area)
{
	NSTrackingArea* new_area;

	if(nil != existing_area)
	{
		[the_view removeTrackingArea:existing_area];
		[existing_area release];
	}

	new_area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
		options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved
			| NSTrackingActiveInActiveApp | NSTrackingInVisibleRect)
		owner:the_view
		userInfo:nil];
	[the_view addTrackingArea:new_area];
	return new_area;
}

/* Expanded into both subclasses so the event plumbing exists once.

   -mouseDown: deliberately does not call super. NSTextField and NSImageView are NSControls, and
   NSControl's -mouseDown: hands off to the cell's trackMouse:inRect:ofView:untilMouseUp:, which
   is free to consume events up to and including the matching mouse-up; if it does, -mouseUp:
   never runs and BUTTON_CB reports presses without releases. A label is display-only and has no
   target/action, so there is nothing to gain from super and skipping it keeps the callback
   symmetric. (A synthetic-event test does not reproduce the swallowing either way, because the
   tracking loop pulls from the real event queue -- hence belt and braces rather than a claim.)

   -rightMouseDown: does call super, because NSView's default implementation is what pops up the
   CONTEXTMENU (the canvas carries the same comment). */
#define IUP_COCOA_LABEL_MOUSE_METHODS \
- (BOOL) acceptsFirstMouse:(NSEvent*)the_event { (void)the_event; return YES; } \
- (void) mouseDown:(NSEvent*)the_event \
{ \
	if(![self isEnabled]) { return; } \
	cocoaLabelHandleMouseButton(self, [self ih], the_event, true); \
} \
- (void) mouseUp:(NSEvent*)the_event \
{ \
	if(![self isEnabled]) { return; } \
	cocoaLabelHandleMouseButton(self, [self ih], the_event, false); \
} \
- (void) rightMouseDown:(NSEvent*)the_event \
{ \
	if([self isEnabled]) { cocoaLabelHandleMouseButton(self, [self ih], the_event, true); } \
	[super rightMouseDown:the_event]; \
} \
- (void) rightMouseUp:(NSEvent*)the_event \
{ \
	if(![self isEnabled]) { [super rightMouseUp:the_event]; return; } \
	cocoaLabelHandleMouseButton(self, [self ih], the_event, false); \
} \
- (void) otherMouseDown:(NSEvent*)the_event \
{ \
	if(![self isEnabled]) { return; } \
	cocoaLabelHandleMouseButton(self, [self ih], the_event, true); \
} \
- (void) otherMouseUp:(NSEvent*)the_event \
{ \
	if(![self isEnabled]) { return; } \
	cocoaLabelHandleMouseButton(self, [self ih], the_event, false); \
} \
- (void) mouseDragged:(NSEvent*)the_event \
{ \
	if(![self isEnabled]) { return; } \
	cocoaLabelHandleMouseMotion(self, [self ih], the_event); \
} \
- (void) rightMouseDragged:(NSEvent*)the_event \
{ \
	if(![self isEnabled]) { return; } \
	cocoaLabelHandleMouseMotion(self, [self ih], the_event); \
} \
- (void) otherMouseDragged:(NSEvent*)the_event \
{ \
	if(![self isEnabled]) { return; } \
	cocoaLabelHandleMouseMotion(self, [self ih], the_event); \
} \
- (void) mouseMoved:(NSEvent*)the_event \
{ \
	if(![self isEnabled]) { return; } \
	cocoaLabelHandleMouseMotion(self, [self ih], the_event); \
} \
- (void) mouseEntered:(NSEvent*)the_event \
{ \
	(void)the_event; \
	if(![self isEnabled]) { return; } \
	if([self ih]) { iupCocoaCommonBaseHandleMouseEnterWindowCallback([self ih]); } \
} \
- (void) mouseExited:(NSEvent*)the_event \
{ \
	/* Deliberately not gated on isEnabled: an app that deactivates the label from inside its own \
	   ENTERWINDOW_CB (the label test does exactly that) would otherwise never see the leave and \
	   would be stuck believing the pointer is still inside. */ \
	(void)the_event; \
	if([self ih]) { iupCocoaCommonBaseHandleMouseLeaveWindowCallback([self ih]); } \
} \
- (void) updateTrackingAreas \
{ \
	[super updateTrackingAreas]; \
	_iupTrackingArea = cocoaLabelReplaceTrackingArea(self, _iupTrackingArea); \
} \
- (void) dealloc \
{ \
	if(nil != _iupTrackingArea) \
	{ \
		[self removeTrackingArea:_iupTrackingArea]; \
		[_iupTrackingArea release]; \
		_iupTrackingArea = nil; \
	} \
	[super dealloc]; \
}

@interface IupCocoaLabelTextField : NSTextField
{
	NSTrackingArea* _iupTrackingArea;
}
@property(nonatomic, assign) Ihandle* ih;
@end

@implementation IupCocoaLabelTextField
@synthesize ih = _ih;
IUP_COCOA_LABEL_MOUSE_METHODS
@end

@interface IupCocoaLabelImageView : NSImageView
{
	NSTrackingArea* _iupTrackingArea;
}
@property(nonatomic, assign) Ihandle* ih;
@end

@implementation IupCocoaLabelImageView
@synthesize ih = _ih;
IUP_COCOA_LABEL_MOUSE_METHODS
@end


static NSView* cocoaLabelGetRootView(Ihandle* ih)
{
	NSView* root_container_view = (NSView*)ih->handle;
	return root_container_view;
}

static NSTextField* cocoaLabelGetTextField(Ihandle* ih)
{
	/* An IupLabel is not always a text field: SEPARATOR and IMAGE labels map to other views.
	   Asserting here aborted the process (e.g. IupGetParam builds separator labels and then sets
	   TITLE on them). Every caller already tests the result for nil, so return nil instead. */
	NSView* root_container_view = cocoaLabelGetRootView(ih);
	if(![root_container_view isKindOfClass:[NSTextField class]])
	{
		return nil;
	}
	return (NSTextField*)root_container_view;
}

static NSImageView* cocoaLabelGetImageView(Ihandle* ih)
{
	NSView* root_container_view = cocoaLabelGetRootView(ih);
	if(![root_container_view isKindOfClass:[NSImageView class]])
	{
		return nil;
	}
	return (NSImageView*)root_container_view;
}


/* Single place that decides which image an image-label shows, transcribed from the Windows
   backend (iupwin_label.c:54-69). The previous inline copies had the branches transposed: when
   the label was inactive and IMINACTIVE *was* set they discarded it and made IMAGE inactive, and
   when it was inactive with no IMINACTIVE they passed that NULL straight to iupImageGetImage.
   IMINACTIVE is documented GTK/Motif-only so it is deliberately not registered, but an
   unregistered attribute still reaches the hash table, so reading it here matches Windows. */
static void cocoaLabelSetNativeImage(Ihandle* ih, const char* image_name, int is_active)
{
	NSImageView* image_view = cocoaLabelGetImageView(ih);
	const char* name;
	int make_inactive = 0;

	if(nil == image_view)
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

	if(!name)
	{
		[image_view setImage:nil];
		return;
	}

	[image_view setImage:iupImageGetImage(name, ih, make_inactive, NULL)];
}


void iupdrvLabelAddExtraPadding(Ihandle* ih, int *x, int *y)
{
	/* Every other backend makes this a no-op, but NSTextFieldCell insets its title by about 2px
	   on each side, so a text label sized to exactly iupdrvFontGetMultiLineStringSize clips.
	   The inset is real only for text: an NSImageView has none, and adding it to a separator
	   made a vertical rule 6px wide where GTK and Windows give 2. */
	if(iupLabelGetTypeBeforeMap(ih) == IUP_LABEL_TEXT)
	{
		*x += 4;
	}
}


/* One place decides the label's text colour, because ACTIVE and FGCOLOR both want to own it and
   the font code can put the field into attributed-string mode where -setTextColor: is ignored.
   Inactive wins over FGCOLOR, matching Windows (COLOR_GRAYTEXT) and GTK (insensitive styling).
   `fg_override` exists because IUP has not stored the new value yet when a setter runs. */
static void cocoaLabelUpdateTextColor(Ihandle* ih, int is_active, const char* fg_override)
{
	NSTextField* the_label = cocoaLabelGetTextField(ih);
	NSColor* the_color;

	if(nil == the_label)
	{
		return;   /* separators and image labels have no text */
	}

	if(!is_active)
	{
		the_color = [NSColor disabledControlTextColor];
	}
	else
	{
		const char* fg_value = fg_override ? fg_override : iupAttribGet(ih, "FGCOLOR");
		unsigned char r;
		unsigned char g;
		unsigned char b;

		if(fg_value && iupStrToRGB(fg_value, &r, &g, &b))
		{
			the_color = [NSColor colorWithCalibratedRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
		}
		else
		{
			/* Deliberately NOT the DLGFGCOLOR global: iupcocoa_open.m captures that once at
			   startup from windowFrameTextColor, so using it would freeze labels to whichever
			   appearance was active then and break Dark Mode. controlTextColor is dynamic. */
			the_color = [NSColor controlTextColor];
		}
	}

	[the_label setTextColor:the_color];

	/* A field showing an NSAttributedString (underline/strikeout fonts) ignores textColor, so the
	   colour has to be written into the string itself. Guarded so a plain field is never
	   silently promoted to attributed. */
	if([iupCocoaGetFont(ih) usesAttributes]
		&& [the_label respondsToSelector:@selector(setAttributedStringValue:)])
	{
		NSMutableAttributedString* mutable_string = [[the_label attributedStringValue] mutableCopy];
		if([mutable_string length] > 0)
		{
			[mutable_string addAttribute:NSForegroundColorAttributeName
				value:the_color range:NSMakeRange(0, [mutable_string length])];
			[the_label setAttributedStringValue:mutable_string];
		}
		[mutable_string release];
	}
}


static int cocoaLabelSetFgColorAttrib(Ihandle* ih, const char* value)
{
	cocoaLabelUpdateTextColor(ih, iupdrvIsActive(ih), value);
	return 1;
}


static int cocoaLabelSetPaddingAttrib(Ihandle* ih, const char* value)
{
	// Our Cocoa iupdrvbaseUpdateLayout contains a special case to handle padding. We just need to make sure the padding values get set here.
	// Other platforms seem to be skipping separators. We could theoretically support this since we are just manually computing offsets in iupdrvbaseUpdateLayout.
	if(ih->handle && ih->data->type != IUP_LABEL_SEP_HORIZ && ih->data->type != IUP_LABEL_SEP_VERT)
	{
		// I believe this sets the internal data structure values.
		iupStrToIntInt(value, &ih->data->horiz_padding, &ih->data->vert_padding, 'x');
		// HACK: I need to force a redraw. iupdrvbaseUpdateLayout queries the PADDING attribute, but it is not immediately set yet. So I'll force it to set now.
		iupAttribSetStr(ih, "PADDING", value);
		
		// Windows always calls iupdrvRedrawNow, and we need to too because the change won't update without it.
		// But this can require a new layout, so we need IupRefresh.
		IupRefresh(ih);
	}
	/* Must return 1 so the value stays in the hash table. iupAttribUpdate() removes any attribute
	   whose setter returns 0 (iup_attrib.c), and the Cocoa layout code reads PADDING back with
	   iupAttribGet -- so returning 0 silently discarded any padding set before map. */
	return 1;
}


static int cocoaLabelSetTitleAttrib(Ihandle* ih, const char* value)
{
	NSTextField* the_label = cocoaLabelGetTextField(ih);
	if(the_label)
	{
		// NSImageCells don't accept a stringValue, so bail out if we have a cell
		if([the_label respondsToSelector:@selector(cell)])
		{
			id cell = [the_label cell];
			if((nil != cell) && [cell isKindOfClass:[NSImageCell class]])
			{
				return 0;
			}
		}
	
	
		NSString* ns_string = nil;
		if(value)
		{
			char* stripped_str = iupStrProcessMnemonic(value, NULL, 0);   /* remove & */
			
			// This will return nil if the string can't be converted.
			ns_string = iupCocoaStringFromCStr(stripped_str);
			
			if(stripped_str && stripped_str != value)
			{
				free(stripped_str);
			}
		}
		else
		{
			ns_string = @"";
		}
		
	
		// If the user set font attributes, we should try to use them
		IupCocoaFont* iup_font = iupCocoaGetFont(ih);
		if([iup_font usesAttributes]
			&& [the_label respondsToSelector:@selector(setAttributedStringValue:)]
		)
		{
			NSAttributedString* attr_str = [[NSAttributedString alloc] initWithString:ns_string attributes:[iup_font attributeDictionary]];
			[the_label setAttributedStringValue:attr_str];
			[attr_str release];
			/* the new attributed string carries no colour of its own */
			cocoaLabelUpdateTextColor(ih, iupdrvIsActive(ih), NULL);
			// I think I need to call this. I noticed in another program, when I suddenly set a long string, it seems to use the prior layout. This forces a relayout.
			IupRefresh(ih);
		}
		else if([the_label respondsToSelector:@selector(setStringValue:)])
		{
			[the_label setStringValue:ns_string];
			// I think I need to call this. I noticed in another program, when I suddenly set a long string, it seems to use the prior layout. This forces a relayout.
			IupRefresh(ih);
		}
	}
	return 1;

}




static int cocoaLabelSetActiveAttrib(Ihandle* ih, const char* value)
{
	int is_active = iupStrBoolean(value);

	/* Pass is_active explicitly rather than asking iupdrvIsActive: the native enabled flag still
	   holds the old value at this point. */
	if(IUP_LABEL_IMAGE == ih->data->type)
	{
		/* gtk and win both grey the image when inactive; previously only setEnabled: was called,
		   which leaves an NSImageView looking identical. */
		cocoaLabelSetNativeImage(ih, iupAttribGet(ih, "IMAGE"), is_active);
	}
	else
	{
		/* No-op for separators, which used to fall into an else that logged
		   "Unexpected type in cocoaLabelSetActiveAttrib" on every call. */
		cocoaLabelUpdateTextColor(ih, is_active, NULL);
	}

	/* Chaining gets the setEnabled: call (iupdrvSetActive dispatches on respondsToSelector:, so
	   NSBox is correctly skipped) plus the parent-is-active check, matching gtk. */
	return iupBaseSetActiveAttrib(ih, value);
}


static char* cocoaLabelGetTitleAttrib(Ihandle* ih)
{
	NSTextField* the_label = cocoaLabelGetTextField(ih);
	if(the_label)
	{
		// This could be a NSTextField, some kind of image, or something else.
		
		if([the_label respondsToSelector:@selector(setStringValue:)])
		{
			NSString* ns_string = [the_label stringValue];
			if(ns_string)
			{
				return iupStrReturnStr([ns_string UTF8String]);
			}
		}
	}
	return NULL;
	
}
static int cocoaLabelSetAlignmentAttrib(Ihandle* ih, const char* value)
{
	if(ih->data->type != IUP_LABEL_SEP_HORIZ && ih->data->type != IUP_LABEL_SEP_VERT)
	{
		if(ih->data->type == IUP_LABEL_TEXT)
		{
			NSTextField* the_label = cocoaLabelGetTextField(ih);

			// Note: We might be able to get away with any kind of NSControl
			NSCAssert([the_label isKindOfClass:[NSTextField class]], @"Expected NSTextField");

			char value1[30], value2[30];
			
			iupStrToStrStr(value, value1, value2, ':');

			
			if (iupStrEqualNoCase(value1, "ARIGHT"))
			{
				[the_label setAlignment:NSTextAlignmentRight];
			}
			else if (iupStrEqualNoCase(value1, "ACENTER"))
			{
				[the_label setAlignment:NSTextAlignmentCenter];
			}
			else /* "ALEFT" */
			{
				[the_label setAlignment:NSTextAlignmentLeft];

			}
			
			
			// Vertical alignment is not built into NSTextField.
			// We implemented our own custom NSTextFieldCell subclass to handle this case.
			
			if (iupStrEqualNoCase(value2, "ABOTTOM"))
			{
				NSCAssert([[the_label cell] isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
				IUPCocoaVerticalAlignmentTextFieldCell* vertical_alignment_cell = (IUPCocoaVerticalAlignmentTextFieldCell*)[the_label cell];
				[vertical_alignment_cell setAlignmentMode:IUPTextVerticalAlignmentBottom];
			}
			else if (iupStrEqualNoCase(value2, "ATOP"))
			{
				NSCAssert([[the_label cell] isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
				IUPCocoaVerticalAlignmentTextFieldCell* vertical_alignment_cell = (IUPCocoaVerticalAlignmentTextFieldCell*)[the_label cell];
				[vertical_alignment_cell setAlignmentMode:IUPTextVerticalAlignmentTop];
			}
			else  /* ACENTER (default) */
			{
				NSCAssert([[the_label cell] isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
				IUPCocoaVerticalAlignmentTextFieldCell* vertical_alignment_cell = (IUPCocoaVerticalAlignmentTextFieldCell*)[the_label cell];
				[vertical_alignment_cell setAlignmentMode:IUPTextVerticalAlignmentCenter];

			}

			return 1;
		}
		else if(ih->data->type == IUP_LABEL_IMAGE)
		{
			NSImageView* the_label = cocoaLabelGetImageView(ih);
			// Note: We might be able to get away with any kind of NSControl
			NSCAssert([the_label isKindOfClass:[NSImageView class]], @"Expected NSImageView");
			
			char value1[30], value2[30];
			
			iupStrToStrStr(value, value1, value2, ':');
			
			
			if(iupStrEqualNoCase(value1, "ARIGHT"))
			{
				if(iupStrEqualNoCase(value2, "ABOTTOM"))
				{
					[the_label setImageAlignment:NSImageAlignBottomRight];
				}
				else if (iupStrEqualNoCase(value2, "ATOP"))
				{
					[the_label setImageAlignment:NSImageAlignTopRight];
				}
				else  /* ACENTER */
				{
					[the_label setImageAlignment:NSImageAlignRight];
				}
			}
			else if (iupStrEqualNoCase(value1, "ACENTER"))
			{
				if(iupStrEqualNoCase(value2, "ABOTTOM"))
				{
					[the_label setImageAlignment:NSImageAlignBottom];
				}
				else if (iupStrEqualNoCase(value2, "ATOP"))
				{
					[the_label setImageAlignment:NSImageAlignTop];
				}
				else  /* ACENTER */
				{
					[the_label setImageAlignment:NSImageAlignCenter];
				}
			}
			else /* "ALEFT" */
			{
				if(iupStrEqualNoCase(value2, "ABOTTOM"))
				{
					[the_label setImageAlignment:NSImageAlignBottomLeft];
				}
				else if (iupStrEqualNoCase(value2, "ATOP"))
				{
					[the_label setImageAlignment:NSImageAlignTopLeft];
				}
				else  /* ACENTER */
				{
					[the_label setImageAlignment:NSImageAlignLeft];
				}
			}
			
			
			return 1;
		}
	}
	
	return 0;
}

// Warning: The pre-10.10 behavior never behaved well. Maybe it should be removed.
static int cocoaLabelSetWordWrapAttrib(Ihandle* ih, const char* value)
{
	if (ih->data->type == IUP_LABEL_TEXT)
	{
		NSTextField* the_label = cocoaLabelGetTextField(ih);
		// Note: We might be able to get away with any kind of NSControl
		NSCAssert([the_label isKindOfClass:[NSTextField class]], @"Expected NSTextField");
		if(iupStrBoolean(value))
		{
			// setLineBreakMode Requires 10.10+. Allows for both word wrapping and different ellipsis behaviors.
			if([the_label respondsToSelector:@selector(setLineBreakMode:)])
			{
				[the_label setLineBreakMode:NSLineBreakByWordWrapping];
				IUPCocoaVerticalAlignmentTextFieldCell* vertical_cell = [the_label cell];
				NSCAssert([vertical_cell isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
				[vertical_cell setUseWordWrap:YES];
				[vertical_cell setUseEllipsis:NO];
			}
			else
			{

				char* ellipsis_state = iupAttribGet(ih, "ELLIPSIS");
				if(iupStrBoolean(ellipsis_state))
				{
					// Ellipsis only seem to appear when multiline is enabled
					[the_label setUsesSingleLineMode:NO];
					[[the_label cell] setScrollable:NO];
					
					[[the_label cell] setWraps:YES];
					[[the_label cell] setLineBreakMode:NSLineBreakByTruncatingTail];
					[[the_label cell] setTruncatesLastVisibleLine:YES];
					
					IUPCocoaVerticalAlignmentTextFieldCell* vertical_cell = [the_label cell];
					NSCAssert([vertical_cell isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
					[vertical_cell setUseWordWrap:YES];
					[vertical_cell setUseEllipsis:YES];

					
				}
				else
				{
					[the_label setUsesSingleLineMode:NO];
					[[the_label cell] setScrollable:NO];
					
					[[the_label cell] setWraps:YES];
					[[the_label cell] setLineBreakMode:NSLineBreakByWordWrapping];
					[[the_label cell] setTruncatesLastVisibleLine:NO];
					
					IUPCocoaVerticalAlignmentTextFieldCell* vertical_cell = [the_label cell];
					NSCAssert([vertical_cell isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
					[vertical_cell setUseWordWrap:YES];
					[vertical_cell setUseEllipsis:NO];
				}
				
			}
			
		}
		else
		{
			// setLineBreakMode Requires 10.10+. Allows for both word wrapping and different ellipsis behaviors.
			if([the_label respondsToSelector:@selector(setLineBreakMode:)])
			{
				// Wrapping and ellipsis are mutually exclusive
				char* ellipsis_state = iupAttribGet(ih, "ELLIPSIS");
				if(iupStrBoolean(ellipsis_state))
				{
					[the_label setLineBreakMode:NSLineBreakByTruncatingTail];
					
					IUPCocoaVerticalAlignmentTextFieldCell* vertical_cell = [the_label cell];
					NSCAssert([vertical_cell isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
					[vertical_cell setUseWordWrap:NO];
					[vertical_cell setUseEllipsis:YES];
				}
				else
				{
					[the_label setLineBreakMode:NSLineBreakByClipping];
					
					IUPCocoaVerticalAlignmentTextFieldCell* vertical_cell = [the_label cell];
					NSCAssert([vertical_cell isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
					[vertical_cell setUseWordWrap:NO];
					[vertical_cell setUseEllipsis:NO];
				}
			}
			else
			{
				
				char* ellipsis_state = iupAttribGet(ih, "ELLIPSIS");
				if(iupStrBoolean(ellipsis_state))
				{
					// Ellipsis only seem to appear when multiline is enabled
					[the_label setUsesSingleLineMode:NO];
					[[the_label cell] setScrollable:NO];
					
					[[the_label cell] setWraps:YES];
					[[the_label cell] setLineBreakMode:NSLineBreakByWordWrapping];
					[[the_label cell] setTruncatesLastVisibleLine:YES];
					
					IUPCocoaVerticalAlignmentTextFieldCell* vertical_cell = [the_label cell];
					NSCAssert([vertical_cell isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
					[vertical_cell setUseWordWrap:NO];
					[vertical_cell setUseEllipsis:YES];
				}
				else
				{
					[the_label setUsesSingleLineMode:YES];
					[[the_label cell] setScrollable:YES];
					
					[[the_label cell] setWraps:NO];
					[[the_label cell] setLineBreakMode:NSLineBreakByClipping];
					[[the_label cell] setTruncatesLastVisibleLine:NO];

					IUPCocoaVerticalAlignmentTextFieldCell* vertical_cell = [the_label cell];
					NSCAssert([vertical_cell isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
					[vertical_cell setUseWordWrap:NO];
					[vertical_cell setUseEllipsis:NO];

				}
				
			}
		}
		return 1;
	}
	return 0;
}


// Warning: The pre-10.10 behavior never behaved well. Maybe it should be removed.
static int cocoaLabelSetEllipsisAttrib(Ihandle* ih, const char* value)
{
	if (ih->data->type == IUP_LABEL_TEXT)
	{
		NSTextField* the_label = cocoaLabelGetTextField(ih);
		// Note: We might be able to get away with any kind of NSControl
		NSCAssert([the_label isKindOfClass:[NSTextField class]], @"Expected NSTextField");


		if(iupStrBoolean(value))
		{
			// setLineBreakMode Requires 10.10+. Allows for both word wrapping and different ellipsis behaviors.
			if([the_label respondsToSelector:@selector(setLineBreakMode:)])
			{
				// Wrapping and ellipsis are mutually exclusive
				// TODO: Expose different ellipsis modes to public API
				[the_label setUsesSingleLineMode:YES];
				[the_label setLineBreakMode:NSLineBreakByTruncatingTail];

				IUPCocoaVerticalAlignmentTextFieldCell* vertical_cell = [the_label cell];
				NSCAssert([vertical_cell isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
				[vertical_cell setUseWordWrap:NO];
				[vertical_cell setUseEllipsis:YES];

			}
			else
			{
				// Ellipsis only seem to appear when multiline is enabled
				[[the_label cell] setScrollable:NO];
				
				[[the_label cell] setWraps:YES];
				[[the_label cell] setLineBreakMode:NSLineBreakByWordWrapping];
				[[the_label cell] setTruncatesLastVisibleLine:YES];
				
				IUPCocoaVerticalAlignmentTextFieldCell* vertical_cell = [the_label cell];
				NSCAssert([vertical_cell isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
				[vertical_cell setUseWordWrap:YES];
				[vertical_cell setUseEllipsis:YES];
				
			}
		}
		else
		{
			// setLineBreakMode Requires 10.10+. Allows for both word wrapping and different ellipsis behaviors.
			if([the_label respondsToSelector:@selector(setLineBreakMode:)])
			{
				// Wrapping and ellipsis are mutually exclusive

				char* wordwrap_state = iupAttribGet(ih, "WORDWRAP");
				if(iupStrBoolean(wordwrap_state))
				{
					[the_label setUsesSingleLineMode:NO];
					[the_label setLineBreakMode:NSLineBreakByWordWrapping];
					
					IUPCocoaVerticalAlignmentTextFieldCell* vertical_cell = [the_label cell];
					NSCAssert([vertical_cell isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
					[vertical_cell setUseWordWrap:YES];
					[vertical_cell setUseEllipsis:NO];
				}
				else
				{
					[the_label setLineBreakMode:NSLineBreakByClipping];
					
					IUPCocoaVerticalAlignmentTextFieldCell* vertical_cell = [the_label cell];
					NSCAssert([vertical_cell isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
					[vertical_cell setUseWordWrap:NO];
					[vertical_cell setUseEllipsis:NO];
				}
				
			}
			else
			{
				
				char* wordwrap_state = iupAttribGet(ih, "WORDWRAP");
				if(iupStrBoolean(wordwrap_state))
				{
					[[the_label cell] setScrollable:NO];
					
					[[the_label cell] setWraps:YES];
					[[the_label cell] setLineBreakMode:NSLineBreakByWordWrapping];
					[[the_label cell] setTruncatesLastVisibleLine:YES];
					
					IUPCocoaVerticalAlignmentTextFieldCell* vertical_cell = [the_label cell];
					NSCAssert([vertical_cell isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
					[vertical_cell setUseWordWrap:YES];
					[vertical_cell setUseEllipsis:NO];
				}
				else
				{
					[[the_label cell] setScrollable:YES];
					
					[[the_label cell] setWraps:NO];
					[[the_label cell] setLineBreakMode:NSLineBreakByClipping];
					[[the_label cell] setTruncatesLastVisibleLine:NO];
					
					IUPCocoaVerticalAlignmentTextFieldCell* vertical_cell = [the_label cell];
					NSCAssert([vertical_cell isKindOfClass:[IUPCocoaVerticalAlignmentTextFieldCell class]], @"Expected IUPCocoaVerticalAlignmentTextFieldCell");
					[vertical_cell setUseWordWrap:NO];
					[vertical_cell setUseEllipsis:NO];
				}
								
			}

		
		}
		return 1;
	}
	return 0;
}


static int cocoaLabelSetImageAttrib(Ihandle* ih, const char* value)
{
	
	if(ih->data->type == IUP_LABEL_IMAGE)
	{
		/* Deliberately no longer resizes the view: the frame belongs to
		   iupdrvBaseLayoutUpdateMethod, which derives it from ih->currentwidth/currentheight, so
		   writing it here only desynchronised the two until the next layout pass. Neither GTK nor
		   Windows resizes on IMAGE set, and IupAnimatedLabel re-sets IMAGE on every timer tick. */
		cocoaLabelSetNativeImage(ih, value, iupdrvIsActive(ih));
		return 1;
	}
	else
	{
		return 0;
	}
}



static int cocoaLabelMapMethod(Ihandle* ih)
{
	char* value;
	// using id because we may be using different types depending on the case
	id the_label = nil;
	
	value = iupAttribGet(ih, "SEPARATOR");
	if (value)
	{
		if (iupStrEqualNoCase(value, "HORIZONTAL"))
		{
			ih->data->type = IUP_LABEL_SEP_HORIZ;

//			NSBox* horizontal_separator= [[NSBox alloc] initWithFrame:NSMakeRect(20.0, 20.0, 250.0, 1.0)];
			NSBox* horizontal_separator= [[NSBox alloc] initWithFrame:NSMakeRect(0.0, 0.0, 250.0, 1.0)];
			[horizontal_separator setBoxType:NSBoxSeparator];
			the_label = horizontal_separator;
			
		}
		else /* "VERTICAL" */
		{
			ih->data->type = IUP_LABEL_SEP_VERT;

//			NSBox* vertical_separator=[[NSBox alloc] initWithFrame:NSMakeRect(20.0, 20.0, 1.0, 250.0)];
			NSBox* vertical_separator=[[NSBox alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1.0, 250.0)];
			[vertical_separator setBoxType:NSBoxSeparator];
			the_label = vertical_separator;

		}
	}
	else
	{
		value = iupAttribGet(ih, "IMAGE");
		if (value)
		{
			ih->data->type = IUP_LABEL_IMAGE;

			int width = 0;
			int height = 0;
			int bpp = 0;

			/* Size the initial frame from the image purely as a placeholder; the real frame
			   arrives from iupdrvBaseLayoutUpdateMethod once IUP computes the layout. */
			iupdrvImageGetInfo(iupImageGetImage(value, ih, 0, NULL), &width, &height, &bpp);

			NSImageView* image_view = [[IupCocoaLabelImageView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
			the_label = image_view;
		}
		else
		{
			ih->data->type = IUP_LABEL_TEXT;

			the_label = [[IupCocoaLabelTextField alloc] initWithFrame:NSZeroRect];
//			the_label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];

#if 1
			IUPCocoaVerticalAlignmentTextFieldCell* textfield_cell = [[IUPCocoaVerticalAlignmentTextFieldCell alloc] initTextCell:@""];
			[the_label setCell:textfield_cell];
			[textfield_cell release];
			//[textfield_cell setScrollable:NO];
			
//			[textfield_cell performClick:nil];
			
//			[textfield_cell setAlignmentMode:IUPTextVerticalAlignmentTop];
			
#endif
			
			
			[the_label setBezeled:NO];
			[the_label setDrawsBackground:NO];
//			[the_label setDrawsBackground:YES]; // sometimes helpful for debugging layout issues
			[the_label setEditable:NO];
//			[the_label setSelectable:NO];
			// TODO: FEATURE: I think this is really convenient for users so it should be the default
			// FIXME: APPLE BUG: setSelectable:YES completely breaks using our vertical alignment cell subclass.
			// When clicking the text, the text will snap to a wrong position and stay there.
//			[the_label setSelectable:YES];
			
//			NSFont* the_font = [the_label font];
//			NSLog(@"font %@", the_font);
			[the_label setFont:[NSFont systemFontOfSize:0.0]];

			
			
#if 1
			if([the_label respondsToSelector:@selector(setLineBreakMode:)])
			{
				[the_label setLineBreakMode:NSLineBreakByClipping];
				
			}
			else
			{
				
				[[the_label cell] setTruncatesLastVisibleLine:NO];


				
				
				[the_label setUsesSingleLineMode:YES];
				[[the_label cell] setScrollable:YES];
				
				[[the_label cell] setWraps:NO];
				[[the_label cell] setLineBreakMode:NSLineBreakByClipping];
				[[the_label cell] setTruncatesLastVisibleLine:NO];
				
			}
			
			
	
#else
			
			
			[the_label setUsesSingleLineMode:NO];
			[[the_label cell] setWraps:YES];
			[[the_label cell] setScrollable:NO];
			
//			[[the_label cell] setTruncatesLastVisibleLine:YES];

			// setLineBreakMode Requires 10.10+. Allows for both word wrapping and different ellipsis behaviors.
//			[the_label setLineBreakMode:NSLineBreakByWordWrapping];
#endif
			

		}
	}
	
	if (!the_label)
	{
		return IUP_ERROR;
	}
	
	
	ih->handle = the_label;
	iupCocoaSetAssociatedViews(ih, the_label, the_label);

	/* Separators are NSBox and have no -setIh:, matching Windows, which does not wire mouse
	   messages for them either. */
	if([the_label respondsToSelector:@selector(setIh:)])
	{
		[the_label setIh:ih];
	}

	/* Now that ih->handle is set, cocoaLabelSetNativeImage can find the view. Doing this here
	   rather than inline above keeps IMINACTIVE handling in exactly one place. */
	if(IUP_LABEL_IMAGE == ih->data->type)
	{
		cocoaLabelSetNativeImage(ih, iupAttribGet(ih, "IMAGE"), iupdrvIsActive(ih));
	}


	
	/* add to the parent, all GTK controls must call this. */
//	iupgtkAddToParent(ih);
	
	
//	Ihandle* ih_parent = ih->parent;
//	id parent_native_handle = ih_parent->handle;
	
	iupCocoaAddToParent(ih);
	
	
	/* configure for DRAG&DROP of files */
	if (IupGetCallback(ih, "DROPFILES_CB"))
	{
		iupAttribSet(ih, "DROPFILESTARGET", "YES");
	}
	
	return IUP_NOERROR;
}


static void cocoaLabelUnMapMethod(Ihandle* ih)
{
	id the_label = ih->handle;
	// Destroy the context menu ih it exists
	{
		Ihandle* context_menu_ih = (Ihandle*)iupCocoaCommonBaseGetContextMenuAttrib(ih);
		if(NULL != context_menu_ih)
		{
			IupDestroy(context_menu_ih);
		}
		iupCocoaCommonBaseSetContextMenuAttrib(ih, NULL);
	}

	/* Drop the back-pointer before anything else can deliver a late event to a dead Ihandle. */
	if([the_label respondsToSelector:@selector(setIh:)])
	{
		[the_label setIh:NULL];
	}

	iupCocoaRemoveFromParent(ih);
	iupCocoaSetAssociatedViews(ih, nil, nil);
	[the_label release];
	ih->handle = nil;

}


void iupdrvLabelInitClass(Iclass* ic)
{
  /* Driver Dependent Class functions */
  ic->Map = cocoaLabelMapMethod;
	ic->UnMap = cocoaLabelUnMapMethod;
	


  /* Driver Dependent Attribute functions */

  /* Overwrite Visual */
  iupClassRegisterAttribute(ic, "ACTIVE", iupBaseGetActiveAttrib, cocoaLabelSetActiveAttrib, IUPAF_SAMEASSYSTEM, "YES", IUPAF_DEFAULT);
  /* Visual */
  /* Getter only, as on Windows: the label is already setDrawsBackground:NO, so it is transparent
     and takes the native parent's colour -- which is what the documentation specifies. The getter
     is not cosmetic: iupImageGetImage() reads BGCOLOR to blend the greyed-out version of an
     image label, so without it an inactive image blends against the wrong colour. */
  iupClassRegisterAttribute(ic, "BGCOLOR", iupBaseNativeParentGetBgColorAttrib, NULL, IUPAF_SAMEASSYSTEM, "DLGBGCOLOR", IUPAF_NO_SAVE);

  /* Special */
  iupClassRegisterAttribute(ic, "FGCOLOR", NULL, cocoaLabelSetFgColorAttrib, IUPAF_SAMEASSYSTEM, "DLGFGCOLOR", IUPAF_DEFAULT);
	
  iupClassRegisterAttribute(ic, "TITLE", cocoaLabelGetTitleAttrib, cocoaLabelSetTitleAttrib, NULL, NULL, IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
  /* IupLabel only */
  iupClassRegisterAttribute(ic, "ALIGNMENT", NULL, cocoaLabelSetAlignmentAttrib, "ALEFT:ACENTER", NULL, IUPAF_NO_INHERIT);  /* force new default value */
  iupClassRegisterAttribute(ic, "IMAGE", NULL, cocoaLabelSetImageAttrib, NULL, NULL, IUPAF_IHANDLENAME|IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
  iupClassRegisterAttribute(ic, "PADDING", iupLabelGetPaddingAttrib, cocoaLabelSetPaddingAttrib, IUPAF_SAMEASSYSTEM, "0x0", IUPAF_NOT_MAPPED);
#if 0
  /* IupLabel GTK and Motif only */
  iupClassRegisterAttribute(ic, "IMINACTIVE", NULL, gtkLabelSetImInactiveAttrib, NULL, NULL, IUPAF_IHANDLENAME|IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
#endif
	
  /* IupLabel Windows and GTK only */
  iupClassRegisterAttribute(ic, "WORDWRAP", NULL, cocoaLabelSetWordWrapAttrib, NULL, NULL, IUPAF_DEFAULT);
  iupClassRegisterAttribute(ic, "ELLIPSIS", NULL, cocoaLabelSetEllipsisAttrib, NULL, NULL, IUPAF_DEFAULT);

  /* IupLabel GTK only -- pango markup has no Cocoa equivalent. Register it the way Windows does
     so it is a known-but-unsupported attribute rather than an unknown one. */
  iupClassRegisterAttribute(ic, "MARKUP", NULL, NULL, NULL, NULL, IUPAF_NOT_SUPPORTED|IUPAF_NO_INHERIT);
	

	/* New API for view specific contextual menus (Mac only) */
	iupClassRegisterAttribute(ic, "CONTEXTMENU", iupCocoaCommonBaseGetContextMenuAttrib, iupCocoaCommonBaseSetContextMenuAttrib, NULL, NULL, IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);


}
