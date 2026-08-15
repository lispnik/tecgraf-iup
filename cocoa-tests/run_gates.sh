#!/bin/bash
# Runs every test suite across the four Tecgraf repositories.
#
#   usage: run_gates.sh [suite ...]        (default: all of them)
#          suites: cd iup-sweep iup-parity iup-mgl imlab
#
# These libraries are built against each other, so a regression in one shows up as a mystery in
# another: a CD driver change surfaces as a plot that will not draw, an IUP change as an ImLab
# dialog that does nothing. Running them together is the point.
#
# Nothing here rebuilds. Build first if you have changed anything:
#
#   cmake --build tecgraf-cd/build-local -j8            && cmake --install tecgraf-cd/build-local
#   cmake --build tecgraf-iup/BUILD-xcode --config Release --target iup ...
#   tecgraf-iup/cocoa-tests/build_apps.sh html/examples/tests tests-apps
#   cmake --build tecgraf-imlab/build -j8
set -u

# This lives in the IUP repository but drives all four, so it works from the directory holding
# them -- two levels up from cocoa-tests/ -- and each can be overridden.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IUP=${IUP:-$(cd "$HERE/.." && pwd)}
WORKSPACE=$(cd "$IUP/.." && pwd)
CD=${CD:-$WORKSPACE/tecgraf-cd}
IMLAB=${IMLAB:-$WORKSPACE/tecgraf-imlab}

SUITES=("$@")
if [ ${#SUITES[@]} -eq 0 ]; then
  SUITES=(cd iup-sweep iup-parity iup-mgl imlab)
fi

status=0
declare -a summary=()

note()
{
  # name : verdict : detail
  summary+=("$1|$2|$3")
  [ "$2" = "ok" ] || status=1
}

for suite in "${SUITES[@]}"; do
  case $suite in

    cd)
      echo "=== CD test suite"
      build=$CD/build-local
      [ -d "$build" ] || build=$CD/build-green
      if [ ! -d "$build" ]; then
        note "CD" "skipped" "no build directory; configure with -DCD_BUILD_TESTS=ON"
        continue
      fi
      out=$(ctest --test-dir "$build" -j4 2>&1)
      echo "$out" | tail -3
      passed=$(echo "$out" | grep -oE "[0-9]+% tests passed, [0-9]+ tests failed out of [0-9]+" | tail -1)

      # "no tests" and "tests failed" are different answers, and only one of them is a problem
      # with the code. A build configured without -DCD_BUILD_TESTS=ON has nothing to run, and a
      # build directory left over from before a move has stale absolute paths, so every test
      # reports "Not Run" -- both used to be reported here as a failure.
      if echo "$out" | grep -q "No tests were found"; then
        note "CD" "skipped" "no tests in $build; configure with -DCD_BUILD_TESTS=ON"
      elif echo "$out" | grep -q "(Not Run)"; then
        note "CD" "FAILED" "test binaries missing -- reconfigure $build from scratch"
      elif echo "$out" | grep -q "100% tests passed"; then
        note "CD" "ok" "${passed:-all passed}"
      else
        note "CD" "FAILED" "${passed:-see output}"
      fi
      ;;

    iup-sweep)
      echo "=== IUP sample sweep"
      out=$("$IUP/cocoa-tests/sweep.sh" 2>&1)
      echo "$out" | grep -E "apps:|NO RESULT|no failures|FAILURES"
      counts=$(echo "$out" | grep -E "apps:" | tr -s ' ' | tr '\n' ' ')
      if echo "$out" | grep -q "^no failures"; then
        note "IUP samples" "ok" "$counts"
      else
        note "IUP samples" "FAILED" "$counts"
      fi
      ;;

    iup-parity)
      echo "=== IUP parity harnesses"
      out=$("$IUP/cocoa-tests/run_parity.sh" 2>&1)
      gaps=$(echo "$out" | grep -cE "^GAP")
      assertions=$(echo "$out" | grep -cE "^ok")
      harnesses=$(echo "$out" | grep -cE "^=== ")
      echo "  $harnesses harnesses, $assertions assertions, $gaps gap(s)"
      echo "$out" | grep -E "^GAP" | head -5
      # No gaps is only good news if something actually ran. When the installed libcd took an
      # @rpath install name, every harness died in dyld before main and asserted nothing -- and
      # this reported "ok, 22 harnesses, 0 assertions", which is the one answer a gate must
      # never give. Silence is not success.
      if [ "$assertions" = "0" ]; then
        note "IUP parity" "FAILED" "$harnesses harnesses ran but asserted nothing -- did they start?"
      elif [ "$gaps" = "0" ]; then
        note "IUP parity" "ok" "$harnesses harnesses, $assertions assertions"
      else
        note "IUP parity" "FAILED" "$gaps gap(s)"
      fi
      ;;

    iup-mgl)
      echo "=== IupMglPlot sample"
      out=$("$IUP/cocoa-tests/run_mglsample.sh" 2>&1)
      echo "$out" | grep -E "^(ok|FAIL)|failure\(s\)|SKIPPED"
      if echo "$out" | grep -q "SKIPPED"; then
        note "IupMglPlot" "skipped" "sample not built"
      elif echo "$out" | grep -q "^0 failure"; then
        note "IupMglPlot" "ok" "$(echo "$out" | grep -cE '^ok') tabs render"
      elif ! echo "$out" | grep -qE "^(ok|FAIL)"; then
        # the sample never got as far as reporting on a tab -- see the note above
        note "IupMglPlot" "FAILED" "the sample reported nothing -- did it start?"
      else
        note "IupMglPlot" "FAILED" "$(echo "$out" | grep -cE '^FAIL') tab(s) blank"
      fi
      ;;

    imlab)
      echo "=== ImLab"
      if [ ! -x "$IMLAB/build/imlab" ]; then
        note "ImLab" "skipped" "not built: cmake -S $IMLAB -B $IMLAB/build && cmake --build $IMLAB/build"
        continue
      fi
      out=$("$IMLAB/test/run_tests.sh" "$IMLAB/build/imlab" 2>&1)
      echo "$out" | grep -E "^(ok|FAIL)|failure\(s\)|no failures|FAILURES"
      if echo "$out" | grep -q "^no failures"; then
        note "ImLab" "ok" "$(echo "$out" | grep -cE '^ok') assertions"
      else
        note "ImLab" "FAILED" "$(echo "$out" | grep -cE '^FAIL') failing"
      fi
      ;;

    *)
      echo "unknown suite: $suite" >&2
      exit 2
      ;;
  esac
  echo
done

echo "================ summary ================"
for row in "${summary[@]}"; do
  IFS='|' read -r name verdict detail <<< "$row"
  printf "  %-14s %-8s %s\n" "$name" "$verdict" "$detail"
done

if [ "$status" = "0" ]; then
  echo "  all gates green"
else
  echo "  SOMETHING FAILED (see above)"
fi
exit $status
