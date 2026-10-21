#!/bin/bash
# The helper app carries a copy of its script inside it, so editing the source
# changes nothing until the app is built again. That is not theoretical: a new
# kind of link did nothing at all for a day while the old ones kept working.
#
#   bash tests/helper.test.sh
set -u

. "$(dirname "$0")/lib.sh"
need_osascript "the helper app"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chhelper)" && pwd)"
trap 'rm -rf "$T"' EXIT
APP="$T/Claude HTML.app"
SCPT="$APP/Contents/Resources/Scripts/main.scpt"
handles() { osadecompile "$SCPT" 2>/dev/null | grep -c "claude-html://$1/"; }

"$HERE/helper-build.sh" "$APP" >/dev/null 2>&1
check "it builds" "$([ -f "$SCPT" ] && echo yes || echo no)" yes
check "  and handles the delete links" "$([ "$(handles delete)" -gt 0 ] && echo yes || echo no)" yes
check "  and the open-a-project links" "$([ "$(handles open)" -gt 0 ] && echo yes || echo no)" yes
check "  and declares the scheme to macOS" \
  "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$APP/Contents/Info.plist" 2>/dev/null)" \
  claude-html
check "  with a signature macOS accepts" \
  "$(codesign --verify "$APP" >/dev/null 2>&1 && echo valid || echo broken)" valid

BEFORE="$(stat -f %m "$SCPT")"
"$HERE/helper-build.sh" "$APP" --if-stale >/dev/null 2>&1
check "an app already current is left alone" "$(stat -f %m "$SCPT")" "$BEFORE"

# Pretend the app was built before the source was last edited.
touch -t 202001010000 "$SCPT"
"$HERE/helper-build.sh" "$APP" --if-stale >/dev/null 2>&1
check "an app older than its source is rebuilt" \
  "$([ "$(stat -f %m "$SCPT")" != "$(date -j -f '%Y%m%d%H%M' 202001010000 +%s)" ] && echo rebuilt || echo stale)" \
  rebuilt
check "  and handles both kinds of link again" \
  "$([ "$(handles open)" -gt 0 ] && [ "$(handles delete)" -gt 0 ] && echo yes || echo no)" yes

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
