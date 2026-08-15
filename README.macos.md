# IUP on macOS — Cocoa backend

This is a fork of [IUP](https://www.tecgraf.puc-rio.br/iup/) 3.32 (Tecgraf/PUC-Rio, MIT
licensed) working on the **Cocoa backend** in `src/cocoa/`. Upstream's own `README` and the
documentation in `html/` are unchanged.

The backend originated as a port of the GTK driver, and much of it arrived with attribute
registrations and code paths commented out or wrapped in `#if 0` — often still naming GTK
functions that do not exist here, so they could not simply be re-enabled. The work here is
mostly finishing those, driven by what the IUP documentation says each control supports on
every platform.

## Building

Requires Xcode and two Tecgraf libraries from Homebrew:

    brew install tecgraf-cd tecgraf-im

Configure with CMake using the **Xcode generator** — the Ninja/Makefile generators do not
substitute `$(PRODUCT_NAME:rfc1034identifier)` in `Info.plist`, and the resulting bundles
crash on launch:

    cmake -G Xcode -B BUILD-xcode
    xcodebuild -project BUILD-xcode/iup.xcodeproj -target iup -configuration Release build

Frameworks land in `BUILD-xcode/Release/`: `iup`, `iupcd`, `iupcontrols`, `iupimglib`,
`iupweb`, `iupgl`, `iupglcontrols`.

`iupgl` (IupGLCanvas) and `iupglcontrols` (the OpenGL-drawn widget set) had no CMake target
on any platform in this tree; they do now. `iupglcontrols` additionally needs FTGL, which it
uses for text — `brew install ftgl`. Without it that one target is skipped with a message and
everything else still builds.

## Samples

    cocoa-tests/build_apps.sh html/examples/tests    tests-apps
    cocoa-tests/build_apps.sh html/examples/C        examples-apps
    cocoa-tests/build_apps.sh html/examples/tutorial tutorial-apps

Each sample becomes a `.app` bundle. Bundles matter: a bare executable cannot become the
active application on modern macOS, so its window never takes key focus.

The script also builds two libraries IUP's `CMakeLists.txt` does not define as targets but
whose dependencies are present — **IupIm** (`srcim/`) and **IupPlot** (`srcplot/`) — and
links stubs for a few symbols macOS genuinely lacks. See `cocoa-tests/README.md`.

## Stock images

`IupImageLibOpen()` used to be a no-op here: every `__APPLE__` branch in
`srcimglib/iup_image_library.c` was empty, and CMake compiled only the two logo files for
this platform, so `IUP_FileOpen` and friends resolved to nothing. It now loads the **win32
artwork** — those sets are plain `IupImageRGBA` pixel data, whereas the GTK sets mostly
register a `gtk-` stock id for the icon theme to resolve, which has no meaning off GTK.

A handful of legacy names (`IUP_Zoom`, `IUP_FileText`, `IUP_FontBold`, `IUP_FontDialog`,
`IUP_FontItalic`, `IUP_WindowsCascade`, `IUP_WindowsTile`) live inside `#ifdef
IUP_IMGLIB_OLD`, which nothing defines — they are unavailable on every platform, not just
this one. Use `IUP_ZoomIn` / `IUP_ZoomOut` / `IUP_ZoomActualSize` / `IUP_ZoomSelection`.

## Tests

    cocoa-tests/run_gates.sh      # everything below, plus CD's and ImLab's suites
    cocoa-tests/sweep.sh          # launch every built sample, report pass/fail
    cocoa-tests/run_parity.sh     # per-control parity harnesses
    cocoa-tests/run_mglsample.sh  # what the IupMglPlot sample actually renders

`run_mglsample.sh` is the odd one out: it drives the real `mglplot` sample rather than a
purpose-built harness, because the failure it guards — MathGL's geometry being clipped away in
OpenGL mode — only reproduces with the plots the sample builds. Every synthetic stand-in tried
(line, bars, crossed origin, tall canvas, inside tabs) rendered correctly either way.

`run_gates.sh` drives all four repositories, because they are built against each other and a
regression in one shows up as a mystery in another -- a CD driver change as a plot that will not
draw, an IUP change as an ImLab dialog that does nothing. It takes suite names to run just
one (`run_gates.sh cd`), and expects the repositories side by side; `CD` and `IMLAB` in the
environment override where it looks.

Both exit non-zero on failure. `cocoa-tests/README.md` explains why the harnesses assert
against **native** state rather than `IupGetAttribute` — an attribute with no registered
setter round-trips perfectly through the hash table while doing nothing, which is exactly
the failure mode this backend had.

## Known gaps

- **OpenGL is deprecated by Apple.** `IupGLCanvas` is implemented (`srcgl/iup_glcanvas_cocoa.m`,
  an `NSOpenGLContext` attached to the IupCanvas view), but macOS caps OpenGL at 4.1, reports
  itself as `2.1 Metal` in the legacy profile, and warns at build time. A core profile is
  available through `CONTEXTPROFILE=CORE`, but it is strictly core — the fixed-function
  pipeline most IUP samples use is not in it.
- **A GL canvas renders at point resolution, not the display's.** AppKit gives a GL surface the
  window's backing resolution, which on a retina display is twice the view in each direction --
  but `RESIZE_CB`, `DRAWSIZE` and every other size IUP hands out are in points, as they are on
  Windows and GTK. An application doing the ordinary `glViewport(0, 0, w, h)` with the size
  `RESIZE_CB` gave it was therefore drawing into the bottom-left *quarter* of its canvas;
  `glcanvas_cube` and `mathglsamples` both did, and MathGL's plots looked as though they would
  not fill their windows. `srcgl/iup_glcanvas_cocoa.m` now clears
  `wantsBestResolutionOpenGLSurface`, so the surface matches the sizes IUP reports and existing
  code is correct. The cost is that the window server scales GL output up on a retina display.
- **`IupGLUseFont` and `IupGLPalette` do nothing** and set `ERROR`. The first needed
  `aglUseFont`, which Apple removed and never replaced; the second needs index-colour
  visuals, which macOS OpenGL has never had. IupGLControls draws its own text via FTGL and
  is unaffected.
- **`IupText` PADDING has no visual effect on a single-line field.** `NSTextField` has no
  inner-inset API (its cell owns that geometry), so only the natural size grows — which is
  also all GTK does there, since it sets an outer widget margin rather than an inner one.
  Multiline gets a real inset via `-setTextContainerInset:`.
- **CD's "Plus" contexts are not built**, so `cdInitContextPlus` is the one symbol
  `cocoa-tests/build_apps.sh` still stubs; samples that ask for the anti-aliased contexts get
  the plain ones. Printing and export are no longer in this list: **CD_PRINTER** is implemented
  on Quartz (`src/quartz/cdquartzprn.m`, spooling through PDF to `NSPrintOperation`), **PDF** is
  native on CGPDFContext with no PDFlib, and **PS/EPS, CGM, DXF and DGN** were portable drivers
  sitting unbuilt in `src/drv` and are now in the CD build. IupPlot's export menu and its
  Print… item all work.
- **Scintilla is not built**, so the `scintilla` sample does not build. MathGL is built:
  `srcmglplot` vendors the library, and `cocoa-tests/build_apps.sh` compiles it into
  `libiup_mglplot.a`, so `mglplot`, `mathglsamples` and `mgllabel` all run.
- **MathGL's OpenGL canvas needed two corrections, both in `srcmglplot/iup_mglplot.cpp`.** They
  are worth knowing about because both are in MathGL's own design rather than in the backend:
  its `mglCanvasGL` builds a projection out of identity, scale and rotation only, so the clip
  volume keeps OpenGL's default z range of [-1,1] while its model transform maps a plot's z
  onto exactly that range — flat geometry lands *on* the near plane and its own primitives
  reach z=3, so nearly everything was clipped (a bar chart drew nothing; a line plot kept only
  its legend). `iMglPlotWidenGLClipDepth` compresses clip z, and only clip z, before the
  geometry is submitted. Separately, `iMglPlotRepaint` used to skip the render when nothing had
  changed and swap anyway; a swapped back buffer has undefined contents, so that put the frame
  before last — or nothing — on screen, which is what made plots blank and reappear while
  clicking through tabs. In GL mode anything that reaches the screen is now drawn first.
- **Menu accelerators map `Ctrl` to the literal Control key**, not Command. An application
  declaring `Ctrl+A` therefore claims ⌃A application-wide, which is also macOS's standard
  emacs binding for move-to-line-start inside a text field.
- **Mnemonics are stripped, not implemented.** `&` is removed from titles; there is no
  Alt-key activation, which macOS has no convention for.
- **`plot.app`'s canvas is larger than the dialog holding it** — 580x462 inside a 525x378
  window, hanging off the bottom right — so the right of the plot is cut off until the window
  is resized. It is not a consequence of the character-width metric: the canvas measured the
  same 580x462 before and after that changed.

## Layout of the Cocoa work

    src/cocoa/           the backend
    cocoa-tests/         test harness, see its own README
    srcplot/             IupPlot (built by cocoa-tests/build_apps.sh, not by CMake)
    srcim/               IupIm    (likewise)
