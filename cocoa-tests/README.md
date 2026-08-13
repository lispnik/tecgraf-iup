# Cocoa backend test harness

Automated checks for IUP's Cocoa (macOS) backend. There is no unit-test framework in IUP, and the
bundled samples are interactive, so this provides the two things needed to change the backend with
any confidence: a way to build every sample, and a way to assert that a control actually does what
IUP documents.

## Why it asserts against native state

`IupGetAttribute` echoes whatever was stored in the hash table. An attribute with no registered
setter will therefore round-trip perfectly while doing nothing at all — which is exactly the
failure mode this backend was full of, since most controls had their attribute registrations
sitting in `#if 0` blocks copied from the GTK driver.

So the parity harnesses read the **native** state instead: the `NSButton`'s `textColor`, the
`NSBox`'s `fillColor`, the `NSTableView`'s first visible row, the `NSComboBox`'s formatter. Several
checks in here were written the lazy way first, passed, and only failed once they were pointed at
the real control.

When a harness samples pixels out of a capture, compare **which channel leads**, not absolute
levels: the captured rep is colour-managed, so pure red comes back as roughly
`(0.94, 0.29, 0.18)` and pure green as `(0.49, 0.95, 0.31)`. Thresholds like `red > 0.9 &&
green < 0.2`, and even a `red > 2*green` ratio, fail on correct output. Reading pixels out of
an `NSImage`'s own `NSBitmapImageRep` (as `imglib.m` does) preserves exact values; only screen
captures are converted.

A related trap: `-cacheDisplayInRect:` does **not** render `NSTextField`, `NSButton` or
`NSScroller`. Screenshots of those come out blank even when the control is drawing perfectly, so do
not use a capture to prove text or a push button is wrong. Custom-drawn views (`IupCanvas`,
`IupMatrix`, `IupCells`, `IupPlot`) and `NSImageView` do capture correctly.

## Finding what the driver does not actually register

    ./audit_disabled.py          # controls with findings
    ./audit_disabled.py --all    # every paired control

Grepping the driver for `iupClassRegisterAttribute` is misleading in **both** directions,
because this backend arrived with large parts wrapped in `#if 0`. Twice the *only*
registration of an attribute was inside such a block — `IupDialog`'s `BGCOLOR` and
`IupText`'s `TABSIZE`/`PADDING`/`OVERWRITE` — and both looked present to grep. The dialog one
cost real time: a getter added to the line grep found changed nothing, because that line was
the dead copy.

So the script strips `#if 0` regions (honouring nesting) from the Cocoa and GTK drivers and
diffs what survives. It reports three things: registrations that exist *only* inside a dead
block, attributes GTK registers and this driver does not, and attributes registered here with
neither getter nor setter where GTK has a real handler.

It deliberately does **not** report: attributes the shared `iupBaseRegisterCommonAttrib`
already provides (GTK re-registers several, like `FONT`, purely to specialise them);
X11/Windows handle attributes; anything either driver marks `IUPAF_NOT_SUPPORTED`, since that
flag is the documented way to declare a known absence; and the cases listed in `ACKNOWLEDGED`,
which are printed with their reason so the decision stays visible.

Those exclusions matter — without them the first run reported 31 findings, of which more than
half were noise.

## Layout

    probe.m          injected via DYLD_INSERT_LIBRARIES; verifies any sample without modifying it
    audit_disabled.py  diffs live registrations against the GTK driver
    build_apps.sh    builds a directory of sample .c files as .app bundles
    sweep.sh         runs every built sample under the probe and reports pass/fail
    run_parity.sh    builds and runs the per-control parity harnesses
    parity/*.m       one harness per control

## Building the samples

    ./build_apps.sh ../html/examples/tests    tests-apps
    ./build_apps.sh ../html/examples/C        examples-apps
    ./build_apps.sh ../html/examples/tutorial tutorial-apps

Output goes to `BUILD-xcode/Release/<outdir>/`, one `.app` bundle each. Bundles matter: a bare
executable cannot become the active application on modern macOS, so its window never takes key
focus.

The script also builds two libraries that IUP's CMakeLists does not define as targets but whose
dependencies are present — **IupIm** (`srcim/`, needs homebrew `tecgraf-im`) and **IupPlot**
(`srcplot/`) — and links a few stubs for symbols macOS genuinely lacks:

* `cdContextPrinter`, `cdContextCGM`, `cdContextPS` — CD has no printer or CGM/PS driver on macOS.
  Callers already check `cdCreateCanvas` for NULL, so those output formats are simply unavailable.
* `IupGLCanvasOpen`, `IupGLMakeCurrent`, `IupGLSwapBuffers` — **IupGLCanvas has no Cocoa
  implementation at all** (`srcgl/` covers only win, x and haiku). IupPlot references them
  unconditionally but only reaches them in OpenGL graphics mode, which cannot occur here.

A handful of samples compile to nothing unless their own feature macro is defined (`plot.c` wraps
its entire body in `#ifdef PLOT_TEST`); the script defines those. A few others call a function
defined in a sibling sample, which is compiled alongside with `-DBIG_TEST`.

## Running

    ./sweep.sh                # all three sample sets, 8 at a time, about a minute
    ./run_parity.sh           # every parity harness
    ./run_parity.sh btnparity # just one

Both exit non-zero on failure. Samples run as background (accessory) applications with their
windows made fully transparent, so a sweep does not steal focus or cover the desktop.

`sweep.sh` only proves an app launched, stayed alive, created a window and received events. That
catches crashes, hangs and dead event loops — it says nothing about whether the app drew the right
thing.

## probe.m

Injected with `DYLD_INSERT_LIBRARIES`, so it verifies unmodified sample binaries. Environment:

    PROBE_LOG=<path>      where to write results (default stderr)
    PROBE_SECONDS=<n>     how long to observe before reporting (default 4)
    PROBE_BACKGROUND=1    accessory activation policy + transparent windows
    PROBE_SHOT=<path.png> capture each window via -cacheDisplayInRect:
    PROBE_TREE=1          dump the NSView hierarchy with frames
    PROBE_KEYS=7:x,18:1   post synthetic key events (mac virtual keycode : character)

`PROBE_TREE` is usually more informative than `PROBE_SHOT`, precisely because of the AppKit
capture limitation above — a wrong frame shows up in the tree even when the pixels cannot be read.

Two things worth knowing before trusting a result:

* In background mode a window is made fully transparent, and a transparent window can report
  `isVisible == NO`. The probe tracks what it hid so it does not report NOWINDOW for a window it
  hid itself.
* Driving an `NSButton` with synthetic events **deadlocks** unless the mouse-up is posted to the
  queue *before* the mouse-down is dispatched: `-mouseDown:` enters the cell's tracking loop and
  blocks until it can dequeue the release. That loop also pumps the run loop, so it re-enters
  timer callbacks — the harnesses guard their entry point against re-entrancy for this reason.

## Adding a harness for another control

Copy the closest `parity/*.m`, and for each attribute IUP documents for that control assert what
the native object does. Structure is always the same: build a dialog, start a one-shot timer,
inspect `ih->handle`, print `ok`/`GAP` per check and a final `N gap(s)`, then `IupExitLoop`.

Before writing the assertions, read the corresponding `iupdrv<Control>InitClass` in
`src/gtk/` and `src/win/` — that is the parity target — and check the common code in
`src/iup_<control>.c` for what it does itself. Several apparent bugs found while building these
turned out to be the test misreading shared semantics: `PADDING` only affects a list's natural size
when it has an editbox, only an *image* toggle's natural size responds to padding, and `SHOWIMAGE`
is creation-only, so setting it after `IupShow` does nothing on every platform.
