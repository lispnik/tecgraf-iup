/** \file
 * \brief String conversion for macOS (Cocoa)
 *
 * See Copyright Notice in "iup.h"
 */

#import <Cocoa/Cocoa.h>

#include <stdlib.h>
#include <string.h>

#include "iup.h"
#include "iup_str.h"
#include "iup_drv.h"


/* Every other driver provides this (iupwin_str.c, iupgtk_str.c, iupmot_str.c); the Cocoa
   driver never did, which is why IupGLControls could not link -- iup_glfont.c declares and
   calls it to hand text to FTGL.

   macOS is natively UTF-8: the Cocoa driver builds every NSString with -UTF8String and IUP's
   UTF8MODE is effectively always on here. So the interesting case is the same one GTK
   handles -- a string that is neither ASCII nor valid UTF-8, which by IUP's convention is
   assumed to be ISO8859-1. */

/* Each driver keeps its own copy of this (it is static in iupwin_str.c and iupgtk_str.c);
   the caller owns the buffer across calls and it grows to fit. */
static char* cocoaCheckUtf8Buffer(char* utf8_buffer, int* utf8_buffer_max, int len)
{
	if(!utf8_buffer)
	{
		utf8_buffer = (char*)malloc((size_t)len + 1);
		*utf8_buffer_max = len;
	}
	else if(*utf8_buffer_max < len)
	{
		utf8_buffer = (char*)realloc(utf8_buffer, (size_t)len + 1);
		*utf8_buffer_max = len;
	}

	return utf8_buffer;
}

static char* cocoaStrCopyToUtf8Buffer(const char* str, int len, char* utf8_buffer, int* utf8_buffer_max)
{
	utf8_buffer = cocoaCheckUtf8Buffer(utf8_buffer, utf8_buffer_max, len);
	memcpy(utf8_buffer, str, len);
	utf8_buffer[len] = 0;
	return utf8_buffer;
}

IUP_SDK_API char* iupStrConvertToUTF8(const char* str, int len, char* utf8_buffer, int* utf8_buffer_max, int utf8mode)
{
	if(utf8mode || iupStrIsAscii(str))  /* already utf8, or ascii which is a subset of it */
	{
		return cocoaStrCopyToUtf8Buffer(str, len, utf8_buffer, utf8_buffer_max);
	}

	@autoreleasepool
	{
		/* If it is valid UTF-8 already, pass it through untouched. */
		NSString* as_utf8 = [[[NSString alloc] initWithBytes:str
		                                             length:(NSUInteger)len
		                                           encoding:NSUTF8StringEncoding] autorelease];
		if(nil != as_utf8)
		{
			return cocoaStrCopyToUtf8Buffer(str, len, utf8_buffer, utf8_buffer_max);
		}

		/* Otherwise assume ISO8859-1, as the GTK and Motif drivers do. */
		NSString* as_latin1 = [[[NSString alloc] initWithBytes:str
		                                               length:(NSUInteger)len
		                                             encoding:NSISOLatin1StringEncoding] autorelease];
		if(nil == as_latin1)
		{
			return cocoaStrCopyToUtf8Buffer(str, len, utf8_buffer, utf8_buffer_max);
		}

		const char* converted = [as_latin1 UTF8String];
		if(NULL == converted)
		{
			return cocoaStrCopyToUtf8Buffer(str, len, utf8_buffer, utf8_buffer_max);
		}

		{
			int converted_len = (int)strlen(converted);
			utf8_buffer = cocoaCheckUtf8Buffer(utf8_buffer, utf8_buffer_max, converted_len);
			memcpy(utf8_buffer, converted, converted_len);
			utf8_buffer[converted_len] = 0;
			return utf8_buffer;
		}
	}
}
