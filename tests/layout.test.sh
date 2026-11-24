#!/bin/bash
# Moving between a release from before the folders (lib/, build/, actions/,
# mac/, linux/) and this tree, both ways, with each release's own
# claude-html, update.sh and install.sh.
#
# settings.json calls save-conversation.sh, guard.sh and statusline.sh at
# the top of the clone by their full path, and an update checks the new
# release out before it runs that release's install.sh: in between, the
# hooks the old install wrote run the new scripts, and after a going back,
# the hooks the new install wrote run the old ones. Each must still work.
#
# Everything is in a sandbox: a throwaway release repository made of the
# last release before the folders (v3.4.0, from this repository's own tag)
# and of this tree as 3.5.0, an install cloned from it, and a home of its
# own. Without the tag (a shallow CI checkout) it skips.
#
#   bash tests/layout.test.sh
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
OLDV=3.4.0 NEWV=3.5.0
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
has() {   # name, text, what it must hold
  case "$2" in *"$3"*) pass=$((pass + 1)); printf '  ok    %s\n' "$1" ;;
    *) fail=$((fail + 1)); printf '  FAIL  %s (no "%s" in: %s)\n' "$1" "$3" "$2" ;; esac
}

export GIT_CONFIG_NOSYSTEM=1
if ! OLDC="$(git -C "$HERE" rev-parse -q --verify "refs/tags/v$OLDV^{commit}" 2>/dev/null)"; then
  echo "  skip  no v$OLDV tag in this checkout (a shallow clone?): the move from before the folders is not tested here"
  exit 0
fi

T="$(cd "$(tmpdir chlayout)" && pwd -P)"
trap 'rm -rf "$T"' EXIT
H="$T/home"; PROJ="$T/projects"; APP="$PROJ/app"; PAGES="$T/pages"
mkdir -p "$H/.claude" "$APP"
gitx() { HOME="$H" XDG_CONFIG_HOME="$H/.config" git -c user.name=tester -c user.email=tester@example.invalid \
           -c init.defaultBranch=main -c advice.detachedHead=false "$@"; }
# Every command below runs in the sandbox's home, against its release
# repository, with no window: the guard's dialog is off, and nothing here
# holds a secret for it to find anyway.
run() { env HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_DATA_HOME="$H/.local/share" \
          CLAUDE_HTML_UPDATE_REMOTE="$BARE" CLAUDE_HTML_UPDATE_CHECK=off \
          CLAUDE_HTML_GUARD_DIALOG=off CLAUDE_HTML_NO_REGISTER=1 "$@"; }

# ── the release repository: v3.4.0 as it was, then this tree ─────────
W="$T/work"; mkdir -p "$W"; gitx init -q "$W"
git -C "$HERE" archive "$OLDC" | tar -x -C "$W"
rm -rf "$W/dev"
gitx -C "$W" add -A && gitx -C "$W" commit -q -m "$OLDV" && gitx -C "$W" tag "v$OLDV"
find "$W" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
( cd "$HERE" && git ls-files -z | grep -zv '^dev/' | xargs -0 tar -cf - ) | tar -x -C "$W"
echo "$NEWV" > "$W/VERSION"
{ printf '# Changelog\n\n## %s — 2026-11-24\n\n- the files in folders.\n\n' "$NEWV"
  sed '1,2d' "$W/CHANGELOG.md"; } > "$W/c.tmp" && mv "$W/c.tmp" "$W/CHANGELOG.md"
gitx -C "$W" add -A && gitx -C "$W" commit -q -m "$NEWV" && gitx -C "$W" tag "v$NEWV"
BARE="$T/release.git"; gitx clone -q --bare "$W" "$BARE"
check "the two releases: one before the folders, one in them" \
  "$(gitx -C "$BARE" cat-file -e "v$OLDV:conf.sh" && echo top) $(gitx -C "$BARE" cat-file -e "v$NEWV:lib/conf.sh" && echo lib)" "top lib"

# ── an install of the old release, by its own install.sh ─────────────
clone() {   # name, release
  INST="$T/$1/claude-html"
  rm -rf "$T/$1"; mkdir -p "$T/$1"
  gitx clone -q "$BARE" "$INST"
  gitx -C "$INST" reset -q --hard "v$2"
  INST="$(cd -P "$INST" && pwd)"
}
install() { (cd "$INST" && run bash ./install.sh --root "$PROJ" --out "$PAGES") </dev/null >"$T/install.out" 2>&1; }
at() { cat "$INST/VERSION"; }

ID=dddddddd-0000-0000-0000-000000000350
D="$(printf '%s' "$APP" | tr '/' '-')"
J="$H/.claude/projects/$D/$ID.jsonl"; mkdir -p "${J%/*}"
printf '%s\n' '{"type":"user","cwd":"'"$APP"'","sessionId":"'"$ID"'","timestamp":"2026-11-24T10:00:00Z","message":{"role":"user","content":"the first prompt"}}' > "$J"
N=0
say() {   # a new reply in the transcript, with a word to look for on the page
  N=$((N + 1))
  printf '%s\n' '{"type":"assistant","cwd":"'"$APP"'","sessionId":"'"$ID"'","timestamp":"2026-11-24T10:0'"$N"':00Z","message":{"role":"assistant","content":[{"type":"text","text":"reply-marker-'"$1"'"}]}}' >> "$J"
}

# The hooks settings.json holds, run as Claude Code runs them: each
# command through bash, its note on stdin, in the project.
hook_cmds() {   # event -> its commands, one per line
  node -e 'var s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (process.argv[2] === "statusLine") { if (s.statusLine) console.log(s.statusLine.command); }
    else (s.hooks[process.argv[2]] || []).forEach(function (g) { (g.hooks || []).forEach(function (h) { console.log(h.command); }); });' \
    "$H/.claude/settings.json" "$1"
}
note() {   # event, [prompt or command]
  case "$1" in
    UserPromptSubmit) printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s","prompt":"%s"}' "$ID" "$J" "$APP" "$1" "$2" ;;
    PreToolUse) printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$ID" "$J" "$APP" "$1" "$2" ;;
    statusLine) printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","model":{"display_name":"Opus"}}' "$ID" "$J" "$APP" ;;
    *) printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s"}' "$ID" "$J" "$APP" "$1" ;;
  esac
}
# A save in the background is waited for, the lock it takes and then the
# process itself, so the next step never moves the clone under it.
wait_saves() {
  local _
  for _ in $(seq 1 1200); do [ -d "$H/.claude/.claude-html.lock" ] || break; sleep 0.1; done
  for _ in $(seq 1 1200); do
    ps ax -o command= 2>/dev/null | grep -F "$INST/save-conversation.sh" | grep -qv grep || return 0
    sleep 0.1
  done
}
# Every hook of every event: what each exits with, and what the guard
# says (nothing, for a prompt and a command with no secret in them).
hooks_run() {   # label, word the save must put on the page
  local ev c rc out bad="" n=0
  say "$2"
  for ev in UserPromptSubmit PreToolUse SessionEnd PreCompact Stop statusLine; do
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      n=$((n + 1))
      out="$(note "$ev" "list the files" | (cd "$APP" && run bash -c "$c") 2>"$T/hook.err")"; rc=$?
      [ "$rc" = 0 ] || bad="$bad $ev:exit$rc"
      case "$ev" in UserPromptSubmit|PreToolUse) [ -z "$out" ] || bad="$bad $ev:said" ;; esac
      [ -s "$T/hook.err" ] && bad="$bad $ev:stderr($(head -c 120 "$T/hook.err" | tr '\n' ' '))"
      wait_saves
    done < <(hook_cmds "$ev")
  done
  check "$1: all $n hooks run cleanly" "${bad:-none}" none
  check "  the save put the new reply on the page" \
    "$(grep -c "reply-marker-$2" "$PAGES/sessions/$ID.html" 2>/dev/null)" 1
  # The guard fails open, so a clean pass proves little: a prompt with a
  # token in it is stopped, in words, and the answer to it is understood.
  local said="" c
  while IFS= read -r c; do
    said="$said$(note UserPromptSubmit "my token is $TOK" | (cd "$APP" && run bash -c "$c") 2>/dev/null |
      grep -c '"decision":"block"')"
    said="$said $(note UserPromptSubmit cancel | (cd "$APP" && run bash -c "$c") 2>/dev/null | grep -c 'Dropped')"
  done < <(hook_cmds UserPromptSubmit)
  check "  the guard stops a token, then takes the answer" "$said" "1 1"
}
# A token for the guard to find, put together from pieces as the suites do.
TOK="$(node -e 'var F=require(process.argv[1]); process.stdout.write(F.cases.filter(function(c){return c.rule==="github"})[0].secret)' "$HERE/tests/fixtures/fake-secrets.js")"
hook_paths() { grep -o "$INST/[a-z-]*\.sh" "$H/.claude/settings.json" | sort -u | sed "s|$INST/||" | tr '\n' ' '; }

echo "an install of $OLDV"
clone a "$OLDV"
install
check "its install ran" "$(grep -c 'done — open' "$T/install.out")" 1
check "  its hooks call the scripts at the top of the clone" "$(hook_paths)" "guard.sh save-conversation.sh statusline.sh "
hooks_run "$OLDV" old1

# ── between the checkout and the install ─────────────────────────────
# What update.sh does in between, done by hand: the new release is on
# disk, the old install's hooks still in settings.json.
gitx -C "$INST" checkout -q --detach "v$NEWV"
hooks_run "$NEWV checked out, $OLDV's hooks" mid1
gitx -C "$INST" checkout -q --detach "v$OLDV"
hooks_run "and back on $OLDV" mid2

# ── the update, by the old release's command ─────────────────────────
echo "update $OLDV → $NEWV"
gitx -C "$INST" checkout -q main 2>/dev/null; gitx -C "$INST" reset -q --hard "v$OLDV"
out="$(run bash "$INST/claude-html" --update </dev/null 2>&1)"; rc=$?
check "the update succeeds" "$rc" 0
has "  and says so" "$out" "Updated $OLDV → $NEWV."
check "  the clone is $NEWV, in folders, nothing changed or left over" \
  "$(at) $([ -f "$INST/lib/platform.sh" ] && [ ! -e "$INST/platform.sh" ] && echo folders) $(gitx -C "$INST" status --porcelain --untracked-files=no | wc -l | tr -d ' ')" \
  "$NEWV folders 0"
check "  its hooks still call the same three scripts" "$(hook_paths)" "guard.sh save-conversation.sh statusline.sh "
hooks_run "$NEWV, installed" new1
check "  the command is the clone's" "$(run bash "$H/.local/bin/claude-html" --version 2>&1)" "claude-html $NEWV"

# The new install's hooks, with the old release checked out under them,
# as a going back leaves them until its install has run.
gitx -C "$INST" checkout -q --detach "v$OLDV"
hooks_run "$OLDV checked out, $NEWV's hooks" mid3
gitx -C "$INST" checkout -q main

# ── going back, by the new release's command ─────────────────────────
echo "back $NEWV → $OLDV"
out="$(run bash "$INST/claude-html" --update "$OLDV" --yes </dev/null 2>&1)"; rc=$?
check "going back succeeds" "$rc" 0
has "  and says so" "$out" "Updated $NEWV → $OLDV."
has "  the archive formats are read from each release's own file" "$out" "both write archive format"
check "  no build or install failed on the way" "$(printf '%s' "$out" | grep -c 'failed')" 0
check "  the clone is $OLDV, at its top again" \
  "$(at) $([ -f "$INST/platform.sh" ] && [ ! -e "$INST/lib" ] && echo top) $(gitx -C "$INST" status --porcelain --untracked-files=no | wc -l | tr -d ' ')" \
  "$OLDV top 0"
check "  its hooks still call the same three scripts" "$(hook_paths)" "guard.sh save-conversation.sh statusline.sh "
hooks_run "$OLDV, installed again" old2

# ── and forward once more, from the release gone back to ─────────────
out="$(run bash "$INST/claude-html" --update </dev/null 2>&1)"; rc=$?
check "forward again succeeds" "$rc $(at)" "0 $NEWV"
hooks_run "$NEWV again" new2

echo
echo "  $pass passed, $fail failed"
[ "$fail" = 0 ]
