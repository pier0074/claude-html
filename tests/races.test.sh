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
convert() { HOME="$T/a/home" run_js "$HERE/build/convert.js" "$C"; }

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

# ── two saves of one session at once ────────────────────────────────
# The session-end save waits for the lock, and past its wait saves without
# it, so two can archive one session together. A stand-in node runs the
# real archiver but holds the first save's output half written until the
# second save has finished, with the transcript grown in between: the
# archive left must be whole, and the second save's, which read more.
ROOTC="$T/c/root"; APPC="$ROOTC/app"; HC="$T/c/home"
DC="$(printf '%s' "$APPC" | tr '/' '-')"
mkdir -p "$HC/.claude/projects/$DC" "$APPC" "$T/c/bin"
SID=cccccccc-0000-0000-0000-000000000003
JC="$HC/.claude/projects/$DC/$SID.jsonl"; AC="$APPC/.claude/.claude-conversations/$SID.json"
printf '%s\n' "$USER_LINE" > "$JC"
REAL_NODE="$(command -v node)"
cat > "$T/c/bin/node" <<STUB
#!/bin/bash
case "\$1" in
  */archive.js)
    if [ -n "\${HOLD:-}" ]; then
      "$REAL_NODE" "\$@" > "\$HOLD.out"; rc=\$?
      head -c 40 "\$HOLD.out"; : > "\$HOLD.started"
      n=0; while [ ! -f "\$HOLD" ] && [ "\$n" -lt 3000 ]; do sleep 0.1; n=\$((n + 1)); done
      tail -c +41 "\$HOLD.out"; exit \$rc
    fi
    exec "$REAL_NODE" "\$@" ;;
  */convert.js) exit 0 ;;
  *) exec "$REAL_NODE" "\$@" ;;
esac
STUB
chmod +x "$T/c/bin/node"
# A lock held by a save that is running, so both go on without it at once.
sleep 600 & HOLDER=$!
mkdir -p "$HC/.claude/.claude-html.lock"; echo "$HOLDER" > "$HC/.claude/.claude-html.lock/pid"
csave() {
  env HOME="$HC" CLAUDE_HTML_ROOT="$ROOTC" CLAUDE_HTML_OUT="$T/c/out" CLAUDE_HTML_ENGINE=node \
    CLAUDE_HTML_NODE_DIRS="$T/c/bin" PATH="$T/c/bin:$PATH" CLAUDE_HTML_DETACHED=1 CLAUDE_HTML_LOCK_WAIT=0 \
    CLAUDE_HTML_TRANSCRIPT="$JC" "$@" /bin/bash -c "cd '$APPC' && exec bash '$HERE/save-conversation.sh'" </dev/null >/dev/null 2>&1
}
csave HOLD="$T/c/hold" & FIRST=$!
n=0; while [ ! -f "$T/c/hold.started" ] && [ "$n" -lt 1200 ]; do sleep 0.1; n=$((n + 1)); done
reply "A LATER REPLY" >> "$JC"
csave
: > "$T/c/hold"; wait "$FIRST"
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null
check "two saves of one session at once leave a whole archive" \
  "$(node -e 'try { JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); console.log("whole"); } catch (e) { console.log("broken"); }' "$AC")" whole
check "  the one made from more of the transcript" \
  "$(head -c 200 "$AC" | sed -n 's/.*"sourceBytes":\([0-9]*\).*/\1/p') $(grep -c 'A LATER REPLY' "$AC")" "$(size_of "$JC") 1"
check "  and no half-written file behind" "$(ls -A "$APPC/.claude/.claude-conversations" | grep -c partial)" 0

# ── a lock whose process is gone, or whose pid is someone else's now ──
rm -rf "$HC/.claude/.claude-html.lock" "$AC"
mkdir -p "$HC/.claude/.claude-html.lock"
echo $$ > "$HC/.claude/.claude-html.lock/pid"
printf '%s Thu Jan  1 00:00:00 1970\n' $$ > "$HC/.claude/.claude-html.lock/owner"
env HOME="$HC" CLAUDE_HTML_ROOT="$ROOTC" CLAUDE_HTML_OUT="$T/c/out" CLAUDE_HTML_TRANSCRIPT="$JC" \
  /bin/bash -c "cd '$APPC' && exec bash '$HERE/save-conversation.sh' --try" </dev/null >/dev/null 2>&1
check "a lock whose pid now names another process does not stop a save" \
  "$([ -f "$AC" ] && echo saved) $([ -d "$HC/.claude/.claude-html.lock" ] && echo locked)" "saved "
sleep 600 & HOLDER=$!
mkdir -p "$HC/.claude/.claude-html.lock"; echo "$HOLDER" > "$HC/.claude/.claude-html.lock/pid"
env HOME="$HC" CLAUDE_HTML_ROOT="$ROOTC" CLAUDE_HTML_OUT="$T/c/out" CLAUDE_HTML_TRANSCRIPT="$JC" \
  /bin/bash -c "cd '$APPC' && exec bash '$HERE/save-conversation.sh' --try" </dev/null >/dev/null 2>&1
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null
check "a reply's save that gives way says so, and who holds the lock" \
  "$(grep -c "mode=gave-way holder=$HOLDER\$" "$T/c/out/.last-save" 2>/dev/null)" 1
rm -rf "$HC/.claude/.claude-html.lock"
# Two waiters that both found the lock left over: the second, finding it
# is no longer the one it judged, leaves the new one alone.
( HOME="$HC"; . "$HERE/lib/lock.sh"
  mkdir "$CH_LOCK"; printf '%s %s\n' $$ "$(ch_proc_start $$)" > "$CH_LOCK/owner"
  ch_lock_reclaim "999999 Thu Jan  1 00:00:00 1970" )
check "a left-over lock is taken away only while it is the one judged so" \
  "$([ -f "$HC/.claude/.claude-html.lock/owner" ] && echo kept)" kept
rm -rf "$HC/.claude/.claude-html.lock"

# The holder and a waiter in different time zones (or either side of a
# daylight-saving change): the same process, so the lock is still held.
# Taken in a subshell, so its holder is this script ($$ there), alive.
( HOME="$HC"; export TZ=America/New_York; . "$HERE/lib/lock.sh"; ch_lock_take 0 )
tzwait() {   # TZ -> live or stale, as a waiter there judges the lock
  ( HOME="$HC"; export TZ="$1"; . "$HERE/lib/lock.sh"
    ch_lock_stale "$(ch_lock_owner)" && echo stale || echo live )
}
check "a live lock is live to a waiter in another time zone" \
  "$(tzwait Asia/Tokyo) $(tzwait UTC0) $(tzwait America/New_York)" "live live live"
# Written by a release before 3.7.3: the start time alone, in local time.
rm -f "$HC/.claude/.claude-html.lock/started"
check "  and one an older release wrote is judged as it always was" "$(tzwait America/New_York)" live
sleep 600 & HOLDER=$!
echo "$HOLDER $(LC_ALL=C TZ=America/New_York ps -o lstart= -p "$HOLDER" | sed 's/^ *//; s/ *$//')" \
  > "$HC/.claude/.claude-html.lock/owner"
echo "not the key of that process" > "$HC/.claude/.claude-html.lock/started"
check "  while a pid now naming another process is still left over" "$(tzwait Asia/Tokyo)" stale
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null
rm -rf "$HC/.claude/.claude-html.lock"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
