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
  # Count against the apps that were LAUNCHED, not against the results that came back. An app
  # that dies before the probe reports produces no RESULT line at all, so counting results
  # against results quietly lowers the denominator and the run still reads as clean -- which
  # is how a crash in text.app during IupMap once showed up as a harmless "74/74".
  launched=$(ls -d "$dir"/*.app 2>/dev/null | wc -l | tr -d ' ')
  total=$(cat "$LOGDIR/$set_name."*.log 2>/dev/null | grep -c RESULT)
  passed=$(cat "$LOGDIR/$set_name."*.log 2>/dev/null | grep -c 'verdict=PASS')
  printf '%-16s %s/%s\n' "$set_name:" "$passed" "$launched"
  [ "$passed" = "$launched" ] || status=1

  if [ "$total" != "$launched" ]; then
    for app in "$dir"/*.app; do
      [ -e "$app" ] || continue
      app_name=$(basename "$app" .app)
      grep -q RESULT "$LOGDIR/$set_name.$app_name.log" 2>/dev/null \
        || echo "  NO RESULT (died before reporting): $app_name"
    done
  fi
done

# Name collisions between sample sets. 43 sample names exist in BOTH html/examples/C and
# html/examples/tests, and no pair is identical -- expander.c is 47 lines in one and 725 in the
# other. So "the plot sample" names two different programs, and a fix applied to one leaves the
# other untouched: plot.app's Export PDF button was repaired in tests-apps while the
# examples-apps copy went on wiping the plot's datasets. Name the ambiguous ones, so the next
# person reading a verdict for "tabs" knows to ask which tabs.
if [ ${#DIRS[@]} -gt 1 ]; then
  # "<set> <set>...<TAB><name>", one line per name built more than once
  dups=$(for dir in "${DIRS[@]}"; do
           [ -d "$dir" ] || continue
           set_name=$(basename "$dir")
           for app in "$dir"/*.app; do
             [ -e "$app" ] || continue
             echo "$(basename "$app" .app) $set_name"
           done
         done | sort | awk '{ sets[$1] = sets[$1] " " $2; n[$1]++ }
                            END { for (k in n) if (n[k] > 1) print substr(sets[k], 2) "\t" k }')

  # grouped by which sets collide, since repeating the same pair forty times says nothing
  echo "$dups" | cut -f1 | sort -u | grep -v '^$' | while read -r pair; do
    names=$(echo "$dups" | awk -F'\t' -v p="$pair" '$1 == p { print $2 }' | sort | tr '\n' ' ')
    printf 'note: %s sample name(s) built from both %s -- fixing one is not fixing the other:\n' \
           "$(echo "$names" | wc -w | tr -d ' ')" "$pair"
    echo "$names" | fold -s -w 96 | sed 's/^/  /'
  done
fi

cat "$LOGDIR"/*.log 2>/dev/null | grep RESULT | grep -v 'verdict=PASS'
# Report against $status, not against the presence of failing RESULT lines: an app that never
# reported has no RESULT line to fail, and saying "no failures" there is the exact blind spot
# the per-set NO RESULT listing above exists to close.
if [ "$status" = "0" ]; then
  echo "no failures"
else
  echo "FAILURES (see above)"
fi
rm -rf "$LOGDIR"
exit $status
