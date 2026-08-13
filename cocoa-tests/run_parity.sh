#!/bin/bash
# Build and run the per-control parity harnesses.
#
# Each one drives a control through the attributes IUP documents for it and asserts against the
# NATIVE state -- the NSButton's textColor, the NSBox's fillColor, the NSTableView's first visible
# row -- rather than against IupGetAttribute, which merely echoes whatever was stored and will
# happily report success for an attribute nothing implements.
#
#   usage: run_parity.sh [name ...]     (default: all)
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IUP=$(cd "$HERE/.." && pwd)
FW=$IUP/BUILD-xcode/Release
PROBE=$HERE/probe.dylib
BIN=$HERE/build
mkdir -p "$BIN"

if [ ! -e "$PROBE" ]; then
  clang -dynamiclib -o "$PROBE" "$HERE/probe.m" -framework Cocoa || exit 1
fi

NAMES=("$@")
if [ ${#NAMES[@]} -eq 0 ]; then
  NAMES=(labelparity labelcb btnparity togparity frmparity lstparity menuparity keyparity enterleave miscattrib dlgsize imglib drawimage glcanvas)
fi

status=0
for name in "${NAMES[@]}"; do
  src=$HERE/parity/$name.m
  [ -e "$src" ] || { echo "no such harness: $name"; status=1; continue; }
  if ! clang -g -o "$BIN/$name" "$src" \
        -I"$IUP/include" -I"$IUP/src" -framework Cocoa \
        -F"$FW" -framework iup -framework iupcontrols -framework iupimglib -framework iupcd -framework iupgl -framework OpenGL -L"$(brew --prefix 2>/dev/null || echo /opt/homebrew)/lib" -lcd -Wl,-rpath,"$FW" \
        -Wno-deprecated-declarations 2>"$BIN/$name.buildlog"; then
    echo "=== $name: BUILD FAILED"; head -5 "$BIN/$name.buildlog"; status=1; continue
  fi
  echo "=== $name"
  # PROBE_BACKGROUND keeps the window off the user's desktop; the generous timeout is because
  # NSButton's mouse tracking runs a nested event loop.
  out=$(timeout 40 env PROBE_BACKGROUND=1 PROBE_SECONDS=30 PROBE_LOG=/dev/null \
        DYLD_INSERT_LIBRARIES="$PROBE" "$BIN/$name" 2>/dev/null)
  echo "$out"
  echo "$out" | grep -qE '^(0 gap|0 failure)' || status=1
done
exit $status
