/** \file
 * \brief Menu Resources
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
#include "iup_childtree.h"
#include "iup_attrib.h"
#include "iup_dialog.h"
#include "iup_str.h"
#include "iup_label.h"
#include "iup_drv.h"
#include "iup_drvfont.h"
#include "iup_image.h"
#include "iup_menu.h"

#include "iupcocoa_drv.h"

/*
For a menu bar:

AppleIcon File Edit Window
               ----
			   Copy
 
 In Cocoa:
 NSMenu (menubar)
 -> addItem: NSMenuItem (for Edit, but not named)
    -> setSubmenu: NSMenu ("Edit", this is the thing that sets the name)
       -> addItem: NSMenuItem (for "Paste")
 
 In IUP:
 IupMenu (menubar)
 -> IupSubmenu (this is the part that gets named "Edit")
    -> IupMenu  (for Edit, but this is not named)
       -> IupItem (for "Paste")
 
 Notice that Submenu is an NSMenuItem. And the naming must be done on the NSMenu attached below it, not on the NSMenuItem itself.
 
*/


// This is for keeping a pointer to the Ihandle to the current set IupMenu for the application menu.
static Ihandle* s_currentIupMainMenu = NULL;


static void cocoaCreateDefaultApplicationMenu()
{
		id app_name = [[NSProcessInfo processInfo] processName];
#if 0
	
	NSBundle* framework_bundle = [NSBundle bundleWithIdentifier:@"br.puc-rio.tecgraf.iup"];

	/* Note: I discovered that some menus use private/magic capabilites which are not accessible through public API.
	 The Services menu and Window are two major examples. They have a extra field in the XIB data as systemMenu="services" and systemMenu="window"
	 The Help and App menu also have systemMenu entries.
	 So the only solution is to use Interface Builder files to provide these.
	 The debate is whether to just target the individual pieces or provide a single monolithic XIB with everything.
	 */
	
	id app_menu = [[[NSMenu alloc] init] autorelease];
	
	id about_menu_item = [[[NSMenuItem alloc] initWithTitle:[[NSLocalizedString(@"About", @"About") stringByAppendingString:@" "] stringByAppendingString:app_name] action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""] autorelease];
	id preferences_menu_item = [[[NSMenuItem alloc] initWithTitle:[NSLocalizedString(@"Preferences", @"Preferences") stringByAppendingString:@"…"] action:nil keyEquivalent:@","] autorelease];
//	id services_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Services", @"Services") action:nil keyEquivalent:@""] autorelease];
	//	id services_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Services", @"Services") action:nil keyEquivalent:@""] autorelease];
	NSNib* services_menu_item_nib = [[[NSNib alloc] initWithNibNamed:@"CanonicalServiceMenu" bundle:framework_bundle] autorelease];
	NSArray* top_level_objects = nil;
	id services_menu_item = nil;
	if([services_menu_item_nib instantiateWithOwner:nil topLevelObjects:&top_level_objects])
	{
		for(id current_object in top_level_objects)
		{
			if([current_object isKindOfClass:[NSMenuItem class]])
			{
				services_menu_item = current_object;
				break;
			}
		}
	}
	
	id hide_menu_item = [[[NSMenuItem alloc] initWithTitle:[[NSLocalizedString(@"Hide", @"Hide") stringByAppendingString:@" "] stringByAppendingString:app_name] action:@selector(hide:) keyEquivalent:@"h"] autorelease];
	id hideothers_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Hide Others", @"Hide Others") action:@selector(hideOtherApplications:) keyEquivalent:@"h"] autorelease];
	[hideothers_menu_item setKeyEquivalentModifierMask:NSEventModifierFlagOption|NSEventModifierFlagCommand];
	id showall_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Show All", @"Show All") action:@selector(unhideAllApplications:) keyEquivalent:@""] autorelease];
	id quit_title = [[NSLocalizedString(@"Quit", @"Quit") stringByAppendingString:@" "] stringByAppendingString:app_name];
	id quit_menu_item = [[[NSMenuItem alloc] initWithTitle:quit_title action:@selector(terminate:) keyEquivalent:@"q"] autorelease];


	[app_menu addItem:about_menu_item];
	[app_menu addItem:[NSMenuItem separatorItem]];
	[app_menu addItem:preferences_menu_item];
	[app_menu addItem:[NSMenuItem separatorItem]];
	[app_menu addItem:services_menu_item];
	[app_menu addItem:[NSMenuItem separatorItem]];
	[app_menu addItem:hide_menu_item];
	[app_menu addItem:hideothers_menu_item];
	[app_menu addItem:showall_menu_item];
	[app_menu addItem:[NSMenuItem separatorItem]];
	[app_menu addItem:quit_menu_item];
	
//	id services_sub_menu = [[[NSMenu alloc] init] autorelease];
//	[services_menu_item setSubmenu:services_sub_menu];


	id app_menu_category = [[[NSMenuItem alloc] init] autorelease];
	[app_menu_category setSubmenu:app_menu];
	// This is supposed to do nothing. This is a cheat so I can look up this menu item later and try to reuse it.
	[app_menu_category setTitle:@"ApplicationMenu"];
	
	
	
	
	
//	id print_title = [NSLocalizedString(@"Print", @"Print") stringByAppendingString:@"…"];
//	id print_menu_item = [[[NSMenuItem alloc] initWithTitle:print_title action:@selector(print:) keyEquivalent:@"p"] autorelease];
	
	id file_menu = [[[NSMenu alloc] init] autorelease];
	[file_menu setTitle:NSLocalizedString(@"File", @"File")];
	
//	[file_menu addItem:print_menu_item];

	
	
	id file_menu_category = [[[NSMenuItem alloc] init] autorelease];
	[file_menu_category setSubmenu:file_menu];
	// This is supposed to do nothing. This is a cheat so I can look up this menu item later and try to reuse it.
	[file_menu_category setTitle:NSLocalizedString(@"File", @"File")];

	
	
	
	id cut_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Cut", @"Cut") action:@selector(cut:) keyEquivalent:@"x"] autorelease];
	id copy_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Copy", @"Copy") action:@selector(copy:) keyEquivalent:@"c"] autorelease];
	id paste_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Paste", @"Paste") action:@selector(paste:) keyEquivalent:@"v"] autorelease];
	id selectall_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Select All", @"Select All") action:@selector(selectAll:) keyEquivalent:@"a"] autorelease];
	id findroot_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Find", @"Find") action:nil keyEquivalent:@""] autorelease];

	
	id edit_menu = [[[NSMenu alloc] init] autorelease];
	[edit_menu setTitle:NSLocalizedString(@"Edit", @"Edit")];

	[edit_menu addItem:cut_menu_item];
	[edit_menu addItem:copy_menu_item];
	[edit_menu addItem:paste_menu_item];
	[edit_menu addItem:selectall_menu_item];
	[edit_menu addItem:[NSMenuItem separatorItem]];
	[edit_menu addItem:findroot_menu_item];

	

	id find_sub_menu = [[[NSMenu alloc] init] autorelease];
	[find_sub_menu setTitle:NSLocalizedString(@"Find", @"Find")];
	[findroot_menu_item setSubmenu:find_sub_menu];
	
	id find_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Find", @"Find") action:@selector(performFindPanelAction:) keyEquivalent:@"f"] autorelease];
	id findreplace_menu_item = [[[NSMenuItem alloc] initWithTitle:[NSLocalizedString(@"Find and Replace", @"Find and Replace") stringByAppendingString:@"…"] action:@selector(performFindPanelAction:) keyEquivalent:@"f"] autorelease];
	[findreplace_menu_item setKeyEquivalentModifierMask:NSEventModifierFlagOption|NSEventModifierFlagCommand];
	id findnext_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Find Next", @"Find Next") action:@selector(performFindPanelAction:) keyEquivalent:@"g"] autorelease];
	id findprevious_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Find Previous", @"Find Previous") action:@selector(performFindPanelAction:) keyEquivalent:@"G"] autorelease];
	id useselection_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Use Selection for Find", @"Use Selection for Find") action:@selector(performFindPanelAction:) keyEquivalent:@"e"] autorelease];
	id jumpselection_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Jump to Selection", @"Jump to Selection") action:@selector(centerSelectionInVisibleArea:) keyEquivalent:@"j"] autorelease];

	
	
	[find_sub_menu addItem:find_menu_item];
	[find_sub_menu addItem:findreplace_menu_item];
	[find_sub_menu addItem:findnext_menu_item];
	[find_sub_menu addItem:findprevious_menu_item];
	[find_sub_menu addItem:useselection_menu_item];
	[find_sub_menu addItem:jumpselection_menu_item];


	id edit_menu_category = [[[NSMenuItem alloc] init] autorelease];
	[edit_menu_category setSubmenu:edit_menu];
	// This is supposed to do nothing. This is a cheat so I can look up this menu item later and try to reuse it.
	[edit_menu_category setTitle:NSLocalizedString(@"Edit", @"Edit")];

	
/*
	id minimize_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Minimize", @"Minimize") action:@selector(performMiniaturize:) keyEquivalent:@"m"] autorelease];
	id zoom_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Zoom", @"Zoom") action:@selector(performZoom:) keyEquivalent:@""] autorelease];
	id bringallfront_menu_item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Bring All to Front", @"Bring All to Front") action:@selector(arrangeInFront:) keyEquivalent:@""] autorelease];


	id window_menu = [[[NSMenu alloc] init] autorelease];
	[window_menu setTitle:NSLocalizedString(@"Window", @"Window")];
	
	[window_menu addItem:minimize_menu_item];
	[window_menu addItem:zoom_menu_item];
	[window_menu addItem:[NSMenuItem separatorItem]];
	[window_menu addItem:bringallfront_menu_item];

	id window_menu_category = [[[NSMenuItem alloc] init] autorelease];
	[window_menu_category setSubmenu:window_menu];
	// This is supposed to do nothing. This is a cheat so I can look up this menu item later and try to reuse it.
	[window_menu_category setTitle:NSLocalizedString(@"Window", @"Window")];
*/
	NSNib* window_menu_category_nib = [[[NSNib alloc] initWithNibNamed:@"CanonicalWindowMenu" bundle:framework_bundle] autorelease];
	top_level_objects = nil;
	id window_menu_category = nil;
	if([window_menu_category_nib instantiateWithOwner:nil topLevelObjects:&top_level_objects])
	{
		for(id current_object in top_level_objects)
		{
			if([current_object isKindOfClass:[NSMenuItem class]])
			{
				window_menu_category = current_object;
				break;
			}
		}
	}
	// This is supposed to do nothing. This is a cheat so I can look up this menu item later and try to reuse it.
	[window_menu_category setTitle:NSLocalizedString(@"Window", @"Window")];
	
	
	id help_menu_item = [[[NSMenuItem alloc] initWithTitle:[[app_name stringByAppendingString:@" "] stringByAppendingString:NSLocalizedString(@"Help", @"Help")] action:@selector(showHelp:) keyEquivalent:@"?"] autorelease];
	id help_menu = [[[NSMenu alloc] init] autorelease];
	[help_menu setTitle:NSLocalizedString(@"Help", @"Help")];
	
	[help_menu addItem:help_menu_item];

	id help_menu_category = [[[NSMenuItem alloc] init] autorelease];
	[help_menu_category setSubmenu:help_menu];
	// This is supposed to do nothing. This is a cheat so I can look up this menu item later and try to reuse it.
	[help_menu_category setTitle:NSLocalizedString(@"Window", @"Window")];
	
	
	id menu_bar = [[[NSMenu alloc] init] autorelease];
	[NSApp setMainMenu:menu_bar];
	
	[menu_bar addItem:app_menu_category];
	[menu_bar addItem:file_menu_category];
	[menu_bar addItem:edit_menu_category];
	[menu_bar addItem:window_menu_category];
	[menu_bar addItem:help_menu_category];
#else
	
	NSNib* main_menu_nib = nil;

	// If the user supplies a MainMenu.xib in their own application bundle, allow the user to override our default one.

	// initWithNibNamed will throw an exception if not found. I could catch the exception, but I would rather avoid the whole exception mechanism if possible.
	// I've read claims we only need to check for nib (and not also xib) since these are always supposed to be compiled to nib.
	if([[NSBundle mainBundle] pathForResource:@"MainMenu" ofType:@"nib"] != nil)
	{
		main_menu_nib = [[[NSNib alloc] initWithNibNamed:@"MainMenu" bundle:nil] autorelease];
	}
	else
	{
		NSBundle* framework_bundle = [NSBundle bundleWithIdentifier:@"br.puc-rio.tecgraf.iup"];
		main_menu_nib = [[[NSNib alloc] initWithNibNamed:@"IupMainMenu" bundle:framework_bundle] autorelease];
	}

	NSMenu* menu_bar = nil;

	NSArray* top_level_objects = nil;
	if([main_menu_nib instantiateWithOwner:nil topLevelObjects:&top_level_objects])
	{
		for(id current_object in top_level_objects)
		{
			if([current_object isKindOfClass:[NSMenu class]])
			{
				menu_bar = current_object;
				[NSApp setMainMenu:current_object];
				break;
			}
		}
	}
	// Go through the items and replace the hardcoded MacCocoaAppTemplate with the real app name.
	for(NSMenuItem* current_top_item in [menu_bar itemArray])
	{

		{
			NSString* title_string = [current_top_item title];
			NSString* fixed_string = [title_string stringByReplacingOccurrencesOfString:@"MacCocoaAppTemplate" withString:app_name];
			if(![title_string isEqualToString:fixed_string])
			{
				[current_top_item setTitle:fixed_string];
			}
		}
		
		NSMenu* current_menu = [current_top_item submenu];
		// Note: This does not recurse down submenus of the primary submenu
		for(NSMenuItem* current_menu_item in [current_menu itemArray])
		{
			NSString* title_string = [current_menu_item title];
			NSString* fixed_string = [title_string stringByReplacingOccurrencesOfString:@"MacCocoaAppTemplate" withString:app_name];
			if(![title_string isEqualToString:fixed_string])
			{
				[current_menu_item setTitle:fixed_string];
			}
		}
	}

#endif
}
@interface IupCocoaMenuItemRepresentedObject : NSObject
{
	Ihandle* _ih;
}
- (instancetype) initWithIhandle:(Ihandle*)ih;
- (Ihandle*) ih;
@end

@implementation IupCocoaMenuItemRepresentedObject

- (instancetype) initWithIhandle:(Ihandle*)ih
{
	self = [super init];
	if(nil == self)
	{
		return nil;
	}
	_ih = ih;
	return self;
}

- (Ihandle*) ih
{
	return _ih;
}

- (IBAction) onMenuItemAction:(id)the_sender
{
	Ihandle* ih = [self ih];
	Icallback call_back;
	
	call_back = IupGetCallback(ih, "ACTION");
	if(call_back)
	{
		int ret_val = call_back(ih);
		if(IUP_CLOSE == ret_val)
		{
			IupExitLoop();
			
		}
	}
	
}

// setEnabled: won't work unless we disable autoenablesItems, which I don't want to do because it disables a lot of useful automatic behavior for default menu items.
// So we must use validateMenuItem.
// The trick we can use is that our custom (non-default) menu items use this IupCocoMenuItemRepresentedObject.
// So we can just query the attribute for ACTIVE on the ih, to see if the user turned it on or off and use that for the result for validateMenuItem
- (BOOL) validateMenuItem:(NSMenuItem*)menu_item
{
	Ihandle* ih = [self ih];

	//	NSLog(@"param menu_item: %@", menu_item);
	//	NSMenuItem* ih_menu_item = (NSMenuItem*)ih->handle;
	//	NSLog(@"ih_menu_item: %@", ih_menu_item);

	// It appears that the initial default value is NULL, and not explicit YES or NO.
	// We must use IupGetAttribute instead of IupGetInt to detect the NULL value.
	// If NULL, we treat as ACTIVE.
	char* active_value = IupGetAttribute(ih, "ACTIVE");
//	NSLog(@"active_value: %s", active_value);
	if(NULL == active_value)
	{
		return YES;
	}
	else
	{
		int is_enabled = IupGetInt(ih, "ACTIVE");
		return is_enabled;
	}
	

}

@end

@interface IupCocoaMenuDelegate : NSObject<NSMenuDelegate>

// Use for HIGHLIGHT_CB?
//- (void) menu:(NSMenu*)the_menu willHighlightItem:(NSMenuItem*)menu_item;
@end


@implementation IupCocoaMenuDelegate



// Use for HIGHLIGHT_CB?
/*
- (void) menu:(NSMenu*)the_menu willHighlightItem:(NSMenuItem*)menu_item
{
}
*/


@end


int iupdrvMenuPopup(Ihandle* ih, int x, int y)
{
	NSWindow* key_window = [[NSApplication sharedApplication] keyWindow];
	NSInteger window_number = [key_window windowNumber];
	NSView* content_view = [key_window contentView];

	// The y passed in is inverted (IUP coordinate system). We need to flip back to cartesian.
	NSRect screen_rect = [[NSScreen mainScreen] frame];
	CGFloat cartesian_y = screen_rect.size.height - y;
	
	NSRect absolute_menu_rect = { x, cartesian_y, 0, 0 };
	NSRect converted_window_rect = [key_window convertRectFromScreen:absolute_menu_rect];


	NSPoint converted_point = converted_window_rect.origin;
	
//		NSPoint converted_point = [self convertPoint:the_point fromView:nil];
	
    NSEvent* the_event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
		location:converted_point
		modifierFlags:(NSEventModifierFlags)0
		timestamp:(NSTimeInterval)0
		windowNumber:window_number
		context:[NSGraphicsContext currentContext]
		subtype:0
		data1:0
		data2:0
	];

	// IMPORTANT: popUpContentMenu blocks until the menu is dismissed.
	// This actually works to our advantage because IUP's API design seems to implicitly assume this and the example in menu.c
	// immediately calls IupDestroy(menu) right after
	// IupPopup(menu, IUP_MOUSEPOS, IUP_MOUSEPOS);
	// Destroying the menu before we are done would be very bad news
	// because we need a valid ih to look up the user's callback functions for the menu items they created.
    [NSMenu popUpContextMenu:ih->handle withEvent:the_event forView:content_view];
	return IUP_NOERROR;
}

int iupdrvMenuGetMenuBarSize(Ihandle* ih)
{
	CGFloat menu_bar_height = [[[NSApplication sharedApplication] mainMenu] menuBarHeight];
	return iupROUND(menu_bar_height);
}

/*
static void cocoaReleaseMenuClass(Iclass* ic)
{
	// Not sure if I should tear this down. Typically apps just quit and leave all this stuff.
	[NSApp setMainMenu:nil];

}
*/


int iupCocoaMenuIsApplicationBar(Ihandle* ih)
{
	if (ih->iclass->nativetype == IUP_TYPEMENU)
	{
		int is_app_menu = IupGetInt(ih, "_IUPMAC_APPMENU");
		if(is_app_menu)
		{
			return 1;
		}
	}

	return 0;
}

// Note: This only gets the user's Ihandle to the application menu. If the user doesn't set it, the default application will not be returned in its place. NULL will be returned instead.
Ihandle* iupCocoaMenuGetApplicationMenu()
{
	return s_currentIupMainMenu;
}

// My current understanding is that IUP will not clean up our application menu Ihandles. So we need to do it ourselves.
void iupCocoaMenuCleanupApplicationMenu()
{
	// I believe (hope) this goes through all submenus and items and cleans up everything the user may have created for the main menu.
	// (Remember, the app menu merges default items. So this only cleans up things users explicitly create.
	IupDestroy(s_currentIupMainMenu);

	// remember to reset the pointer in case the user keeps going and calls IupOpen again.
	s_currentIupMainMenu = NULL;
	

	// Let's try not to leave anything behind to avoid accidental leaks in the NSAutoreleasePool drain.
	[NSApp setMainMenu:nil];

}


// Helper to set the menu.
void iupCocoaMenuSetApplicationMenu(Ihandle* ih)
{
	

	
	if(NULL == ih)
	{
		// remove the existing menu?

		// We need a way to know if there was a previous MainMenu set. If so, we need to UnMap that object.
		if(NULL != s_currentIupMainMenu)
		{
			IupUnmap(s_currentIupMainMenu);
			s_currentIupMainMenu = NULL;
		}
		
		[NSApp setMainMenu:nil];
		
		// We just removed everything in the menu. We want to restore the default menu.
		cocoaCreateDefaultApplicationMenu();

	}
	else
	{
		// add the menu
		
		// identify this is a app menu
		IupSetInt(ih, "_IUPMAC_APPMENU", 1);
		
		// User error?
		if(ih->iclass->nativetype != IUP_TYPEMENU)
		{
			// call IUPASSERT?
			return;
		}
		
		// We need a way to know if there was a previous MainMenu set. If so, we need to UnMap that object.
		if(NULL != s_currentIupMainMenu)
		{
			// check if the user has already set this menu before and is the current menu
			if(ih->handle == s_currentIupMainMenu)
			{
				// we don't need to do anything since this is the same menu
				return;
			}
			else
			{
				// this is a different menu so we want to remove the old one
				IupUnmap(s_currentIupMainMenu);
				s_currentIupMainMenu = NULL;
			}
		}
		
		
		// I don't think it is possible to have an already Mapped menu, but just in case, I'll check. (Maybe this should be an assert)
		if(ih->handle)
		{
			// don't call Map since it already is created
		}
		else
		{
			IupMap(ih);
		}
		[NSApp setMainMenu:(NSMenu*)ih->handle];
		s_currentIupMainMenu = ih;
	}
	
	

	
#if 0
	if (!ih->handle)
	{
		Ihandle* menu = IupGetHandle(value);
		ih->data->menu = menu;
		return 1;
	}
	
	if (!value)
	{
		if (ih->data->menu && ih->data->menu->handle)
		{
			ih->data->ignore_resize = 1;
			IupUnmap(ih->data->menu);  /* this will remove the menu from the dialog */
			ih->data->ignore_resize = 0;
			
			ih->data->menu = NULL;
		}
	}
	else
	{
		Ihandle* menu = IupGetHandle(value);
		if (!menu || menu->iclass->nativetype != IUP_TYPEMENU || menu->parent)
			return 0;
		
		/* already the current menu and it is mapped */
		if (ih->data->menu && ih->data->menu==menu && menu->handle)
			return 1;
		
		/* the current menu is mapped, so unmap it */
		if (ih->data->menu && ih->data->menu->handle && ih->data->menu!=menu)
		{
			ih->data->ignore_resize = 1;
			IupUnmap(ih->data->menu);   /* this will remove the menu from the dialog */
			ih->data->ignore_resize = 0;
		}
		
		ih->data->menu = menu;
		
		menu->parent = ih;    /* use this to create a menu bar instead of a popup menu */
		
		ih->data->ignore_resize = 1;
		IupMap(menu);     /* this will automatically add the menu to the dialog */
		ih->data->ignore_resize = 0;
	}
	return 1;
	
#endif
	
}



static int cocoaMenuMapMethod(Ihandle* ih)
{
	/* A dialog's MENU and the Mac-only application menu are the same thing here: macOS has one
	   application-wide menu bar, not a bar per window. This branch used to return IUP_ERROR for
	   the IupDialog case with the real code disabled behind `#if 0`, so IupSetAttribute(dlg,
	   "MENU", ...) -- the portable way every IUP application builds a menu -- silently did
	   nothing at all and the app was left with only the default menu bar. The submenus below
	   merge into the existing bar by title, which is what keeps the standard application, Edit
	   and Window menus intact. */
	if(iupMenuIsMenuBar(ih) || iupCocoaMenuIsApplicationBar(ih))
	{
		NSMenu* main_menu = [NSApp mainMenu];

		/* IupOpen installs a default bar (application, File, Edit, Format, View, Window, Help) so
		   that an application with no menu still behaves like a Mac application. Once the
		   application supplies its own menu bar, those placeholders must go: otherwise its menus
		   simply appear alongside them and the user sees both a stock File menu and their own.
		   Index 0 is kept because macOS requires an application menu -- the one carrying About,
		   Services, Hide and Quit -- and IUP has no way to express it. */
		if([main_menu numberOfItems] > 1)
		{
			/* AppKit holds separate references to these; drop them before the menus go away.
			   The Services menu lives inside the application menu, which survives, so it is left
			   alone. */
			[NSApp setWindowsMenu:nil];
			if([NSApp respondsToSelector:@selector(setHelpMenu:)])
			{
				[NSApp setHelpMenu:nil];
			}
			while([main_menu numberOfItems] > 1)
			{
				[main_menu removeItemAtIndex:1];
			}
		}

		ih->handle = main_menu;

		// not sure if I should retain it because I don't know if this is going to ever get released, but probably should to obey normal patterns.
		[main_menu retain];
		


	}
	else
	{
		if(ih->parent)
		{

//			NSLog(@"cocoaMenuMapMethod ih->parent %@", ih->parent->handle);
		/* parent is a submenu, it is created here */


			NSMenuItem* parent_menu = (NSMenuItem*)(ih->parent->handle);
			NSString* parent_menu_title = [parent_menu title];
			
			NSMenu* the_menu = [parent_menu submenu];

			// Try searching for an existing menu by this name and only create is not there.
			if(nil == [parent_menu submenu])
			{
				the_menu = [[NSMenu alloc] init];
				ih->handle = the_menu;
				
				[parent_menu setSubmenu:the_menu];
				// In Cocoa, the name (e.g. "Edit") goes on the NSMenu, not the above NSMenuItem.
				// I earlier set the name on the parent (which isn't visible), and now set it on the correct widget.
				// Not sure if I should unset the title on the NSMenuItem afterwards.
				[the_menu setTitle:parent_menu_title];
//				NSLog(@"cocoaMenuMapMethod created NSMenu %@", the_menu);
			}
			else
			{
				// Already exists. Let's try reusing the existing one.
				[the_menu retain];
				ih->handle = the_menu;
				
//				NSLog(@"cocoaMenuMapMethod reused NSMenu %@", the_menu);

			}
			
			

//			NSLog(@"cocoaMenuMapMethod [parent_menu setSubmenu:the_menu]");
		}
		else
		{
			/* top level menu used for IupPopup */

			NSMenu* the_menu = [[NSMenu alloc] init];
			ih->handle = the_menu;

//			NSLog(@"else cocoaMenuMapMethod created NSMenu %@", the_menu);

			
			//iupAttribSet(ih, "_IUPWIN_POPUP_MENU", "1");
		}
	}

	
	

	
	return IUP_NOERROR;
}

static void cocoaMenuUnMapMethod(Ihandle* ih)
{
	NSMenu* the_menu = (NSMenu*)ih->handle;
	// do I need to remove it from the parent???
	ih->handle = NULL;
	[the_menu release];
}

void iupdrvMenuInitClass(Iclass* ic)
{
	cocoaCreateDefaultApplicationMenu();
	
//	ic->Release = cocoaReleaseMenuClass;

	/* Driver Dependent Class functions */
	ic->Map = cocoaMenuMapMethod;
	ic->UnMap = cocoaMenuUnMapMethod;
	/* menu colour and font are owned by the system appearance on macOS */
	iupClassRegisterAttribute(ic, "BGCOLOR", NULL, NULL, NULL, NULL, IUPAF_NOT_SUPPORTED);
	iupClassRegisterAttribute(ic, "FONT", NULL, NULL, IUPAF_SAMEASSYSTEM, "DEFAULTFONT", IUPAF_NOT_SUPPORTED|IUPAF_NOT_MAPPED);
}





/* Every string in this file is a menu title, and IUP titles may carry a "&" mnemonic marker.
   macOS has no menu mnemonics, so the marker has to be removed or it shows up literally -- real
   applications were displaying "&File" and "F&ormat" in the menu bar. NSMenuItem's
   -setTitleWithMnemonic: also strips it, but it is deprecated and does not exist on NSMenu, so
   both go through IUP's own helper instead. */
static NSString* cocoaMenuTitleString(const char* title)
{
	NSString* ns_string;
	char* stripped_str;

	if(!title)
	{
		return @"";
	}
	stripped_str = iupStrProcessMnemonic(title, NULL, 0);   /* remove & */
	ns_string = iupCocoaStringFromCStr(stripped_str);
	if(stripped_str && (stripped_str != title))
	{
		free(stripped_str);
	}
	return ns_string;
}

/* ---- Menu accelerators ---------------------------------------------------------------------
   An IUP menu title carries its accelerator after a tab: "&Save\tCtrl+S". Windows lets Win32
   right-align that text and gtk just puts it in the label; IUP documents it as decorative and
   expects the application to bind the real shortcut with a K_* callback on the dialog.

   Passing it to -setTitle: on macOS shows a literal tab followed by "Ctrl+S" in the middle of the
   menu. AppKit produces the right-aligned, dimmed shortcut from -setKeyEquivalent: and
   -setKeyEquivalentModifierMask:, so the title is split and the tail translated. */

static void cocoaMenuRightTrim(char* str)
{
	size_t len;
	if(!str)
	{
		return;
	}
	len = strlen(str);
	while((len > 0) && ((str[len-1] == ' ') || (str[len-1] == '\t')))
	{
		str[--len] = 0;
	}
}

/* Named keys that have a macOS key-equivalent character. Anything absent from here has none and
   makes the whole accelerator unparseable, which is what we want -- an accelerator we cannot
   express should render nothing rather than something misleading. */
static NSString* cocoaMenuNamedKeyEquivalent(const char* key_name)
{
	static const struct { const char* name; unichar code; } k_named_keys[] = {
		/* Del is the FORWARD delete, matching iupmac_key.m where kVK_ForwardDelete is K_DEL and
		   kVK_Delete is K_BS -- otherwise a menu item and a K_DEL callback in the same
		   application would answer to different physical keys. */
		{ "Del",       NSDeleteFunctionKey },
		{ "Delete",    NSDeleteFunctionKey },
		{ "BS",        NSBackspaceCharacter },
		{ "Backspace", NSBackspaceCharacter },
		/* Return, not the keypad Enter (NSEnterCharacter, 0x03) */
		{ "Enter",     NSCarriageReturnCharacter },
		{ "Return",    NSCarriageReturnCharacter },
		{ "CR",        NSCarriageReturnCharacter },
		{ "Esc",       0x001B },
		{ "Escape",    0x001B },
		{ "Tab",       NSTabCharacter },
		{ "Space",     0x0020 },
		{ "SP",        0x0020 },
		{ "Up",        NSUpArrowFunctionKey },
		{ "Down",      NSDownArrowFunctionKey },
		{ "Left",      NSLeftArrowFunctionKey },
		{ "Right",     NSRightArrowFunctionKey },
		{ "Home",      NSHomeFunctionKey },
		{ "End",       NSEndFunctionKey },
		{ "PgUp",      NSPageUpFunctionKey },
		{ "PgDn",      NSPageDownFunctionKey },
	};
	size_t i;

	/* F1 .. F12 are contiguous from NSF1FunctionKey */
	if(((key_name[0] == 'F') || (key_name[0] == 'f')) && isdigit((unsigned char)key_name[1]))
	{
		int function_number = atoi(key_name + 1);
		const char* digits = key_name + 1;
		while(isdigit((unsigned char)*digits)) { digits++; }
		if((*digits == 0) && (function_number >= 1) && (function_number <= 12))
		{
			return [NSString stringWithFormat:@"%C", (unichar)(NSF1FunctionKey + function_number - 1)];
		}
	}

	for(i = 0; i < sizeof(k_named_keys)/sizeof(k_named_keys[0]); i++)
	{
		if(0 == strcasecmp(key_name, k_named_keys[i].name))
		{
			return [NSString stringWithFormat:@"%C", k_named_keys[i].code];
		}
	}
	return nil;
}

/* Returns NO, writing neither output, when the text cannot be expressed as a macOS shortcut. */
static BOOL cocoaMenuParseAccelerator(const char* accel_text, NSString** out_key_equivalent,
	NSEventModifierFlags* out_modifier_mask)
{
	static const struct { const char* name; NSEventModifierFlags flag; } k_modifiers[] = {
		{ "Control", NSEventModifierFlagControl }, { "Ctrl", NSEventModifierFlagControl },
		{ "Shift",   NSEventModifierFlagShift },
		{ "Option",  NSEventModifierFlagOption },  { "Alt",  NSEventModifierFlagOption },
		{ "Command", NSEventModifierFlagCommand }, { "Cmd",  NSEventModifierFlagCommand },
	};
	NSEventModifierFlags modifier_mask = 0;
	NSString* key_equivalent = nil;
	const char* scan;
	char key_token[64];
	size_t token_length;

	if(!accel_text)
	{
		return NO;
	}
	scan = accel_text;
	while(' ' == *scan) { scan++; }

	/* Consume modifier prefixes left to right; whatever is left is the key. Splitting on '+'
	   instead would break "Ctrl++" and "Ctrl+-", where the key IS the separator character. */
	for(;;)
	{
		size_t i;
		BOOL matched_one = NO;

		for(i = 0; i < sizeof(k_modifiers)/sizeof(k_modifiers[0]); i++)
		{
			size_t name_length = strlen(k_modifiers[i].name);
			const char* after;

			if(0 != strncasecmp(scan, k_modifiers[i].name, name_length))
			{
				continue;
			}
			after = scan + name_length;

			/* "Ctrl_Num +" is the keypad spelling. The qualifier is dropped rather than turned
			   into NSEventModifierFlagNumericPad: most Mac keyboards have no keypad, so the
			   shortcut would be unpressable, and the application that uses this spelling binds
			   plain Ctrl-plus (K_c+) for the real shortcut anyway. */
			if(0 == strncasecmp(after, "_Num", 4))
			{
				after += 4;
				while(' ' == *after) { after++; }
			}
			else if(('+' == *after) || ('-' == *after))
			{
				after++;
				while(' ' == *after) { after++; }
			}
			else
			{
				continue;   /* name matched but no separator: this is the key, not a modifier */
			}

			modifier_mask |= k_modifiers[i].flag;
			scan = after;
			matched_one = YES;
			break;
		}
		if(!matched_one)
		{
			break;
		}
	}

	token_length = strlen(scan);
	if((0 == token_length) || (token_length >= sizeof(key_token)))
	{
		return NO;
	}
	strcpy(key_token, scan);
	cocoaMenuRightTrim(key_token);
	token_length = strlen(key_token);
	if(0 == token_length)
	{
		return NO;
	}

	/* Quoted form "Ctrl+'+'" -- must be tried before the single-character rule. */
	if((3 == token_length) && ('\'' == key_token[0]) && ('\'' == key_token[2]))
	{
		key_equivalent = [NSString stringWithFormat:@"%c", key_token[1]];
	}
	else if(1 == token_length)
	{
		/* Lower case for letters: AppKit takes an upper-case equivalent to imply Shift, and we
		   express Shift with the modifier mask instead so that one rule covers letters,
		   punctuation and function keys alike. */
		key_equivalent = [NSString stringWithFormat:@"%c", tolower((unsigned char)key_token[0])];
	}
	else
	{
		key_equivalent = cocoaMenuNamedKeyEquivalent(key_token);
	}

	if(nil == key_equivalent)
	{
		return NO;
	}

	/* An equivalent with no modifiers is dispatched on the bare keystroke, application-wide and
	   ahead of the responder chain -- a bare Del, Enter, Esc or arrow in the menu bar would stop
	   text fields from working. Function keys carry no such duty, so they are the exception. */
	if(0 == modifier_mask)
	{
		unichar first_char = [key_equivalent characterAtIndex:0];
		if((first_char < NSF1FunctionKey) || (first_char > NSF1FunctionKey + 11))
		{
			return NO;
		}
	}

	*out_key_equivalent = key_equivalent;
	*out_modifier_mask = modifier_mask;
	return YES;
}

/* The label is everything before the tab. Shared by the map method's reuse-by-title search so
   both sides of that comparison agree. Caller must free the result. */
static char* cocoaMenuSplitTitle(const char* raw_title, const char** out_accel_text)
{
	const char* scan = raw_title;
	char* label;

	*out_accel_text = NULL;
	if(!raw_title)
	{
		return NULL;
	}
	label = iupStrDupUntil(&scan, '\t');
	if(!label)
	{
		return iupStrDup(raw_title);   /* no tab: the whole thing is the label */
	}
	*out_accel_text = scan;
	return label;
}

static NSString* cocoaMenuItemLabelString(const char* raw_title)
{
	const char* accel_text = NULL;
	char* label = cocoaMenuSplitTitle(raw_title, &accel_text);
	NSString* ns_string;

	if(!label)
	{
		return @"";
	}
	cocoaMenuRightTrim(label);   /* "Item with Image \tCtrl+M" leaves a trailing space */
	ns_string = cocoaMenuTitleString(label);
	free(label);
	return ns_string;
}

static void cocoaMenuItemApplyTitle(Ihandle* ih, NSMenuItem* menu_item, const char* raw_title)
{
	const char* accel_text = NULL;
	char* label;
	NSString* key_equivalent = nil;
	NSEventModifierFlags modifier_mask = 0;

	if(nil == menu_item)
	{
		return;
	}

	label = cocoaMenuSplitTitle(raw_title, &accel_text);
	if(label)
	{
		cocoaMenuRightTrim(label);
		[menu_item setTitle:cocoaMenuTitleString(label)];
		free(label);
	}
	else
	{
		[menu_item setTitle:@""];
	}

	if(accel_text && cocoaMenuParseAccelerator(accel_text, &key_equivalent, &modifier_mask)
		&& IupGetCallback(ih, "ACTION"))
	{
		/* Guarded on ACTION deliberately. NSMenu key equivalents are dispatched in
		   -performKeyEquivalent: BEFORE the responder chain, so an item claiming a shortcut
		   consumes that keystroke and the dialog's K_ANY path never sees it. For an item with no
		   ACTION the command usually lives in the dialog's own K_* callback, and installing an
		   equivalent would swallow the key and break it outright. */
		[menu_item setKeyEquivalent:key_equivalent];
		[menu_item setKeyEquivalentModifierMask:modifier_mask];
		iupAttribSet(ih, "_IUPCOCOA_MENUACCEL", "1");
	}
	else if(iupAttribGet(ih, "_IUPCOCOA_MENUACCEL"))
	{
		/* Clear only an equivalent we installed ourselves. An IupItem can adopt a pre-existing
		   NSMenuItem by title (see the search in cocoaItemMapMethod), and clearing
		   unconditionally would strip the shortcut off a standard item such as Edit > Copy. */
		[menu_item setKeyEquivalent:@""];
		[menu_item setKeyEquivalentModifierMask:0];
		iupAttribSet(ih, "_IUPCOCOA_MENUACCEL", NULL);
	}
}


static int cocoaItemSetTitleAttrib(Ihandle* ih, const char* value)
{
	/* The old body also scanned the title for "&" and installed the following character as a key
	   equivalent. That looked dead -- cocoaMenuTitleString strips mnemonics first -- but
	   iupStrProcessMnemonic turns "&&" into a literal "&", so for a title such as
	   "Item && Acc\tCtrl+A" it found that ampersand, took the next character (a space) and gave
	   the item a spurious Command-Space shortcut. */
	cocoaMenuItemApplyTitle(ih, (NSMenuItem*)ih->handle, value);
	return 1;
}

/*
 // Drat: These don't work because I have to also disable autoenablesItems in the NSMenu's.
 // But that will also disable a lot of items we might like automatic behavior for.

 [menu_item setAutoenablesItems:NO];	}
char* cocoaItemGetActiveAttrib(Ihandle *ih)
{
	NSMenuItem* menu_item = (NSMenuItem*)ih->handle;
	BOOL is_enabled = [menu_item isEnabled];
	return iupStrReturnBoolean(is_enabled);
}

static int cocoaItemSetActiveAttrib(Ihandle* ih, const char* value)
{
	BOOL is_enabled = (BOOL)iupStrBoolean(value);
	NSMenuItem* menu_item = (NSMenuItem*)ih->handle;
	[menu_item setEnabled:is_enabled];
	return 1;
}
*/

static NSMenuItem* cocoaMenuGetNativeItem(Ihandle* ih)
{
	id handle = (id)ih->handle;
	if([handle isKindOfClass:[NSMenuItem class]])
	{
		return (NSMenuItem*)handle;
	}
	/* A submenu's handle is the NSMenu it owns; the state an application sets -- enabled, image --
	   belongs to the NSMenuItem that presents it in the parent menu. */
	if([handle isKindOfClass:[NSMenu class]])
	{
		NSMenu* the_menu = (NSMenu*)handle;
		NSMenu* parent_menu = [the_menu supermenu] ? [the_menu supermenu] : [NSApp mainMenu];
		for(NSMenuItem* menu_item in [parent_menu itemArray])
		{
			if([menu_item submenu] == the_menu)
			{
				return menu_item;
			}
		}
	}
	return nil;
}

static int cocoaItemSetValueAttrib(Ihandle* ih, const char* value)
{
	NSMenuItem* menu_item = cocoaMenuGetNativeItem(ih);
	if(nil == menu_item)
	{
		return 0;
	}
	[menu_item setState:iupStrBoolean(value) ? NSOnState : NSOffState];
	return 0;
}

static char* cocoaItemGetValueAttrib(Ihandle* ih)
{
	NSMenuItem* menu_item = cocoaMenuGetNativeItem(ih);
	if(nil == menu_item)
	{
		return NULL;
	}
	return iupStrReturnChecked((int)[menu_item state]);
}

/* HIDEMARK asks for a checkable item that never draws its mark. NSMenuItem has no such flag, but
   clearing the on/mixed state images achieves it without disturbing the state itself. */
static int cocoaItemSetHideMarkAttrib(Ihandle* ih, const char* value)
{
	NSMenuItem* menu_item = cocoaMenuGetNativeItem(ih);
	if(nil == menu_item)
	{
		return 1;
	}
	if(iupStrBoolean(value))
	{
		[menu_item setOnStateImage:nil];
		[menu_item setMixedStateImage:nil];
	}
	else
	{
		[menu_item setOnStateImage:[NSImage imageNamed:@"NSMenuOnStateTemplate"]];
		[menu_item setMixedStateImage:[NSImage imageNamed:@"NSMenuMixedStateTemplate"]];
	}
	return 1;
}

static int cocoaMenuItemSetImageAttrib(Ihandle* ih, const char* value)
{
	NSMenuItem* menu_item = cocoaMenuGetNativeItem(ih);
	if(nil == menu_item)
	{
		return 1;
	}
	[menu_item setImage:value ? (NSImage*)iupImageGetImage(value, ih, 0, NULL) : nil];
	return 1;
}

static int cocoaMenuItemSetActiveAttrib(Ihandle* ih, const char* value)
{
	NSMenuItem* menu_item = cocoaMenuGetNativeItem(ih);
	if(nil != menu_item)
	{
		/* A menu whose items have targets re-enables them automatically unless this is off. */
		[[menu_item menu] setAutoenablesItems:NO];
		[menu_item setEnabled:iupStrBoolean(value) ? YES : NO];
	}
	return iupBaseSetActiveAttrib(ih, value);
}


static int cocoaItemMapMethod(Ihandle* ih)
{

	if(!ih->parent)
	{
		NSLog(@"IUP_ERROR cocoaItemMapMethod !ih->parent");
		return IUP_ERROR;
	}
	
	
	

	
	if (iupMenuIsMenuBar(ih))
	{
		/* top level menu used for MENU attribute in IupDialog (a menu bar) */
		
//		NSLog(@"cocoaItemMapMethod iupMenuIsMenuBar %@", ih->parent->handle);
		
	}
	else
	{
		if(ih->parent)
		{
			/* parent is a submenu, it is created here */
//			NSLog(@"cocoaItemMapMethod ih->parent %@", ih->parent->handle);
			
		}
		else
		{
//			NSLog(@"cocoaItemMapMethod else");
		}
	}
	
	
	
	NSMenu* parent_menu = (NSMenu*)(ih->parent->handle);
	const char* c_title = IupGetAttribute(ih, "TITLE");
	NSString* ns_string = nil;
	NSMenuItem* menu_item = nil;
	if(!c_title)
	{
		ns_string = @"";
	}
	else
	{
		/* label only: item titles no longer carry the accelerator text, so the search has to
		   compare like with like -- and this now also matches nib-provided items, whose titles
		   are plain labels. */
		ns_string = cocoaMenuItemLabelString(c_title);
	}
	// search through parent to see if this item already exists
	for(NSMenuItem* current_menu_item in [parent_menu itemArray])
	{
		if([[current_menu_item title] isEqualToString:ns_string])
		{
			menu_item = current_menu_item;
			break;
		}
	}
	
	if(nil == menu_item)
	{
		// create new item
		menu_item = [[NSMenuItem alloc] init];
		ih->handle = menu_item;
		[parent_menu addItem:menu_item];
		
		// RepresentedObject is to handle the callbacks
		IupCocoaMenuItemRepresentedObject* represented_object = [[IupCocoaMenuItemRepresentedObject alloc] initWithIhandle:ih];
		[menu_item setRepresentedObject:represented_object];
		[represented_object release];
		[menu_item setTarget:represented_object];
		[menu_item setAction:@selector(onMenuItemAction:)];
	}
	else
	{
		ih->handle = menu_item;
		[menu_item retain];

		// For built-in XIB menu items, we may not have setup the represented object stuff, so do that now.
		if([menu_item representedObject] == nil)
		{
			// RepresentedObject is to handle the callbacks
			IupCocoaMenuItemRepresentedObject* represented_object = [[IupCocoaMenuItemRepresentedObject alloc] initWithIhandle:ih];
			[menu_item setRepresentedObject:represented_object];
			[represented_object release];
			[menu_item setTarget:represented_object];
			[menu_item setAction:@selector(onMenuItemAction:)];
		}
		
	}
	
	

	return IUP_NOERROR;
}

static void cocoaItemUnMapMethod(Ihandle* ih)
{
	NSMenuItem* menu_item = (NSMenuItem*)ih->handle;
	// do I need to remove it from the parent???
	ih->handle = NULL;
	[menu_item release];
}


void iupdrvItemInitClass(Iclass* ic)
{
  /* Driver Dependent Class functions */
  ic->Map = cocoaItemMapMethod;
  ic->UnMap = cocoaItemUnMapMethod;

	/* Visual. An NSMenu re-enables its items automatically whenever they have a target, which is
	   why the previous attempt at ACTIVE was abandoned ("Drat: These don't work because I have to
	   also disable autoenablesItems"); the setter turns that off. */
	iupClassRegisterAttribute(ic, "ACTIVE", iupBaseGetActiveAttrib, cocoaMenuItemSetActiveAttrib, IUPAF_SAMEASSYSTEM, "YES", IUPAF_DEFAULT);

	iupClassRegisterAttribute(ic, "TITLE", NULL, cocoaItemSetTitleAttrib, NULL, NULL, IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);

	/* IupItem only */
	iupClassRegisterAttribute(ic, "VALUE", cocoaItemGetValueAttrib, cocoaItemSetValueAttrib, NULL, NULL, IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
	/* An NSMenuItem has a single image slot, drawn to the left of the title -- which is what
	   TITLEIMAGE describes -- so IMAGE and TITLEIMAGE both target it. */
	iupClassRegisterAttribute(ic, "IMAGE", NULL, cocoaMenuItemSetImageAttrib, NULL, NULL, IUPAF_IHANDLENAME|IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
	iupClassRegisterAttribute(ic, "TITLEIMAGE", NULL, cocoaMenuItemSetImageAttrib, NULL, NULL, IUPAF_IHANDLENAME|IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
	iupClassRegisterAttribute(ic, "HIDEMARK", NULL, cocoaItemSetHideMarkAttrib, NULL, NULL, IUPAF_NOT_MAPPED);

	/* Not supported: a pressed-state image has no NSMenuItem equivalent, and menu colour and font
	   are owned by the system appearance on macOS. Registered so they are known attributes. */
	iupClassRegisterAttribute(ic, "IMPRESS", NULL, NULL, NULL, NULL, IUPAF_NOT_SUPPORTED|IUPAF_NO_INHERIT);
	iupClassRegisterAttribute(ic, "BGCOLOR", NULL, NULL, NULL, NULL, IUPAF_NOT_SUPPORTED);
	iupClassRegisterAttribute(ic, "FONT", NULL, NULL, IUPAF_SAMEASSYSTEM, "DEFAULTFONT", IUPAF_NOT_SUPPORTED|IUPAF_NOT_MAPPED);
}


static int cocoaSubmenuSetTitleAttrib(Ihandle* ih, const char* value)
{
	//	char *str;
	
	/* check if the submenu handle was created in winSubmenuAddToParent */
	/*
	 if (ih->handle == (InativeHandle*)-1)
		return 1;
	 */
	
#if 0
	NSMenu* the_menu = (NSMenu*)ih->handle;
	
	NSString* ns_string = nil;
	if(!value)
	{
		ns_string = @"";
	}
	else
	{
		ns_string = cocoaMenuTitleString(value);
		
	}
	
	[the_menu setTitle:ns_string];
#else

	
	
	NSMenuItem* menu_item = (NSMenuItem*)ih->handle;
	
	
	NSString* ns_string = nil;
	if(!value)
	{
		ns_string = @"";
	}
	else
	{
		ns_string = cocoaMenuTitleString(value);
		
	}
	
	[menu_item setTitle:ns_string];
#endif
	
	return 1;
}


static int cocoaSubmenuMapMethod(Ihandle* ih)
{
	if(!ih->parent)
	{
		NSLog(@"IUP_ERROR cocoaSubmenuMapMethod !ih->parent");
		return IUP_ERROR;
	}
	
	
	if (iupMenuIsMenuBar(ih->parent))
	{
		/* top level menu used for MENU attribute in IupDialog (a menu bar) */
		
//		NSLog(@"cocoaSubmenuMapMethod iupMenuIsMenuBar %@", ih->parent->handle);
		
	}
	else
	{
		if(ih->parent)
		{
			/* parent is a submenu, it is created here */
//			NSLog(@"cocoaSubmenuMapMethod ih->parent %@", ih->parent->handle);
			
		}
		else
		{
//			NSLog(@"cocoaSubmenuMapMethod else");
		}
	}
	
	
	
	
	NSObject* parent_object = (NSObject*)ih->parent->handle;
	if([parent_object isKindOfClass:[NSMenuItem class]])
	{
		/* parent is a submenu, it is created here */
		NSMenu* the_menu = [[NSMenu alloc] init];
		ih->handle = the_menu;
		
		NSMenuItem* parent_menu = (NSMenuItem*)(ih->parent->handle);
		[parent_menu setSubmenu:the_menu];
		
/*
		NSLog(@"cocoaSubmenuMapMethod iupMenuIsMenuBar %@", ih->parent->handle);
		NSLog(@"cocoaSubmenuMapMethod created NSMenu %@", the_menu);
		NSLog(@"[parent_menu setSubmenu:the_menu]");
*/
		
		
	}
	else if([parent_object isKindOfClass:[NSMenu class]])
	{
		

		
#if 0
		NSMenu* the_menu = [[NSMenu alloc] init];
		ih->handle = the_menu;
		
			NSMenu* parent_menu = (NSMenu*)(ih->parent->handle);
			NSMenuItem* replacement_parent_menu_item = [[NSMenuItem alloc] initWithTitle:[parent_menu title] action:nil keyEquivalent:@""];
			[parent_menu release];
			ih->parent->handle = replacement_parent_menu_item;
#else
		
		NSMenu* parent_menu = (NSMenu*)(ih->parent->handle);
		NSArray* list_of_menu_items = [parent_menu itemArray];
//		NSInteger number_of_items = [parent_menu numberOfItems];
		NSMenuItem* found_menu_item = nil;
		
		const char* c_title = IupGetAttribute(ih, "TITLE");
		NSString* ns_string = nil;
		if(!c_title)
		{
			ns_string = @"";
		}
		else
		{
			ns_string = cocoaMenuTitleString(c_title);
			
		}
		
		for(NSMenuItem* menu_item in list_of_menu_items)
		{
			NSString* menu_item_title = [menu_item title];
			if([menu_item_title isEqualToString:ns_string])
			{
				found_menu_item = menu_item;
				break;
			}
		}
		
		if(found_menu_item)
		{
//			NSLog(@"found menu item for Submenu");
			ih->handle = found_menu_item;
			[found_menu_item retain];
			
		}
		else
		{
			//		NSMenuItem* menu_item_for_submenu = [[NSMenuItem alloc] initWithTitle:[parent_menu title] action:nil keyEquivalent:@""];
//			NSMenuItem* menu_item_for_submenu = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(onMenuItemAction:) keyEquivalent:@""];
			NSMenuItem* menu_item_for_submenu = [[NSMenuItem alloc] init];
			
			
			/* 
			Okay, now we're going to get tricky.
			Cocoa has strong conventions about what should be in the menu and where.
			Currently I'm operating on the assumption that we are going to pre-populate a default menu for IUP and the user is going to add (and maybe remove) items.
			So we need to search through the existing menu and determine where things go.
			Current assumption: All normal menu categories are already in the menu. So if the user adds a new one, we must put it in the right place.
			The Apple Human User Interface Guidelines (HIG) state that new menu entries appear between the View and Window items.
			View is also sometimes optional, so for robustness, we should scan for Window and insert right before Window. 
			(This also handles the case where user entries have already been added since we will add after those entries which is expected behavior.)
			*/
			NSInteger index_to_insert_at = -1; // start at -1 because we are 1 slot before our stopping marker
			BOOL found_window_slot = NO;
			for(NSMenuItem* current_menu_item in [parent_menu itemArray])
			{
//				NSLog(@"current_menu_item.title %@", [current_menu_item title]);
				index_to_insert_at = index_to_insert_at + 1;
				if(([[current_menu_item title] isEqualToString:NSLocalizedString(@"Window", @"Window")]) || ([[current_menu_item title] isEqualToString:@"Window"]))
				{
					found_window_slot = YES;
					break;
				}
			}
			
			if(found_window_slot)
			{
				[parent_menu insertItem:menu_item_for_submenu atIndex:index_to_insert_at];
			}
			else
			{
				NSLog(@"Warning: Did not find Window menu to insert category in");
				[parent_menu addItem:menu_item_for_submenu];
			}
			
			ih->handle = menu_item_for_submenu;
//			[menu_item_for_submenu setTitle:ns_string];
			[menu_item_for_submenu setTitle:ns_string];

			/*
			// RepresentedObject is to handle the callbacks
			IupCocoaMenuItemRepresentedObject* represented_object = [[IupCocoaMenuItemRepresentedObject alloc] initWithIhandle:ih];
			[menu_item_for_submenu setRepresentedObject:represented_object];
			[represented_object release];
			[menu_item_for_submenu setTarget:represented_object];
			[menu_item setAction:@selector(onMenuItemAction:)];
*/

/*
			NSLog(@"cocoaSubmenuMapMethod parent_menu %@", parent_menu);
			NSLog(@"cocoaSubmenuMapMethod replacement_parent_menu_item %@", menu_item_for_submenu);
			NSLog(@"[parent_menu setSubmenu:the_menu]");
*/
		
		}
		//[replacement_parent_menu_item setSubmenu:the_menu];
		
		
#endif
		
		
		
//		NSLog(@"NSMenu swap");
		//NSCAssert(0==1, @"NSMenu");
		
		
//		return iupBaseTypeVoidMapMethod(ih);

		
		return IUP_NOERROR;
	}
	else
	{
		NSLog(@"What menu thing is this?");
		NSCAssert(0==1, @"What is this?");
		return IUP_ERROR;

	}

	
	return IUP_NOERROR;
}

static void cocoaSubmenuUnMapMethod(Ihandle* ih)
{
	NSMenuItem* menu_item = (NSMenuItem*)ih->handle;
	// do I need to remove it from the parent???
	ih->handle = NULL;
	[menu_item release];
}



void iupdrvSubmenuInitClass(Iclass* ic)
{
  /* Driver Dependent Class functions */
  ic->Map = cocoaSubmenuMapMethod;
  ic->UnMap = cocoaSubmenuUnMapMethod;

	/* Visual */
	iupClassRegisterAttribute(ic, "ACTIVE", iupBaseGetActiveAttrib, cocoaMenuItemSetActiveAttrib, IUPAF_SAMEASSYSTEM, "YES", IUPAF_DEFAULT);

	iupClassRegisterAttribute(ic, "TITLE", NULL, cocoaSubmenuSetTitleAttrib, NULL, NULL, IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);

	/* IupSubmenu only */
	iupClassRegisterAttribute(ic, "IMAGE", NULL, cocoaMenuItemSetImageAttrib, NULL, NULL, IUPAF_IHANDLENAME|IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);

	/* menu colour and font are owned by the system appearance on macOS */
	iupClassRegisterAttribute(ic, "BGCOLOR", NULL, NULL, NULL, NULL, IUPAF_NOT_SUPPORTED);
	iupClassRegisterAttribute(ic, "FONT", NULL, NULL, IUPAF_SAMEASSYSTEM, "DEFAULTFONT", IUPAF_NOT_SUPPORTED|IUPAF_NOT_MAPPED);
}


static int cocoaSeparatorMapMethod(Ihandle* ih)
{
	NSMenu* parent_menu = (NSMenu*)(ih->parent->handle);

	// create new item
	NSMenuItem* menu_item = [NSMenuItem separatorItem];
	[menu_item retain];
	ih->handle = menu_item;
	[parent_menu addItem:menu_item];
	
	return IUP_NOERROR;
}

static void cocoaSeparatorUnMapMethod(Ihandle* ih)
{
	NSMenuItem* menu_item = (NSMenuItem*)ih->handle;
	// do I need to remove it from the parent???
	ih->handle = NULL;
	[menu_item release];
}

void iupdrvSeparatorInitClass(Iclass* ic)
{
#if 1
  /* Driver Dependent Class functions */
  ic->Map = cocoaSeparatorMapMethod;
  ic->UnMap = cocoaSeparatorUnMapMethod;
#endif
	
}
