#!/bin/bash
# Build a directory of IUP sample .c files as .app bundles against the Xcode-built frameworks.
# Bundles matter: a bare executable cannot become the active app on modern macOS, so its window
# never takes key focus. Launch these with `open <name>.app`.
#   usage: build_apps.sh <source-dir> <output-dir-name> [extra-cflags...]
# this script lives in <iup>/cocoa-tests/
IUP=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# IM and CD come from homebrew (tecgraf-im / tecgraf-cd)
BREW=$(brew --prefix 2>/dev/null || echo /opt/homebrew)
SRCDIR="$1"; OUTNAME="$2"; shift 2
FW=$IUP/BUILD-xcode/Release
OUT=$FW/$OUTNAME
LOG=$OUT/_logs
rm -rf "$OUT"; mkdir -p "$OUT" "$LOG"

# -include stdlib.h: several samples use EXIT_SUCCESS without including it.
# The rest silence C89-era constructs modern clang rejects outright.
CFLAGS="-I$IUP/include -I$BREW/include -include stdlib.h \
 -Wno-invalid-source-encoding -Wno-deprecated-declarations \
 -Wno-implicit-function-declaration -Wno-int-conversion $*"
# IupIm (srcim/iup_im.c) is not a target in IUP's CMakeLists, but the IM library it needs is
# installed, and several tutorial samples (simple_paint, example4_*) will not link without it.
# Build it here rather than leaving those samples unbuildable.
IUPIM=$FW/extra/iup_im.o
if [ ! -e "$IUPIM" ] || [ "$IUP/srcim/iup_im.c" -nt "$IUPIM" ]; then
  mkdir -p "$FW/extra"
  clang -c -o "$IUPIM" "$IUP/srcim/iup_im.c" -I"$IUP/include" -I"$IUP/src" \
    -I$BREW/include -Wno-deprecated-declarations -Wno-invalid-source-encoding || exit 1
fi

# IupPlot (srcplot/*.cpp) is not a CMake target either, but it is pure C++ over CD and builds
# cleanly, so build it here rather than leaving the plot samples unbuildable.
IUPPLOT=$FW/extra/plot/libiup_plot.a
if [ ! -e "$IUPPLOT" ]; then
  mkdir -p "$FW/extra/plot"
  for src in "$IUP"/srcplot/*.cpp; do
    n=$(basename "$src" .cpp)
    clang++ -c -std=c++11 -I"$IUP/include" -I"$IUP/src" -I"$IUP/srcplot" -I"$IUP/srccd" \
      -I$BREW/include -Wno-everything -o "$FW/extra/plot/$n.o" "$src" || exit 1
  done
  ar rcs "$IUPPLOT" "$FW"/extra/plot/*.o || exit 1
fi

# CD has no printer driver on macOS -- cdContextPrinter is a Windows/GDI-only symbol, and the
# Quartz build of libcd exports nothing like it. Several tutorial samples reference CD_PRINTER
# unconditionally and so will not link at all. They all guard on cdCreateCanvas returning NULL
# ("if (!print_canvas) return IUP_DEFAULT"), so supplying a context that yields NULL lets the
# samples build and run with every feature except printing, which is genuinely unavailable.
# This stub is linked ONLY into the samples; the IUP library itself is untouched.
CDSTUB=""
if ! nm -gU $BREW/lib/libcd.dylib 2>/dev/null | grep -q " _cdContextPrinter$"; then
  CDSTUB=$FW/extra/sample_link_stubs.o
  if [ ! -e "$CDSTUB" ]; then
    mkdir -p "$FW/extra"
    cat > "$FW/extra/sample_link_stubs.c" <<'STUB'
/* No printer driver in CD on macOS; see build_apps.sh. cdCreateCanvas returns NULL for a NULL
   context, which is what the samples already check for. */
void* cdContextPrinter(void) { return 0; }

/* IupPlot references these three unconditionally, but only reaches them when its graphics_mode
   is IUP_PLOT_OPENGL -- which cannot happen here, because IupGLCanvas has no Cocoa backend at
   all (srcgl/ has only win, x and haiku implementations). IupPlotOpen() does call
   IupGLCanvasOpen() unconditionally, so it has to link; a no-op is correct. */
void IupGLCanvasOpen(void) { }
void IupGLMakeCurrent(void* ih) { (void)ih; }
void IupGLSwapBuffers(void* ih) { (void)ih; }

/* The macOS libcd exports 17 contexts, but not the CGM or PS ones IupPlot offers in its
   export-to-file menu (it does have Picture and SVG). cdCreateCanvas returns NULL for a NULL
   context, which is what the callers check, so those two export formats are simply unavailable. */
void* cdContextCGM(void) { return 0; }
void* cdContextPS(void) { return 0; }
STUB
    clang -c -o "$CDSTUB" "$FW/extra/sample_link_stubs.c" || exit 1
  fi
fi

LDFLAGS="$CDSTUB $IUPIM $IUPPLOT -lc++ -lim -lim_process -F$FW -framework iup -framework iupimglib -framework iupcontrols -framework iupcd -framework iupweb -L$BREW/lib -lcd -Wl,-rpath,$FW"

# A few tests in html/examples/tests call a function defined in a sibling test file without
# declaring it; the symbol is satisfied at link time by compiling the sibling with -DBIG_TEST
# so its own main() is suppressed.
companion() {
  case "$1" in
    flatlist)           echo list ;;
    flatsample)         echo sample ;;
    flattree)           echo tree ;;
    canvas_scrollbar2)  echo canvas_scrollbar ;;
    canvas_scrollbar3)  echo canvas_scrollbar ;;
    dial)               echo dial_led ;;
    webbrowser_editor)  echo rt_editor_images ;;
    *)                  echo "" ;;
  esac
}

ok=0; fail=0
for src in "$SRCDIR"/*.c; do
  [ -e "$src" ] || continue
  name=$(basename "$src" .c)
  app="$OUT/$name.app"; mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$name</string>
<key>CFBundleIdentifier</key><string>br.puc-rio.tecgraf.iup.sample.$name</string>
<key>CFBundleName</key><string>$name</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
  # a few tests compile to nothing unless their own feature macro is defined
  case "$name" in
    plot)    CFLAGS_EXTRA="-DPLOT_TEST" ;;
    mglplot) CFLAGS_EXTRA="-DMGLPLOT_TEST" ;;
    *)       CFLAGS_EXTRA="" ;;
  esac
  comp=$(companion "$name"); extra=""
  if [ -n "$comp" ] && [ -e "$SRCDIR/$comp.c" ]; then
    clang -c -DBIG_TEST $CFLAGS "$SRCDIR/$comp.c" -o "$LOG/$comp.big.o" >> "$LOG/$name.log" 2>&1
    extra="$LOG/$comp.big.o"
  fi
  if clang $CFLAGS $CFLAGS_EXTRA -o "$app/Contents/MacOS/$name" "$src" $extra $LDFLAGS > "$LOG/$name.log" 2>&1; then
    # Samples that load images look for them next to the executable.
    for res in "$SRCDIR"/*.png "$SRCDIR"/*.jpg "$SRCDIR"/*.bmp "$SRCDIR"/*.gif "$SRCDIR"/*.xbm "$SRCDIR"/*.led "$SRCDIR"/*.pts; do
      [ -e "$res" ] && cp "$res" "$app/Contents/MacOS/" 2>/dev/null
    done
    ok=$((ok+1)); echo "$name" >> "$OUT/_ok.txt"
  else
    fail=$((fail+1)); rm -rf "$app"; echo "$name" >> "$OUT/_fail.txt"
  fi
done
echo "built=$ok failed=$fail  -> $OUT"
