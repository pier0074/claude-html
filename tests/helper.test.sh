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
check "  and the resume links" "$([ "$(handles resume)" -gt 0 ] && echo yes || echo no)" yes
check "  and the update link, exactly and in this case only" \
  "$(osadecompile "$SCPT" 2>/dev/null | grep -c 'considering case\|theURL is "claude-html://update"\|" --update-terminal"')" 3
check "  open, delete and resume unaffected beside it" \
  "$(osadecompile "$SCPT" 2>/dev/null | grep -c '" --open "\|" --resume-session "\|" --delete-plan "')" 3
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

# What the update link makes the command do, dry: Terminal opens a
# launcher that runs this clone's own command, then the login shell.
H="$T/home"; mkdir -p "$H/.claude"
PLAN="$(env HOME="$H" CLAUDE_HTML_FORCE_NODE=1 bash "$HERE/claude-html" --update-terminal-plan 2>&1)"
check "the update opens with Terminal" "$(printf '%s\n' "$PLAN" | sed -n 's/^opens with: //p')" Terminal
check "  through /usr/bin/open and a launcher" "$(printf '%s\n' "$PLAN" | sed -n 's/^command: //p')" \
  "'/usr/bin/open' '$H/.claude/.claude-html-update.command'"
env HOME="$H" CLAUDE_HTML_FORCE_NODE=1 CH_DRY=1 bash "$HERE/claude-html" --update-terminal >/dev/null 2>&1
L="$H/.claude/.claude-html-update.command"
check "  which runs this clone's claude-html --update, then exec's the login shell, last" \
  "$(grep -v '^#' "$L" | head -1) | $(tail -1 "$L")" "'$(cd -P "$HERE" && pwd)/claude-html' --update | exec \"\$s\" -l"
# Run as Terminal would, with a stand-in for the command that fails and a
# shell that says where it started: the window ends as that shell.
printf '#!/bin/sh\nprintf "%%s|%%s\\n" "$(pwd -P)" "$*" > "%s/shell"\n' "$T" > "$T/stubshell"; chmod +x "$T/stubshell"
mkdir -p "$T/fake"; printf '#!/bin/sh\necho "refused"; exit 1\n' > "$T/fake/claude-html"; chmod +x "$T/fake/claude-html"
sed "s|^'$(cd -P "$HERE" && pwd)/claude-html' --update|'$T/fake/claude-html' --update|" "$L" > "$T/l.command"
OUTL="$(cd "$H" && HOME="$H" SHELL="$T/stubshell" bash "$T/l.command")"
check "  its output stays, and the window is the shell, even after a refusal" \
  "$(printf '%s' "$OUTL" | head -1) | $(cat "$T/shell" 2>/dev/null)" "refused | $(cd -P "$H" && pwd)|-l"
check "  and can be run" "$([ -x "$L" ] && echo yes)" yes

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
