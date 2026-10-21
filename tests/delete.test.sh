#!/bin/bash
# Deleting a conversation: everything that belongs to it goes, nothing else
# does, a conversation still open is refused, and a claude.ai chat is hidden.
#
# Runs in a home of its own, and a plain directory stands in for the Trash, so
# nothing real is touched.
#
#   bash tests/delete.test.sh
set -u

. "$(dirname "$0")/lib.sh"
need_osascript "the Trash helper"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chdelete)" && pwd)"
trap 'rm -rf "$T"' EXIT

H="$T/home"; ROOT="$T/root"; APP="$ROOT/app"; OUT="$ROOT/pages"; TRASH="$T/trash"
D="$(printf '%s' "$APP" | tr '/' '-')"
A=aaaaaaaa-1111-1111-1111-000000000001      # the one to delete
B=bbbbbbbb-2222-2222-2222-000000000002      # a neighbour that must survive
mkdir -p "$H/.claude/projects/$D/$A" "$H/.claude/file-history/$A" "$H/.claude/session-env/$A" \
         "$H/.claude/sessions" "$APP/.claude/.claude-conversations" "$OUT"
printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$ROOT" "$OUT" > "$H/.claude/claude-html.conf"
line() { printf '{"type":"user","cwd":"%s","timestamp":"2026-09-11T10:00:00Z","message":{"role":"user","content":"%s"}}\n' "$APP" "$1"; }
line "the one to delete" > "$H/.claude/projects/$D/$A.jsonl"
line "a sub-agent"       > "$H/.claude/projects/$D/$A/agent.jsonl"
echo snapshot            > "$H/.claude/file-history/$A/edit-1"
line "the neighbour"     > "$H/.claude/projects/$D/$B.jsonl"
printf '{"sessionId":"%s","messages":[{"role":"user","text":"archived"}]}\n' "$A" \
  > "$APP/.claude/.claude-conversations/$A.json"
{
  printf '{"display":"first","sessionId":"%s","timestamp":1}\n' "$A"
  printf '{"display":"neighbour","sessionId":"%s","timestamp":2}\n' "$B"
  printf '{"display":"second","sessionId":"%s","timestamp":3}\n' "$A"
  printf '{"display":"no session","timestamp":4}\n'
} > "$H/.claude/history.jsonl"

cli() { env HOME="$H" CLAUDE_HTML_TRASH="$TRASH" /bin/bash "$HERE/claude-html" "$@" </dev/null 2>&1; }
build() { HOME="$H" run_js "$HERE/convert.js" \
  "{\"root\":\"$ROOT\",\"out\":\"$OUT\",\"here\":\"$HERE\",\"exportPath\":\"${1:-/nonexistent}\"}" >/dev/null; }
gone() { [ -e "$1" ] && echo still-there || echo gone; }
listed() { grep -q "$1" "$OUT/index.html" && echo listed || echo absent; }
build

# ── the plan ────────────────────────────────────────────────────────
PLAN="$(cli --delete-plan "$A")"
check "the plan offers to trash it" "$(printf '%s\n' "$PLAN" | awk -F'\t' '$1=="ACTION"{print $2}')" trash
check "  and names every piece" "$(printf '%s\n' "$PLAN" | grep -c '^ITEM')" 8
check "  and its two history prompts" "$(printf '%s\n' "$PLAN" | awk -F'\t' '$1=="HISTORY"{print $2}')" 2
check "  and changes nothing by itself" "$(gone "$H/.claude/projects/$D/$A.jsonl")" still-there

# ── a refusal ───────────────────────────────────────────────────────
printf '{"sessionId":"%s","pid":%s}\n' "$B" "$$" > "$H/.claude/sessions/$$.json"
cli --delete "$B" --yes >/dev/null
check "a conversation still open is refused" "$(gone "$H/.claude/projects/$D/$B.jsonl")" still-there
rm -f "$H/.claude/sessions/$$.json"
check "a partial id is refused" "$(cli --delete aaaaaaaa --yes >/dev/null; echo $?)" 2
cli --delete "$A" </dev/null >/dev/null     # no --yes and no terminal: it must not go ahead
check "without confirmation, nothing happens" "$(gone "$H/.claude/projects/$D/$A.jsonl")" still-there

# ── the delete ──────────────────────────────────────────────────────
cli --delete "$A" --yes >/dev/null
for f in "$H/.claude/projects/$D/$A.jsonl" "$H/.claude/projects/$D/$A" \
         "$H/.claude/file-history/$A" "$H/.claude/session-env/$A" \
         "$APP/.claude/.claude-conversations/$A.json" "$OUT/sessions/$A.html" "$OUT/search/$A.js"; do
  check "gone: ${f#$T/}" "$(gone "$f")" gone
done
check "everything went to the Trash, not away" "$(ls "$TRASH" | wc -l | tr -d ' ')" 9
check "its prompts left the history" "$(grep -c "$A" "$H/.claude/history.jsonl")" 0
check "  and a copy of them is in the Trash" "$(cat "$TRASH"/*removed\ history* | grep -c "$A")" 2
check "the neighbour's prompt stayed" "$(grep -c "$B" "$H/.claude/history.jsonl")" 1
check "  and so did the prompt with no session" "$(grep -c '"no session"' "$H/.claude/history.jsonl")" 1
check "the index no longer lists it" "$(listed "$A")" absent
check "the neighbour is still listed" "$(listed "$B")" listed
check "  and still has its transcript" "$(gone "$H/.claude/projects/$D/$B.jsonl")" still-there

# ── a claude.ai chat ────────────────────────────────────────────────
W=cccccccc-3333-3333-3333-000000000003
X="$T/conversations.json"
printf '[{"uuid":"%s","name":"a web chat","updated_at":"2026-05-01T11:00:00Z","chat_messages":[{"sender":"human","created_at":"2026-05-01T10:00:00Z","content":[{"type":"text","text":"from the web"}]}]}]\n' "$W" > "$X"
build "$X"
check "a web chat is listed" "$(listed "$W")" listed
check "  its plan is to hide it" "$(cli --delete-plan "$W" | awk -F'\t' '$1=="ACTION"{print $2}')" hide
cli --delete "$W" --yes >/dev/null
build "$X"
check "hidden, it stays off the index even with the export unchanged" "$(listed "$W")" absent
check "  and the export itself is untouched" "$(grep -c "$W" "$X")" 1

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
