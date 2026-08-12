/** \file
 * \brief Toggle Control
 *
 * See Copyright Notice in "iup.h"
 */

#import <Cocoa/Cocoa.h>



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
#include "iup_drv.h"
#include "iup_drvfont.h"
#include "iup_image.h"
#include "iup_key.h"
#include "iup_toggle.h"

#include "iupcocoa_drv.h"


/** \file
 * \brief Toggle Control
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
#include "iup_toggle.h"
#include "iup_drv.h"
#include "iup_drvfont.h"
#include "iup_image.h"
#include "iup_key.h"

#include "iupcocoa_drv.h"


// the point of this is we have a unique memory address for an identifier
static const void* IUP_COCOA_TOGGLE_RECEIVER_OBJ_KEY = "IUP_COCOA_TOGGLE_RECEIVER_OBJ_KEY";


@interface IupCocoaToggleReceiver : NSObject
- (IBAction) myToggleClickAction:(id)the_sender;
@end

@implementation IupCocoaToggleReceiver

/*
 - (void) dealloc
 {
	[super dealloc];
 }
 */


- (IBAction) myToggleClickAction:(id)the_sender;
{
//	Icallback callback_function;
	Ihandle* ih = (Ihandle*)objc_getAssociatedObject(the_sender, IHANDLE_ASSOCIATED_OBJ_KEY);
	
	NSControlStateValue new_state = [the_sender state];
	
	
	// CONFLICT: Cocoa Toggles don't normally do anything for non-primary click. (Second click is supposed to trigger the contextual menu.)
	// Also Cocoa doesn't normall give callbacks for both down and up
	/*
	 callback_function = IupGetCallback(ih, "toggle_CB");
	 if(callback_function)
	 {
		if(callback_function(ih) == IUP_CLOSE)
		{
	 IupExitLoop();
		}
		
	 }
	 */
	
	IFni action_callback_function = (IFni)IupGetCallback(ih, "ACTION");
	if(action_callback_function)
	{
		if(action_callback_function(ih, (int)new_state) == IUP_CLOSE)
		{
			IupExitLoop();
		}
	}
	Icallback valuechanged_callback_function = IupGetCallback(ih, "VALUECHANGED_CB");
	if(valuechanged_callback_function)
	{
		if(valuechanged_callback_function(ih) == IUP_CLOSE)
		{
			IupExitLoop();
		}
	}
}

@end

// This only gets called for images
void iupdrvToggleAddBorders(Ihandle* ih, int *x, int *y)
{
}



void iupdrvToggleAddCheckBox(Ihandle* ih, int *x, int *y, const char* str)
{
	// Includes padding between box and text
	*x += 20;
	
	// Add a little more for border padding because iupdrvToggleAddBorders only calls for images
	*x += 4;
	*y += 4;

}


static NSButton* cocoaToggleGetButton(Ihandle* ih)
{
	NSView* root_view = (NSView*)ih->handle;
	if(![root_view isKindOfClass:[NSButton class]])
	{
		return nil;
	}
	return (NSButton*)root_view;
}

/* Which image the toggle shows. Transcribed from iupwin_toggle.c; the map method used to do
   `if (IMINACTIVE is set) make_inactive = 1;` and apply that to IMAGE whether or not the toggle
   was inactive, so merely defining IMINACTIVE greyed out an enabled toggle and the IMINACTIVE
   image itself was never loaded. */
static void cocoaToggleApplyImage(Ihandle* ih, int is_active)
{
	NSButton* the_toggle = cocoaToggleGetButton(ih);
	const char* image_name = iupAttribGet(ih, "IMAGE");
	const char* name;
	int make_inactive = 0;

	if((nil == the_toggle) || (ih->data->type != IUP_TOGGLE_IMAGE))
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

	[the_toggle setImage:name ? iupImageGetImage(name, ih, make_inactive, NULL) : nil];

	{
		const char* press_name = iupAttribGet(ih, "IMPRESS");
		if(press_name && *press_name != 0)
		{
			[the_toggle setAlternateImage:iupImageGetImage(press_name, ih, 0, NULL)];
		}
	}
}

/* FGCOLOR has to go through the attributed title -- NSButton has no -setTextColor:. Setting a
   plain title clears any attributed one, which is also how the colour is removed. */
static void cocoaToggleApplyTitleColor(Ihandle* ih)
{
	NSButton* the_toggle = cocoaToggleGetButton(ih);
	const char* fg_value;
	unsigned char r;
	unsigned char g;
	unsigned char b;

	if((nil == the_toggle) || (ih->data->type != IUP_TOGGLE_TEXT))
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

		[paragraph_style setAlignment:[the_toggle alignment]];
		attributes = [NSDictionary dictionaryWithObjectsAndKeys:
			the_color, NSForegroundColorAttributeName,
			paragraph_style, NSParagraphStyleAttributeName,
			[the_toggle font], NSFontAttributeName,
			nil];
		attributed_title = [[NSAttributedString alloc] initWithString:[the_toggle title] attributes:attributes];
		[the_toggle setAttributedTitle:attributed_title];
		[attributed_title release];
		[paragraph_style release];
	}
	else
	{
		/* back to the system colour, which is dynamic and follows Dark Mode */
		[the_toggle setTitle:[the_toggle title]];
	}
}

static int cocoaToggleSetFgColorAttrib(Ihandle* ih, const char* value)
{
	iupAttribSetStr(ih, "FGCOLOR", value);
	cocoaToggleApplyTitleColor(ih);
	return 1;
}

static int cocoaToggleSetBgColorAttrib(Ihandle* ih, const char* value)
{
	(void)value;
	(void)ih;
	/* A checkbox/radio draws its own control background; win and gtk effectively ignore BGCOLOR
	   here too. Registered so it is readable and reports the native parent colour. */
	return 1;
}

static int cocoaToggleSetImageAttrib(Ihandle* ih, const char* value)
{
	iupAttribSetStr(ih, "IMAGE", value);
	cocoaToggleApplyImage(ih, iupdrvIsActive(ih));
	return 1;
}

static int cocoaToggleSetImInactiveAttrib(Ihandle* ih, const char* value)
{
	iupAttribSetStr(ih, "IMINACTIVE", value);
	cocoaToggleApplyImage(ih, iupdrvIsActive(ih));
	return 1;
}

static int cocoaToggleSetImPressAttrib(Ihandle* ih, const char* value)
{
	iupAttribSetStr(ih, "IMPRESS", value);
	cocoaToggleApplyImage(ih, iupdrvIsActive(ih));
	return 1;
}

static int cocoaToggleSetAlignmentAttrib(Ihandle* ih, const char* value)
{
	NSButton* the_toggle = cocoaToggleGetButton(ih);
	char value1[30];
	char value2[30];

	if(nil == the_toggle)
	{
		return 1;
	}

	iupStrToStrStr(value, value1, value2, ':');

	if(iupStrEqualNoCase(value1, "ARIGHT"))
	{
		[the_toggle setAlignment:NSTextAlignmentRight];
	}
	else if(iupStrEqualNoCase(value1, "ALEFT"))
	{
		[the_toggle setAlignment:NSTextAlignmentLeft];
	}
	else
	{
		[the_toggle setAlignment:NSTextAlignmentCenter];
	}

	/* the attributed title carries its own paragraph style, so it has to be rebuilt */
	cocoaToggleApplyTitleColor(ih);

	/* Vertical alignment is not settable on an NSButton title; Motif has the same restriction. */
	return 1;
}

static int cocoaTogglePaddingAttrib(Ihandle* ih, const char* value)
{
	iupStrToIntInt(value, &ih->data->horiz_padding, &ih->data->vert_padding, 'x');
	if(ih->handle)
	{
		/* the common ComputeNaturalSize adds 2*padding, so re-run the layout */
		IupRefresh(ih);
	}
	/* Return 1: iupAttribUpdate() drops any attribute whose setter returns 0, which would discard
	   padding set before map. */
	return 1;
}

static int cocoaToggleSetActiveAttrib(Ihandle* ih, const char* value)
{
	int is_active = iupStrBoolean(value);

	/* gtk and win both swap in the inactive image; nothing happened here before. */
	cocoaToggleApplyImage(ih, is_active);

	return iupBaseSetActiveAttrib(ih, value);
}


static int cocoaToggleSetTitleAttrib(Ihandle* ih, const char* value)
{
	NSButton* the_toggle = ih->handle;

	char* stripped_str = iupStrProcessMnemonic(value, NULL, 0);   /* remove & */

	if (ih->data->type == IUP_TOGGLE_TEXT)
	{
		if(stripped_str && *stripped_str!=0)
		{
			NSString* ns_string = iupCocoaStringFromCStr(stripped_str);
			[the_toggle setTitle:ns_string];
			cocoaToggleApplyTitleColor(ih);
			/*
			 if(ih->data->type == IUP_TOGGLE_IMAGE)
			 {
			 // TODO: FEATURE: Cocoa allows text to be placed in different positions
			 // https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/Toggle/Tasks/SettingToggleImage.html
			 [the_toggle setImagePosition:NSImageLeft];
			 }
			 else
			 {
			 //			[the_toggle setImagePosition:NSNoImage];
			 
			 }
			 */
		}
		else
		{
			[the_toggle setTitle:@""];
		}

		return 1;
	}
	
	return 0;
}



static int cocoaToggleSetValueAttrib(Ihandle* ih, const char* value)
{
	NSButton* the_toggle = cocoaToggleGetButton(ih);
	Ihandle* radio_parent;
	NSInteger new_state;

	if(nil == the_toggle)
	{
		return 0;
	}

	if(iupStrEqualNoCase(value, "NOTDEF"))
	{
		new_state = NSMixedState;
	}
	else if(iupStrEqualNoCase(value, "TOGGLE"))
	{
		new_state = ([the_toggle state] == NSOffState) ? NSOnState : NSOffState;
	}
	else
	{
		new_state = iupStrBoolean(value) ? NSOnState : NSOffState;
	}

	/* Cocoa only auto-deselects sibling radios that share a superview AND an action, which IUP's
	   layout does not guarantee, and it never does so for a programmatic change. Track the
	   selected one on the IupRadio and clear it by hand, exactly as the Windows driver does. */
	radio_parent = iupRadioFindToggleParent(ih);
	if(radio_parent)
	{
		if(NSOffState != new_state)
		{
			Ihandle* last_toggle = (Ihandle*)iupAttribGet(radio_parent, "_IUPCOCOA_LASTTOGGLE");
			if(iupObjectCheck(last_toggle) && (last_toggle != ih))
			{
				NSButton* last_button = cocoaToggleGetButton(last_toggle);
				[last_button setState:NSOffState];
			}
			iupAttribSet(radio_parent, "_IUPCOCOA_LASTTOGGLE", (char*)ih);
		}
	}

	[the_toggle setState:new_state];
	return 0;
}

static char* cocoaToggleGetValueAttrib(Ihandle* ih)
{
	NSButton* the_toggle = ih->handle;
	int current_state = (int)[the_toggle state];
	// it happens that iupStrReturnChecked uses the same values for mixed, off, and on
	return iupStrReturnChecked(current_state);
}



static int cocoaToggleMapMethod(Ihandle* ih)
{
	char* value;

	
	
	static int woffset = 0;
	static int hoffset = 0;
	
//	woffset += 30;
//	hoffset += 30;
	//	ih->data->type = 0;
	
	NSButton* the_toggle = [[NSButton alloc] initWithFrame:NSZeroRect];

	/* A toggle inside an IupRadio must be a radio button, not a checkbox. Nothing here consulted
	   iupRadioFindToggleParent before, so ih->data->is_radio stayed 0 (making the RADIO attribute
	   report NO) and every radio rendered as a checkbox. gtk and win both do this at map. */
	Ihandle* radio_parent = iupRadioFindToggleParent(ih);
	if(radio_parent)
	{
		ih->data->is_radio = 1;
		[the_toggle setButtonType:NSRadioButton];

		/* make sure it has at least one name, as gtk does */
		if(!iupAttribGetHandleName(ih))
		{
			iupAttribSetHandleName(ih);
		}

		/* the first toggle of a radio starts selected, matching win */
		if(!iupAttribGet(radio_parent, "_IUPCOCOA_LASTTOGGLE"))
		{
			iupAttribSet(ih, "VALUE", "ON");
		}
	}
	else
	{
		[the_toggle setButtonType:NSSwitchButton];
	}

	if(iupAttribGetBoolean(ih, "3STATE"))
	{
		[the_toggle setAllowsMixedState:YES];
	}
	else
	{
		// too aggressive? should we just leave it alone?
		[the_toggle setAllowsMixedState:NO];
	}
	
	

	value = iupAttribGet(ih, "IMAGE");
	if(value && *value!=0)
	{
		ih->data->type = IUP_TOGGLE_IMAGE;
		
		// I don't know what the style should be for images
		// https://mackuba.eu/2014/10/06/a-guide-to-nsToggle-styles/
		//		[the_toggle setBezelStyle:NSRoundedBezelStyle];
//		[the_toggle setBezelStyle:NSThickSquareBezelStyle];
		//		[the_toggle setBezelStyle:NSShadowlessSquareBezelStyle];
		//		[the_toggle setBezelStyle:NSTexturedSquareBezelStyle];
		//		[the_toggle setBezelStyle:NSThickerSquareBezelStyle];
		
		
		/* the image itself is applied after ih->handle is set, by cocoaToggleApplyImage */
	}
	else
	{
		ih->data->type = IUP_TOGGLE_TEXT;
	}
    value = iupAttribGet(ih, "TITLE");
    if(value && *value!=0)
    {
        char* stripped_str = iupStrProcessMnemonic(value, NULL, 0);   /* remove & */
        
        // This will return nil if the string can't be converted.
        NSString* ns_string = iupCocoaStringFromCStr(stripped_str);
        
        if(stripped_str && stripped_str != value)
        {
            free(stripped_str);
        }
        
        [the_toggle setTitle:ns_string];

    }

	//	[the_toggle setToggleType:NSMomentaryLightButton];



	
//	[the_toggle sizeToFit];
	
	
	
	ih->handle = the_toggle;
	
	// I'm using objc_setAssociatedObject/objc_getAssociatedObject because it allows me to avoid making subclasses just to hold ivars.
	objc_setAssociatedObject(the_toggle, IHANDLE_ASSOCIATED_OBJ_KEY, (id)ih, OBJC_ASSOCIATION_ASSIGN);
	// I also need to track the memory of the buttion action receiver.
	// I prefer to keep the Ihandle the actual NSView instead of the receiver because it makes the rest of the implementation easier if the handle is always an NSView (or very small set of things, e.g. NSWindow, NSView, CALayer).
	// So with only one pointer to deal with, this means we need our Toggle to hold a reference to the receiver object.
	// This is generally not good Cocoa as Toggles don't retain their receivers, but this seems like the best option.
	// Be careful of retain cycles.
	IupCocoaToggleReceiver* toggle_receiver = [[IupCocoaToggleReceiver alloc] init];
	[the_toggle setTarget:toggle_receiver];
	[the_toggle setAction:@selector(myToggleClickAction:)];
	// I *think* is we use RETAIN, the object will be released automatically when the Toggle is freed.
	// However, the fact that this is tricky and I had to look up the rules (not to mention worrying about retain cycles)
	// makes me think I should just explicitly manage the memory so everybody is aware of what's going on.
	objc_setAssociatedObject(the_toggle, IUP_COCOA_TOGGLE_RECEIVER_OBJ_KEY, (id)toggle_receiver, OBJC_ASSOCIATION_ASSIGN);
	
	
	iupCocoaSetAssociatedViews(ih, the_toggle, the_toggle);
	// All Cocoa views shoud call this to add the new view to the parent view.
	/* both need ih->handle, so they run after it is assigned */
	cocoaToggleApplyImage(ih, iupdrvIsActive(ih));
	cocoaToggleApplyTitleColor(ih);

	iupCocoaAddToParent(ih);
	
	

	
	
	
	
	
	//	cocoa_widget_realize(ih->handle);
	
	/* update a mnemonic in a label if necessary */
	//	iupcocoaUpdateMnemonic(ih);
	
	return IUP_NOERROR;
}

static void cocoaToggleUnMapMethod(Ihandle* ih)
{
	id the_toggle = ih->handle;
	
	// Destroy the context menu ih it exists
	{
		Ihandle* context_menu_ih = (Ihandle*)iupCocoaCommonBaseGetContextMenuAttrib(ih);
		if(NULL != context_menu_ih)
		{
			IupDestroy(context_menu_ih);
		}
		iupCocoaCommonBaseSetContextMenuAttrib(ih, NULL);
	}
	
	id butten_receiver = objc_getAssociatedObject(the_toggle, IUP_COCOA_TOGGLE_RECEIVER_OBJ_KEY);
	objc_setAssociatedObject(the_toggle, IUP_COCOA_TOGGLE_RECEIVER_OBJ_KEY, nil, OBJC_ASSOCIATION_ASSIGN);
	[butten_receiver release];
	
	iupCocoaRemoveFromParent(ih);

	iupCocoaSetAssociatedViews(ih, nil, nil);
	[the_toggle release];
	ih->handle = NULL;
	
}


void iupdrvToggleInitClass(Iclass* ic)
{
	/* Driver Dependent Class functions */
	ic->Map = cocoaToggleMapMethod;
	ic->UnMap = cocoaToggleUnMapMethod;
	
  /* Overwrite Visual */
  iupClassRegisterAttribute(ic, "ACTIVE", iupBaseGetActiveAttrib, cocoaToggleSetActiveAttrib, IUPAF_SAMEASSYSTEM, "YES", IUPAF_DEFAULT);

  /* Visual */
  iupClassRegisterAttribute(ic, "BGCOLOR", iupBaseNativeParentGetBgColorAttrib, cocoaToggleSetBgColorAttrib, IUPAF_SAMEASSYSTEM, "DLGBGCOLOR", IUPAF_NO_SAVE);

  /* Special */
  iupClassRegisterAttribute(ic, "FGCOLOR", NULL, cocoaToggleSetFgColorAttrib, IUPAF_SAMEASSYSTEM, "DLGFGCOLOR", IUPAF_DEFAULT);

  iupClassRegisterAttribute(ic, "TITLE", NULL, cocoaToggleSetTitleAttrib, NULL, NULL, IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);

  /* IupToggle only */
  iupClassRegisterAttribute(ic, "ALIGNMENT", NULL, cocoaToggleSetAlignmentAttrib, IUPAF_SAMEASSYSTEM, "ACENTER:ACENTER", IUPAF_NO_INHERIT);
  iupClassRegisterAttribute(ic, "IMAGE", NULL, cocoaToggleSetImageAttrib, NULL, NULL, IUPAF_IHANDLENAME|IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
  iupClassRegisterAttribute(ic, "IMINACTIVE", NULL, cocoaToggleSetImInactiveAttrib, NULL, NULL, IUPAF_IHANDLENAME|IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
  iupClassRegisterAttribute(ic, "IMPRESS", NULL, cocoaToggleSetImPressAttrib, NULL, NULL, IUPAF_IHANDLENAME|IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
	
  iupClassRegisterAttribute(ic, "VALUE", cocoaToggleGetValueAttrib, cocoaToggleSetValueAttrib, NULL, NULL, IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);

  iupClassRegisterAttribute(ic, "PADDING", iupToggleGetPaddingAttrib, cocoaTogglePaddingAttrib, IUPAF_SAMEASSYSTEM, "0x0", IUPAF_NOT_MAPPED);

  /* NOT supported: MARKUP is pango-specific, and RIGHTBUTTON (the checkbox on the trailing side)
     has no NSButton equivalent -- gtk marks RIGHTBUTTON unsupported for the same reason.
     Registered so both are known attributes rather than unknown ones. */
  iupClassRegisterAttribute(ic, "MARKUP", NULL, NULL, NULL, NULL, IUPAF_NOT_SUPPORTED|IUPAF_NO_INHERIT);
  iupClassRegisterAttribute(ic, "RIGHTBUTTON", NULL, NULL, NULL, NULL, IUPAF_NOT_SUPPORTED);
	
	/* New API for view specific contextual menus (Mac only) */
	iupClassRegisterAttribute(ic, "CONTEXTMENU", iupCocoaCommonBaseGetContextMenuAttrib, iupCocoaCommonBaseSetContextMenuAttrib, NULL, NULL, IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
	iupClassRegisterAttribute(ic, "LAYERBACKED", iupCocoaCommonBaseGetLayerBackedAttrib, iupCocoaCommonBaseSetLayerBackedAttrib, NULL, NULL, IUPAF_NO_DEFAULTVALUE);

}
