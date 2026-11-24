#!/bin/bash
# The token dashboard. What must never be wrong: a reply written as several
# records (one message id) counts once, not once per record; a sub-agent's
# tokens land in its parent's total; and a build where nothing changed still
# knows every session's usage, because the manifest carries it.
#
#   bash tests/usage.test.sh
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/lib.sh"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chusage)" && pwd)"
trap 'rm -rf "$T"' EXIT

ROOT="$T/root"; APP="$ROOT/app"; OUT="$T/out"; H="$T/home"
D="$(printf '%s' "$APP" | tr '/' '-')"
P=11111111-2222-3333-4444-555555555555
mkdir -p "$H/.claude/projects/$D/$P/subagents" "$APP"

J="$H/.claude/projects/$D/$P.jsonl"
{
  printf '{"type":"user","cwd":"%s","timestamp":"2026-10-06T10:00:00Z","message":{"role":"user","content":"hello"}}\n' "$APP"
  # one reply, two records, same message id: usage-so-far then final — only the final 222 may count
  printf '{"type":"assistant","cwd":"%s","timestamp":"2026-10-06T10:00:01Z","message":{"id":"msg_A","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":111,"cache_read_input_tokens":1000,"cache_creation_input_tokens":50},"role":"assistant","content":[{"type":"text","text":"part"}]}}\n' "$APP"
  printf '{"type":"assistant","cwd":"%s","timestamp":"2026-10-06T10:00:02Z","message":{"id":"msg_A","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":222,"cache_read_input_tokens":1000,"cache_creation_input_tokens":50},"role":"assistant","content":[{"type":"text","text":"whole"}]}}\n' "$APP"
  # another model, another day
  printf '{"type":"assistant","cwd":"%s","timestamp":"2026-10-07T09:00:00Z","message":{"id":"msg_B","model":"claude-haiku-4-5-20251001","usage":{"input_tokens":5,"output_tokens":555,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"role":"assistant","content":[{"type":"text","text":"more"}]}}\n' "$APP"
} > "$J"

A="$H/.claude/projects/$D/$P/subagents/agent-abc123.jsonl"
{
  printf '{"type":"user","cwd":"%s","isSidechain":true,"timestamp":"2026-10-06T10:00:03Z","message":{"role":"user","content":"task"}}\n' "$APP"
  printf '{"type":"assistant","cwd":"%s","isSidechain":true,"timestamp":"2026-10-06T10:00:04Z","message":{"id":"msg_C","model":"claude-opus-5","usage":{"input_tokens":7,"output_tokens":777,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"role":"assistant","content":[{"type":"text","text":"done"}]}}\n' "$APP"
} > "$A"
printf '{"agentType":"general-purpose","description":"task","toolUseId":"t1","model":"opus"}\n' \
  > "$H/.claude/projects/$D/$P/subagents/agent-abc123.meta.json"

build() { HOME="$H" run_js "$HERE/build/convert.js" \
  "{\"root\":\"$ROOT\",\"out\":\"$OUT\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}"; }
# A JavaScript expression over d, the JSON on stdin (or, with a file and an
# id, the JSON a page embeds there), printed as a list or a word would be
# read: [1, 2], True, None.
js() {
  node -e '
    var fs = require("fs"), a = process.argv;
    var d = a[2] ? JSON.parse(new RegExp("id=\"" + a[3] + "\">([\\s\\S]*?)</script>").exec(fs.readFileSync(a[2], "utf8"))[1])
                 : JSON.parse(fs.readFileSync(0, "utf8"));
    function py(v, inner) {
      if (v === null || v === undefined) return "None";
      if (v === true) return "True"; if (v === false) return "False";
      if (Array.isArray(v)) return "[" + v.map(function (x) { return py(x, 1); }).join(", ") + "]";
      if (typeof v === "string") return inner ? "\x27" + v + "\x27" : v;
      if (typeof v === "object") return JSON.stringify(v);
      return String(v);
    }
    console.log(py(eval(a[1])));' "$1" "${2:-}" "${3:-}" "${4:-}"
}
# the aggregated numbers, straight from the page's JSON
usage_json() { js 'JSON.stringify(d.byProject)' "$OUT/usage.html" usage-data; }
# the parent's two replies are at 10:00 and 10:00; the sub-agent's too
opus6() { usage_json | js 'var t = [0, 0, 0, 0, 0, 0, 0]; Object.keys(d.app).forEach(function (h) {
  var m = d.app[h]["claude-opus-5"]; if (h.indexOf("2026-10-06") === 0 && m) m.forEach(function (v, i) { t[i] += v; }); }); t'; }

build >/dev/null
check "the dashboard is written" "$([ -s "$OUT/usage.html" ] && echo yes || echo no)" yes
check "  with every placeholder filled, so its script actually runs" \
  "$(grep -c '{{' "$OUT/usage.html")" 0
check "one reply in two records counts once, and the final record wins" \
  "$(opus6)" "[17, 999, 1000, 50, 2, 0, 50]"
check "  (222 from the parent + 777 from its sub-agent)" \
  "$(opus6 | grep -c 999)" 1
check "the other model lands on its own hour" "$(usage_json | js '(d.app["2026-10-07T09"] || {})["claude-haiku-4-5-20251001"] || []')" "[5, 555, 0, 0, 1, 0, 0]"
check "  keyed by the UTC hour, so the page can place it in local time" \
  "$(usage_json | js 'Object.keys(d.app).every(function (k) { return k.length === 13 && k[10] === "T"; })')" True
check "  and the tokens are filed under their project" \
  "$(usage_json | js 'Object.keys(d).sort().join(",")')" app
check "the page offers the three periods" \
  "$(grep -o 'id="pweek"\|id="pmonth"\|id="pall"' "$OUT/usage.html" | wc -l | tr -d ' ')" 3
check "the manifest carries the session's usage" \
  "$(grep -c '"usage"' "$OUT/.manifest.json")" 1
check "the index links to it" "$(grep -c 'href="usage.html"' "$OUT/index.html")" 1
check "  but does not carry the numbers itself" \
  "$(js 'd.sessions.filter(function (s) { return "usage" in s; }).length' "$OUT/index.html" index-data)" 0

# the week anchor reaches the page, and only when it was asked for
check "no anchor configured means calendar weeks" \
  "$(grep -c '"weekReset":"mon 00:00"' "$OUT/usage.html")" 1
check "  which the page is not told is the plan's" \
  "$(grep -c '"weekResetSet":false' "$OUT/usage.html")" 1
CLAUDE_HTML_WEEK_RESET="tue 09:00" build >/dev/null
check "an anchor from the environment reaches the page" \
  "$(grep -c '"weekReset":"tue 09:00"' "$OUT/usage.html")" 1
check "  and only then is it called the plan's" \
  "$(grep -c '"weekResetSet":true' "$OUT/usage.html")" 1
build >/dev/null

# nothing changed: the session is skipped, yet the dashboard is rebuilt whole
rm -f "$OUT/usage.html"
R="$(build)"
check "an unchanged session is still skipped" \
  "$(printf '%s' "$R" | sed -n 's/.*"built":\([0-9]*\).*/\1/p')" 0
check "  and the dashboard returns from the manifest alone" \
  "$(opus6)" "[17, 999, 1000, 50, 2, 0, 50]"

# ── after the transcript is gone ────────────────────────────────────
# Tokens are recorded only in the transcript, and Claude Code deletes it
# after cleanupPeriodDays. The archive must carry them, or the dashboard
# rewrites its own history the day the transcript goes.
sed -n "/^cat > \"\$ARCHIVER\" <<'ARCHIVEREOF'\$/,/^ARCHIVEREOF\$/p" "$HERE/save-conversation.sh" |
  sed '1d;$d' > "$T/archive.js"
# The save appends the redactor and the parse to it, and so does this, and
# hands it the archive format lib/version.sh names.
cat "$HERE/build/redact.js" "$HERE/build/parse.js" >> "$T/archive.js"
AF="$(. "$HERE/lib/version.sh"; printf '%s' "$CH_ARCHIVE_FORMAT")"
printf '{"type":"assistant","cwd":"%s","timestamp":"2026-10-07T09:00:01Z","message":{"role":"assistant","content":[{"type":"thinking","thinking":"SECRET REASONING"}]}}\n' "$APP" >> "$J"
build >/dev/null
BEFORE="$(usage_json)"
index_tok() { js 'd.sessions.map(function (s) { return [s.kind, s.tok, s.models]; })' "$OUT/index.html" index-data; }
TOK_BEFORE="$(index_tok | sed 's/transcript/KIND/')"
CONV="$APP/.claude/.claude-conversations"; mkdir -p "$CONV"
archive() { run_js "$T/archive.js" "$J" "$P" "$APP" "$(size_of "$J")" "" "" "" "" "$AF"; }
archive > "$CONV/$P.json"
field_of() { js 'JSON.stringify(d[process.argv[4]] === undefined ? null : d[process.argv[4]])' < "$1" "" "" "$2"; }
check "the archive records tokens, sub-agent's included, as the build counts them" \
  "$(field_of "$CONV/$P.json" usage)" \
  "$(printf '%s' "$BEFORE" | js 'JSON.stringify(d.app)')"
check "  and each reply under its message id" \
  "$(js 'd.replies.map(function (r) { return r[0]; }).sort()' < "$CONV/$P.json")" \
  "['msg_A', 'msg_B', 'msg_C']"
check "  and the thinking" "$(grep -c 'SECRET REASONING' "$CONV/$P.json")" 1
check "  while the fields it always had are as they were" \
  "$(js '[d.sessionId, d.promptCount, d.project === process.argv[4]].map(function (x) { return x === true ? "True" : String(x); }).join(" ")' < "$CONV/$P.json" "" "" "$APP")" "$P 1 True"
if command -v osascript >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  check "  and both engines write it byte for byte the same" \
    "$(cmp -s <(osascript -l JavaScript "$T/archive.js" "$J" "$P" "$APP" 9 "" "" "" "" "$AF") \
               <(node "$T/archive.js" "$J" "$P" "$APP" 9 "" "" "" "" "$AF") && echo same || echo differ)" same
fi

# Sub-agents can run to a gigabyte, so a save reuses what the last one kept
# of those whose size has not changed — and only those. On a copy, so the
# fixture stays as the checks below expect it.
mkdir -p "$T/copy"; cp "$J" "$T/copy/$P.jsonl"; cp -R "$H/.claude/projects/$D/$P" "$T/copy/"
STATE="$T/copy/cache/$P.archive"
again() { run_js "$T/archive.js" "$T/copy/$P.jsonl" "$P" "$APP" 9 "$T/copy/prev.json" "$STATE" "" "" "$AF"; }
again > "$T/copy/fresh.json"
cp "$T/copy/fresh.json" "$T/copy/prev.json"
again > "$T/copy/reused.json"
check "  a save reusing the sub-agents' count writes the same archive" \
  "$(cmp -s "$T/copy/fresh.json" "$T/copy/reused.json" && echo same || echo differ)" same
# Mark the kept count, and seal it again, as only this script would.
sed 's/"mid":"msg_C","hour":"2026-10-06T10","model":"claude-opus-5","t":\[7,777,/&MARK/; s/,777,MARK/,778,/' \
  "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
node -e 'var f=process.argv[1],c=require("crypto"),fs=require("fs");
  fs.writeFileSync(f+".md5",c.createHash("md5").update(fs.readFileSync(f)).digest("hex")+"\n")' "$STATE"
check "  and does reuse it, not read them again" \
  "$(again | grep -c '"msg_C","2026-10-06T10","claude-opus-5",7,778')" 1
printf '{"type":"assistant","cwd":"%s","isSidechain":true,"timestamp":"2026-10-06T10:00:05Z","message":{"id":"msg_E","model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"role":"assistant","content":[{"type":"text","text":"more"}]}}\n' "$APP" \
  >> "$T/copy/$P/subagents/agent-abc123.jsonl"
check "  but a sub-agent that grew is read again" \
  "$(again > "$T/copy/grown.json"
     grep -c '"msg_E"' "$T/copy/grown.json") $(grep -c '"msg_C","2026-10-06T10","claude-opus-5",7,777,' "$T/copy/grown.json")" "1 1"

mv "$J" "$T/gone.jsonl"; mv "$H/.claude/projects/$D/$P" "$T/gone-agents"
build >/dev/null
check "with the transcript gone the page is rebuilt from the archive" \
  "$(index_tok | grep -c "'archive'")" 1
check "  and the dashboard is exactly as it was" "$(usage_json)" "$BEFORE"
check "  as are the index's tokens and models" "$(index_tok | sed 's/archive/KIND/')" "$TOK_BEFORE"
check "  and the thinking is still on the page" \
  "$(grep -c 'SECRET REASONING' "$OUT/sessions/$P.html")" 1
check "  and still searchable" "$(grep -c 'SECRET REASONING' "$OUT/search/$P.js")" 1

# A resumed session starts with a copy of the replies before it. With the
# source known only from its archive, a copied reply still counts once.
Q=11111111-2222-3333-4444-666666666666
{
  printf '{"type":"user","cwd":"%s","timestamp":"2026-10-08T10:00:00Z","message":{"role":"user","content":"resumed"}}\n' "$APP"
  grep '"msg_A"' "$T/gone.jsonl" | tail -1
} > "$H/.claude/projects/$D/$Q.jsonl"
rm -rf "$OUT"
build >/dev/null
check "a copy of an archived reply is counted once, even from a clean build" \
  "$(opus6)" "[17, 999, 1000, 50, 2, 0, 50]"
rm -f "$H/.claude/projects/$D/$Q.jsonl"

# Archives written before they carried tokens. While the last build still
# knows the numbers, they are kept; with nothing to go on, the session is
# still built, only without tokens.
build >/dev/null
node -e 'var fs=require("fs"),p=process.argv[1],a=JSON.parse(fs.readFileSync(p,"utf8"));
  delete a.usage; delete a.replies; delete a.format; a.messages.forEach(function (m) { delete m.thinking; });
  fs.writeFileSync(p,JSON.stringify(a))' "$CONV/$P.json"
R="$(build)"
check "an old archive is rebuilt" "$(printf '%s' "$R" | sed -n 's/.*"built":\([0-9]*\).*"errors":\(\[\]\).*/\1 \2/p')" "1 []"
check "  and keeps the numbers the last build had" "$(usage_json)" "$BEFORE"
check "  on the index too" "$(index_tok | sed 's/archive/KIND/')" "$TOK_BEFORE"
node -e 'var fs=require("fs"),p=process.argv[1],m=JSON.parse(fs.readFileSync(p,"utf8"));
  Object.keys(m).forEach(function (k) { m[k].uv = 3;
    Object.keys(m[k].usage || {}).forEach(function (h) { Object.keys(m[k].usage[h]).forEach(function (x) {
      m[k].usage[h][x].length = 5; }); }); }); fs.writeFileSync(p,JSON.stringify(m))' "$OUT/.manifest.json"
build >/dev/null
check "  and across the upgrade that added cost, from a version 3 manifest" "$(usage_json)" "$BEFORE"
R="$(HOME="$H" run_js "$HERE/build/convert.js" \
  "{\"root\":\"$ROOT\",\"out\":\"$OUT\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\",\"force\":true}")"
check "  through a forced rebuild as well" \
  "$(printf '%s' "$R" | sed -n 's/.*"built":\([0-9]*\).*"errors":\(\[\]\).*/\1 \2/p') $(usage_json)" "1 [] $BEFORE"
rm -rf "$OUT"
R="$(build)"
check "an old archive with no build behind it still builds" \
  "$(printf '%s' "$R" | sed -n 's/.*"sessions":\([0-9]*\).*"errors":\(\[\]\).*/\1 \2/p')" "1 []"
check "  just without tokens" "$(usage_json)" "{}"

# ── cost ────────────────────────────────────────────────────────────
# Claude Code writes "cost-state" records: a running total per model for the
# whole session, at its own API list prices, with no timestamp of its own.
# Each must become what it added since the one before, on the hour of the
# last record that had a time — never the running total again.
C="$T/cost"; CR="$C/root"; CAPP="$CR/capp"; CH_="$C/home"; CO="$C/out"
CD="$(printf '%s' "$CAPP" | tr '/' '-')"; CP="$CH_/.claude/projects/$CD"
mkdir -p "$CP" "$CAPP"
S1=77777777-0000-0000-0000-000000000001     # three snapshots, a duplicate, a restart
S2=77777777-0000-0000-0000-000000000002     # no cost-state at all
S3=77777777-0000-0000-0000-000000000003     # work before its counter began
SF=77777777-0000-0000-0000-000000000004     # a fork of S1, carrying S1's records
OTHER=77777777-0000-0000-0000-0000000000ff
crep() {   # session, message id, timestamp
  printf '{"type":"assistant","sessionId":"%s","cwd":"%s","timestamp":"%s","message":{"id":"%s","model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"role":"assistant","content":[{"type":"text","text":"r"}]}}\n' "$1" "$CAPP" "$3" "$2"
}
cask() { printf '{"type":"user","sessionId":"%s","cwd":"%s","timestamp":"%s","message":{"role":"user","content":"%s"}}\n' "$1" "$CAPP" "$2" "${3:-go}"; }
cstate() {   # session, startTime (ms), opus cost, haiku cost
  printf '{"type":"cost-state","sessionId":"%s","totalCostUSD":0,"startTime":%s,"hasUnknownModelCost":false,"modelUsage":{"claude-opus-5":{"outputTokens":1,"costUSD":%s},"claude-haiku-4-5-20251001":{"outputTokens":1,"costUSD":%s}}}\n' "$1" "$2" "$3" "$4"
}
T0=1791277200000   # 2026-10-06T09:00:00Z
T1=1791450000000   # 2026-10-08T09:00:00Z, a new counter
{
  cask "$S1" 2026-10-06T10:00:00Z
  crep "$S1" msg_S1a 2026-10-06T10:00:01Z
  # written twice, as Claude Code does: counts once
  cstate "$S1" $T0 1.2345674 0.25
  cstate "$S1" $T0 1.2345674 0.25
  cask "$S1" 2026-10-07T09:00:00Z
  crep "$S1" msg_S1b 2026-10-07T09:00:01Z
  # a copy from another session, in this file: not this session's money
  cstate "$OTHER" $T0 900 900
  cstate "$S1" $T0 1.7345674 0.25
  cask "$S1" 2026-10-08T12:00:00Z
  crep "$S1" msg_S1c 2026-10-08T12:00:01Z
  # a new counter: opus fell, startTime moved, so it starts again from nothing
  cstate "$S1" $T1 0.30000000000000004 0
} > "$CP/$S1.jsonl"
{ cask "$S2" 2026-10-06T11:00:00Z; crep "$S2" msg_S2a 2026-10-06T11:00:01Z; } > "$CP/$S2.jsonl"
{
  cask "$S3" 2026-10-05T10:00:00Z
  crep "$S3" msg_S3a 2026-10-05T10:00:01Z     # before the counter began: outside it
  cask "$S3" 2026-10-06T10:00:00Z
  crep "$S3" msg_S3b 2026-10-06T10:00:01Z
  cstate "$S3" $T0 2 0
} > "$CP/$S3.jsonl"
COPT="{\"root\":\"$CR\",\"out\":\"$CO\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}"
cbuild() { HOME="$CH_" run_js "$HERE/build/convert.js" "$COPT"; }
cdata() {   # page, expression over d
  node -e 'var h=require("fs").readFileSync(process.argv[1],"utf8");
    var m=/id="(?:session|index|usage)-data">([\s\S]*?)<\/script>/.exec(h);
    var d=JSON.parse(m[1]); console.log(JSON.stringify(eval(process.argv[2])));' "$1" "$2"
}
sess() { cdata "$CO/index.html" 'd.sessions.filter(function(s){return s.id==="'$1'"}).map(function(s){return [s.tok&&s.tok[5],!!s.costPart]})[0]'; }
cells() { cdata "$CO/usage.html" '(function(){var o=[];var p=d.byProject.capp||{};Object.keys(p).sort().forEach(function(h){Object.keys(p[h]).sort().forEach(function(m){if(p[h][m].length>7)o.push(h+" "+m.replace("claude-","")+" "+p[h][m][7])})});return o.join(", ")})()'; }
costsum() { cdata "$CO/usage.html" '(function(){var s=0;Object.keys(d.byProject).forEach(function(p){Object.keys(d.byProject[p]).forEach(function(h){Object.keys(d.byProject[p][h]).forEach(function(m){s+=d.byProject[p][h][m][7]||0})})});return s})()'; }
cbuild >/dev/null
check "cost: each snapshot adds only what it added, on the hour before it, duplicates once" \
  "$(cells)" '"2026-10-06T10 haiku-4-5-20251001 250000, 2026-10-06T10 opus-5 3234567, 2026-10-07T09 opus-5 500000, 2026-10-08T12 opus-5 300000"'
check "  (S1's 1.2345674 and S3's 2 share that hour and project)" "$(sess $S3 | cut -c2-8)" 2000000
check "  in whole micro-dollars, with a restart counted from nothing" "$(sess $S1)" "[2284567,false]"
check "  and another session's snapshot, copied in, ignored" "$(costsum)" 4284567
check "a session without cost-state has none, not zero" "$(sess $S2)" "[null,false]"
check "a session with work before its counter is a floor" "$(sess $S3)" "[2000000,true]"
check "the coverage line has the numbers to say so" "$(cdata "$CO/usage.html" 'd.coverage')" '{"capp":[3,2,1]}'

# A fork starts with a copy of its source: replies, and the source's
# cost-state too. The copy's tokens are taken back out; its cost must not be
# counted again, and the fork's own cost, landing in the same cell as the
# copied reply, must survive that. In a folder of its own, as after a
# rename, so the cell holds nothing but the copy and the fork's cost.
sleep 1
CAPP2="$CR/capp2"; mkdir -p "$CAPP2"
{
  printf '{"type":"user","sessionId":"%s","cwd":"%s","timestamp":"2026-10-06T10:00:00Z","message":{"role":"user","content":"forked"}}\n' "$SF" "$CAPP2"
  cat "$CP/$S1.jsonl" | sed -n 2,3p
  cstate "$SF" $T1 0.5 0
  cask "$SF" 2026-10-09T10:00:00Z
  crep "$SF" msg_SFa 2026-10-09T10:00:01Z
  cstate "$SF" $T1 0.75 0
} > "$CP/$SF.jsonl"
cbuild >/dev/null
check "a fork's copied cost-state is not counted again" "$(sess $SF)" "[750000,false]"
check "  so the dashboard holds both sessions' cost exactly once" "$(costsum)" 5034567
check "  the copied reply is taken back out, and the cell kept for the fork's cost" \
  "$(cdata "$CO/usage.html" 'd.byProject.capp2["2026-10-06T10"]["claude-opus-5"]')" "[0,0,0,0,0,0,0,500000]"
rm -rf "$CO"; cbuild >/dev/null
check "  the same from a clean build" "$(costsum)" 5034567

# The archive carries the cost, so it outlives the transcript.
CCONV="$CAPP/.claude/.claude-conversations"; mkdir -p "$CCONV"
for s in $S1 $S3; do
  run_js "$T/archive.js" "$CP/$s.jsonl" "$s" "$CAPP" "$(size_of "$CP/$s.jsonl")" "" "" "" "" "$AF" > "$CCONV/$s.json"
done
check "the archive records the cost as the build does" \
  "$(js 'var n = 0; Object.keys(d.usage).forEach(function (h) { Object.keys(d.usage[h]).forEach(function (m) {
    var r = d.usage[h][m]; if (r.length > 7) n += r[7]; }); }); n + " " + (d.costPart === undefined ? "None" : d.costPart)' < "$CCONV/$S1.json")" "2284567 None"
check "  and that it is a floor, when it is" \
  "$(js 'd.costPart' < "$CCONV/$S3.json")" True
if command -v osascript >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  check "  both engines write it byte for byte the same" \
    "$(cmp -s <(osascript -l JavaScript "$T/archive.js" "$CP/$S1.jsonl" "$S1" "$CAPP" 9 "" "" "" "" "$AF") \
               <(node "$T/archive.js" "$CP/$S1.jsonl" "$S1" "$CAPP" 9 "" "" "" "" "$AF") && echo same || echo differ)" same
fi
BEFORE_COST="$(cells)"
mkdir -p "$C/gone"; mv "$CP/$S1.jsonl" "$CP/$S3.jsonl" "$C/gone/"
cbuild >/dev/null
check "with the transcripts gone, the cost comes from the archives" \
  "$(sess $S1) $(sess $S3) $(cdata "$CO/index.html" 'd.sessions.filter(function(s){return s.id==="'$S1'"})[0].kind')" \
  '[2284567,false] [2000000,true] "archive"'
check "  and the dashboard is exactly as it was" "$(cells)" "$BEFORE_COST"

# An archive from yesterday has five figures to a cell: it still builds,
# with tokens and without a cost.
node -e 'var fs=require("fs"),p=process.argv[1],a=JSON.parse(fs.readFileSync(p,"utf8")); a.format=2;
  Object.keys(a.usage).forEach(function (h) { Object.keys(a.usage[h]).forEach(function (m) { a.usage[h][m].length = Math.min(5, a.usage[h][m].length); }); });
  fs.writeFileSync(p,JSON.stringify(a))' "$CCONV/$S1.json"
R="$(cbuild)"
check "a five-figure archive still builds" \
  "$(printf '%s' "$R" | sed -n 's/.*"built":\([0-9]*\).*"errors":\(\[\]\).*/\1 \2/p')" "1 []"
check "  with its tokens and no cost" \
  "$(cdata "$CO/index.html" 'd.sessions.filter(function(s){return s.id==="'$S1'"}).map(function(s){return [s.tok.length,s.tok[1]]})[0]')" "[5,30]"
mv "$C/gone/"* "$CP/"

# ── the page itself ─────────────────────────────────────────────────
# usage.js run under Node against a stand-in for the few DOM calls it makes:
# the filter's arithmetic is what matters, and Linux CI has no browser.
# Two projects, two models, two consecutive weeks (mon 00:00, in UTC):
#   week of 10-05  a/opus [10,100,1000,50,2]  a/haiku [1,10,0,0,1]
#   week of 10-12  b/opus [5,50,500,0,1]
cat > "$T/page.js" <<'EOF'
var fs = require("fs"), vm = require("vm");
var here = process.argv[2], stored = process.argv[3];
var data = { weekReset: "mon 00:00", weekResetSet: !!process.env.SET, byProject: {
  a: { "2026-10-06T10": { "claude-opus-5": [10, 100, 1000, 50, 2, 0, 0], "claude-haiku-4-5": [1, 10, 0, 0, 1, 0, 0] } },
  b: { "2026-10-13T10": { "claude-opus-5": [5, 50, 500, 0, 1, 0, 0] } } } };
var els = {}, onClick = null, store = {};
if (stored) store["ch-usage-filter"] = stored;
function el(id) {
  return els[id] = els[id] || { id: id, innerHTML: "", textContent: id === "usage-data" ? JSON.stringify(data) : "",
    hidden: false, listeners: {}, classList: { toggle: function () {}, add: function () {}, remove: function () {} },
    addEventListener: function (t, f) { this.listeners[t] = f; }, setAttribute: function () {} };
}
var ctx = {
  document: { getElementById: el, documentElement: { setAttribute: function () {}, removeAttribute: function () {} },
              addEventListener: function (t, f) { if (t === "click") onClick = f; } },
  localStorage: { getItem: function (k) { return k in store ? store[k] : null; },
                  setItem: function (k, v) { store[k] = String(v); }, removeItem: function (k) { delete store[k]; } },
  setTimeout: setTimeout, clearTimeout: clearTimeout, console: console,
  // the page redraws on resize, to fit the axis labels to the width
  window: { addEventListener: function () {} }
};
vm.runInNewContext(fs.readFileSync(here + "/viewer/viewer.js", "utf8") + "\n" +
                   fs.readFileSync(here + "/viewer/usage.js", "utf8"), ctx);
function text(id) { return el(id).innerHTML.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim(); }
function names(id) {
  var out = [], re = /data-fk="([^"]*)" data-fv="([^"]*)"/g, m;
  while ((m = re.exec(el(id).innerHTML))) out.push(m[1] + "=" + m[2]);
  return out;
}
function click(fk, fv) { onClick({ target: { closest: function () {
  return { getAttribute: function (a) { return a === "data-fk" ? fk : fv; } }; } } }); }
function button(id) { el(id).listeners.click(); }
var shot = function () { return JSON.stringify([text("cards"), text("buckets"), text("projects"), text("legend"), el("filt").hidden]); };
var out = { chip0: el("filt").hidden ? "" : text("filt"), sub: el("sub").textContent };
button("pall"); button("bmodel");
out.all = text("cards");
out.allState = shot();
out.legend = names("legend").join(",");
out.lower = names("projects").join(",");
click("model", "claude-opus-5");
out.opus = text("cards");
out.opusLegend = names("legend").join(",");
out.chip = el("filt").hidden ? "" : text("filt");
out.stored = store["ch-usage-filter"] || "";
click("model", "claude-opus-5");
out.restored = shot() === out.allState;
out.storedAfter = store["ch-usage-filter"] || "";
click("project", "b"); click("model", "claude-opus-5");
out.both = text("cards");
out.bothChip = text("filt");
button("pweek"); button("bproject");
out.weekKeeps = text("filt") === out.bothChip;
out.lowerHead = el("oth").textContent + " / " + el("ph").textContent.split(" ·")[0];
out.weekCards = text("cards");
click("model", "claude-haiku-4-5");
out.fresh = text("filt");
click("model", "claude-haiku-4-5");
button("pall"); button("bmodel");
out.end = shot() === out.allState;
// week view: the last week (b only) against the one right before it (a only)
button("pweek");
out.weekAll = text("cards");
click("project", "b");
out.weekB = text("cards");
console.log(JSON.stringify(out));
EOF
page() { TZ=UTC node "$T/page.js" "$HERE" "${1:-}"; }
field() { js 'd[process.argv[4]]' "" "" "$1"; }
P0="$(page)"
check "the subtitle claims no plan reset nobody configured" \
  "$(printf '%s' "$P0" | field sub | grep -c "plan's reset")" 0
check "  and claims it when one was" \
  "$(SET=1 page | field sub | grep -c "matching your plan's reset")" 1
check "the page draws: all-time total of both projects" \
  "$(printf '%s' "$P0" | field all | cut -d' ' -f1-3)" "1.7 k all"
check "  and the local formatter is gone in favour of the shared one" \
  "$(grep -c 'function fmt\b' "$HERE/viewer/usage.js")" 0
check "every model in the legend and project below is a filter" \
  "$(printf '%s' "$P0" | field legend) / $(printf '%s' "$P0" | field lower)" \
  "model=claude-opus-5,model=claude-haiku-4-5 / project=a,project=b"
check "clicking a model narrows the cards to it" \
  "$(printf '%s' "$P0" | field opus | cut -d' ' -f1-10)" "1.7 k all time — recorded by Claude Code 150"
check "  the legend shrinks to what is left" "$(printf '%s' "$P0" | field opusLegend)" "model=claude-opus-5"
check "  the filter says so, with a way out" "$(printf '%s' "$P0" | field chip)" "filtered · model opus-5 ×"
check "  and is remembered" "$(printf '%s' "$P0" | field stored)" '{"model":"claude-opus-5"}'
check "clicking it again restores every number exactly" "$(printf '%s' "$P0" | field restored)" True
check "  and forgets it" "$(printf '%s' "$P0" | field storedAfter)" ""
check "a model and a project combine" \
  "$(printf '%s' "$P0" | field both | cut -d' ' -f1-3)" "555 all time"
check "  both shown" "$(printf '%s' "$P0" | field bothChip)" "filtered · model opus-5 × project b ×"
check "switching period and breakdown keeps the filter" "$(printf '%s' "$P0" | field weekKeeps)" True
check "the lower table's first heading names what it lists" \
  "$(printf '%s' "$P0" | field lowerHead)" "Model / By model"
check "a model the project never used starts a fresh filter, not an empty page" \
  "$(printf '%s' "$P0" | field fresh)" "filtered · model haiku-4-5 ×"
check "undoing everything leaves the page as it began" "$(printf '%s' "$P0" | field end)" True
check "the week compares with the week before it" \
  "$(printf '%s' "$P0" | field weekAll | cut -d' ' -f1-9)" "555 week of 2026-10-12 00:00 ▼ 53% vs previous"
check "  and with a filter, with the same filtered week — empty here" \
  "$(printf '%s' "$P0" | field weekB | cut -d' ' -f1-14)" "555 week of 2026-10-12 00:00 nothing the week before — recorded by Claude Code"
# A fixed table gives a column without a width of its own whatever is left,
# which under 900px was nothing: the names vanished. Both tables scroll in
# their own box below that instead of the page.
check "a narrow window keeps room for the names" \
  "$(grep -c '@media(max-width:900px)' "$HERE/viewer/usage.html") $(grep -o '<div class="tu"><table class="u">' "$HERE/viewer/usage.html" | wc -l | tr -d ' ')" "1 2"
check "a stored filter naming what no longer exists clears itself" \
  "$(page '{"model":"claude-gone"}' | field chip0)" ""
check "  as does one whose two halves never met" \
  "$(page '{"model":"claude-haiku-4-5","project":"b"}' | field chip0)" ""
check "  and one that is not JSON at all" "$(page 'not json' | field chip0)" ""
check "  while one that still matches is put back" \
  "$(page '{"project":"b"}' | field chip0)" "filtered · project b ×"

# The same page with a cost on some cells and not others. A sum with no
# known cost in it reads "—", never "$0.00", and the cost follows every
# filter exactly as the tokens do.
#   week of 10-05  a/opus [10,100,1000,50,2, $1.23]  a/haiku [1,10,0,0,1]  (no cost)
#   week of 10-12  b/opus [5,50,500,0,1]  (no cost)
# The stand-in above, up to its own clicks, with other data in.
sed -n '1,/^function button/p' "$T/page.js" |
  sed 's/^var els = {}/data = JSON.parse(process.argv[4]); var els = {}/' > "$T/pagecost.js"
cat >> "$T/pagecost.js" <<'JS'
var c = {};
button("pall"); button("bmodel");
c.all = text("cards"); c.cover = el("cover").textContent; c.tip = /title="[^"]*≈[^"]*"/.test(el("chart").innerHTML);
c.lower = text("projects");
c.zero = /\$0\.00/.test(el("cards").innerHTML + el("buckets").innerHTML + el("projects").innerHTML);
click("project", "b");
c.b = text("cards"); c.bCover = el("cover").textContent; c.bRows = text("buckets");
click("project", "b"); click("model", "claude-opus-5");
c.opus = text("cards");
click("model", "claude-opus-5"); click("model", "claude-haiku-4-5");
c.haiku = text("cards");
click("model", "claude-haiku-4-5");
button("pweek");
c.week = text("cards");
console.log(JSON.stringify(c));
JS
CDATA='{"weekReset":"mon 00:00","coverage":{"a":[2,1,0],"b":[1,0,0]},"byProject":{
 "a":{"2026-10-06T10":{"claude-opus-5":[10,100,1000,50,2,0,50,1234567],"claude-haiku-4-5":[1,10,0,0,1,0,0]}},
 "b":{"2026-10-13T10":{"claude-opus-5":[5,50,500,0,1,0,0]}}}}'
PC="$(TZ=UTC node "$T/pagecost.js" "$HERE" "" "$CDATA")"
cf() { printf '%s' "$PC" | js 'd[process.argv[4]]' "" "" "$1"; }
check "cost: the all-time card says what is known" "$(cf all | cut -d' ' -f5-9)" "\$1.23 recorded by Claude Code"
check "  the bar's tooltip carries it" "$(cf tip)" True
check "  the lower table has it per project, and — where none is known" \
  "$(cf lower)" "a 11 110 1.0 k 50 3 1.2 k ≈ \$1.23 b 5 50 500 0 1 555 —"
check "  nowhere does an unknown cost read \$0.00" "$(cf zero)" False
check "  the coverage line counts sessions" "$(cf cover | cut -d' ' -f1-8)" "Cost is known for 1 of 3 sessions"
check "filtered to a project with no cost, the card says —" "$(cf b | cut -d' ' -f1-9)" "555 all time — recorded by Claude Code 50"
check "  and its coverage line follows the filter" "$(cf bCover | cut -d' ' -f1-10)" "Cost is known for 0 of 1 session in b"
check "  as do its rows" "$(cf bRows)" "2026-10-13 opus-5 5 50 500 0 1 555 —"
check "filtered to a model, the cost is that model's" "$(cf opus | cut -d' ' -f1-9)" "1.7 k all time \$1.23 recorded by Claude Code"
check "  and to one whose cost is unknown, —" "$(cf haiku | cut -d' ' -f1-8)" "11 all time — recorded by Claude Code"
check "a week with no cost against one with: — and no delta" "$(cf week | cut -d' ' -f1-15)" "555 week of 2026-10-12 00:00 ▼ 53% vs previous — recorded by Claude Code 50"

# ── a resumed and a forked session ──────────────────────────────────
# What Claude Code writes on a resume: a new transcript that starts with a
# copy of the last part of the one it came from — the same uuids, message
# ids and times, a reply still several records under one id, only the
# session id rewritten — then replies of its own, and a cost counter of its
# own, started afresh. A fork (--fork-session) is the same copy, of all of
# it. Every total shown anywhere must count a copied reply once: the
# dashboard's tokens, its recorded and calculated costs, the budget's
# spend, a project's heading on the index. A session's own row and page
# count its whole transcript, copy included, and say so.
#
# The fixture (resume-gen.js): O, the original, four replies on three
# models over three weeks, its counter from the start (or, "nocost", no
# counter at all: from before Claude Code wrote one); R, resumed from it,
# with O's last two replies; F, forked from it, with all four, still
# running, so no counter of its own yet. resume-want.js works out every
# total from the transcripts by itself; resume-got.js reads them off the
# built pages. Under each engine, built from nothing, and built a save at
# a time (O, then R joining, then F); with O the oldest of the three, and
# with O still in use after both (newest), which hands the dashboard's
# count of the copies to them.
RT="$T/resume"; mkdir -p "$RT"
cat > "$RT/resume-gen.js" <<'GENEOF'
// A resumed and a forked session, in the shape Claude Code writes them.
//   node resume-gen.js <project dir> <cwd> [nocost]
var fs = require("fs"), dir = process.argv[2], cwd = process.argv[3], nocost = process.argv[4] === "nocost";
var O = "88888888-0000-0000-0000-000000000001";   // the original
var R = "88888888-0000-0000-0000-000000000002";   // resumed from it: a copy of its last part
var F = "88888888-0000-0000-0000-000000000003";   // forked from it: a copy of all of it
var n = 0, recs = [];
function uuid() { n++; return "00000000-0000-4000-8000-" + ("000000000000" + n).slice(-12); }
function ask(at, text) {
  return { type: "user", uuid: uuid(), timestamp: at, cwd: cwd, message: { role: "user", content: text } };
}
// One reply as several records under one message id, one per block, the
// usage so far on each and the last one final; each record its own uuid.
function reply(mid, model, at, u) {
  var t0 = Date.parse(at), out = [];
  ["thinking", "text", "tool_use"].forEach(function (b, i) {
    var last = i === 2;
    out.push({ type: "assistant", uuid: uuid(), timestamp: new Date(t0 + i * 1000).toISOString(), cwd: cwd,
      message: { id: mid, model: model, role: "assistant",
        usage: { input_tokens: u[0], output_tokens: last ? u[1] : 3 * (i + 1),
                 cache_read_input_tokens: u[2], cache_creation_input_tokens: u[3],
                 cache_creation: { ephemeral_5m_input_tokens: u[3] - u[4], ephemeral_1h_input_tokens: u[4] } },
        content: [b === "text" ? { type: "text", text: "r" } : b === "thinking" ? { type: "thinking", thinking: "t" }
                                : { type: "tool_use", id: "tu_" + mid, name: "Bash", input: {} }] } });
  });
  return out;
}
function cost(start, opus, haiku, sonnet) {
  return { type: "cost-state", totalCostUSD: 0, startTime: start, hasUnknownModelCost: false,
    modelUsage: { "claude-opus-5": { costUSD: opus }, "claude-haiku-4-5-20251001": { costUSD: haiku },
                  "claude-sonnet-5-5": { costUSD: sonnet } } };
}
function as(sid, list) { return list.map(function (e) { var c = JSON.parse(JSON.stringify(e)); c.sessionId = sid; return c; }); }
function write(sid, list) {
  fs.writeFileSync(dir + "/" + sid + ".jsonl", as(sid, list).map(JSON.stringify).join("\n") + "\n");
}
var T0 = Date.parse("2026-10-05T09:00:00Z"), T1 = Date.parse("2026-11-02T09:30:00Z");
// The original: four replies over three weeks, its counter from the start.
var early = [].concat(
  [ask("2026-10-05T10:00:00Z", "start")],
  reply("msg_o1", "claude-sonnet-5-5", "2026-10-05T10:00:01Z", [100, 2000, 30000, 4000, 1000]),
  [ask("2026-10-12T09:00:00Z", "more")],
  reply("msg_o2", "claude-opus-5", "2026-10-12T09:00:01Z", [200, 3000, 50000, 6000, 0]),
  nocost ? [] : [cost(T0, 0.4, 0, 0.3)]);
var late = [].concat(
  [ask("2026-10-13T11:00:00Z", "and more")],
  reply("msg_o3", "claude-haiku-4-5-20251001", "2026-10-13T11:00:01Z", [300, 4000, 70000, 8000, 2000]),
  [ask("2026-10-16T17:00:00Z", "last")],
  reply("msg_o4", "claude-opus-5", "2026-10-16T17:00:01Z", [400, 5000, 90000, 10000, 5000]));
write(O, early.concat(late, nocost ? [] : [cost(T0, 1.25, 0.2, 0.3)]));
// Resumed: the original's last part again, the same uuids, message ids and
// times, under the new session's id; then new replies and a counter of its
// own, started afresh.
write(R, late.concat(
  [ask("2026-11-02T10:00:00Z", "resumed")],
  reply("msg_r1", "claude-opus-5", "2026-11-02T10:00:01Z", [500, 6000, 110000, 12000, 0]),
  [cost(T1, 0.5, 0, 0)],
  [ask("2026-11-03T12:00:00Z", "again")],
  reply("msg_r2", "claude-sonnet-5-5", "2026-11-03T12:00:01Z", [600, 7000, 130000, 14000, 7000]),
  [cost(T1, 0.5, 0, 0.75)]));
// Forked: all of the original, then a reply of its own; still running, so
// no counter written yet.
write(F, early.filter(function (e) { return e.type !== "cost-state"; }).concat(late,
  [ask("2026-11-05T08:00:00Z", "forked")],
  reply("msg_f1", "claude-haiku-4-5-20251001", "2026-11-05T08:00:01Z", [700, 8000, 150000, 16000, 0])));
GENEOF
cat > "$RT/resume-want.js" <<'WANTEOF'
// node resume-want.js <here> <project dir> <budget start> <end>: every total, from the transcripts
var fs = require("fs"), here = process.argv[2], dir = process.argv[3];
var from = +process.argv[4] * 1000, until = +process.argv[5] * 1000;
var PR = new Function(fs.readFileSync(here + "/build/prices.js", "utf8") + "\nreturn claudeHtmlPrices;")()(
  fs.readFileSync(here + "/build/prices.tsv", "utf8"));
function canon(v) {   // JSON with its keys in order, so two ways of adding up compare
  if (v && typeof v === "object" && !Array.isArray(v))
    return "{" + Object.keys(v).sort().map(function (k) { return JSON.stringify(k) + ":" + canon(v[k]); }).join(",") + "}";
  return JSON.stringify(v);
}
var files = fs.readdirSync(dir).filter(function (f) { return /\.jsonl$/.test(f); }).sort();
var replies = {}, held = {}, counters = {}, recorded = 0;
files.forEach(function (f) {
  var sid = f.replace(/\.jsonl$/, ""), mine = {}, last = {};
  fs.readFileSync(dir + "/" + f, "utf8").split("\n").filter(Boolean).forEach(function (l) {
    var e = JSON.parse(l);
    if (e.type === "cost-state" && e.sessionId === sid) {
      var t = 0; Object.keys(e.modelUsage).forEach(function (m) { t += Math.round(e.modelUsage[m].costUSD * 1e6); });
      last[e.startTime] = t;
      (counters[sid] = counters[sid] || []).push(e.startTime);
    }
    if (e.type !== "assistant") return;
    var u = e.message.usage, w = u.cache_creation_input_tokens, h1 = u.cache_creation.ephemeral_1h_input_tokens;
    mine[e.message.id] = { at: Date.parse(e.timestamp), hour: e.timestamp.slice(0, 13), model: e.message.model,
      t: [u.input_tokens, u.output_tokens, u.cache_read_input_tokens, w, 1, h1, 0] };
  });
  Object.keys(last).forEach(function (s) { recorded += last[s]; });
  Object.keys(mine).forEach(function (mid) {
    if (!replies[mid]) replies[mid] = mine[mid];
    (held[mid] = held[mid] || []).push(sid);
  });
  held[sid] = Object.keys(mine);
});
function tok(t) { return t[0] + t[1] + t[2] + t[3]; }
var cells = {}, sum = { all: 0 }, spend = recorded;
Object.keys(replies).sort().forEach(function (mid) {
  var r = replies[mid], c = (cells[r.hour] = cells[r.hour] || {})[r.model] =
    (cells[r.hour] || {})[r.model] || [0, 0, 0, 0, 0, 0, 0];
  for (var i = 0; i < 7; i++) c[i] += r.t[i];
  var d = new Date(r.hour + ":00:00Z"), mon = new Date(d - ((d.getUTCDay() + 6) % 7) * 864e5);
  ["all", "month " + r.hour.slice(0, 7), "week " + mon.toISOString().slice(0, 10), "model " + r.model,
   "project rapp"].forEach(function (k) { sum[k] = (sum[k] || 0) + tok(r.t); });
  // Its money: in a counter of a session that holds it and had begun by
  // then, or else the price table's, once.
  var paid = held[mid].some(function (sid) { return (counters[sid] || []).some(function (s) { return s <= r.at; }); });
  if (!paid && r.at >= from && r.at < until) spend += PR.cellCost(r.model, r.hour, r.t, false);
});
var calc = PR.total(cells), now = PR.total(cells, { today: true });
var rows = files.map(function (f) {
  var sid = f.replace(/\.jsonl$/, ""), n = 0, s = 0, shared = 0;
  held[sid].forEach(function (mid) {
    n += tok(replies[mid].t);
    if (held[mid].length > 1) { shared++; s += tok(replies[mid].t); }
  });
  return sid.slice(-1) + " " + n + " " + (shared ? shared + "/" + s : "-");
});
console.log(JSON.stringify({ cells: canon({ rapp: cells }), sums: canon(sum), recorded: recorded,
  calc: Math.round(calc.calc), now: Math.round(now.calc), spend: Math.round(spend), rows: rows.join(", "),
  heading: sum.all, pages: rows.join(", ") }));
WANTEOF
cat > "$RT/resume-got.js" <<'GOTEOF'
// node resume-got.js <here> <out> <spend file>: every total, as the pages show it
var fs = require("fs"), here = process.argv[2], out = process.argv[3];
function data(f, id) { return JSON.parse(new RegExp('id="' + id + '">([\\s\\S]*?)</script>').exec(fs.readFileSync(f, "utf8"))[1]); }
var PR = new Function(fs.readFileSync(here + "/build/prices.js", "utf8") + "\nreturn claudeHtmlPrices;")()(
  fs.readFileSync(here + "/build/prices.tsv", "utf8"));
function canon(v) {   // JSON with its keys in order, so two ways of adding up compare
  if (v && typeof v === "object" && !Array.isArray(v))
    return "{" + Object.keys(v).sort().map(function (k) { return JSON.stringify(k) + ":" + canon(v[k]); }).join(",") + "}";
  return JSON.stringify(v);
}
var bp = data(out + "/usage.html", "usage-data").byProject, cells = {}, sum = { all: 0 }, recorded = 0;
function tok(t) { return t[0] + t[1] + t[2] + t[3]; }
Object.keys(bp).forEach(function (p) {
  Object.keys(bp[p]).sort().forEach(function (h) {
    Object.keys(bp[p][h]).sort().forEach(function (m) {
      var c = bp[p][h][m];
      recorded += c[7] || 0;
      if (!tok(c) && !c[4]) return;          // a cell kept for its cost alone
      ((cells[p] = cells[p] || {})[h] = cells[p][h] || {})[m] = c.slice(0, 7);
      var d = new Date(h + ":00:00Z"), mon = new Date(d - ((d.getUTCDay() + 6) % 7) * 864e5);
      ["all", "month " + h.slice(0, 7), "week " + mon.toISOString().slice(0, 10), "model " + m,
       "project " + p].forEach(function (k) { sum[k] = (sum[k] || 0) + tok(c); });
    });
  });
});
var spend = /micro=(\d+)/.exec(fs.readFileSync(process.argv[4], "utf8"))[1];
var ix = data(out + "/index.html", "index-data").sessions.slice().sort(function (a, b) { return a.id < b.id ? -1 : 1; });
var heading = 0;
ix.forEach(function (s) { heading += tok(s.tok) - (s.dup || 0); });
console.log(JSON.stringify({ cells: canon(cells), sums: canon(sum), recorded: recorded,
  calc: Math.round(PR.total(bp.rapp || {}).calc), now: Math.round(PR.total(bp.rapp || {}, { today: true }).calc),
  spend: +spend, rows: ix.map(function (s) { return s.id.slice(-1) + " " + tok(s.tok) + " " + (s.shares ? s.shares.join("/") : "-"); }).join(", "),
  heading: heading,
  pages: ix.map(function (s) {
    var m = data(out + "/sessions/" + s.id + ".html", "session-data").meta;
    return s.id.slice(-1) + " " + tok(m.tok) + " " + (m.shares ? m.shares.join("/") : "-");
  }).join(", ") }));
GOTEOF
cat > "$RT/resume-page.js" <<'PAGEEOF'
// node resume-page.js <here> <page.html>: the header's token line, as page.js draws it
var fs = require("fs"), vm = require("vm"), here = process.argv[2];
var html = fs.readFileSync(process.argv[3], "utf8");
var json = /id="session-data">([\s\S]*?)<\/script>/.exec(html)[1];
var els = {};
function any(name) {
  var f = function () { return any(name + "()"); };
  return new Proxy(f, {
    get: function (t, k) {
      if (k === Symbol.toPrimitive) return function () { return ""; };
      if (k === "length") return 0;
      if (k in t && k !== "name") return t[k];
      return t[k] = any(name + "." + String(k));
    },
    set: function (t, k, v) { t[k] = v; return true; },
    apply: function () { return any(name + "()"); }
  });
}
function el(id) {
  if (els[id]) return els[id];
  var e = any("#" + id); e.innerHTML = ""; e.textContent = id === "session-data" ? json : ""; e.hidden = true;
  return els[id] = e;
}
var doc = any("document"); doc.getElementById = el; doc.querySelector = function () { return null; };
doc.querySelectorAll = function () { return []; };
var win = any("window");
var ctx = { document: doc, window: win, localStorage: { getItem: function () { return null; }, setItem: function () {} },
  location: { hash: "", href: "" }, history: any("history"), navigator: { platform: "", userAgent: "" },
  setTimeout: function () {}, clearTimeout: function () {}, requestAnimationFrame: function () {}, console: console,
  matchMedia: function () { return { matches: false, addEventListener: function () {}, addListener: function () {} }; },
  getComputedStyle: function () { return {}; } };
try {
  vm.runInNewContext(fs.readFileSync(here + "/viewer/viewer.js", "utf8") + "\n" + fs.readFileSync(here + "/viewer/page.js", "utf8"), ctx);
} catch (e) { if (!els.tok || !els.tok.innerHTML) { console.error(e.stack); process.exit(1); } }
console.log(String(els.tok.innerHTML).replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim());
PAGEEOF
RAPP="$RT/root/rapp"; RH="$RT/home"; RD="$(printf '%s' "$RAPP" | tr '/' '-')"; RP="$RH/.claude/projects/$RD"
RO=88888888-0000-0000-0000-000000000001; RR=88888888-0000-0000-0000-000000000002; RF=88888888-0000-0000-0000-000000000003
RS0=$(( $(node -e 'console.log(Date.parse("2026-10-01T00:00:00Z") / 1000)') )); RS1=$((RS0 + 61 * 86400))
rbuild() {   # engine, out
  local o="{\"root\":\"$RT/root\",\"out\":\"$2\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\",\"limits\":{\"budget\":{\"start\":$RS0,\"end\":$RS1},\"spendFile\":\"$RT/spend\"}}"
  if [ "$1" = osascript ]; then HOME="$RH" osascript -l JavaScript "$HERE/build/convert.js" "$o" >/dev/null
  else HOME="$RH" node "$HERE/build/convert.js" "$o" >/dev/null; fi
  cp "$RT/spend" "$2.spend"
}
rtimes() {   # order: O oldest, or O newest — still in use after the resume and the fork
  touch -t 202610161800 "$RP/$RO.jsonl" 2>/dev/null; touch -t 202611031300 "$RP/$RR.jsonl" 2>/dev/null
  touch -t 202611050900 "$RP/$RF.jsonl" 2>/dev/null
  [ "$1" = newest ] && touch -t 202611200000 "$RP/$RO.jsonl"; return 0
}
rlabel() {
  case "$1" in
    cells) echo "the dashboard's cells, each copied reply once" ;;
    sums) echo "  its tokens by week, month and all, by model and by project" ;;
    recorded) echo "  the recorded cost, each session's own counter once" ;;
    calc) echo "  the calculated cost at the price of the time" ;;
    now) echo "  and at today's prices" ;;
    spend) echo "  the budget's spend, each reply's money once" ;;
    heading) echo "  the project's heading on the index" ;;
    rows) echo "  each row its whole transcript, and how much of it is shared" ;;
    pages) echo "  each page's header the same" ;;
  esac
}
rcheck() {   # label, out
  local got want k
  got="$(node "$RT/resume-got.js" "$HERE" "$2" "$2.spend")"
  want="$(node "$RT/resume-want.js" "$HERE" "$RP" "$RS0" "$RS1")"
  for k in cells sums recorded calc now spend heading rows pages; do
    check "$1: $(rlabel $k)" "$(printf '%s' "$got" | js 'd[process.argv[4]]' "" "" "$k")" \
      "$(printf '%s' "$want" | js 'd[process.argv[4]]' "" "" "$k")"
  done
}
for ENG in $([ "$HAVE_OSASCRIPT" = true ] && echo osascript) node; do
  for RM in cost nocost; do
    for RORD in oldest newest; do
      L="$ENG, $RM, O $RORD"
      rm -rf "$RT/root" "$RH" "$RT"/out*; mkdir -p "$RAPP" "$RP"
      node "$RT/resume-gen.js" "$RP" "$RAPP" "$RM"; rtimes "$RORD"
      rbuild "$ENG" "$RT/out1"
      rcheck "$L, from nothing" "$RT/out1"
      # A save at a time: O alone, then R as it is resumed, then F.
      mkdir -p "$RT/later"; mv "$RP/$RR.jsonl" "$RP/$RF.jsonl" "$RT/later/"
      rbuild "$ENG" "$RT/out2"
      check "$L: O alone has nothing shared" "$(node "$RT/resume-got.js" "$HERE" "$RT/out2" "$RT/out2.spend" | js 'd.rows')" "1 283000 -"
      mv "$RT/later/$RR.jsonl" "$RP/"; rtimes "$RORD"; rbuild "$ENG" "$RT/out2"
      mv "$RT/later/$RF.jsonl" "$RP/"; rtimes "$RORD"; rbuild "$ENG" "$RT/out2"
      rcheck "$L, a save at a time" "$RT/out2"
      check "  and every page and the dashboard the same bytes as from nothing" \
        "$(for f in usage.html sessions/$RO.html sessions/$RR.html sessions/$RF.html; do cmp -s "$RT/out1/$f" "$RT/out2/$f" || echo "$f differs"; done
           cmp -s "$RT/out1.spend" "$RT/out2.spend" || echo "spend differs")" ""
    done
  done
done
check "the page says how much of it is shared, and that all usage counts it once" \
  "$(node "$RT/resume-page.js" "$HERE" "$RT/out1/sessions/$RR.html" | grep -o 'incl\. 2 replies (187\.7 k tokens) also in another session')" \
  "incl. 2 replies (187.7 k tokens) also in another session"
check "  and a session sharing nothing says nothing of it" \
  "$(rm -f "$RP/$RR.jsonl" "$RP/$RF.jsonl"; rbuild node "$RT/out1"; node "$RT/resume-page.js" "$HERE" "$RT/out1/sessions/$RO.html" | grep -c 'another session')" 0

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
