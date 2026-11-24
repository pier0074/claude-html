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
# The app built here is unregistered before it is deleted: macOS registers
# an app it sees appear, whatever folder it is in, and one deleted while
# still registered is left claiming the links.
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
trap '[ -x "$LSREG" ] && "$LSREG" -u "$T/Claude HTML.app" >/dev/null 2>&1; rm -rf "$T"' EXIT
APP="$T/Claude HTML.app"
SCPT="$APP/Contents/Resources/Scripts/main.scpt"
handles() { osadecompile "$SCPT" 2>/dev/null | grep -c "claude-html://$1/"; }

"$HERE/helper-build.sh" "$APP" >/dev/null 2>&1
check "it builds" "$([ -f "$SCPT" ] && echo yes || echo no)" yes
check "  and handles the delete links" "$([ "$(handles delete)" -gt 0 ] && echo yes || echo no)" yes
check "  and the open-a-project links" "$([ "$(handles open)" -gt 0 ] && echo yes || echo no)" yes
check "  and the resume links" "$([ "$(handles resume)" -gt 0 ] && echo yes || echo no)" yes
check "  and the update link, exactly and in this case only" \
  "$(osadecompile "$SCPT" 2>/dev/null | grep -c 'theURL is "claude-html://update"\|" --update-terminal"') $(osadecompile "$SCPT" 2>/dev/null | grep -B1 'set isUpdate to' | grep -c 'considering case')" "2 1"
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

# The limits link: the helper takes the payload's whole grammar and
# nothing else, as limits-cli.sh and handler.sh do. Its handler is loaded
# from the script alone, compiled here, no app: nothing is registered.
check "  and the limits link, through --limits-apply only" \
  "$(osadecompile "$SCPT" 2>/dev/null | grep -c '" --limits-apply " & quoted form of payload\|if not my isLimitsPayload(payload) then return')" 2
osacompile -o "$T/h.scpt" "$HERE/helper.applescript"
isl() { osascript -e "on run argv" -e "set s to load script POSIX file \"$T/h.scpt\"" -e "tell s to return isLimitsPayload(item 1 of argv)" -e "end run" -- "$1" 2>/dev/null; }
n=0; m=0
for p in "v1/fri-2000-80.sat-0000-90/50-week/80-95/off" "v1/none/none/80-95/on" "v1/mon-0000-1/12.50-month/1-99/off" \
         "v1/sun-2359-100.mon-0100-5.tue-0200-10.wed-0300-20.thu-0400-30.fri-0500-40.sat-0600-50.sun-0700-60/999999.99-day/50-51/on"; do
  m=$((m + 1)); [ "$(isl "$p")" = true ] && n=$((n + 1))
done
check "the helper takes the good payloads ($m)" "$n" "$m"
n=0; m=0
for p in "v1/fri-2400-80/none/80-95/on" "v1/fri-2060-80/none/80-95/on" "v1/fri-2000-0/none/80-95/on" "v1/fri-2000-101/none/80-95/on" \
         "v1/fri-2000-080/none/80-95/on" "v1/Fri-2000-80/none/80-95/on" "V1/fri-2000-80/none/80-95/on" "v2/none/none/80-95/on" \
         "v1/none/none/80-95/on/" "/v1/none/none/80-95/on" "v1//none/80-95/on" "v1/fri-2000-80..sat-0000-90/none/80-95/on" \
         "v1/fri-2000-80./none/80-95/on" "v1/none/0.5-week/80-95/on" "v1/none/050-week/80-95/on" "v1/none/50-year/80-95/on" \
         "v1/none/50.123-week/80-95/on" "v1/none/1000000-week/80-95/on" "v1/none/none/80-100/on" "v1/none/none/80/on" \
         "v1/none/none/80-95/yes" "v1/none/none/80-95/on?x=1" "v1/none/none/80-95/on#f" "v1/none/none/80-95/on%0a" \
         "v1/none/none/80-95/on;id" "v1/none/none/80-95/on \$(id)" "v1/friday-2000-80/none/80-95/on" "v1/none/none/80-95/ON" \
         "v1/sun-2359-100.mon-0100-5.tue-0200-10.wed-0300-20.thu-0400-30.fri-0500-40.sat-0600-50.sun-0700-60.mon-0800-70/none/80-95/on" \
         "v1/none/none/80-95/on
x" "" "$(printf 'v1/none/none/80-95/on%0200d' 0)"; do
  m=$((m + 1)); [ "$(isl "$p")" = false ] && n=$((n + 1))
done
check "  and refuses every variant ($m)" "$n" "$m"

# What the update link makes the command do, dry: Terminal opens a
# launcher that runs this clone's own command, then the login shell.
H="$T/home"; mkdir -p "$H/.claude"
PLAN="$(env HOME="$H" CLAUDE_HTML_FORCE_NODE=1 bash "$HERE/claude-html" --update-terminal-plan 2>&1)"
check "the update opens with Terminal" "$(printf '%s\n' "$PLAN" | sed -n 's/^opens with: //p')" Terminal
check "  through /usr/bin/open and a launcher" "$(printf '%s\n' "$PLAN" | sed -n 's/^command: //p')" \
  "'/usr/bin/open' '$H/.claude/.claude-html-update.command'"
env HOME="$H" CLAUDE_HTML_FORCE_NODE=1 CH_DRY=1 bash "$HERE/claude-html" --update-terminal >/dev/null 2>&1
L="$H/.claude/.claude-html-update.command"
check "  which asks first, runs this clone's claude-html --update on a yes, then exec's the login shell, last" \
  "$(grep -c "^printf 'Update claude-html $(cat "$HERE/VERSION") -> the newest release? \[y/N\] '\$" "$L") $(grep -c "y|Y|yes|YES) '$(cd -P "$HERE" && pwd)/claude-html' --update ;;" "$L") | $(tail -1 "$L")" \
  "1 1 | exec \"\$s\" -l"
# Run as Terminal would, with a stand-in for the command that fails and a
# shell that says where it started: the window ends as that shell.
printf '#!/bin/sh\nprintf "%%s|%%s\\n" "$(pwd -P)" "$*" > "%s/shell"\n' "$T" > "$T/stubshell"; chmod +x "$T/stubshell"
mkdir -p "$T/fake"; printf '#!/bin/sh\necho "refused"; exit 1\n' > "$T/fake/claude-html"; chmod +x "$T/fake/claude-html"
sed "s|'$(cd -P "$HERE" && pwd)/claude-html' --update|'$T/fake/claude-html' --update|" "$L" > "$T/l.command"
OUTL="$(cd "$H" && echo y | HOME="$H" SHELL="$T/stubshell" bash "$T/l.command")"
check "  its output stays, and the window is the shell, even after a refusal" \
  "$(printf '%s' "$OUTL" | head -1) | $(cat "$T/shell" 2>/dev/null)" "Update claude-html $(cat "$HERE/VERSION") -> the newest release? [y/N] refused | $(cd -P "$H" && pwd)|-l"
OUTL="$(cd "$H" && printf '\n' | HOME="$H" SHELL="$T/stubshell" bash "$T/l.command")"
check "  and without a yes it changes nothing" "$(printf '%s' "$OUTL" | head -1)" \
  "Update claude-html $(cat "$HERE/VERSION") -> the newest release? [y/N] nothing was changed"
check "  a second window within a minute is refused" \
  "$(env HOME="$H" CLAUDE_HTML_FORCE_NODE=1 CH_DRY=1 bash "$HERE/claude-html" --update-terminal 2>&1 | tr -d "\n"; echo " ${PIPESTATUS[0]}")" \
  "an update window was opened less than a minute ago; nothing was opened 1"
check "  and can be run" "$([ -x "$L" ] && echo yes)" yes


# ── the windows, for real ────────────────────────────────────────────
# Each one shown, then closed by itself: a test's limit of a few seconds,
# and a hard stop past it, so none can stay on the screen of whoever runs
# the suite.
realwin() {   # seconds args…
  local lim="$1"; shift
  osascript -l JavaScript "$HERE/dialog.js" "$@" 2>/dev/null & local p=$!
  ( sleep "$lim"; kill "$p" 2>/dev/null ) >/dev/null 2>&1 & local w=$!
  wait "$p"; local rc=$?; kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  return $rc
}
box() {   # name text: a private file, as guard.sh makes them
  (umask 077; printf '%s' "$2" > "$T/$1")
}
box found "$(printf 'GitHub token:  …deploy with \001%s\002 and …' "not-a-secret-value")"
box command "$(printf 'echo one\necho two')"
OUTS="$(realwin 20 --limit 10 --box Found: "$T/found" --pre Command: "$T/command" --selftest "$T/selftest" bash Weather "GitHub token (1)" "echo one …")"
check "the guard's window: it ran, and read and deleted its private files before drawing" \
  "$OUTS $([ -e "$T/found" ] || [ -e "$T/command" ] && echo left || echo gone)" "cancel gone"
check "  a selected title, ⌘C: copied, through the Edit menu the window installs" \
  "$(grep '^cmd-c=' "$T/selftest")" "cmd-c=Claude's command has been interrupted"
check "  Found ▸ opens a box and the window grows" "$(grep '^open=' "$T/selftest")" "open=1 grew=1"
check "  its copy button copies the box's whole text, unmarked, and says so" "$(grep '^copy=' "$T/selftest")" "copy=same title=copied"
check "  closed again, the window is as it was" "$(grep '^closed=' "$T/selftest")" "closed=1 back=1"
check "  and the clipboard holds none of the test's text" "$(pbpaste 2>/dev/null | grep -c "interrupted\|nothing copied\|not-a-secret-value")" 0
check "the countdown closes the window at 0:00, as no answer" \
  "$(realwin 15 --limit 2 prompt P "GitHub token (1)") $(realwin 15 --limit 2 limits h k1 v1 k2 v2 c3 c4) $(realwin 15 --limit 2 confirm T S "$(printf 'A:\tb')")" \
  "timeout timeout timeout"
box rule "CLAUDE_HTML_LIMIT_RULES=\"fri 20:00 80%\""
box lines "CLAUDE_HTML_LIMIT_NOTIFY=\"on\""
realwin 15 --limit 8 --box Rule: "$T/rule" --open Rule: --snap "$T/stop.png" limits "Weekly limit rule reached" "Used:" "81 %" "Rule:" "from Fri 20:00, stop at 80 %" c3 c4 >/dev/null
realwin 15 --limit 8 --box File: "$T/lines" --open File: --snap "$T/confirm.png" confirm "Change claude-html limits?" "Asked by the Token usage page." "$(printf 'File:\t~/.claude/claude-html.conf')" >/dev/null
check "the stop and confirmation windows draw, their box open" \
  "$(head -c 4 "$T/stop.png" | od -c | head -1 | grep -c 'P   N   G') $(head -c 4 "$T/confirm.png" | od -c | head -1 | grep -c 'P   N   G') $(ls "$T/rule" "$T/lines" 2>/dev/null | wc -l | tr -d ' ')" "1 1 0"
check "no window of a test is left running" "$(pgrep -f "$HERE/dialog.js" | wc -l | tr -d ' ')" 0

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
