#!/bin/bash
# tests/run-all.sh itself, stopped part way: whatever stops it (Ctrl-C, a
# kill, the terminal closed) stops every suite it started too, their
# children and theirs, and it cleans up as it does at its end. Before, only
# run-all.sh died, and its suites ran on with no one waiting for them.
#
# A copy of run-all.sh runs a stand-in tests folder, its one suite slow and
# with children of every kind: a sleep, a nested bash, node, and a sleep that
# ignores TERM, which only KILL stops. It is in two parts, as the long suites
# are, so two jobs run it side by side: both are stopped.
#
#   bash tests/gate.test.sh
set -u

SRC="$(cd "$(dirname "$0")" && pwd)"
. "$SRC/lib.sh"

T="$(cd "$(tmpdir chgate)" && pwd -P)"
PIDS="$T/pids"
# Whatever is left of it goes with the suite, whether or not the copy stopped it.
cleanup() { [ -f "$PIDS" ] && kill -KILL $(cat "$PIDS") 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

C="$T/clone"; mkdir -p "$C/tests" "$T/home" "$T/tmp"
cp "$SRC/run-all.sh" "$SRC/app-leaks.sh" "$C/tests/"
# The copy runs the stand-in suite alone.
sed -e 's/^QUICK=.*/QUICK=""/' -e 's/^SUITES=.*/SUITES="slow"/' "$SRC/run-all.sh" > "$C/tests/run-all.sh"
check "the copy runs the stand-in suite alone" "$(grep -c -e '^SUITES="slow"$' -e '^QUICK=""$' "$C/tests/run-all.sh")" 2

# Its header, written so that this file is not taken for a suite in parts.
printf '#!/bin/bash\n# parts: %s\n' 2 > "$C/tests/slow.test.sh"
cat >> "$C/tests/slow.test.sh" <<EOF
# A helper app built in the clone, as a suite must not, and one in a temp folder.
mkdir -p "\$(dirname "\$0")/../Claude HTML.app/Contents" "\$TMPDIR/x/Claude HTML.app/Contents"
sleep 300 & echo \$! >> '$PIDS'
bash -c 'sleep 300 & echo \$! >> "$PIDS"; wait' & echo \$! >> '$PIDS'
node -e 'setTimeout(function () {}, 300000)' & echo \$! >> '$PIDS'
bash -c 'trap "" TERM; sleep 300 & echo \$! >> "$PIDS"; wait' & echo \$! >> '$PIDS'
echo \$\$ >> '$PIDS'
wait
EOF

# Every process the suite's two parts started, once they are all there.
started() { [ -f "$PIDS" ] && [ "$(grep -c . "$PIDS")" -ge 14 ]; }
alive() { local n=0 p; for p in $(cat "$PIDS" 2>/dev/null); do
  ps -o stat= -p "$p" 2>/dev/null | grep -qv '^ *Z' && n=$((n + 1)); done; echo "$n"; }

for how in TERM INT HUP; do
  rm -f "$PIDS"
  # In a group of its own, as a command typed at a terminal is: started in
  # the background without one, a shell ignores INT from the start for good.
  set -m
  env -i CLAUDE_HTML_NO_SCREEN="$T/shown" HOME="$T/home" PATH="$PATH" TMPDIR="$T/tmp" \
    CLAUDE_HTML_TEST_LOCK="$T/lock" CLAUDE_HTML_TEST_JOBS=2 \
    bash "$C/tests/run-all.sh" > "$T/out" 2>&1 &
  rp=$!; set +m
  i=0; until started || [ $i -ge 150 ]; do sleep 0.1; i=$((i + 1)); done
  check "$how: both parts of the suite and their children started" "$(started && alive)" 14
  check "$how: the run holds its lock" "$(cat "$T/lock/pid" 2>/dev/null)" "$rp"
  kill -"$how" "$rp"
  # Not waiting forever on a copy that does not stop.
  i=0; while kill -0 "$rp" 2>/dev/null && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
  kill -KILL "$rp" 2>/dev/null
  # (Its end not reported as a job's, it is one only to have a group.)
  { wait "$rp"; rc=$?; } 2>/dev/null
  # Stopped processes not yet reaped by whoever inherited them.
  i=0; while [ "$(alive)" != 0 ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i + 1)); done
  check "$how: no process of the suite is left" "$(alive)" 0
  check "$how: it ends with a failure" "$([ "$rc" != 0 ] && echo yes)" yes
  has "$how: it says it was stopped" "$(cat "$T/out")" "interrupted"
  check "$how: its temp folder is gone" "$(ls "$T/tmp" | grep -c .)" 0
  check "$how: its lock is gone" "$([ -e "$T/lock" ] && echo there || echo gone)" gone
  check "$how: the helper app built in the clone is gone" \
    "$([ -e "$C/Claude HTML.app" ] && echo there || echo gone)" gone
  kill -KILL $(cat "$PIDS" 2>/dev/null) 2>/dev/null; rm -rf "$C/Claude HTML.app" "$T/lock" "$T/tmp"/*
done

verdict
