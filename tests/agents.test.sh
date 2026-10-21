#!/bin/bash
# Sub-agents belong to the conversation that spawned them.
#
# Claude Code writes each one as its own transcript, in <session>/subagents,
# with a .meta.json naming the Task call behind it. Left alone, each appeared
# on the index as a conversation of its own: seventy-six rows for one session.
#
#   bash tests/agents.test.sh
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chagents)" && pwd)"
trap 'rm -rf "$T"' EXIT

ROOT="$T/root"; APP="$ROOT/app"; OUT="$ROOT/pages"; H="$T/home"
D="$(printf '%s' "$APP" | tr '/' '-')"
P=11111111-2222-3333-4444-555555555555
mkdir -p "$H/.claude/projects/$D/$P/subagents" "$APP" "$OUT"
printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$ROOT" "$OUT" > "$H/.claude/claude-html.conf"

# The parent: a question, then a Task call that spawns the sub-agent.
{
  printf '{"type":"user","cwd":"%s","timestamp":"2026-10-06T10:00:00Z","message":{"role":"user","content":"audit this"}}\n' "$APP"
  printf '{"type":"assistant","cwd":"%s","timestamp":"2026-10-06T10:00:01Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_TEST","name":"Task","input":{"description":"check the backend"}}]}}\n' "$APP"
} > "$H/.claude/projects/$D/$P.jsonl"

A="$H/.claude/projects/$D/$P/subagents/agent-abc123.jsonl"
printf '{"type":"user","cwd":"%s","isSidechain":true,"timestamp":"2026-10-06T10:00:02Z","message":{"role":"user","content":"You are checking the backend"}}\n' "$APP" > "$A"
printf '{"type":"assistant","cwd":"%s","isSidechain":true,"timestamp":"2026-10-06T10:00:03Z","message":{"role":"assistant","content":[{"type":"text","text":"THE AGENT FOUND SOMETHING"}]}}\n' "$APP" >> "$A"
printf '{"agentType":"general-purpose","description":"check the backend","toolUseId":"toolu_TEST","model":"opus"}\n' \
  > "$H/.claude/projects/$D/$P/subagents/agent-abc123.meta.json"

build() { HOME="$H" run_js "$HERE/convert.js" \
  "{\"root\":\"$ROOT\",\"out\":\"$OUT\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}"; }
field() { python3 -c "
import json,sys,pathlib
m=json.loads(pathlib.Path('$OUT/.manifest.json').read_text())
print(m.get('$P',{}).get('$1',''))"; }

build >/dev/null
check "the session is listed" "$(field project)" app
check "  and its sub-agent is not a session of its own" \
  "$(python3 -c "
import json,pathlib
m=json.loads(pathlib.Path('$OUT/.manifest.json').read_text())
print(len(m), sum(1 for k in m if k.startswith('agent-')))")" "1 0"
check "  the session says it had one" "$(field agents)" 1
check "the sub-agent has a page" \
  "$([ -s "$OUT/sessions/$P/agent-abc123.html" ] && echo yes || echo no)" yes
check "  holding what it said" \
  "$(grep -c 'THE AGENT FOUND SOMETHING' "$OUT/sessions/$P/agent-abc123.html")" 1
check "  and saying whose it is" \
  "$(grep -c '"parent"' "$OUT/sessions/$P/agent-abc123.html")" 1
check "the parent links to it, by the call that spawned it" \
  "$(grep -c 'toolu_TEST' "$OUT/sessions/$P.html")" 1
check "  and the parent keeps the sub-agent's text out of its own page" \
  "$(grep -c 'THE AGENT FOUND SOMETHING' "$OUT/sessions/$P.html")" 0

check "nothing to do on a second run" "$(build | sed -n 's/.*"built":\([0-9]*\).*/\1/p')" 0
printf '{"type":"assistant","cwd":"%s","isSidechain":true,"timestamp":"2026-10-06T10:00:04Z","message":{"role":"assistant","content":[{"type":"text","text":"ONE MORE THING"}]}}\n' "$APP" >> "$A"
check "a sub-agent that grows rebuilds its session" \
  "$(build | sed -n 's/.*"built":\([0-9]*\).*/\1/p')" 1
check "  and its own page has the new message" \
  "$(grep -c 'ONE MORE THING' "$OUT/sessions/$P/agent-abc123.html")" 1

# The breadcrumb at the top of a page is built from meta, so what the page
# can do depends on what the converter put there. A sub-agent has no folder of
# its own, and has to borrow its parent's to be able to open the project.
check "the session carries what its project crumb opens" \
  "$(grep -c "\"open\":\"$P\"" "$OUT/sessions/$P.html")" 1
check "  and the sub-agent inherits it, having no folder of its own" \
  "$(grep -c "\"open\":\"$P\"" "$OUT/sessions/$P/agent-abc123.html")" 1
check "  and the sub-agent page knows one folder deeper is home" \
  "$(grep -c '"up":"../../index.html"' "$OUT/sessions/$P/agent-abc123.html")" 1

# The hook archived them as conversations, because its fallback search is
# recursive and they record the same working directory.
env HOME="$H" /bin/bash -c "cd '$APP' && /bin/bash '$HERE/save-conversation.sh'" </dev/null >/dev/null 2>&1
check "the hook archives the session" \
  "$([ -s "$APP/.claude/.claude-conversations/$P.json" ] && echo yes || echo no)" yes
check "  and not its sub-agents" \
  "$(ls "$APP/.claude/.claude-conversations" | grep -c '^agent-')" 0

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
