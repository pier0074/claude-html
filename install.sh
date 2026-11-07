#!/bin/bash
# Install claude-html. Run it from wherever you cloned this.
set -euo pipefail

# Editing settings.json and building the helper are a Mac's own work, done
# with osascript there; node elsewhere. The JavaScript is the same under both.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# What kind of machine this is, and which of its own tools it has.
# shellcheck source=platform.sh
. "$HERE/platform.sh"
ch_detect
ch_pick_engine
if [ -z "${CLAUDE_HTML_FORCE_NODE:-}" ] && command -v osascript >/dev/null 2>&1; then
  run_js() { osascript -l JavaScript "$@"; }; MAC=true
else
  # The node the engine check found, which need not be on PATH.
  run_js() { ch_node_run "${CH_NODE:-node}" "$@"; }; MAC=false
fi
CONF="${CLAUDE_HTML_CONF:-$HOME/.claude/claude-html.conf}"
SETTINGS="$HOME/.claude/settings.json"

usage() {
  cat <<EOF
claude-html — read, search and resume your Claude Code sessions as static HTML.

Usage
  ./install.sh                    install, using the defaults below
  ./install.sh --out DIR          write pages to DIR instead
  ./install.sh --root DIR         watch DIR instead
  ./install.sh --uninstall        remove the command and the hooks
  ./install.sh --help             this

Defaults
  pages     $HERE
            (the folder this script is in)
  projects  $(dirname "$HERE")
            (sessions started here or below are archived)

What it changes
  ~/.claude/claude-html.conf   the two directories above; a later run adds
                               only what is missing, and --out or --root
                               change just their own line
  ~/.claude/settings.json      adds hooks that save after every reply and at
                               session end, keeping anything already there
  ~/.local/bin/claude-html     a symlink, so you can type claude-html
  Claude HTML.app              macOS: beside this script, handles the index's
                               delete, open and resume links, and asks before
                               it deletes anything
  ~/.local/share/applications/claude-html-handler.desktop
                               Linux: the same, through handler.sh, registered
                               with xdg-mime where there is a desktop for it

Needs nothing extra: osascript on macOS, node on Linux — the machine has one.
Where both are, node builds the pages, being faster; nothing is installed.

It asks nothing and moves nothing. Run it again any time: it adds only what is
missing, and never overwrites a setting you chose. --uninstall reverses it and
leaves your pages alone.
EOF
}

ROOT=""; OUT=""; UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --out)  OUT="$2";  shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; echo "try --help" >&2; exit 1 ;;
  esac
done

say() { printf '  %s\n' "$1"; }
expand() { printf '%s' "${1/#\~/$HOME}"; }

# ── uninstall ───────────────────────────────────────────────────────
if [ "$UNINSTALL" = 1 ]; then
  for d in "$HOME/.local/bin" /usr/local/bin; do
    [ -L "$d/claude-html" ] && rm -f "$d/claude-html" && say "removed $d/claude-html"
  done
  LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  if [ -d "$HERE/Claude HTML.app" ]; then
    "$LSREG" -u "$HERE/Claude HTML.app" >/dev/null 2>&1 || true
    rm -rf "$HERE/Claude HTML.app" && say "removed the delete helper"
  fi
  if [ "$CH_OS" = linux ]; then
    GONE="$(ch_unregister_handler)" && say "$GONE" || true
  fi
  RESULT="$(run_js "$HERE/settings-hooks.js" "$SETTINGS" "$HERE" remove 2>/dev/null || true)"
  case "$RESULT" in
    unparseable) say "settings.json is not valid JSON — left alone" ;;
    removed*)    say "$RESULT hook(s); everything else in settings.json is untouched" ;;
    *)           say "could not update $SETTINGS — remove the hooks yourself" ;;
  esac
  say "your pages, archives and cleanupPeriodDays are left as they are"
  exit 0
fi

echo; echo "claude-html"; echo


# ── 1. where things go ──────────────────────────────────────────────
# Nothing to ask: you cloned this where you want the pages, so that is where
# they go, and the projects it watches are the ones beside it. --out and
# --root override either.
#
# The conf is the user's once written: they may have edited it, or added
# settings this script knows nothing about. So a later run keeps every line,
# adds only what is missing, and changes ROOT or OUT only when told to.
conf_value() {
  # Double quotes keep a space; these four are what is still special in them.
  printf '"%s"' "$(printf '%s' "$1" | sed 's/[\\"$`]/\\&/g')"
}
conf_has() { grep -Eq "^[[:space:]]*(export[[:space:]]+)?$1=" "$CONF"; }
conf_set() {
  # Replaced where it stands, so its comments and neighbours stay put. Copied
  # back rather than moved: a conf kept with the user's dotfiles is a symlink,
  # and a move would leave their real file behind, unchanged.
  local tmp="$CONF.tmp.$$"
  KEY="$1" LINE="$1=$(conf_value "$2")" awk '
    $0 ~ "^[[:space:]]*(export[[:space:]]+)?" ENVIRON["KEY"] "=" { print ENVIRON["LINE"]; next }
    { print }' "$CONF" > "$tmp" && cat "$tmp" > "$CONF" && rm -f "$tmp"
}
conf_add() {
  # An editor that saves without a final newline would otherwise have the new
  # line glued onto the user's last one, spoiling both.
  [ -z "$(tail -c 1 "$CONF")" ] || echo >> "$CONF"
  printf '%s\n' "$1" >> "$CONF"
}
WEEK_NOTE='
# When your plan'"'"'s weekly allowance resets, so the token dashboard'"'"'s weeks
# line up with the ones you are actually billed for. Your reset day and hour
# are fixed per account — Claude Code shows them when you near a limit.
# Local time, e.g. "tue 09:00". Left out, weeks are calendar Mondays.
#CLAUDE_HTML_WEEK_RESET="tue 09:00"'

if [ -n "$OUT" ]; then OUT="$(expand "$OUT")"; OUT="${OUT%/}"; fi
if [ -n "$ROOT" ]; then ROOT="$(expand "$ROOT")"; ROOT="${ROOT%/}"; fi
mkdir -p "$(dirname "$CONF")"
if [ ! -f "$CONF" ]; then
  {
    echo "# Written by install.sh, and yours from now on: running it again only adds"
    echo "# what is missing. An environment variable of the same name wins over it."
    echo "CLAUDE_HTML_ROOT=$(conf_value "${ROOT:-$(dirname "$HERE")}")"
    echo "CLAUDE_HTML_OUT=$(conf_value "${OUT:-$HERE}")"
    printf '%s\n' "$WEEK_NOTE"
  } > "$CONF"
else
  if conf_has CLAUDE_HTML_ROOT; then [ -z "$ROOT" ] || conf_set CLAUDE_HTML_ROOT "$ROOT"
  else conf_add "CLAUDE_HTML_ROOT=$(conf_value "${ROOT:-$(dirname "$HERE")}")"; fi
  if conf_has CLAUDE_HTML_OUT; then [ -z "$OUT" ] || conf_set CLAUDE_HTML_OUT "$OUT"
  else conf_add "CLAUDE_HTML_OUT=$(conf_value "${OUT:-$HERE}")"; fi
  # Offered once, commented out, as a first install offers it. A line for it
  # in any form means the user has seen it, and maybe chosen to leave it out.
  grep -q 'CLAUDE_HTML_WEEK_RESET' "$CONF" || conf_add "$WEEK_NOTE"
fi

# What the command and the hook will now use, by the rule they both follow,
# so this run builds the very pages they will.
FROM_ENV="${CLAUDE_HTML_OUT:-}${CLAUDE_HTML_ROOT:-}"
# shellcheck source=conf.sh
. "$HERE/conf.sh"
mkdir -p "$OUT"
echo
say "pages:    $OUT"
say "projects: $ROOT"
[ -z "$FROM_ENV" ] || say "          (from your environment, which wins over $CONF)"

# ── 2. the command ──────────────────────────────────────────────────
chmod +x "$HERE/claude-html" "$HERE"/*.sh 2>/dev/null || true

LINKED=""
for d in "$HOME/.local/bin" /usr/local/bin; do
  [ -d "$d" ] || mkdir -p "$d" 2>/dev/null || continue
  [ -w "$d" ] && ln -sf "$HERE/claude-html" "$d/claude-html" && LINKED="$d" && break
done
if [ -n "$LINKED" ]; then
  say "command:  $LINKED/claude-html"
  case ":$PATH:" in
    *":$LINKED:"*) : ;;
    *) say "          (add it to your PATH: export PATH=\"$LINKED:\$PATH\")" ;;
  esac
else
  say "command:  could not write to a bin directory — run $HERE/claude-html"
fi

# ── 3. hooks ───────────────────────────────────────────────────────
# || true: a failure here must not abandon the install half-done.
HOOKED=1
RESULT="$(run_js "$HERE/settings-hooks.js" "$SETTINGS" "$HERE" add 2>/dev/null || true)"
case "$RESULT" in
  unparseable)
    HOOKED=0
    say "hooks:    settings.json is not valid JSON — left alone, add them yourself" ;;
  unwritable|"")
    HOOKED=0
    say "hooks:    could not write $SETTINGS — add them yourself" ;;
  *)
    ADDED="$(printf '%s' "$RESULT" | sed -n 's/.*"added":\[\([^]]*\)\].*/\1/p' \
             | tr -d '"' | sed 's/,/, /g' || true)"
    [ -n "$ADDED" ] && say "hooks:    $ADDED" || say "hooks:    already configured"
    THEIRS="$(printf '%s' "$RESULT" | sed -n 's/.*"theirs":\([0-9]*\).*/\1/p' || true)"
    [ "${THEIRS:-0}" -gt 0 ] && say "          ($THEIRS hook(s) of yours left exactly as they were)" || true
    DAYS="$(printf '%s' "$RESULT" | sed -n 's/.*"cleanupPeriodDays":\([0-9]*\).*/\1/p' || true)"
    case "$RESULT" in *'"keptTheirCleanup":true'*)
      [ "${DAYS:-3650}" -lt 365 ] && \
        say "note:     your cleanupPeriodDays is $DAYS, so transcripts are deleted after $DAYS days" || true ;;
    esac ;;
esac

# ── 4. the delete helper ─────────────────────────────────────────────
# A page opened from disk cannot delete files, so the bin on the index is a
# claude-html:// link, and this small app receives it. Built here, from source,
# with Apple's own tools.
# On Linux the same links go to handler.sh, through a desktop file that
# claims the scheme; with no desktop to register it with, the index simply
# leaves those controls out.
if [ "$MAC" != true ]; then
  if [ "$CH_OS" = linux ]; then
    LINKS="$(ch_register_handler "$HERE")" || true
    say "links:    $LINKS"
    say "          (claude-html --doctor shows what this machine has for each job)"
  else
    say "links:    the helper app needs osascript - the index leaves its links out"
  fi
elif "$HERE/helper-build.sh" "$HERE/Claude HTML.app" --register >/dev/null 2>&1; then
  say "delete:   $HERE/Claude HTML.app"
else
  say "delete:   could not build the helper — the bin on the index will do nothing"
fi

# ── 5. build ────────────────────────────────────────────────────────
# With the engine the hook and the command will use, picked the same way:
# node when a working one is here, osascript when not. Nothing is installed.
say "engine:   $CH_ENGINE${CH_NODE:+ ($CH_NODE)}"
[ -z "$CH_ENGINE_NOTE" ] || say "          ($CH_ENGINE_NOTE)"
echo
# Without the build cache: a save may be building beside this one, and only
# the saves and the command, which take turns, may write it.
REPORT="$(ch_js "$HERE/convert.js" "$(cat <<EOF
{"root":"$ROOT","out":"$OUT","here":"$HERE","cache":false}
EOF
)" 2>&1 || true)"
case "$REPORT" in
  *'"sessions"'*)
    N="$(printf '%s' "$REPORT" | sed -n 's/.*"sessions":\([0-9]*\).*/\1/p')"
    say "built:    $N session(s)" ;;
  *)
    say "build:    could not build the pages — $REPORT" ;;
esac
echo
say "done — open $OUT/index.html"
echo
