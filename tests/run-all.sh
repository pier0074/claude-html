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

for t in viewer diff index; do
  printf '%-9s ' "$t"
  if out="$(node "$HERE/$t.test.js" 2>&1)"; then echo "$out" | tail -1
  else echo "$out" | tail -3; failed=1; fi
done
for t in backend engine incremental races build hooks agents usage delete open helper install safety linux; do
  printf '%-9s ' "$t"
  if out="$(bash "$HERE/$t.test.sh" 2>&1)"; then echo "$out" | tail -1
  else echo "$out" | grep -E "FAIL|failed" | tail -5; failed=1; fi
done

# The suites build helper apps in temp folders. None of them may be left
# registered with macOS, or the real delete button launches a ghost.
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [ -x "$LSREG" ]; then
  leaked=$("$LSREG" -dump 2>/dev/null | grep -c 'path: .*/\(tmp\|var/folders\)/.*Claude HTML\.app' || true)
  printf '%-9s ' "leaks"
  if [ "${leaked:-0}" = 0 ]; then echo "no helper app registered from a temp folder"
  else echo "FAIL  $leaked helper app(s) registered from temp folders"; failed=1; fi
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
[ "$failed" = 0 ] && echo "all suites passed" || echo "SOMETHING FAILED"
exit "$failed"
