#!/bin/bash
# Launch every built sample under probe.dylib and report a pass/fail verdict for each.
#
# Each app runs for a few seconds as a background (accessory) application with its windows made
# fully transparent, so a full sweep does not steal focus or cover the desktop. Eight run at a
# time; the whole set takes about a minute.
#
#   usage: sweep.sh [app-dir ...]      (default: all three sample sets)
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IUP=$(cd "$HERE/.." && pwd)
FW=$IUP/BUILD-xcode/Release
PROBE=$HERE/probe.dylib
SECONDS_PER_APP=${PROBE_SECONDS:-3}

if [ ! -e "$PROBE" ]; then
  clang -dynamiclib -o "$PROBE" "$HERE/probe.m" -framework Cocoa || exit 1
fi

DIRS=("$@")
if [ ${#DIRS[@]} -eq 0 ]; then
  DIRS=("$FW/tests-apps" "$FW/examples-apps" "$FW/tutorial-apps")
fi

LOGDIR=$(mktemp -d /tmp/iup-sweep.XXXXXX)
run_one()
{
  app="$1"; logdir="$2"; probe="$3"; secs="$4"
  name=$(basename "$app" .app)
  set_name=$(basename "$(dirname "$app")")
  # one log per app: parallel writers must not interleave
  PROBE_LOG="$logdir/$set_name.$name.log" PROBE_BACKGROUND=1 PROBE_SECONDS="$secs" \
    DYLD_INSERT_LIBRARIES="$probe" "$app/Contents/MacOS/$name" >/dev/null 2>&1
}
export -f run_one

for dir in "${DIRS[@]}"; do
  [ -d "$dir" ] || continue
  ls -d "$dir"/*.app 2>/dev/null
done | xargs -P 8 -I{} bash -c 'run_one "$@"' _ {} "$LOGDIR" "$PROBE" "$SECONDS_PER_APP"

status=0
for dir in "${DIRS[@]}"; do
  [ -d "$dir" ] || continue
  set_name=$(basename "$dir")
  total=$(cat "$LOGDIR/$set_name."*.log 2>/dev/null | grep -c RESULT)
  passed=$(cat "$LOGDIR/$set_name."*.log 2>/dev/null | grep -c 'verdict=PASS')
  printf '%-16s %s/%s\n' "$set_name:" "$passed" "$total"
  [ "$passed" = "$total" ] || status=1
done

if ! cat "$LOGDIR"/*.log 2>/dev/null | grep RESULT | grep -v 'verdict=PASS'; then
  echo "no failures"
fi
rm -rf "$LOGDIR"
exit $status
