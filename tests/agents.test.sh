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

build() { HOME="$H" run_js "$HERE/build/convert.js" \
  "{\"root\":\"$ROOT\",\"out\":\"$OUT\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\",\"actions\":true}"; }
field() { node -e 'var m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
  var v=(m[process.argv[2]]||{})[process.argv[3]]; console.log(v===undefined?"":v)' "$OUT/.manifest.json" "$P" "$1"; }

build >/dev/null
check "the session is listed" "$(field project)" app
check "  and its sub-agent is not a session of its own" \
  "$(node -e 'var m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")), k=Object.keys(m);
  console.log(k.length, k.filter(function(x){return x.indexOf("agent-")===0;}).length)' "$OUT/.manifest.json")" "1 0"
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
# The crumb only carries a link where something can act on it, so the build is
# told that something can: a Linux runner with no handler installed would
# otherwise, correctly, leave it empty.
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

# A sub-agent caught while its last line is being written, cut inside a
# character: read all the same, by either engine, its tokens counted.
A2="$H/.claude/projects/$D/$P/subagents/agent-cut456.jsonl"
printf '{"type":"assistant","cwd":"%s","isSidechain":true,"timestamp":"2026-10-06T10:00:04Z","message":{"id":"msg_CUT","model":"claude-opus-5","role":"assistant","content":[{"type":"text","text":"CUT BUT READ é"}],"usage":{"input_tokens":3,"output_tokens":4,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$APP" > "$A2"
printf '{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"d\xc3' >> "$A2"
build >/dev/null
check "a sub-agent whose last line is cut inside a character still has its page" \
  "$(grep -c 'CUT BUT READ' "$OUT/sessions/$P/agent-cut456.html" 2>/dev/null)" 1
check "  and its tokens count" "$(grep -c '"tok":\[3,4,' "$OUT/.manifest.json")" 1
# One that cannot be read at all is said, not dropped in silence.
printf '{}\n' > "$H/.claude/projects/$D/$P/subagents/agent-bad789.jsonl"
chmod 000 "$H/.claude/projects/$D/$P/subagents/agent-bad789.jsonl"
check "a sub-agent that cannot be read is reported" "$(build | grep -c 'agent-bad789.jsonl.*could not be read')" 1
rm -f "$H/.claude/projects/$D/$P/subagents/agent-bad789.jsonl"

echo
verdict
