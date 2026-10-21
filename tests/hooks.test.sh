#!/bin/bash
# The hooks name their transcript on stdin, so a save need not search for it.
#
# The session here is filed under another directory and records another cwd,
# as after a project is renamed — so searching this folder's sessions cannot
# find it, and only the hook's note can. That is what tells the two apart.
#
#   bash tests/hooks.test.sh
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chhooks)" && pwd)"
trap 'rm -rf "$T"' EXIT

ROOT="$T/root"; APP="$ROOT/app"
D="$(printf '%s' "$APP" | tr '/' '-')"
mkdir -p "$T/home/.claude/projects/$D" "$T/home/.claude/projects/-elsewhere" "$APP" "$ROOT/pages"
printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$ROOT" "$ROOT/pages" \
  > "$T/home/.claude/claude-html.conf"

ID=eeeeeeee-0000-0000-0000-000000000005
J="$T/home/.claude/projects/-elsewhere/$ID.jsonl"
printf '%s\n' '{"type":"user","cwd":"/somewhere/old","timestamp":"2026-09-11T10:00:00Z","message":{"role":"user","content":"named by the hook"}}' > "$J"
A="$APP/.claude/.claude-conversations/$ID.json"
NOTE="{\"session_id\":\"$ID\",\"transcript_path\":\"$J\",\"cwd\":\"$APP\",\"hook_event_name\":\"Stop\"}"
save() { env HOME="$T/home" /bin/bash -c "cd '$APP' && /bin/bash '$HERE/save-conversation.sh' $1" >/dev/null 2>&1; }
found() { sed -n 's/.*found=\([a-z]*\).*/\1/p' "$ROOT/pages/.last-save" 2>/dev/null; }
exists() { [ -f "$1" ] && echo yes || echo no; }

save "" </dev/null
check "run by hand, it searches" "$(found)" search
check "  and cannot find a session filed elsewhere" "$(exists "$A")" no

printf '%s' "$NOTE" | save "--try"
check "given the hook's note, it does not search" "$(found)" hook
check "  and archives the session it names" "$(exists "$A")" yes

# The reply hook detaches, and the detached copy has no stdin: the note must
# survive the hand-off.
rm -f "$A"
printf '%s' "$NOTE" | save "--background"
for _ in $(seq 1 60); do [ -f "$A" ] && break; sleep 0.25; done
check "the detached save still knows which transcript" "$(exists "$A")" yes

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
