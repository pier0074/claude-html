#!/bin/bash
# The guard's hook: Claude Code runs it before a prompt is sent
# (UserPromptSubmit) and before a Bash command runs (PreToolUse), with its
# JSON note on stdin. guard.js does the judging; this decides whether it
# needs to run at all.
#
#   guard.sh prompt     guard.sh bash
#
# It fails open: whatever goes wrong — no engine, no redact.js, a note it
# cannot read — it prints nothing and exits 0, and the prompt or the
# command goes ahead as if it were not here.

KIND="${1:-}"
case "$KIND" in prompt|bash) ;; *) exit 0 ;; esac
NOTE=""
IFS= read -r -t 5 -d '' NOTE || true
[ -n "$NOTE" ] || exit 0

# Every fork costs a few milliseconds on every prompt, so the common path
# takes none it can do without.
HERE="${BASH_SOURCE[0]%/*}"
[ "$HERE" = "${BASH_SOURCE[0]}" ] && HERE=.
case "$HERE" in /*) ;; *) HERE="$PWD/$HERE" ;; esac
# shellcheck source=conf.sh
. "$HERE/conf.sh" 2>/dev/null || exit 0
case "${CLAUDE_HTML_GUARD:-on}" in
  [Oo][Ff][Ff]|0|[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]) exit 0 ;;
  [Pp][Rr][Oo][Mm][Pp][Tt]) [ "$KIND" = bash ] && exit 0 ;;
esac
STATE="$HOME/.claude/.claude-html.guard"
LIST="${CLAUDE_HTML_REDACT_FILE:-$HOME/.claude/claude-html.redact}"

# Most prompts and commands hold nothing a rule could start at, and need
# no JavaScript engine at all: every text a rule of redact.js starts from
# is looked for here, in any case, in the note less the fields that are
# not what was typed. tests/guard.test.sh checks that this list holds
# every one of them. Skipped when an answer may be pending, or when the
# owner's list has entries of its own, which can match anything.
ANCHORS='-----begin |eyj|sk-|gh|github_pat_|glpat-|ia|acca|aiza|xox|xapp-|hooks.slack.com/|_live_|_test_|whsec_|npm_|pypi-|hf_|sg.|twilio|:aa|discord|bearer|://|-u|pass|pwd|secret|token|key|auth|credential|mdp|cookie|-p|sshpass'
if [ ! -f "$STATE" ] &&
   ! { [ -f "$LIST" ] && grep -qvE '^[[:space:]]*(#|safe:|$)' "$LIST" 2>/dev/null; }; then
  TEXT="$(printf '%s' "$NOTE" |
    sed -E 's/"(transcript_path|cwd|session_id|permission_mode|hook_event_name|tool_use_id|tool_name|agent_id|agent_type)"[[:space:]]*:[[:space:]]*"[^"]*"//g')"
  printf '%s' "$TEXT" | LC_ALL=C grep -qiE -e "$(printf '%s' "$ANCHORS" | sed 's/[.]/[.]/g')" || exit 0
fi

# Which engine: picked once a day and remembered, since asking node for its
# version on every prompt would cost more than the check itself.
ENGINE_CACHE="$HOME/.claude/.claude-html.guard-engine"
CH_ENGINE=""; CH_NODE=""; CH_OSASCRIPT=""
if [ -f "$ENGINE_CACHE" ] && [ -n "$(find "$ENGINE_CACHE" -mtime -1 2>/dev/null)" ]; then
  IFS='|' read -r _want CH_ENGINE CH_NODE < "$ENGINE_CACHE"
  [ "$_want" = "${CLAUDE_HTML_ENGINE:-}" ] || CH_ENGINE=""
  [ "$CH_ENGINE" = node ] && [ ! -x "$CH_NODE" ] && CH_ENGINE=""
fi
# shellcheck source=platform.sh
. "$HERE/platform.sh" 2>/dev/null || exit 0
if [ -z "$CH_ENGINE" ]; then
  ch_pick_engine
  ( umask 077; printf '%s|%s|%s\n' "${CLAUDE_HTML_ENGINE:-}" "$CH_ENGINE" "$CH_NODE" > "$ENGINE_CACHE" ) 2>/dev/null
else
  CH_OSASCRIPT=osascript
fi

# Someone at the screen answers in a dialog; with no one there — ssh, no
# desktop, CLAUDE_HTML_GUARD_DIALOG=off — the answer is typed as the next
# prompt instead. Which it is, is worked out only once there is something
# to ask about, and before anything is opened.
CH_HERE="$HERE"; DIALOG=dialog
case "${CLAUDE_HTML_GUARD_DIALOG:-on}" in [Oo][Ff][Ff]|0|[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]) DIALOG="" ;; esac
OUT_JSON="$(printf '%s' "$NOTE" | ch_js "$HERE/guard.js" "$KIND" "$HERE" "$STATE" "$LIST" "$CONF" "$DIALOG" 2>/dev/null)" || exit 0
case "$OUT_JSON" in
  '{"choose":'*)
    FOUND="$(printf '%s' "$OUT_JSON" | sed -n 's/^{"choose":"\([^"]*\)".*/\1/p')"
    PROJ="$(printf '%s' "$OUT_JSON" | sed -n 's/.*"project":"\([^"]*\)"}$/\1/p')"
    ANS=""
    # No one to ask is no answer, which is the answer in words, as the
    # next prompt.
    if ch_detect 2>/dev/null && ch_can_ask; then ANS="$(ch_choose "$KIND" "$PROJ" "$FOUND" 2>/dev/null)" || ANS=""; fi
    OUT_JSON="$(printf '%s' "$NOTE" | ch_js "$HERE/guard.js" "answer-$KIND" "$HERE" "$STATE" "$LIST" "$CONF" "$ANS" "$CH_GUARD_LIMIT" 2>/dev/null)" || exit 0 ;;
esac
# Only a decision is ever passed on: never an error, never anything else.
case "$OUT_JSON" in '{'*'}') printf '%s\n' "$OUT_JSON" ;; esac
exit 0
