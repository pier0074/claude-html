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

# ── a transcript the parser no longer understands keeps its page ────
# Claude Code renaming its record types would make every transcript parse to
# nothing. That must read as a failure to report, never as "every session is
# gone" — which used to prune the whole site and call it success.
mkdir -p "$T/z/out" "$T/z/projects/-x-app"
ID=eeeeeeee-0000-0000-0000-000000000005
J="$T/z/projects/-x-app/$ID.jsonl"
PAGE="$T/z/out/sessions/$ID.html"
{
  printf '%s\n' '{"type":"user","cwd":"/x/app","timestamp":"2026-09-11T10:00:00Z","message":{"role":"user","content":"a question in the old format"}}'
  printf '%s\n' '{"type":"assistant","cwd":"/x/app","timestamp":"2026-09-11T10:00:01Z","message":{"role":"assistant","content":[{"type":"text","text":"an answer"}]}}'
} > "$J"
CZ="{\"root\":\"$T/z/none\",\"out\":\"$T/z/out\",\"projects\":\"$T/z/projects\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}"
build "$CZ" >/dev/null
sed 's/"type":"user"/"type":"human"/; s/"type":"assistant"/"type":"model"/' "$J" > "$J.new" && mv "$J.new" "$J"
R="$(build "$CZ")"
check "a transcript that now parses to nothing is reported" "$(printf '%s' "$R" | errors)" 1
check "  nothing is removed" "$(printf '%s' "$R" | sed -n 's/.*"removed":\([0-9]*\).*/\1/p')" 0
check "  its last good page is kept" "$(has "$PAGE")" yes
check "  with its search file" "$(has "$T/z/out/search/$ID.js")" yes
check "  and it stays on the index" \
  "$(grep -q "$ID" "$T/z/out/index.html" && echo listed || echo gone)" listed
check "  and the error is left for the next look" "$(has "$T/z/out/.build-errors.json")" yes

# A run that finds no session at all, where pages exist, is a run that lost
# sight of them: a moved folder, a wrong HOME. It must not prune.
rm "$J"
R="$(build "$CZ")"
check "finding nothing where pages exist removes nothing" \
  "$(printf '%s' "$R" | sed -n 's/.*"removed":\([0-9]*\).*/\1/p')" 0
check "  and says so" "$(printf '%s' "$R" | grep -c 'nothing was removed')" 1
check "  the page is still there" "$(has "$PAGE")" yes
check "  and still listed" "$(grep -q "$ID" "$T/z/out/index.html" && echo listed || echo gone)" listed
check "  the manifest still knows it" "$(grep -c "$ID" "$T/z/out/.manifest.json")" 1

# The same with the manifest gone too: the pages on disk are what count.
rm "$T/z/out/.manifest.json"
R="$(build "$CZ")"
check "finding nothing with no manifest removes nothing either" \
  "$(printf '%s' "$R" | sed -n 's/.*"removed":\([0-9]*\).*/\1/p')" 0
check "  and says so" "$(printf '%s' "$R" | grep -c 'nothing was removed')" 1
check "  the page is still there" "$(has "$PAGE")" yes
check "  with its search file" "$(has "$T/z/out/search/$ID.js")" yes

# A brand-new transcript with nothing to show yet is not an error: only one
# that used to have a page is.
mkdir -p "$T/n/out" "$T/n/projects/-x-app"
printf '%s\n' '{"type":"user","isMeta":true,"cwd":"/x/app","timestamp":"2026-09-11T10:00:00Z","message":{"role":"user","content":"harness context"}}' \
  > "$T/n/projects/-x-app/ffffffff-0000-0000-0000-000000000006.jsonl"
CN="{\"root\":\"$T/n/none\",\"out\":\"$T/n/out\",\"projects\":\"$T/n/projects\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}"
check "a new transcript with nothing in it yet is no error" "$(build "$CN" | errors)" 0

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
