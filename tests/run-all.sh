#!/bin/bash
# Every suite, one verdict. What CI runs, on macOS and on Linux, and what a
# contributor runs before pushing:
#
#   bash tests/run-all.sh
#
# On macOS the macOS-only suites run too; on Linux they skip and say so.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
failed=0
# The suites run node directly below, without lib.sh: nothing of the
# owner's own redaction settings may reach them.
unset CLAUDE_HTML_REDACT
export CLAUDE_HTML_REDACT_FILE="${TMPDIR:-/tmp}/claude-html-tests-no-such.redact"
# Nor ask the network whether a release is out.
export CLAUDE_HTML_UPDATE_CHECK=off
export CLAUDE_HTML_UPDATE_REMOTE="${TMPDIR:-/tmp}/claude-html-tests-no-such-remote"
# Nor register anything with the system, whoever runs them: inside the
# tests' own homes the "only the installed copy registers" rule cannot see
# the real install, and a second app claiming claude-html:// links breaks them.
export CLAUDE_HTML_NO_REGISTER=1
# On a Mac the command keeps a helper app beside itself, so the suites build
# one in this clone. One that was not here before the run is taken away after.
CLONE="$(cd "$HERE/.." && pwd -P)"
HAD_APP=no; [ -e "$CLONE/Claude HTML.app" ] && HAD_APP=yes

# The suites run side by side: each works in a folder and a home of its
# own, so none can see another. CLAUDE_HTML_TEST_JOBS=1 runs them one after
# another, as they used to be.
JOBS="${CLAUDE_HTML_TEST_JOBS:-}"
if [ -z "$JOBS" ]; then
  n="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
  JOBS=$(( n / 2 )); [ "$JOBS" -lt 2 ] && JOBS=2; [ "$JOBS" -gt 6 ] && JOBS=6
fi
case "$JOBS" in ''|*[!0-9]*|0) JOBS=1 ;; esac
OUTD="$(mktemp -d "${TMPDIR:-/tmp}/claude-html-tests.XXXXXX")" || exit 1
trap 'rm -rf "$OUTD"' EXIT
T0="$(date +%s)"

# The longest start first, so the last one to end is not a long one begun late.
QUICK="viewer diff index docs"
SUITES="incremental guard linux update usage engine install hooks backend redact races build agents delete open helper safety"
run_one() {   # name
  local t="$1" s rc
  s="$(date +%s)"
  case " $QUICK " in
    *" $t "*) node "$HERE/$t.test.js" > "$OUTD/$t.out" 2>&1 ;;
    *) bash "$HERE/$t.test.sh" > "$OUTD/$t.out" 2>&1 ;;
  esac
  rc=$?
  echo "$(( $(date +%s) - s ))" > "$OUTD/$t.secs"
  echo "$rc" > "$OUTD/$t.rc"
}
for t in $SUITES $QUICK; do
  while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$JOBS" ]; do sleep 0.2; done
  run_one "$t" &
done
wait

# The verdicts in a fixed order, whatever order they ended in.
for t in $QUICK $SUITES; do
  printf '%-9s ' "$t"
  rc="$(cat "$OUTD/$t.rc" 2>/dev/null || echo 1)"
  case " $QUICK " in
    *" $t "*) if [ "$rc" = 0 ]; then tail -1 "$OUTD/$t.out"; else tail -3 "$OUTD/$t.out"; failed=1; fi ;;
    # A suite passes on its own verdict, not on its exit status alone: one
    # cut short by an error (its clean-up then exiting 0) has no verdict.
    *) last="$(tail -1 "$OUTD/$t.out")"
       if [ "$rc" = 0 ] && printf '%s' "$last" | grep -Eq '[0-9]+ passed, 0 failed$|^ *skip '; then echo "$last"
       else grep -E "FAIL|failed" "$OUTD/$t.out" | tail -5
         [ "$rc" = 0 ] && echo "FAIL  ended without its verdict; its last lines:" && tail -3 "$OUTD/$t.out"
         [ -s "$OUTD/$t.out" ] || echo "no output"; failed=1; fi ;;
  esac
done

# Unregistered first: macOS registers an app by itself, and one deleted while
# still registered would be left claiming the links.
if [ "$HAD_APP" = no ] && [ -e "$CLONE/Claude HTML.app" ]; then
  LSREG_U=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  [ -x "$LSREG_U" ] && "$LSREG_U" -u "$CLONE/Claude HTML.app" 2>/dev/null
  rm -rf "$CLONE/Claude HTML.app"
fi

# The suites build helper apps in temp folders. None of them may be left
# registered with macOS, or the real delete button launches a ghost.
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [ -x "$LSREG" ]; then
  leaked=$("$LSREG" -dump 2>/dev/null | grep -c 'path: .*/\(tmp\|var/folders\)/.*Claude HTML\.app' || true)
  # Nor this clone's own, unless it is the installed copy.
  INSTALLED_AT="$(cd "$(dirname "$(readlink "$HOME/.local/bin/claude-html" 2>/dev/null)")" 2>/dev/null && pwd -P)"
  if [ "$INSTALLED_AT" != "$CLONE" ] &&
     "$LSREG" -dump 2>/dev/null | grep -qF "$CLONE/Claude HTML.app"; then leaked=$((leaked + 1)); fi
  printf '%-9s ' "leaks"
  if [ "${leaked:-0}" = 0 ]; then echo "no helper app registered from a temp folder or this clone"
  else echo "FAIL  $leaked helper app(s) registered from temp folders or this clone"; failed=1; fi
fi

# The same on Linux: a handler registered from a temp folder would leave
# every claude-html:// link launching a script that is gone.
HF="${XDG_DATA_HOME:-$HOME/.local/share}/applications/claude-html-handler.desktop"
if [ "$(uname -s)" = Linux ]; then
  printf '%-9s ' "leaks"
  if [ -f "$HF" ] && grep -Eq '^Exec="?(/tmp/|/var/tmp/|/dev/shm/)' "$HF"; then
    echo "FAIL  the claude-html link handler points into a temp folder"; failed=1
  else echo "no link handler registered from a temp folder"; fi
fi

echo
SLOW="$(for t in $SUITES $QUICK; do printf '%s %s\n' "$(cat "$OUTD/$t.secs" 2>/dev/null || echo 0)" "$t"; done |
        sort -rn | head -3 | awk '{ printf "%s%s %ss", (NR > 1 ? ", " : ""), $2, $1 }')"
echo "$(( $(date +%s) - T0 ))s, $JOBS at a time; longest: $SLOW"
[ "$failed" = 0 ] && echo "all suites passed" || echo "SOMETHING FAILED"
exit "$failed"
