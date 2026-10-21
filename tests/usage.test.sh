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

build() { HOME="$H" run_js "$HERE/convert.js" \
  "{\"root\":\"$ROOT\",\"out\":\"$OUT\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}"; }
# the aggregated numbers for opus on the 6th, straight from the page's JSON
usage_json() { python3 -c "
import json,re,pathlib
h=pathlib.Path('$OUT/usage.html').read_text()
print(json.dumps(json.loads(re.search(r'id=\"usage-data\">(.*?)</script>',h,re.S).group(1))['byProject']))"; }
# the parent's two replies are at 10:00 and 10:00; the sub-agent's too
opus6() { usage_json | python3 -c "
import json,sys
d=json.load(sys.stdin)['app']
t=[0]*5
for hour,models in d.items():
    if hour.startswith('2026-10-06') and 'claude-opus-5' in models:
        for i,v in enumerate(models['claude-opus-5']): t[i]+=v
print(t)"; }

build >/dev/null
check "the dashboard is written" "$([ -s "$OUT/usage.html" ] && echo yes || echo no)" yes
check "  with every placeholder filled, so its script actually runs" \
  "$(grep -c '{{' "$OUT/usage.html")" 0
check "one reply in two records counts once, and the final record wins" \
  "$(opus6)" "[17, 999, 1000, 50, 2]"
check "  (222 from the parent + 777 from its sub-agent)" \
  "$(opus6 | grep -c 999)" 1
check "the other model lands on its own hour" "$(usage_json | python3 -c "
import json,sys
print(json.load(sys.stdin)['app'].get('2026-10-07T09',{}).get('claude-haiku-4-5-20251001',[]))")" "[5, 555, 0, 0, 1]"
check "  keyed by the UTC hour, so the page can place it in local time" \
  "$(usage_json | python3 -c "
import json,sys
print(all(len(k)==13 and k[10]=='T' for k in json.load(sys.stdin)['app']))")" True
check "  and the tokens are filed under their project" \
  "$(usage_json | python3 -c "
import json,sys
print(','.join(sorted(json.load(sys.stdin))))")" app
check "the page offers the three periods" \
  "$(grep -o 'id="pweek"\|id="pmonth"\|id="pall"' "$OUT/usage.html" | wc -l | tr -d ' ')" 3
check "the manifest carries the session's usage" \
  "$(grep -c '"usage"' "$OUT/.manifest.json")" 1
check "the index links to it" "$(grep -c 'href="usage.html"' "$OUT/index.html")" 1
check "  but does not carry the numbers itself" \
  "$(python3 -c "
import json,re,pathlib
h=pathlib.Path('$OUT/index.html').read_text()
d=json.loads(re.search(r'id=\"index-data\">(.*?)</script>',h,re.S).group(1))
print(sum('usage' in s for s in d['sessions']))")" 0

# the week anchor reaches the page, and only when it was asked for
check "no anchor configured means calendar weeks" \
  "$(grep -c '"weekReset":"mon 00:00"' "$OUT/usage.html")" 1
CLAUDE_HTML_WEEK_RESET="tue 09:00" build >/dev/null
check "an anchor from the environment reaches the page" \
  "$(grep -c '"weekReset":"tue 09:00"' "$OUT/usage.html")" 1
build >/dev/null

# nothing changed: the session is skipped, yet the dashboard is rebuilt whole
rm -f "$OUT/usage.html"
R="$(build)"
check "an unchanged session is still skipped" \
  "$(printf '%s' "$R" | sed -n 's/.*"built":\([0-9]*\).*/\1/p')" 0
check "  and the dashboard returns from the manifest alone" \
  "$(opus6)" "[17, 999, 1000, 50, 2]"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
