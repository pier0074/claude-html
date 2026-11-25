#!/bin/bash
# What a build must never do: fail to rebuild a claude.ai chat because its
# export has not changed, or lose a page because one attempt to build it failed.
# Both happened: the first deleted 23 pages on the way to the second.
#
#   bash tests/build.test.sh
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
T="$(cd "$(tmpdir chbuild)" && pwd)"
trap 'chmod -R u+rw "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/home"
build() { HOME="$T/home" run_js "$HERE/build/convert.js" "$1"; }
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

# ── a transcript of more than 512 MiB ───────────────────────────────
# Read whole, it was more than a string can hold: the read failed and the
# session left the index without a word. Sparse, so it costs no disk: a
# first line, a hole of 600 MiB of zeros (one "line" too long to parse),
# and a last line after it.
mkdir -p "$T/g/out" "$T/g/projects/-x-app"
ID=eeeeeeee-0000-0000-0000-000000000005
J="$T/g/projects/-x-app/$ID.jsonl"
printf '%s\n' '{"type":"user","cwd":"/x/app","timestamp":"2026-09-11T10:00:00Z","message":{"role":"user","content":"the first question of a huge one"}}' > "$J"
dd if=/dev/null of="$J" bs=1 count=0 seek=629145600 2>/dev/null
printf '\n%s\n' '{"type":"user","cwd":"/x/app","timestamp":"2026-09-11T11:00:00Z","message":{"role":"user","content":"the last question, after the hole"}}' >> "$J"
CG="{\"root\":\"$T/g/none\",\"out\":\"$T/g/out\",\"projects\":\"$T/g/projects\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}"
check "a transcript over 512 MiB is built, not dropped" \
  "$(build "$CG" | sed -n 's/.*"sessions":\([0-9]*\).*/\1/p') $(grep -c "$ID" "$T/g/out/index.html" 2>/dev/null)" "1 1"
check "  with what comes before the line too long to read, and after it" \
  "$(grep -c 'the first question of a huge one' "$T/g/out/sessions/$ID.html") $(grep -c 'the last question, after the hole' "$T/g/out/sessions/$ID.html")" "1 1"
rm -rf "$T/g"

# Read a piece at a time: the same page however small the pieces, a line
# longer than a piece included; one longer than the longest line read is
# passed over, and the rest of the session is still there.
mkdir -p "$T/k/projects/-x-app"
ID=eeeeeeee-0000-0000-0000-000000000007
J="$T/k/projects/-x-app/$ID.jsonl"
LONGTXT="$(head -c 30000 /dev/zero | tr '\0' 'x')"
{ for i in 1 2 3 4 5 6 7 8 9; do
    printf '{"type":"user","cwd":"/x/app","timestamp":"2026-09-11T10:0%s:00Z","message":{"role":"user","content":"question %s with some words in it to fill the lines"}}\n' "$i" "$i"
    printf '{"type":"assistant","cwd":"/x/app","timestamp":"2026-09-11T10:0%s:30Z","message":{"id":"m%s","role":"assistant","content":[{"type":"text","text":"answer %s, plain"}]}}\n' "$i" "$i" "$i"
    [ "$i" = 5 ] && printf '{"type":"user","cwd":"/x/app","timestamp":"2026-09-11T10:05:40Z","message":{"role":"user","content":"a long one %s"}}\n' "$LONGTXT"
  done; } > "$J"
ck() { printf '{"root":"%s/k/none","out":"%s/k/%s","projects":"%s/k/projects","here":"%s","exportPath":"/nonexistent"%s}' "$T" "$T" "$1" "$T" "$HERE" "${2:-}"; }
build "$(ck whole)" >/dev/null
build "$(ck pieces ',"readChunk":4096')" >/dev/null
check "built in 4 KiB pieces, the page is the page built whole" \
  "$(cmp -s "$T/k/whole/sessions/$ID.html" "$T/k/pieces/sessions/$ID.html" && echo same || echo different)" same
check "  and so is its search file" \
  "$(cmp -s "$T/k/whole/search/$ID.js" "$T/k/pieces/search/$ID.js" && echo same || echo different)" same
build "$(ck short ',"readChunk":4096,"lineMax":8192')" >/dev/null
check "a line longer than can be read is passed over, the rest kept" \
  "$(grep -c 'a long one' "$T/k/short/sessions/$ID.html") $(grep -c 'question 9 with' "$T/k/short/sessions/$ID.html") $(grep -c 'question 1 with' "$T/k/short/sessions/$ID.html")" "0 1 1"

echo
verdict
