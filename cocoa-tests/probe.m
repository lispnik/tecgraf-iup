/* probe.dylib - injected via DYLD_INSERT_LIBRARIES to verify any Cocoa app without touching it.
 *
 * Checks, all without user input or special permissions:
 *   launched   - process got as far as running our constructor
 *   runloop    - the main run loop is alive (timer fires)
 *   window     - a visible window of reasonable size exists
 *   events     - [NSApp currentEvent] became non-nil  <-- catches the IupFlush wedge exactly
 *   exception  - no uncaught ObjC exception
 *
 * Writes one line of RESULT= key/value pairs to $PROBE_LOG, then exits so nothing is left running.
 */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <stdlib.h>
#include <execinfo.h>
#include <signal.h>

static FILE* g_log;
static int   g_ticks;
static long  g_events;
static int   g_sawEvent;
static int   g_sawWindow;
static char  g_exception[512];
static double g_seconds;
static int    g_background;
static NSMutableSet* g_hidden;   /* windows this probe made transparent in background mode */

static BOOL probe_window_is_visible(NSWindow* w)
{
    if ([w isVisible]) return YES;
    return g_hidden && [g_hidden containsObject:[NSValue valueWithNonretainedObject:w]];
}   /* PROBE_BACKGROUND=1: never steal focus from the user */

static void write_result(const char* verdict)
{
    fprintf(g_log,
        "RESULT app=%s verdict=%s runloop=%s window=%s events=%s eventcount=%ld exception=%s\n",
        [[[NSProcessInfo processInfo] processName] UTF8String],
        verdict,
        g_ticks > 0 ? "ok" : "DEAD",
        g_sawWindow ? "ok" : "NONE",
        g_sawEvent ? "ok" : "NONE",
        g_events,
        g_exception[0] ? g_exception : "none");
    fflush(g_log);
}

static void handler(NSException* e)
{
    snprintf(g_exception, sizeof(g_exception), "%s: %s",
             [[e name] UTF8String], [[e reason] UTF8String]);
    write_result("CRASH");
}

static void crash_bt(int sig)
{
    void* bt[40];
    int n = backtrace(bt, 40);
    fprintf(g_log, "\n*** SIGNAL %d backtrace ***\n", sig);
    fflush(g_log);
    backtrace_symbols_fd(bt, n, fileno(g_log));
    _exit(1);
}

static void dump_view(NSView* v, int d)
{
    fprintf(g_log, "   %*s%s %.0fx%.0f@%.0f,%.0f%s\n", d*2 + 2, "",
        [NSStringFromClass([v class]) UTF8String],
        [v frame].size.width, [v frame].size.height,
        [v frame].origin.x, [v frame].origin.y,
        [v isHidden] ? " HIDDEN" : "");
    if (d < 6) for (NSView* c in [v subviews]) dump_view(c, d + 1);
}

@interface Probe : NSObject
@end

@implementation Probe
- (void) tick:(NSTimer*)t
{
    g_ticks++;

    if (g_background) {
        /* Make the window invisible rather than parking it offscreen: AppKit constrains windows
           to the screen, and a window shoved to (-12000,-12000) gets RESIZED, which desynced the
           real window size from IUP's layout and looked exactly like a layout bug (simple_paint
           reported a 1361-wide canvas inside a 735-wide window). Alpha 0 changes no geometry. */
        for (NSWindow* w in [NSApp windows]) {
            if ([w alphaValue] != 0.0) {
                [w setAlphaValue:0.0];
                [w setIgnoresMouseEvents:YES];
                /* Remember it: a fully transparent window can report isVisible=NO, which made
                   the checks below miss a window this probe had itself hidden (IupPlot). */
                if (!g_hidden) g_hidden = [[NSMutableSet alloc] init];
                [g_hidden addObject:[NSValue valueWithNonretainedObject:w]];
            }
        }
    }

    for (NSWindow* w in [NSApp windows]) {
        if (!probe_window_is_visible(w)) continue;
        /* A tray app (IupDialog backed by NSStatusItem) legitimately has only a small status-bar
           window; judging it by size reported a false failure. */
        BOOL is_status = [NSStringFromClass([w class]) containsString:@"StatusBar"];
        if (is_status) {
            /* Status-bar-only apps never activate and so receive no events until the user clicks
               the item; requiring events would report a false failure. */
            g_sawWindow = 1; g_sawEvent = 1; break;
        }
        /* A legitimate dialog can be tiny -- examples/C/dialog1 is a single "Quit" button at
           53x64 -- so keep this threshold low enough to only reject stray zero-size windows. */
        if ([w frame].size.width > 40 && [w frame].size.height > 30)
            { g_sawWindow = 1; break; }
    }

    if ([NSApp currentEvent]) g_sawEvent = 1;

    /* PROBE_KEYS="7:x,18:1": send synthetic key events (mac virtual keycode : character) straight
       to the key window, exercising the real responder chain without Accessibility permission. */
    {
        const char* keys = getenv("PROBE_KEYS");
        if (keys && g_ticks == 4) {
            NSWindow* win = [NSApp keyWindow];
            if (!win) for (NSWindow* w in [NSApp windows]) if (probe_window_is_visible(w)) { win = w; break; }
            if (win) {
                NSArray* specs = [[NSString stringWithUTF8String:keys] componentsSeparatedByString:@","];
                for (NSString* spec in specs) {
                    NSArray* parts = [spec componentsSeparatedByString:@":"];
                    if ([parts count] != 2) continue;
                    unsigned short kc = (unsigned short)[[parts objectAtIndex:0] intValue];
                    NSString* ch = [parts objectAtIndex:1];
                    for (int down = 1; down >= 0; down--) {
                        NSEvent* e = [NSEvent keyEventWithType:(down ? NSEventTypeKeyDown : NSEventTypeKeyUp)
                            location:NSZeroPoint modifierFlags:0 timestamp:[NSDate timeIntervalSinceReferenceDate]
                            windowNumber:[win windowNumber] context:nil
                            characters:ch charactersIgnoringModifiers:ch isARepeat:NO keyCode:kc];
                        if (e) [win sendEvent:e];
                    }
                    fprintf(g_log, "   sent key %d '%s'\n", (int)kc, [ch UTF8String]);
                }
            } else {
                fprintf(g_log, "   PROBE_KEYS: no window to send to\n");
            }
        }
    }

    if (g_ticks * 0.25 >= g_seconds) {
        /* PROBE_SHOT=<path.png>: render each visible window's content view into a bitmap and write
           it out. Uses -cacheDisplayInRect:, so it needs no Screen Recording permission and works
           even with the window parked offscreen in background mode. */
        /* PROBE_TREE=1: dump the NSView hierarchy of each visible window, which shows layout
           problems that a screenshot cannot (AppKit controls do not render via
           -cacheDisplayInRect:, so they come out blank in a capture). */
        if (getenv("PROBE_TREE")) {
            for (NSWindow* w in [NSApp windows]) {
                if (!probe_window_is_visible(w) || ![w contentView]) continue;
                fprintf(g_log, "   window '%s' %.0fx%.0f\n", [[w title] UTF8String],
                        [[w contentView] bounds].size.width, [[w contentView] bounds].size.height);
                dump_view([w contentView], 0);
            }
        }

        const char* shot = getenv("PROBE_SHOT");
        if (shot) {
            int n = 0;
            for (NSWindow* w in [NSApp windows]) {
                NSView* v = [w contentView];
                if (!probe_window_is_visible(w) || !v) continue;
                NSRect b = [v bounds];
                if (b.size.width < 30 || b.size.height < 30) continue;
                NSBitmapImageRep* rep = [v bitmapImageRepForCachingDisplayInRect:b];
                if (!rep) continue;
                [v cacheDisplayInRect:b toBitmapImageRep:rep];
                NSData* png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                NSString* path = (n == 0) ? [NSString stringWithUTF8String:shot]
                    : [NSString stringWithFormat:@"%@-%d.png",
                        [[NSString stringWithUTF8String:shot] stringByDeletingPathExtension], n];
                [png writeToFile:path atomically:YES];
                fprintf(g_log, "   shot -> %s (%.0fx%.0f)\n", [path UTF8String], b.size.width, b.size.height);
                n++;
            }
        }
        /* window is required; events are required only if a window appeared */
        const char* verdict = (!g_sawWindow)             ? "NOWINDOW"
                            : (!g_sawEvent && !g_background) ? "NOEVENTS"
                                                             : "PASS";
        if (!g_sawWindow) {   /* explain why nothing counted as a window */
            for (NSWindow* w in [NSApp windows]) {
                NSRect f = [w frame];
                fprintf(g_log, "   window '%s' visible=%s %.0fx%.0f@%.0f,%.0f class=%s alpha=%.2f\n",
                        [[w title] UTF8String],
                        [w isVisible] ? "YES" : "no",
                        f.size.width, f.size.height, f.origin.x, f.origin.y,
                        [NSStringFromClass([w class]) UTF8String],
                        [w alphaValue]);
            }
        }
        write_result(verdict);
        exit(0);
    }
}
@end

__attribute__((constructor))
static void probe_init(void)
{
    const char* path = getenv("PROBE_LOG");
    g_log = path ? fopen(path, "a") : stderr;
    if (!g_log) g_log = stderr;
    setvbuf(g_log, NULL, _IOLBF, 0);

    const char* secs = getenv("PROBE_SECONDS");
    g_seconds = secs ? atof(secs) : 4.0;

    NSSetUncaughtExceptionHandler(&handler);
    signal(SIGSEGV, crash_bt);
    signal(SIGBUS,  crash_bt);

    g_background = (getenv("PROBE_BACKGROUND") != NULL);

    /* Install the timer once the main run loop is up. */
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_background) {
            /* Accessory: runs and draws, but never becomes the active app, so it cannot take
               keyboard focus from whatever the user is doing. Windows are parked offscreen so
               they do not flash over the desktop. NOTE: an unactivated app receives no events,
               so the events check is informational in this mode -- run without PROBE_BACKGROUND
               to exercise it (that is what catches an IupFlush-style event wedge). */
            [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        }
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskAny
            handler:^NSEvent*(NSEvent* e) { g_events++; return e; }];
        /* Must be in COMMON modes: many IUP tests open a modal dialog at startup, which runs a
           nested loop in NSModalPanelRunLoopMode where a default-mode timer never fires. */
        NSTimer* t = [NSTimer timerWithTimeInterval:0.25
                      target:[[Probe alloc] init] selector:@selector(tick:)
                      userInfo:nil repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
    });
}
