#!/bin/bash
# What a build must never do: fail to rebuild a claude.ai chat because its
# export has not changed, or lose a page because one attempt to build it failed.
# Both happened: the first deleted 23 pages on the way to the second.
#
#   bash tests/build.test.sh
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chbuild)" && pwd)"
trap 'chmod -R u+rw "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/home"
build() { HOME="$T/home" run_js "$HERE/convert.js" "$1"; }
errors() { grep -o '"error":' | wc -l | tr -d ' '; }
has() { [ -s "$1" ] && echo yes || echo no; }

# ── a claude.ai chat rebuilt while its export is unchanged ──────────
mkdir -p "$T/w/out" "$T/w/projects"
X="$T/w/conversations.json"
ID=cccccccc-0000-0000-0000-000000000003
cat > "$X" <<EOF
[{"uuid":"$ID","name":"A web chat","created_at":"2026-05-01T10:00:00Z",
  "updated_at":"2026-05-01T11:00:00Z","chat_messages":[
  {"sender":"human","created_at":"2026-05-01T10:00:00Z","content":[{"type":"text","text":"a question from the web"}]},
  {"sender":"assistant","created_at":"2026-05-01T10:00:05Z","content":[{"type":"text","text":"an answer"}]}]}]
EOF
CW="{\"root\":\"$T/w/none\",\"out\":\"$T/w/out\",\"projects\":\"$T/w/projects\",\"here\":\"$HERE\",\"exportPath\":\"$X\"}"
build "$CW" >/dev/null
rm -f "$T/w/out/search/$ID.js"          # anything that forces this one to rebuild
check "a web chat rebuilds while its export is unchanged" "$(build "$CW" | errors)" 0
check "  and its search file is written again" "$(has "$T/w/out/search/$ID.js")" yes
# A claude.ai chat has no folder on this Mac, so its project crumb must not
# offer to open one.
check "  and a web chat offers nothing to open" \
  "$(grep -c '"open":""' "$T/w/out/sessions/$ID.html")" 1

# ── a session that fails to build keeps its page ────────────────────
mkdir -p "$T/f/out" "$T/f/projects/-x-app"
ID=dddddddd-0000-0000-0000-000000000004
J="$T/f/projects/-x-app/$ID.jsonl"
PAGE="$T/f/out/sessions/$ID.html"
printf '%s\n' '{"type":"user","cwd":"/x/app","timestamp":"2026-09-11T10:00:00Z","message":{"role":"user","content":"a question worth keeping"}}' > "$J"
CF="{\"root\":\"$T/f/none\",\"out\":\"$T/f/out\",\"projects\":\"$T/f/projects\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}"
build "$CF" >/dev/null
printf '%s\n' '{"type":"assistant","cwd":"/x/app","timestamp":"2026-09-11T10:00:01Z","message":{"role":"assistant","content":[{"type":"text","text":"a newer reply"}]}}' >> "$J"
chmod 000 "$J"                           # it changed, and can no longer be read
check "an unreadable transcript is reported" "$(build "$CF" | errors)" 1
check "  its last good page is kept" "$(has "$PAGE")" yes
check "  and it stays on the index" \
  "$(grep -q "$ID" "$T/f/out/index.html" && echo listed || echo gone)" listed
chmod 644 "$J"
check "readable again, it builds and the error clears" "$(build "$CF" | errors)" 0
check "  with the newer reply on its page" \
  "$(grep -q 'a newer reply' "$PAGE" && echo yes || echo no)" yes

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
