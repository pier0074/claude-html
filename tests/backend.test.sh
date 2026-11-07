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
  # What Claude Code says it cost: running totals, floats that do not add up
  # exactly, a restart — the arithmetic both engines must agree on.
  printf '{"type":"assistant","sessionId":"%s","cwd":"%s","timestamp":"2026-10-06T10:00:06Z","message":{"id":"msg_B1","model":"claude-opus-5","usage":{"input_tokens":3,"output_tokens":40,"cache_read_input_tokens":900,"cache_creation_input_tokens":7},"role":"assistant","content":[{"type":"text","text":"costed"}]}}\n' "$P" "$APP"
  printf '{"type":"cost-state","sessionId":"%s","startTime":1791277200000,"totalCostUSD":0.3,"modelUsage":{"claude-opus-5":{"costUSD":0.30000000000000004},"claude-haiku-4-5-20251001":{"costUSD":0.0009545}}}\n' "$P"
  printf '{"type":"user","cwd":"%s","timestamp":"2026-10-06T11:30:00Z","message":{"role":"user","content":"more"}}\n' "$APP"
  printf '{"type":"cost-state","sessionId":"%s","startTime":1791277200000,"totalCostUSD":1.1,"modelUsage":{"claude-opus-5":{"costUSD":1.1000000000000003},"claude-haiku-4-5-20251001":{"costUSD":0.0009545}}}\n' "$P"
  printf '{"type":"cost-state","sessionId":"%s","startTime":1791290000000,"totalCostUSD":0.2,"modelUsage":{"claude-opus-5":{"costUSD":0.2}}}\n' "$P"
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

check "  with the session's cost, as whole micro-dollars" \
  "$(node -e 'var h=require("fs").readFileSync(process.argv[1],"utf8");
    var d=JSON.parse(/id="index-data">([\s\S]*?)<\/script>/.exec(h)[1]);
    console.log(d.sessions.filter(function(s){return s.tok}).map(function(s){return s.tok[5]+" "+!!s.costPart}).join())' "$NOUT/index.html")" \
  "1300955 false"

# a second run must be a no-op under node too
check "node skips what has not changed" \
  "$(HOME="$H" node "$HERE/convert.js" "$(opts "$NOUT")" | sed -n 's/.*"built":\([0-9]*\).*/\1/p')" 0

# ── and byte for byte what osascript builds ─────────────────────────
if command -v osascript >/dev/null 2>&1; then
  JOUT="$T/out-jxa"
  HOME="$H" osascript -l JavaScript "$HERE/convert.js" "$(opts "$JOUT")" >/dev/null
  # Both are on this mac, whichever engine built them, so both offer the
  # macOS-only controls: node here must not hide a working delete button.
  check "osascript tells the index it is on a mac" "$(grep -c '"mac":true}' "$JOUT/index.html")" 1
  check "  and so does node on the same mac" "$(grep -c '"mac":true}' "$NOUT/index.html")" 1
  # And when: the two builds are seconds apart, which the index rightly says.
  check "both say when they were built" \
    "$(cat "$JOUT/index.html" "$NOUT/index.html" | grep -c '"built":[0-9]\{10\},')" 2
  for f in "$JOUT/index.html" "$NOUT/index.html"; do
    sed 's/"built":[0-9]*,/"built":0,/' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  done
  # Launchers differ only by their out path, which the two builds must have,
  # so compare them after erasing that one difference.
  DIFF="$(diff -r "$JOUT" "$NOUT" 2>&1 | grep -v "^Binary" ; true)"
  DIFF="$(printf '%s' "$DIFF" | sed "s|$JOUT|OUT|g; s|$NOUT|OUT|g" | sort -u | grep -v '^$' || true)"
  check "both runtimes produce byte-identical output" "${DIFF:-identical}" identical
else
  printf '  skip  no osascript here — the comparison half runs on macOS\n'
fi

# ── the rest runs under whichever engine lib.sh picked ──────────────
build() { HOME="$2" run_js "$HERE/convert.js" "$1"; }
num() { sed -n "s/.*\"$1\":\([0-9]*\).*/\1/p"; }
has() { [ -s "$1" ] && echo yes || echo no; }
# The page's data, back out of its script element and through JSON.parse.
data() {
  node -e 'var h=require("fs").readFileSync(process.argv[1],"utf8");
    var m=/id="(?:session|index|usage)-data">([\s\S]*?)<\/script>/.exec(h);
    var d=JSON.parse(m[1]); console.log(JSON.stringify(eval(process.argv[2])));' "$1" "$2" 2>/dev/null
}

# ── a project nested below the root keeps its conversations ─────────
# The hook archives wherever a session ran, so an archive two levels down
# must still be found once Claude Code has cleaned the transcript away.
N="$T/nested"; NR="$N/root"; NAPP="$NR/group/website"; NH="$N/home"; NO="$N/out"
ND="$(printf '%s' "$NAPP" | tr '/' '-')"
S1=33333333-0000-0000-0000-000000000001
S2=33333333-0000-0000-0000-000000000002
mkdir -p "$NH/.claude/projects/$ND" "$NAPP/.claude/.claude-conversations"
printf '{"type":"user","cwd":"%s","timestamp":"2026-10-06T10:00:00Z","message":{"role":"user","content":"a nested question"}}\n' "$NAPP" \
  > "$NH/.claude/projects/$ND/$S1.jsonl"
printf '{"sessionId":"%s","project":"%s","messages":[{"role":"user","text":"a nested question"},{"role":"assistant","text":"an answer kept in the archive"}]}\n' "$S1" "$NAPP" \
  > "$NAPP/.claude/.claude-conversations/$S1.json"
# A second session from the same folder whose transcript is already gone.
printf '{"sessionId":"%s","project":"%s","messages":[{"role":"user","text":"an older nested question"},{"role":"assistant","text":"older answer"}]}\n' "$S2" "$NAPP" \
  > "$NAPP/.claude/.claude-conversations/$S2.json"
NOPT="{\"root\":\"$NR\",\"out\":\"$NO\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}"
R="$(build "$NOPT" "$NH")"
check "a nested project builds" "$(printf '%s' "$R" | num sessions)" 2
check "  its archive-only sibling is found through the live transcript" "$(has "$NO/sessions/$S2.html")" yes
check "  named after its own folder" "$(data "$NO/sessions/$S2.html" 'd.meta.project')" '"website"'
rm "$NH/.claude/projects/$ND/$S1.jsonl"
R="$(build "$NOPT" "$NH")"
check "with its transcript gone, nothing is removed" "$(printf '%s' "$R" | num removed)" 0
check "  the page survives" "$(has "$NO/sessions/$S1.html")" yes
check "  rebuilt from the nested archive" "$(data "$NO/sessions/$S1.html" 'd.meta.kind')" '"archive"'
check "  with the archive's answer on it" \
  "$(grep -c 'an answer kept in the archive' "$NO/sessions/$S1.html")" 1
check "  and its search file kept" "$(has "$NO/search/$S1.js")" yes
check "  and both still on the index" "$(data "$NO/index.html" 'd.sessions.length')" 2

# The folder is remembered outside the pages, so neither a lost manifest nor
# a lost output folder forgets it once no transcript names it any more.
check "the nested folder is on the durable list" \
  "$(grep -cxF "$NAPP" "$NH/.claude/claude-html.archives")" 1
rm "$NO/.manifest.json"
R="$(build "$NOPT" "$NH")"
check "with the manifest gone, nothing is removed" "$(printf '%s' "$R" | num removed)" 0
check "  and both nested archives are still read" "$(data "$NO/index.html" 'd.sessions.length')" 2
rm -rf "$NO"
build "$NOPT" "$NH" >/dev/null
check "with the whole output folder gone, both pages come back" \
  "$(has "$NO/sessions/$S1.html") $(has "$NO/sessions/$S2.html")" "yes yes"
check "  from the archives" "$(data "$NO/sessions/$S2.html" 'd.meta.kind')" '"archive"'
# No list at all — an upgrade, or a new machine — and the root is walked once.
rm -rf "$NO" "$NH/.claude/claude-html.archives"
build "$NOPT" "$NH" >/dev/null
check "with no list, a walk of the root finds them" \
  "$(has "$NO/sessions/$S1.html") $(has "$NO/sessions/$S2.html")" "yes yes"
check "  and writes the list again" "$(grep -cxF "$NAPP" "$NH/.claude/claude-html.archives")" 1
# A listed folder that is gone is let go; one under another root is kept.
mkdir -p "$N/other/app/.claude/.claude-conversations"
printf '%s\n' "$N/gone/app" "$N/other/app" >> "$NH/.claude/claude-html.archives"
build "$NOPT" "$NH" >/dev/null
check "a listed folder that no longer exists is dropped" \
  "$(grep -c "$N/gone/app" "$NH/.claude/claude-html.archives")" 0
check "  one under another root is kept for that root's builds" \
  "$(grep -cxF "$N/other/app" "$NH/.claude/claude-html.archives")" 1
check "  and the rest of the list stays" \
  "$(grep -cxF "$NAPP" "$NH/.claude/claude-html.archives")" 1

# A session run in the root itself archives into the root's own .claude.
S3=33333333-0000-0000-0000-000000000003
mkdir -p "$NR/.claude/.claude-conversations"
printf '{"sessionId":"%s","project":"%s","messages":[{"role":"user","text":"asked at the root"},{"role":"assistant","text":"ok"}]}\n' "$S3" "$NR" \
  > "$NR/.claude/.claude-conversations/$S3.json"
build "$NOPT" "$NH" >/dev/null
check "an archive in the root itself is found" "$(has "$NO/sessions/$S3.html")" yes

# ── CLAUDE_HTML_EXPORT names an export the build would not find alone ──
E="$T/env"; mkdir -p "$E/home" "$E/elsewhere"
EW=eeeeeeee-0000-0000-0000-000000000005
cat > "$E/elsewhere/conversations.json" <<JSON
[{"uuid":"$EW","name":"Found by name","created_at":"2026-05-01T10:00:00Z",
  "updated_at":"2026-05-01T11:00:00Z","chat_messages":[
  {"sender":"human","created_at":"2026-05-01T10:00:00Z","content":[{"type":"text","text":"list the files"}]},
  {"sender":"assistant","created_at":"2026-05-01T10:00:05Z","content":[
    {"type":"text","text":"Let me look."},
    {"type":"tool_use","id":"tu_1","name":"bash","input":{"command":"ls"}},
    {"type":"tool_result","tool_use_id":"tu_1","content":[{"type":"text","text":"a.txt b.txt"}]},
    {"type":"text","text":"Two files."}]}]}]
JSON
EOPT="{\"root\":\"$E/root\",\"out\":\"$E/out\",\"projects\":\"$E/projects\",\"here\":\"$HERE\"}"
R="$(CLAUDE_HTML_EXPORT="$E/elsewhere/conversations.json" build "$EOPT" "$E/home")"
check "CLAUDE_HTML_EXPORT is read" "$(has "$E/out/sessions/$EW.html")" yes

# ── an export's tool output follows the call that produced it ──────
check "export roles come out in the order they happened" \
  "$(data "$E/out/sessions/$EW.html" 'd.messages.map(function(m){return m.role}).join(" ")')" \
  '"user assistant tool_result assistant"'
check "  the call is in the turn before its output" \
  "$(data "$E/out/sessions/$EW.html" 'd.messages[1].text + "|" + d.messages[1].tools[0].id')" \
  '"Let me look.|tu_1"'
check "  and the text after it, after it" "$(data "$E/out/sessions/$EW.html" 'd.messages[3].text')" '"Two files."'

# ── a reply copied into a resumed session counts once on the dashboard ──
U="$T/dup"; UR="$U/root"; UAPP="$UR/app"; UH="$U/home"; UO="$U/out"
UD="$(printf '%s' "$UAPP" | tr '/' '-')"
mkdir -p "$UH/.claude/projects/$UD" "$UAPP"
SRC=44444444-0000-0000-0000-000000000001
FORK=44444444-0000-0000-0000-000000000002
reply() {   # id, output tokens, hour
  printf '{"type":"assistant","cwd":"%s","timestamp":"2026-10-06T%s:00:01Z","message":{"id":"%s","model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":%s,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"role":"assistant","content":[{"type":"text","text":"r"}]}}\n' "$UAPP" "$3" "$1" "$2"
}
ask() { printf '{"type":"user","cwd":"%s","timestamp":"2026-10-06T%s:00:00Z","message":{"role":"user","content":"%s"}}\n' "$UAPP" "$2" "$1"; }
{ ask first 10; reply msg_ONE 100 10; } > "$UH/.claude/projects/$UD/$SRC.jsonl"
UOPT="{\"root\":\"$UR\",\"out\":\"$UO\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}"
total() { data "$UO/usage.html" 'Object.keys(d.byProject).reduce(function(s,p){return Object.keys(d.byProject[p]).reduce(function(s,h){return Object.keys(d.byProject[p][h]).reduce(function(s,m){return s+d.byProject[p][h][m][1]},s)},s)},0)'; }
replies() { data "$UO/usage.html" 'Object.keys(d.byProject).reduce(function(s,p){return Object.keys(d.byProject[p]).reduce(function(s,h){return Object.keys(d.byProject[p][h]).reduce(function(s,m){return s+d.byProject[p][h][m][4]},s)},s)},0)'; }
build "$UOPT" "$UH" >/dev/null
check "one session, one reply" "$(total)" 100
# The resumed session carries a copy of the first reply, then one of its own.
sleep 1
{ ask first 10; reply msg_ONE 100 10; ask second 11; reply msg_TWO 20 11; } > "$UH/.claude/projects/$UD/$FORK.jsonl"
build "$UOPT" "$UH" >/dev/null
check "a copied reply is counted once across sessions" "$(total)" 120
check "  and is one reply, not two" "$(replies)" 2
check "  while the resumed session's own total keeps it" \
  "$(data "$UO/index.html" 'd.sessions.filter(function(s){return s.id==="'$FORK'"})[0].tok[1]')" 120
check "  and the index carries no reply keys" "$(grep -c '"ids"' "$UO/index.html")" 0
# From scratch, both built in one run, in either order, the answer is the same.
rm -rf "$UO"; build "$UOPT" "$UH" >/dev/null
check "  the same from a clean build" "$(total)" 120
build "$(printf '{"root":"%s","out":"%s","here":"%s","exportPath":"/nonexistent","force":true}' "$UR" "$UO" "$HERE")" "$UH" >/dev/null
check "  and from a forced rebuild over a full manifest" "$(total)" 120

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
