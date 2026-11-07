#!/bin/bash
# The two ways a message could be lost, reproduced exactly.
#
# Both were real, and both failed before they were fixed: deciding a
# transcript was unchanged from its timestamp missed a reply that landed in the
# same second as a build, and a final reply that landed while its archive was
# being written. Sub-second timestamps are set through whichever engine the
# machine has, so this runs on macOS and Linux alike.
#
#   bash tests/races.test.sh
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/lib.sh"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
# A JS object literal holding an NSDate does not bridge to the NSDictionary
# this call wants — it throws, and the timestamp silently stays unset — so the
# dictionary is built explicitly. The check after it makes that failure loud.
setm() {
  if [ "$HAVE_OSASCRIPT" = true ]; then
    osascript -l JavaScript -e 'function run(a) {
      var d = $.NSMutableDictionary.alloc.init;
      d.setObjectForKey($.NSDate.dateWithTimeIntervalSince1970(Number(a[1])),
                        $.NSFileModificationDate);
      return $.NSFileManager.defaultManager.setAttributesOfItemAtPathError(d, a[0], null);
    }' "$1" "$2" >/dev/null 2>&1
  else
    node -e 'const t = Number(process.argv[2]);
      require("fs").utimesSync(process.argv[1], t, t);' "$1" "$2" >/dev/null 2>&1
  fi
  local got; got="$(mtime_of "$1")"
  if [ "$got" != "${2%.*}" ]; then
    echo "  setup failed: could not set the time on $1" >&2; exit 2
  fi
}
built() { sed -n 's/.*"built":\([0-9]*\).*/\1/p'; }

T="$(cd "$(tmpdir chraces)" && pwd)"
trap 'rm -rf "$T"' EXIT

USER_LINE='{"type":"user","cwd":"/x/app","timestamp":"2026-09-11T10:00:00Z","message":{"role":"user","content":"first question"}}'
reply() {
  printf '{"type":"assistant","cwd":"/x/app","timestamp":"2026-09-11T10:00:01Z","message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$1"
}

# ── a reply in the same second as the build ─────────────────────────
mkdir -p "$T/a/projects/-x-app" "$T/a/out" "$T/a/home"
J="$T/a/projects/-x-app/aaaaaaaa-0000-0000-0000-000000000001.jsonl"
PAGE="$T/a/out/sessions/aaaaaaaa-0000-0000-0000-000000000001.html"
C="{\"root\":\"$T/a/none\",\"out\":\"$T/a/out\",\"projects\":\"$T/a/projects\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}"
convert() { HOME="$T/a/home" run_js "$HERE/convert.js" "$C"; }

printf '%s\n' "$USER_LINE" > "$J"; setm "$J" 1789200000.2
convert >/dev/null
reply "THE LATEST REPLY" >> "$J"; setm "$J" 1789200000.4      # 0.2 s later
convert >/dev/null
check "a reply in the same second as the build reaches the page" \
  "$(grep -c 'THE LATEST REPLY' "$PAGE")" 1
check "an unchanged transcript is still skipped" "$(convert | built)" 0

# ── the final reply while the archive is being written ──────────────
ROOTB="$T/b/root"; APP="$ROOTB/app"
D="$(printf '%s' "$APP" | tr '/' '-')"
mkdir -p "$T/b/home/.claude/projects/$D" "$APP" "$ROOTB/pages"
printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$ROOTB" "$ROOTB/pages" \
  > "$T/b/home/.claude/claude-html.conf"
J="$T/b/home/.claude/projects/$D/bbbbbbbb-0000-0000-0000-000000000002.jsonl"
A="$APP/.claude/.claude-conversations/bbbbbbbb-0000-0000-0000-000000000002.json"
save() { env HOME="$T/b/home" /bin/bash -c "cd '$APP' && /bin/bash '$HERE/save-conversation.sh'" </dev/null >/dev/null 2>&1; }

printf '%s\n' "$USER_LINE" > "$J"; setm "$J" 1789200000.0
save
setm "$A" 1789200001.0                                     # archive finished at …01.0
reply "THE FINAL REPLY" >> "$J"; setm "$J" 1789200000.5    # reply landed at …00.5
save
check "a final reply that lands mid-archive reaches the archive" \
  "$(grep -c 'THE FINAL REPLY' "$A")" 1
check "the archive records how much transcript it was made from" \
  "$(head -c 200 "$A" | sed -n 's/.*"sourceBytes":\([0-9]*\).*/\1/p')" "$(size_of "$J")"
BEFORE="$(mtime_of "$A")"; sleep 1.1; save
check "an unchanged transcript is not archived again" "$(mtime_of "$A")" "$BEFORE"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
