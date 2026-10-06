#!/bin/bash
# One converter, two runtimes. osascript carries it on macOS and node
# everywhere else, and the proof that they are the same program is that they
# produce the same bytes: the same fixture, built by each, diffed whole.
#
#   bash tests/backend.test.sh
# On a machine without osascript (Linux), the comparison half is skipped and
# the node half still has to produce a correct build on its own.
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chbackend)" && pwd)"
trap 'rm -rf "$T"' EXIT

# A fixture with every kind of thing in it: a session with a sub-agent, an
# archive-only session, and a claude.ai export.
ROOT="$T/root"; APP="$ROOT/app"; H="$T/home"
D="$(printf '%s' "$APP" | tr '/' '-')"
P=11111111-2222-3333-4444-555555555555
Q=22222222-3333-4444-5555-666666666666
W=cccccccc-0000-0000-0000-000000000003
mkdir -p "$H/.claude/projects/$D/$P/subagents" "$APP/.claude/.claude-conversations"

{
  printf '{"type":"user","cwd":"%s","timestamp":"2026-10-06T10:00:00Z","message":{"role":"user","content":"audit this — and mind the unicode: déjà vu 🙂"}}\n' "$APP"
  printf '{"type":"assistant","cwd":"%s","timestamp":"2026-10-06T10:00:01Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_TEST","name":"Task","input":{"description":"check the backend"}}]}}\n' "$APP"
  printf '{"type":"assistant","cwd":"%s","timestamp":"2026-10-06T10:00:05Z","message":{"role":"assistant","content":[{"type":"text","text":"All done."}]}}\n' "$APP"
} > "$H/.claude/projects/$D/$P.jsonl"

A="$H/.claude/projects/$D/$P/subagents/agent-abc123.jsonl"
printf '{"type":"user","cwd":"%s","isSidechain":true,"timestamp":"2026-10-06T10:00:02Z","message":{"role":"user","content":"You are checking the backend"}}\n' "$APP" > "$A"
printf '{"type":"assistant","cwd":"%s","isSidechain":true,"timestamp":"2026-10-06T10:00:03Z","message":{"role":"assistant","content":[{"type":"text","text":"FOUND SOMETHING"}]}}\n' "$APP" >> "$A"
printf '{"agentType":"general-purpose","description":"check the backend","toolUseId":"toolu_TEST","model":"opus"}\n' \
  > "$H/.claude/projects/$D/$P/subagents/agent-abc123.meta.json"

printf '{"session_id":"%s","cwd":"%s","messages":[{"role":"user","text":"an archived question"},{"role":"assistant","text":"an archived answer"}]}\n' "$Q" "$APP" \
  > "$APP/.claude/.claude-conversations/$Q.json"

X="$T/conversations.json"
cat > "$X" <<JSON
[{"uuid":"$W","name":"A web chat","created_at":"2026-05-01T10:00:00Z",
  "updated_at":"2026-05-01T11:00:00Z","chat_messages":[
  {"sender":"human","created_at":"2026-05-01T10:00:00Z","content":[{"type":"text","text":"a question from the web"}]},
  {"sender":"assistant","created_at":"2026-05-01T10:00:05Z","content":[{"type":"text","text":"an answer"}]}]}]
JSON

opts() { printf '{"root":"%s","out":"%s","here":"%s","exportPath":"%s"}' "$ROOT" "$1" "$HERE" "$X"; }

# ── node builds it, wherever we are ─────────────────────────────────
NOUT="$T/out-node"
R="$(HOME="$H" node "$HERE/convert.js" "$(opts "$NOUT")")"
check "node builds the fixture" \
  "$(printf '%s' "$R" | sed -n 's/.*"sessions":\([0-9]*\).*/\1/p')" 3
check "  with no errors" "$(printf '%s' "$R" | grep -c '"error":')" 0
check "  the session page exists" "$([ -s "$NOUT/sessions/$P.html" ] && echo yes || echo no)" yes
check "  the sub-agent page exists" "$([ -s "$NOUT/sessions/$P/agent-abc123.html" ] && echo yes || echo no)" yes
check "  the index exists" "$([ -s "$NOUT/index.html" ] && echo yes || echo no)" yes
check "  search is written per session" "$(ls "$NOUT/search" | grep -c '\.js$')" 3

# a second run must be a no-op under node too
check "node skips what has not changed" \
  "$(HOME="$H" node "$HERE/convert.js" "$(opts "$NOUT")" | sed -n 's/.*"built":\([0-9]*\).*/\1/p')" 0

# ── and byte for byte what osascript builds ─────────────────────────
if command -v osascript >/dev/null 2>&1; then
  JOUT="$T/out-jxa"
  HOME="$H" osascript -l JavaScript "$HERE/convert.js" "$(opts "$JOUT")" >/dev/null
  # Launchers differ only by their out path, which the two builds must have,
  # so compare them after erasing that one difference.
  DIFF="$(diff -r "$JOUT" "$NOUT" 2>&1 | grep -v "^Binary" ; true)"
  DIFF="$(printf '%s' "$DIFF" | sed "s|$JOUT|OUT|g; s|$NOUT|OUT|g" | sort -u | grep -v '^$' || true)"
  check "both runtimes produce byte-identical output" "${DIFF:-identical}" identical
else
  printf '  skip  no osascript here — the comparison half runs on macOS\n'
fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
