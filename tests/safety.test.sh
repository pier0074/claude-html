#!/bin/bash
# What a file from outside must never do to a build: write outside the pages
# directory, or break a page by what a conversation happens to say. And what
# a clone must never let a contributor commit by accident.
#
#   bash tests/safety.test.sh
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chsafety)" && pwd)"
trap 'rm -rf "$T"' EXIT
build() { HOME="$T/home" run_js "$HERE/convert.js" "$1"; }
has() { [ -e "$1" ] && echo yes || echo no; }
mkdir -p "$T/home"

# ── an export's uuid is a path component, so only a real uuid is one ──
# A conversations.json lands in Downloads by itself and is read on every
# save, so its ids are anyone's. These two once wrote outside the pages
# directory, the second over a viewer every page loads.
mkdir -p "$T/x/out/viewer" "$T/x/projects"
printf 'original\n' > "$T/x/out/viewer/viewer.js"
GOOD=aaaaaaaa-0000-0000-0000-000000000001
chat() {
  printf '{"uuid":%s,"name":"chat","created_at":"2026-05-01T10:00:00Z","chat_messages":[{"sender":"human","created_at":"2026-05-01T10:00:00Z","content":[{"type":"text","text":"hello"}]}]}' "$1"
}
printf '[%s,%s,%s,%s]\n' "$(chat '"../../pwned"')" "$(chat '"../viewer/viewer"')" \
  "$(chat '{"not":"a string"}')" "$(chat "\"$GOOD\"")" > "$T/x/conversations.json"
CX="{\"root\":\"$T/x/none\",\"out\":\"$T/x/out\",\"projects\":\"$T/x/projects\",\"here\":\"$HERE\",\"exportPath\":\"$T/x/conversations.json\"}"
R="$(build "$CX")"
check "nothing is written above the pages directory" \
  "$(find "$T" -name 'pwned*' | wc -l | tr -d ' ')" 0
check "  the viewer beside it is untouched" "$(cat "$T/x/out/viewer/viewer.js")" original
check "  each refused chat is reported" "$(printf '%s' "$R" | grep -o 'not a claude.ai conversation id' | wc -l | tr -d ' ')" 3
check "  and the genuine chat beside them still builds" "$(has "$T/x/out/sessions/$GOOD.html")" yes
check "  as the only session" "$(printf '%s' "$R" | sed -n 's/.*"sessions":\([0-9]*\).*/\1/p')" 1

# ── what a conversation says cannot end its own page's data early ──
# "<!--" then "<script" puts the HTML tokenizer where the data element's own
# end tag no longer ends it, and the page renders nothing at all.
mkdir -p "$T/e/out" "$T/e/projects/-x-app"
ID=bbbbbbbb-0000-0000-0000-000000000002
TEXT='look at this html: <!--<script> hello </script> and </SCRIPT >'
node -e 'console.log(JSON.stringify({type:"user",cwd:"/x/app",timestamp:"2026-09-11T10:00:00Z",message:{role:"user",content:process.argv[1]}}))' "$TEXT" \
  > "$T/e/projects/-x-app/$ID.jsonl"
CE="{\"root\":\"$T/e/none\",\"out\":\"$T/e/out\",\"projects\":\"$T/e/projects\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}"
build "$CE" >/dev/null
P="$T/e/out/sessions/$ID.html"
# Every "<" inside the data element is escaped, so the element ends where it should.
inside() {
  node -e 'var h=require("fs").readFileSync(process.argv[1],"utf8");
    var m=new RegExp("id=\"" + process.argv[2] + "-data\">([\\s\\S]*?)</script>").exec(h);
    var d=JSON.parse(m[1]); console.log(m[1].indexOf("<") + " " + JSON.stringify(eval(process.argv[3])));' "$1" "$2" "$3" 2>/dev/null
}
check "the session data holds no raw '<'" "$(inside "$P" session '0' | cut -d' ' -f1)" -1
check "  and reads back exactly as said" "$(inside "$P" session 'd.messages[0].text' | cut -d' ' -f2-)" \
  "$(node -e 'console.log(JSON.stringify(process.argv[1]))' "$TEXT")"
check "  the viewer scripts after it are still scripts" \
  "$(grep -c '^<script>' "$P")" "$(grep -c '^<script>' "$HERE/viewer/page.html")"
check "the index, which shows it as a title, holds no raw '<' either" \
  "$(inside "$T/e/out/index.html" index '0' | cut -d' ' -f1)" -1
# The symptom itself, where there is a browser to see it: an empty page.
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ -x "$CHROME" ]; then
  check "  and the page renders the message in a browser" \
    "$("$CHROME" --headless=new --disable-gpu --no-sandbox --user-data-dir="$T/chrome" \
        --dump-dom "file://$P" 2>/dev/null | grep -c 'id="m0"')" 1
else
  printf '  skip  no Chrome here — the rendering half runs where there is one\n'
fi

# ── a clone never offers a conversation archive for commit ──────────
# The hook archives into whatever folder a session ran in, and that can be
# the clone itself. A worktree's .git is a file, not a folder, so ask git
# itself whether this is a checkout: testing for a .git folder once skipped
# these four in every worktree without a word.
if command -v git >/dev/null 2>&1 \
   && [ "$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$HERE" && pwd -P)" ]; then
  check "the clone ignores conversation archives" \
    "$(git -C "$HERE" check-ignore -q --no-index .claude/.claude-conversations/x.json && echo ignored || echo tracked)" ignored
  # A personal global ignore can hide a gap here, and CI has none, so every
  # check below sets it aside.
  check "  by the repository's own rule, not a personal one" \
    "$(git -C "$HERE" -c core.excludesFile=/dev/null check-ignore -q --no-index .claude/.claude-conversations/x.json && echo ignored || echo tracked)" ignored
  check "  wherever the archive sits in it" \
    "$(git -C "$HERE" -c core.excludesFile=/dev/null check-ignore -q --no-index tests/.claude/.claude-conversations/x.json && echo ignored || echo tracked)" ignored
  check "  while the rest of a .claude folder stays committable" \
    "$(git -C "$HERE" -c core.excludesFile=/dev/null check-ignore -q --no-index .claude/settings.json && echo ignored || echo tracked)" tracked
else
  printf '  skip  not a git clone — the ignore rule is checked where there is one\n'
fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
