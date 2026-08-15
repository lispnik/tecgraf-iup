#!/bin/bash
# Checks that every plot in the IupMglPlot sample actually renders.
#
# This runs the real sample with a probe injected into it (mglprobe.m), selects each tab through
# its native tab view the way a click does, and measures what MathGL rendered. It exists because
# the failure it guards -- MathGL's geometry being clipped away in OpenGL mode -- could not be
# reproduced with a plot built by hand, only with the ones the sample builds.
#
#   usage: run_mglsample.sh [path-to-mglplot]
#
# The window is kept off the desktop while it runs, which is what PROBE_BACKGROUND does.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IUP=$(cd "$HERE/.." && pwd)
FW=$IUP/BUILD-xcode/Release
SAMPLE=${1:-$FW/tests-apps/mglplot.app/Contents/MacOS/mglplot}
PROBE=$HERE/probe.dylib
BIN=$HERE/build
mkdir -p "$BIN"

if [ ! -x "$SAMPLE" ]; then
  echo "=== mglsample: SKIPPED (run build_apps.sh first to build $SAMPLE)"
  exit 0
fi

if [ ! -e "$PROBE" ]; then
  clang -dynamiclib -o "$PROBE" "$HERE/probe.m" -framework Cocoa || exit 1
fi

MGLPROBE=$BIN/mglprobe.dylib
if [ ! -e "$MGLPROBE" ] || [ "$HERE/mglprobe.m" -nt "$MGLPROBE" ]; then
  clang -dynamiclib -o "$MGLPROBE" "$HERE/mglprobe.m" \
        -I"$IUP/include" -I"$IUP/src" \
        -framework Cocoa -framework OpenGL -Wno-deprecated-declarations \
        -F"$FW" -framework iup -Wl,-rpath,"$FW" -undefined dynamic_lookup || exit 1
fi

# The sample reads its fonts relative to the working directory.
out=$(cd "$(dirname "$SAMPLE")" && timeout 90 env \
      MGL_TEST=1 PROBE_BACKGROUND=1 PROBE_SECONDS=60 PROBE_LOG=/dev/null \
      DYLD_INSERT_LIBRARIES="$PROBE:$MGLPROBE" "$SAMPLE" 2>/dev/null)
rc=$?

echo "$out" | grep -E '^(ok|FAIL)|failure\(s\)'
if [ "$rc" != "0" ]; then
  echo "  sample exited $rc"
  exit 1
fi
exit 0
