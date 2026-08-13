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
CFLAGS="-I$IUP/include -I$BREW/include -I$IUP/cocoa-tests/glshim -include stdlib.h \
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
  # Rebuild when the stub source changes, not just when the object is missing: a stale object
  # kept exporting no-op IupGLCanvasOpen/MakeCurrent/SwapBuffers after the real iupgl framework
  # existed, and being listed ahead of the frameworks it won the link -- so the glcanvas class
  # was never registered and every GL sample came up as a 0x0 window.
  if [ ! -e "$CDSTUB" ] || [ "$0" -nt "$CDSTUB" ]; then
    mkdir -p "$FW/extra"
    cat > "$FW/extra/sample_link_stubs.c" <<'STUB'
/* No printer driver in CD on macOS; see build_apps.sh. cdCreateCanvas returns NULL for a NULL
   context, which is what the samples already check for. */
void* cdContextPrinter(void) { return 0; }

/* The macOS libcd exports 17 contexts, but not the CGM or PS ones IupPlot offers in its
   export-to-file menu (it does have Picture and SVG). cdCreateCanvas returns NULL for a NULL
   context, which is what the callers check, so those two export formats are simply unavailable. */
void* cdContextCGM(void) { return 0; }
void* cdContextPS(void) { return 0; }

/* cdInitContextPlus enables CD's anti-aliased "Plus" contexts, which the macOS libcd does
   not ship. The samples that call it (canvas1, canvas_scrollbar2/3) only use it to opt into
   nicer rendering, so a no-op leaves them on the regular contexts. */
void cdInitContextPlus(void) { }
STUB
    clang -c -o "$CDSTUB" "$FW/extra/sample_link_stubs.c" || exit 1
  fi
fi

# GL: link the real iupgl framework, and put a GL/gl.h -> OpenGL/gl.h shim on the include
# path, since macOS ships OpenGL as a framework and the samples use the header path every
# other platform has.
LDFLAGS="$CDSTUB $IUPIM $IUPPLOT -lc++ -lim -lim_process -F$FW -framework iup -framework iupimglib -framework iupcontrols -framework iupcd -framework iupgl -framework iupglcontrols -framework iupweb -framework OpenGL -framework GLUT -L$BREW/lib -lcd -Wl,-rpath,$FW"

# A few tests in html/examples/tests call a function defined in a sibling test file without
# declaring it; the symbol is satisfied at link time by compiling the sibling with -DBIG_TEST
# so its own main() is suppressed.
companion() {
  case "$1" in
    flatlist)           echo list ;;
    flatsample)         echo sample ;;
    flattree)           echo tree ;;
    dial)               echo dial_led ;;
    webbrowser_editor)  echo rt_editor_images ;;
    *)                  echo "" ;;
  esac
}

ok=0; fail=0; skipped=0
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
    plot)                CFLAGS_EXTRA="-DPLOT_TEST" ;;
    mglplot)             CFLAGS_EXTRA="-DMGLPLOT_TEST" ;;
    glcanvas|glcanvas_cube) CFLAGS_EXTRA="-DUSE_OPENGL" ;;
    *)                   CFLAGS_EXTRA="" ;;
  esac
  comp=$(companion "$name"); extra=""
  if [ -n "$comp" ] && [ -e "$SRCDIR/$comp.c" ]; then
    clang -c -DBIG_TEST $CFLAGS "$SRCDIR/$comp.c" -o "$LOG/$comp.big.o" >> "$LOG/$name.log" 2>&1
    extra="$LOG/$comp.big.o"
  fi
  # Some files in these directories are not programs: dial_led.c and rt_editor_images.c are
  # include-fragments (a LED description and an image resource table), and bigtest.c is a
  # driver that needs every sibling compiled with -DBIG_TEST. Building every .c in the
  # directory turns those into "failures" that no amount of backend work can fix, which
  # inflates the failure count and hides real ones. Detect them by the only symptom that
  # actually distinguishes them -- a link that fails solely because there is no main -- so
  # nothing has to be hardcoded.
  if clang $CFLAGS $CFLAGS_EXTRA -o "$app/Contents/MacOS/$name" "$src" $extra $LDFLAGS > "$LOG/$name.log" 2>&1; then
    # Samples that load images look for them next to the executable.
    for res in "$SRCDIR"/*.png "$SRCDIR"/*.jpg "$SRCDIR"/*.bmp "$SRCDIR"/*.gif "$SRCDIR"/*.xbm "$SRCDIR"/*.led "$SRCDIR"/*.pts; do
      [ -e "$res" ] && cp "$res" "$app/Contents/MacOS/" 2>/dev/null
    done
    ok=$((ok+1)); echo "$name" >> "$OUT/_ok.txt"
  elif [ "$(grep -cE '^ +"_' "$LOG/$name.log")" = "1" ] \
       && grep -q '"_main", referenced from' "$LOG/$name.log"; then
    rm -rf "$app"
    skipped=$((skipped+1)); echo "$name" >> "$OUT/_skipped.txt"
  else
    fail=$((fail+1)); rm -rf "$app"; echo "$name" >> "$OUT/_fail.txt"
  fi
done
if [ "$skipped" -gt 0 ]; then
  echo "built=$ok failed=$fail skipped=$skipped (not standalone programs: $(tr '\n' ' ' < "$OUT/_skipped.txt"))  -> $OUT"
else
  echo "built=$ok failed=$fail  -> $OUT"
fi
