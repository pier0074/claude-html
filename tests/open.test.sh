#!/bin/bash
# Clicking a project name: what it resolves to, and what it refuses.
#
# Everything runs in plan mode, so nothing is actually opened, and in a home of
# its own. The "running server" case is a real listener started with netcat in
# the project's folder, because that is exactly what the resolution looks for.
#
#   bash tests/open.test.sh
set -u

. "$(dirname "$0")/lib.sh"
need_osascript "opening projects"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chopen)" && pwd)"
NC=""
trap '[ -n "$NC" ] && kill "$NC" 2>/dev/null; rm -rf "$T"' EXIT

ROOT="$T/root"; OUT="$ROOT/pages"
SITE=$ROOT/a-site; CODE=$ROOT/some-code; SERVED=$ROOT/a-server
mkdir -p "$SITE" "$CODE" "$SERVED" "$OUT" "$T/elsewhere"
echo "<h1>hello</h1>" > "$SITE/index.html"

ids() { printf '%s' "$1"; }
A=11111111-0000-0000-0000-00000000000a     # has an index.html
B=22222222-0000-0000-0000-00000000000b     # just code
C=33333333-0000-0000-0000-00000000000c     # has a server running
D=44444444-0000-0000-0000-00000000000d     # a claude.ai chat
E=55555555-0000-0000-0000-00000000000e     # a folder outside the projects root
cat > "$OUT/.manifest.json" <<EOF
{"$A":{"cwd":"$SITE","project":"a-site","kind":"transcript"},
 "$B":{"cwd":"$CODE","project":"some-code","kind":"transcript"},
 "$C":{"cwd":"$SERVED","project":"a-server","kind":"transcript"},
 "$D":{"cwd":"","project":"claude.ai","kind":"web"},
 "$E":{"cwd":"$T/elsewhere","project":"elsewhere","kind":"transcript"}}
EOF

resolve() {
  osascript -l JavaScript "$HERE/open.js" \
    "{\"id\":\"$1\",\"mode\":\"plan\",\"root\":\"$ROOT\",\"out\":\"$OUT\"}" 2>&1
}
what() { resolve "$1" | awk -F'\t' '{print $1}'; }
where() { resolve "$1" | awk -F'\t' '{print $2}'; }
refused() { resolve "$1" >/dev/null 2>&1 && echo allowed || echo refused; }

check "a project with a page opens the page" "$(what "$A")" page
check "  and it is that project's own page" "$(where "$A")" "$SITE/index.html"
check "a project with neither opens its folder" "$(what "$B")" folder
check "  which is the project itself" "$(where "$B")" "$CODE"

# A real listener, started in the project's folder.
PORT=$(( 20000 + RANDOM % 20000 ))
( cd "$SERVED" && exec nc -l "$PORT" >/dev/null 2>&1 ) & NC=$!
for _ in $(seq 1 20); do lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 && break; sleep 0.2; done
check "a project that is serving opens its server" "$(what "$C")" server
check "  on the port it is actually using" "$(where "$C")" "http://localhost:$PORT"
check "  and its neighbours are unaffected" "$(what "$A")" page
kill "$NC" 2>/dev/null; NC=""
sleep 0.5
check "once it stops serving, its folder again" "$(what "$C")" folder

check "a claude.ai chat is refused" "$(refused "$D")" refused
check "a folder outside the projects root is refused" "$(refused "$E")" refused
check "an id that is not in the index is refused" \
  "$(refused 99999999-0000-0000-0000-00000000000f)" refused
check "something that is not an id at all is refused" "$(refused 'oops; rm -rf /')" refused

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
