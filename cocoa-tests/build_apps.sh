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
# Rebuild per source file when it changes, and re-archive whenever any object is newer than
# the archive. Building this only when the .a was missing meant an edit to srcplot never
# reached the samples: plot.app kept linking a stale archive while a direct link of the
# freshly built objects picked the fix up, which is a confusing pair of results to debug.
mkdir -p "$FW/extra/plot"
for src in "$IUP"/srcplot/*.cpp; do
  n=$(basename "$src" .cpp)
  if [ ! -e "$FW/extra/plot/$n.o" ] || [ "$src" -nt "$FW/extra/plot/$n.o" ]; then
    clang++ -c -std=c++11 -I"$IUP/include" -I"$IUP/src" -I"$IUP/srcplot" -I"$IUP/srccd" \
      -I$BREW/include -Wno-everything -o "$FW/extra/plot/$n.o" "$src" || exit 1
  fi
done
for obj in "$FW"/extra/plot/*.o; do
  if [ ! -e "$IUPPLOT" ] || [ "$obj" -nt "$IUPPLOT" ]; then
    ar rcs "$IUPPLOT" "$FW"/extra/plot/*.o || exit 1
    break
  fi
done

# IupMglPlot (srcmglplot). MathGL itself is vendored in that directory -- 39 sources plus its
# mgl2 headers -- so this needs nothing installed, and the three MathGL samples went unbuilt
# only because nobody had compiled it here.
#
# The include path is staged rather than pointed at srcmglplot directly: that directory holds a
# text file called "version", and with it on the include path libc++'s <version> resolves to
# "2.3.5.1" and every standard header that includes it fails to parse. Staging a directory that
# contains only a link to mgl2 keeps that file out of the way. MathGL's own sources include
# "mgl2/..." with quotes, so the compiler finds them relative to themselves regardless.
IUPMGL=$FW/extra/mgl/libiup_mglplot.a
MGLSTAGE=$FW/extra/mgl/include
mkdir -p "$FW/extra/mgl" "$MGLSTAGE"
ln -sfn "$IUP/srcmglplot/mgl2" "$MGLSTAGE/mgl2"

for src in "$IUP"/srcmglplot/iup_mglplot.cpp "$IUP"/srcmglplot/src/*.cpp "$IUP"/srcmglplot/src/s_hull/*.cpp; do
  n=$(basename "$src" .cpp)
  if [ ! -e "$FW/extra/mgl/$n.o" ] || [ "$src" -nt "$FW/extra/mgl/$n.o" ]; then
    clang++ -c -std=c++11 -O2 -DMGL_STATIC_DEFINE -DMGL_SRC \
      -I"$MGLSTAGE" -I"$IUP/include" -I"$IUP/src" -Wno-everything \
      -o "$FW/extra/mgl/$n.o" "$src" || exit 1
  fi
done
for obj in "$FW"/extra/mgl/*.o; do
  if [ ! -e "$IUPMGL" ] || [ "$obj" -nt "$IUPMGL" ]; then
    ar rcs "$IUPMGL" "$FW"/extra/mgl/*.o || exit 1
    break
  fi
done

# CD has no printer driver on macOS -- cdContextPrinter is a Windows/GDI-only symbol, and the
# Quartz build of libcd exports nothing like it. Several tutorial samples reference CD_PRINTER
# unconditionally and so will not link at all. They all guard on cdCreateCanvas returning NULL
# ("if (!print_canvas) return IUP_DEFAULT"), so supplying a context that yields NULL lets the
# samples build and run with every feature except printing, which is genuinely unavailable.
# This stub is linked ONLY into the samples; the IUP library itself is untouched.
# Emit a stub PER MISSING SYMBOL rather than all-or-nothing on cdContextPrinter. This object
# is listed ahead of -lcd on the link line, so a stub here SHADOWS a real definition in libcd:
# a strong symbol in an explicitly listed object always beats one in a library. Stubbing
# unconditionally therefore silently disabled features as soon as libcd gained them -- exactly
# what happened when a native CD_PDF driver appeared and the samples went on calling a stub
# that returned NULL. Ask libcd what it actually exports and fill only the real gaps.
CDSTUB=$FW/extra/sample_link_stubs.o
CDSTUB_SRC=$FW/extra/sample_link_stubs.c
mkdir -p "$FW/extra"

cd_has() { nm -gU "$BREW/lib/libcd.dylib" 2>/dev/null | grep -q " _$1$"; }

{
  echo "/* Generated by build_apps.sh: one stub per symbol libcd does not export. */"
  cd_has cdContextPrinter || cat <<'STUB'
/* CD has no printer driver on macOS. Callers check cdCreateCanvas for NULL, which is what a
   NULL context produces, so the samples run with every feature except printing. */
void* cdContextPrinter(void) { return 0; }
STUB
  cd_has cdContextCGM || echo 'void* cdContextCGM(void) { return 0; }'
  cd_has cdContextPS  || echo 'void* cdContextPS(void) { return 0; }'
  cd_has cdContextPDF || cat <<'STUB'
/* Only needed against a libcd without the CGPDFContext driver (or PDFlib). */
void* cdContextPDF(void) { return 0; }
STUB
  cd_has cdInitContextPlus || cat <<'STUB'
/* cdInitContextPlus enables CD's anti-aliased "Plus" contexts, which the macOS libcd does not
   ship. The samples that call it only use it to opt into nicer rendering. */
void cdInitContextPlus(void) { }
STUB
} > "$CDSTUB_SRC.new"

if [ ! -e "$CDSTUB_SRC" ] || ! cmp -s "$CDSTUB_SRC.new" "$CDSTUB_SRC"; then
  mv "$CDSTUB_SRC.new" "$CDSTUB_SRC"
  clang -c -o "$CDSTUB" "$CDSTUB_SRC" || exit 1
else
  rm -f "$CDSTUB_SRC.new"
  [ -e "$CDSTUB" ] || clang -c -o "$CDSTUB" "$CDSTUB_SRC" || exit 1
fi

# GL: link the real iupgl framework, and put a GL/gl.h -> OpenGL/gl.h shim on the include
# path, since macOS ships OpenGL as a framework and the samples use the header path every
# other platform has.
LDFLAGS="$CDSTUB $IUPIM $IUPPLOT $IUPMGL -lc++ -lim -lim_process -F$FW -framework iup -framework iupimglib -framework iupcontrols -framework iupcd -framework iupgl -framework iupglcontrols -framework iupweb -framework OpenGL -framework GLUT -L$BREW/lib -lcd -Wl,-rpath,$FW"

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
  # A few samples call a function defined in a sibling file without declaring it. Whether the
  # sibling is needed differs between the two sample directories -- html/examples/C's
  # canvas_scrollbar2 defines CanvasScrollbarTest itself and duplicates the symbol if the
  # sibling is linked, while html/examples/tests' version does not define it and fails to link
  # without. Rather than hardcode which is which, build without the sibling and only add it if
  # the link fails on an undefined symbol.
  comp=$(companion "$name"); extra=""
  if [ -n "$comp" ] && [ -e "$SRCDIR/$comp.c" ] \
     && ! clang $CFLAGS $CFLAGS_EXTRA -o "$app/Contents/MacOS/$name" "$src" $LDFLAGS \
              > "$LOG/$name.probe.log" 2>&1 \
     && grep -q 'Undefined symbols' "$LOG/$name.probe.log"; then
    clang -c -DBIG_TEST $CFLAGS "$SRCDIR/$comp.c" -o "$LOG/$comp.big.o" >> "$LOG/$name.log" 2>&1
    extra="$LOG/$comp.big.o"
  fi
  rm -f "$LOG/$name.probe.log"
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
