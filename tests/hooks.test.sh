#!/bin/bash
# The hooks name their transcript on stdin, so a save need not search for it.
#
# The session here is filed under another directory and records another cwd,
# as after a project is renamed — so searching this folder's sessions cannot
# find it, and only the hook's note can. That is what tells the two apart.
#
#   bash tests/hooks.test.sh
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chhooks)" && pwd)"
trap 'rm -rf "$T"' EXIT

ROOT="$T/root"; APP="$ROOT/app"
D="$(printf '%s' "$APP" | tr '/' '-')"
mkdir -p "$T/home/.claude/projects/$D" "$T/home/.claude/projects/-elsewhere" "$APP" "$ROOT/pages"
printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$ROOT" "$ROOT/pages" \
  > "$T/home/.claude/claude-html.conf"

ID=eeeeeeee-0000-0000-0000-000000000005
J="$T/home/.claude/projects/-elsewhere/$ID.jsonl"
printf '%s\n' '{"type":"user","cwd":"/somewhere/old","timestamp":"2026-09-11T10:00:00Z","message":{"role":"user","content":"named by the hook"}}' > "$J"
A="$APP/.claude/.claude-conversations/$ID.json"
NOTE="{\"session_id\":\"$ID\",\"transcript_path\":\"$J\",\"cwd\":\"$APP\",\"hook_event_name\":\"Stop\"}"
save() { env HOME="$T/home" /bin/bash -c "cd '$APP' && /bin/bash '$HERE/save-conversation.sh' $1" >/dev/null 2>&1; }
found() { sed -n 's/.*found=\([a-z]*\).*/\1/p' "$ROOT/pages/.last-save" 2>/dev/null; }
exists() { [ -f "$1" ] && echo yes || echo no; }

save "" </dev/null
check "run by hand, it searches" "$(found)" search
check "  and cannot find a session filed elsewhere" "$(exists "$A")" no

printf '%s' "$NOTE" | save "--try"
check "given the hook's note, it does not search" "$(found)" hook
check "  and archives the session it names" "$(exists "$A")" yes

# The reply hook detaches, and the detached copy has no stdin: the note must
# survive the hand-off.
rm -f "$A"
printf '%s' "$NOTE" | save "--background"
for _ in $(seq 1 60); do [ -f "$A" ] && break; sleep 0.25; done
check "the detached save still knows which transcript" "$(exists "$A")" yes

# A save that fails must leave the last good archive where it was: the
# transcript it was made from may already have been cleaned up.
GOOD="$(cat "$A")"
# The detached save above may still hold the lock, and --try would give way.
for _ in $(seq 1 100); do [ -d "$T/home/.claude/.claude-html.lock" ] || break; sleep 0.1; done
printf '%s\n' '{"type":"user","cwd":"/somewhere/old","timestamp":"2026-09-11T10:01:00Z","message":{"role":"user","content":"more"}}' >> "$J"
chmod 000 "$J"
printf '%s' "$NOTE" | save "--try"
chmod 644 "$J"
check "a failed save keeps the previous archive" "$(cat "$A" 2>/dev/null)" "$GOOD"
check "  records the failure" "$(exists "$ROOT/pages/.archive-errors/$ID.json")" yes
check "  and leaves no partial file behind" \
  "$(ls -A "$APP/.claude/.claude-conversations" | grep -c partial)" 0

# Nor may one that is cut short, as a full disk leaves it: the engine exits
# cleanly having written only part. A stand-in node does exactly that.
mkdir -p "$T/shim"
printf '#!/bin/sh\nprintf %%s %s\n' "'{\"sourceBytes\":1,\"messages\":[{\"role\"'" > "$T/shim/node"
chmod +x "$T/shim/node"
rm -f "$ROOT/pages/.archive-errors/$ID.json"
printf '%s' "$NOTE" | env PATH="$T/shim:$PATH" CLAUDE_HTML_FORCE_NODE=1 \
  HOME="$T/home" /bin/bash -c "cd '$APP' && /bin/bash '$HERE/save-conversation.sh' --try" >/dev/null 2>&1
check "a save cut short keeps the previous archive" "$(cat "$A" 2>/dev/null)" "$GOOD"
check "  and records the failure" "$(exists "$ROOT/pages/.archive-errors/$ID.json")" yes
printf '%s' "$NOTE" | save "--try"
check "the next good save replaces it" "$(grep -c '"more"' "$A")" 1
check "  and clears the failure" "$(exists "$ROOT/pages/.archive-errors/$ID.json")" no

# An archive written before the format carried tokens and thinking is
# written again once while its transcript is still here, though the
# transcript has not grown — and only once.
check "an archive says which format it is" "$(head -c 200 "$A" | grep -c '"format":3,')" 1
python3 -c "
import json; p='$A'; a=json.load(open(p)); a.pop('format'); a.pop('usage'); a.pop('replies')
open(p,'w').write(json.dumps(a,separators=(',',':')))"
printf '%s' "$NOTE" | save "--try"
check "an older archive is brought up to date from the same transcript" \
  "$(head -c 200 "$A" | grep -c '"format":3,') $(grep -c '"usage":{' "$A")" "1 1"
touch -t 202001010000 "$A"
printf '%s' "$NOTE" | save "--try"
check "  and then left alone" "$(mtime_of "$A")" "$(touch -t 202001010000 "$T/ref" && mtime_of "$T/ref")"

# Cost arrived with format 3. A format 2 archive of a transcript that has
# stopped growing — a session long since ended, its final cost already
# written — is rewritten once, or the cost would be lost with the transcript.
printf '%s\n' '{"type":"cost-state","sessionId":"'"$ID"'","totalCostUSD":1.25,"startTime":1789000000000,"modelUsage":{"claude-opus-5":{"costUSD":1.25}}}' >> "$J"
printf '%s' "$NOTE" | save "--try"
python3 -c "
import json; p='$A'; a=json.load(open(p)); a['format']=2
for h in a['usage'].values():
    for m in h.values(): del m[5:]
open(p,'w').write(json.dumps(a,separators=(',',':')))"
printf '%s' "$NOTE" | save "--try"
check "a format 2 archive of an unchanged transcript is rewritten with its cost" \
  "$(head -c 200 "$A" | grep -c '"format":3,') $(python3 -c "
import json; a=json.load(open('$A'))
print(sum(m[5] for h in a['usage'].values() for m in h.values() if len(m)>5))")" "1 1250000"

# A nested folder the build cannot find on its own — the transcript is filed
# elsewhere and names another cwd — goes on the durable list when the hook
# archives there, so the build reads it once the transcript has expired.
NAPP="$ROOT/group/site"; mkdir -p "$NAPP"
NID=eeeeeeee-0000-0000-0000-000000000006
NJ="$T/home/.claude/projects/-elsewhere/$NID.jsonl"
printf '%s\n' '{"type":"user","cwd":"/somewhere/older","timestamp":"2026-09-11T10:00:00Z","message":{"role":"user","content":"nested"}}' > "$NJ"
LIST="$T/home/.claude/claude-html.archives"
check "the build has started the list" "$(exists "$LIST")" yes
printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$NID" "$NJ" "$NAPP" |
  env HOME="$T/home" /bin/bash -c "cd '$NAPP' && /bin/bash '$HERE/save-conversation.sh' --try" >/dev/null 2>&1
check "the hook puts a nested folder it archived into on the list" "$(grep -cxF "$NAPP" "$LIST")" 1
rm -f "$NJ"; rm -rf "$ROOT/pages"
HOME="$T/home" run_js "$HERE/convert.js" \
  "{\"root\":\"$ROOT\",\"out\":\"$ROOT/pages\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}" >/dev/null
check "  and with its transcript and the pages gone, the build still finds it" \
  "$(exists "$ROOT/pages/sessions/$NID.html")" yes
printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$ID" "$J" "$NAPP" |
  env HOME="$T/home" /bin/bash -c "cd '$NAPP' && /bin/bash '$HERE/save-conversation.sh' --try" >/dev/null 2>&1
check "  and a second save there does not list it twice" "$(grep -cxF "$NAPP" "$LIST")" 1

# Session end: Claude Code cancels a hook that is still running as it quits,
# so the save must hand itself off and return at once — and still happen.
rm -f "$A"
END_NOTE="{\"session_id\":\"$ID\",\"transcript_path\":\"$J\",\"cwd\":\"$APP\",\"hook_event_name\":\"SessionEnd\"}"
# hold the lock, as a save already in progress would, so a hook that waited
# for its turn in the foreground would visibly hang here
mkdir -p "$T/home/.claude/.claude-html.lock" && echo $$ > "$T/home/.claude/.claude-html.lock/pid"
start=$(date +%s)
printf '%s' "$END_NOTE" | save ""
took=$(( $(date +%s) - start ))
check "the session-end hook returns at once, even with another save running" \
  "$([ "$took" -le 2 ] && echo yes || echo "no, ${took}s")" yes
check "  and has not saved yet: it is waiting its turn in the background" "$(exists "$A")" no
rm -rf "$T/home/.claude/.claude-html.lock"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -f "$A" ] && break; sleep 0.5; done
check "  and the save still happens once it can" "$(exists "$A")" yes

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
