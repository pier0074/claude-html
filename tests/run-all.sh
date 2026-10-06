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

for t in viewer diff; do
  printf '%-9s ' "$t"
  if out="$(node "$HERE/$t.test.js" 2>&1)"; then echo "$out" | tail -1
  else echo "$out" | tail -3; failed=1; fi
done
for t in backend races build hooks agents delete open helper; do
  printf '%-9s ' "$t"
  if out="$(bash "$HERE/$t.test.sh" 2>&1)"; then echo "$out" | tail -1
  else echo "$out" | grep -E "FAIL|failed" | tail -5; failed=1; fi
done

echo
[ "$failed" = 0 ] && echo "all suites passed" || echo "SOMETHING FAILED"
exit "$failed"
