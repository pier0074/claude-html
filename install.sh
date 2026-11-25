#!/usr/bin/env bash
# Install claude-html. Run it from wherever you cloned this.
set -euo pipefail
# What it writes holds conversations: for its owner only.
umask 077

# Editing settings.json and building the helper are a Mac's own work, done
# with osascript there; node elsewhere. The JavaScript is the same under both.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# What kind of machine this is, and which of its own tools it has.
# shellcheck source=lib/platform.sh
. "$HERE/lib/platform.sh"
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
  ./install.sh --no-guard         install without the guard: prompts and
                                  commands holding a secret are not stopped
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
                               session end, keeping anything already there,
                               and the status line (around yours, if you
                               have one: --uninstall gives yours back)
  ~/.local/bin/claude-html     a symlink, so you can type claude-html
  Claude HTML.app              macOS: beside this script, handles the index's
                               delete, open and resume links, and asks before
                               it deletes anything
  ~/.local/share/applications/claude-html-handler.desktop
                               Linux: the same, through handler.sh, registered
                               with xdg-mime where there is a desktop for it

Needs osascript on macOS, which every Mac has, and node 14.14 or later on
Linux, which Claude Code's own installer does not bring: install it first if
node --version prints nothing. Where both are, node builds the pages, being
faster; nothing is installed.

It asks nothing and moves nothing. Run it again any time: it adds only what is
missing, and never overwrites a setting you chose. --uninstall reverses it and
leaves your pages alone.
EOF
}

ROOT=""; OUT=""; UNINSTALL=0; NOGUARD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --out)  OUT="$2";  shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    --no-guard) NOGUARD=no-guard; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; echo "try --help" >&2; exit 1 ;;
  esac
done

say() { printf '  %s\n' "$1"; }
# Where a claude-html command on PATH leads: the clone it belongs to, as a
# physical path, or nothing for one that leads nowhere.
link_clone() { ( cd -P "$(dirname "$1")" 2>/dev/null && t="$(readlink "$1")" &&
                 case "$t" in /*) ;; *) t="$PWD/$t" ;; esac && cd -P "$(dirname "$t")" 2>/dev/null && pwd ); }
HERE_P="$(cd -P "$HERE" && pwd)"

# ── uninstall ───────────────────────────────────────────────────────
if [ "$UNINSTALL" = 1 ]; then
  # Only a command that leads here: another install's stays its own.
  for d in "$HOME/.local/bin" /usr/local/bin; do
    if [ -L "$d/claude-html" ]; then
      if [ "$(link_clone "$d/claude-html")" = "$HERE_P" ]; then rm -f "$d/claude-html" && say "removed $d/claude-html"
      else say "left $d/claude-html: it belongs to the install in $(link_clone "$d/claude-html")"; fi
    fi
  done
  LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  if [ -d "$HERE/Claude HTML.app" ]; then
    "$LSREG" -u "$HERE/Claude HTML.app" >/dev/null 2>&1 || true
    rm -rf "$HERE/Claude HTML.app" && say "removed the delete helper"
  fi
  if [ "$CH_OS" = linux ]; then
    GONE="$(ch_unregister_handler)" && say "$GONE" || true
  fi
  RESULT="$(run_js "$HERE/actions/settings-hooks.js" "$SETTINGS" "$HERE" remove 2>/dev/null || true)"
  case "$RESULT" in
    unparseable) say "settings.json is not valid JSON — left alone" ;;
    unreadable)  say "settings.json could not be read — left alone, remove the hooks yourself" ;;
    removed*)    _sl=""; [ "${RESULT#*;}" != "$RESULT" ] && _sl=";${RESULT#*;}"
                 say "${RESULT%%;*} hook(s)$_sl; everything else in settings.json is untouched" ;;
    *)           say "could not update $SETTINGS — remove the hooks yourself" ;;
  esac
  # What it kept for itself in ~/.claude, which nothing reads without it:
  # the update check's state, the guard's pending answers and engine, the
  # update launchers, the latest plan figures and what was announced. Not the conf, the list of archive folders, the hidden
  # chats or the own list of secrets: those are yours.
  n=0
  for f in .claude-html.update .claude-html.guard .claude-html.guard-engine .claude-html-guard \
           .claude-html-update.command .claude-html-update.sh \
           .claude-html.limits .claude-html.limits-marks .claude-html.spend .claude-html-limits-ask \
           .claude-html.today .claude-html.autoupdate.log .claude-html-settings-ask; do
    [ -e "$HOME/.claude/$f" ] && rm -rf "${HOME:?}/.claude/$f" && n=$((n + 1))
  done
  [ "$n" = 0 ] || say "removed $n file(s) of its own state from ~/.claude"
  say "your pages, archives, conf and cleanupPeriodDays are left as they are"
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
# conf.sh's helpers, run in a subshell: sourcing it here would also set
# ROOT and OUT from the conf, over what was asked for.
conf_value() { _v="$1"; ( . "$HERE/lib/conf.sh" >/dev/null 2>&1; ch_conf_value "$_v" ); }
conf_has() { grep -Eq "^[[:space:]]*(export[[:space:]]+)?$1=" "$CONF"; }
conf_set() { _k="$1" _v="$2"; ( . "$HERE/lib/conf.sh" >/dev/null 2>&1; ch_conf_set "$_k" "$_v" ); }
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
# Best in UTC, since that is how it is fixed: "tue 07:00 UTC" is 09:00 in
# summer and 08:00 in winter in Zurich. Local time works too ("tue 09:00")
# but drifts an hour when the clocks change. Left out, weeks are calendar Mondays.
#CLAUDE_HTML_WEEK_RESET="tue 07:00 UTC"'

# Whole paths in the conf: a relative one would be read from wherever the
# hook or the command happens to run, and every project would get pages of
# its own.
# ch_abs_path is conf.sh's, read in a subshell, where what it sets is lost.
# shellcheck source=lib/conf.sh
abs() { _a="$1"; ( . "$HERE/lib/conf.sh" >/dev/null 2>&1; ch_abs_path "$_a" ); }
if [ -n "$OUT" ]; then OUT="$(abs "$OUT")"; fi
if [ -n "$ROOT" ]; then ROOT="$(abs "$ROOT")"; fi
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
# --no-guard turns the guard off in the conf, as --out sets its own line.
if [ -n "$NOGUARD" ]; then
  if conf_has CLAUDE_HTML_GUARD; then conf_set CLAUDE_HTML_GUARD off
  else conf_add "CLAUDE_HTML_GUARD=$(conf_value off)"; fi
fi

# What the command and the hook will now use, by the rule they both follow,
# so this run builds the very pages they will.
FROM_ENV="${CLAUDE_HTML_OUT:-}${CLAUDE_HTML_ROOT:-}"
# shellcheck source=lib/conf.sh
. "$HERE/lib/conf.sh"
mkdir -p "$OUT"
echo
say "pages:    $OUT"
say "projects: $ROOT"
[ -z "$FROM_ENV" ] || say "          (from your environment, which wins over $CONF)"

# ── 2. the command ──────────────────────────────────────────────────
chmod +x "$HERE/claude-html" "$HERE"/*.sh "$HERE"/lib/*.sh "$HERE"/mac/*.sh "$HERE"/linux/*.sh 2>/dev/null || true

# The command is put on PATH where there is none, or one that leads here
# or nowhere. One that leads to another install, or a file that is not a
# link, is that install's: it is left, and said how to switch.
LINKED=""; OTHER=""
for d in "$HOME/.local/bin" /usr/local/bin; do
  [ -d "$d" ] || mkdir -p "$d" 2>/dev/null || continue
  [ -w "$d" ] || continue
  if [ -e "$d/claude-html" ] || [ -L "$d/claude-html" ]; then
    owner=""; [ -L "$d/claude-html" ] && owner="$(link_clone "$d/claude-html")"
    if [ ! -L "$d/claude-html" ] || { [ -n "$owner" ] && [ "$owner" != "$HERE_P" ] && [ -e "$d/claude-html" ]; }; then
      OTHER="$d/claude-html"; OTHER_AT="${owner:-a file of its own}"; break
    fi
  fi
  ln -sf "$HERE/claude-html" "$d/claude-html" && LINKED="$d" && break
done
if [ -n "$OTHER" ]; then
  say "command:  $OTHER is another install's ($OTHER_AT), left as it is"
  say "          to use this one: ln -sf $(printf '%q' "$HERE/claude-html") $(printf '%q' "$OTHER")"
elif [ -n "$LINKED" ]; then
  say "command:  $LINKED/claude-html"
  case ":$PATH:" in
    *":$LINKED:"*) : ;;
    *) say "          (add it to your PATH: export PATH=\"$LINKED:\$PATH\")" ;;
  esac
else
  say "command:  could not write to a bin directory — run $HERE/claude-html"
fi

# ── 3. hooks ───────────────────────────────────────────────────────
# A guard turned off in the conf - by --no-guard or by claude-html --guard
# off - is not put back by a bare run, which is what an update makes: its
# hooks are left as they are. The conf's own line decides, not the
# environment, which may say otherwise for one shell only.
if [ -z "$NOGUARD" ]; then
  CONF_GUARD="$( unset CLAUDE_HTML_GUARD; . "$CONF" >/dev/null 2>&1; printf '%s' "${CLAUDE_HTML_GUARD:-}" )" || CONF_GUARD=""
  if ch_is_off "$CONF_GUARD"; then NOGUARD=keep-guard
    say "guard:    off in the conf, so its hooks are left as they are (claude-html --guard on)"
  fi
fi
# || true: a failure here must not abandon the install half-done.
HOOKED=1
RESULT="$(run_js "$HERE/actions/settings-hooks.js" "$SETTINGS" "$HERE" add $NOGUARD 2>/dev/null || true)"
case "$RESULT" in
  unparseable)
    HOOKED=0
    say "hooks:    settings.json is not valid JSON — left alone, add them yourself" ;;
  unreadable)
    HOOKED=0
    say "hooks:    settings.json could not be read — left alone, add them yourself" ;;
  unwritable|"")
    HOOKED=0
    say "hooks:    could not write $SETTINGS — add them yourself" ;;
  *)
    ADDED="$(printf '%s' "$RESULT" | sed -n 's/.*"added":\[\([^]]*\)\].*/\1/p' \
             | tr -d '"' | sed 's/,/, /g' || true)"
    [ -n "$ADDED" ] && say "hooks:    $ADDED" || say "hooks:    already configured"
    THEIRS="$(printf '%s' "$RESULT" | sed -n 's/.*"theirs":\([0-9]*\).*/\1/p' || true)"
    [ "${THEIRS:-0}" -gt 0 ] && say "          ($THEIRS hook(s) of yours left exactly as they were)" || true
    # The status line: one slot, claude-html's in it, or around yours.
    case "$RESULT" in
      *'"statusLine":"added"'*) say "status:   Claude Code's status line shows the plan's usage (claude-html --limits)" ;;
      *'"statusLine":"wrapped"'*) say "status:   yours first, then the plan's usage, on Claude Code's status line" ;;
      *'"statusLine":"left"'*) say "status:   your statusLine is not a command, so it was left as it is" ;;
    esac
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
elif [ -n "${CLAUDE_HTML_NO_REGISTER:-}" ]; then
  # macOS registers an app by itself soon after it appears, so none is built.
  say "delete:   no helper app built (CLAUDE_HTML_NO_REGISTER is set)"
elif ch_helper_refresh "$HERE"; then
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
REPORT="$(ch_js "$HERE/build/convert.js" "$(ch_js_opts "$(cd -P "$HERE" && pwd)" :cache false)" 2>&1 || true)"
ch_private_out "$OUT"
case "$REPORT" in
  *'"sessions"'*)
    N="$(printf '%s' "$REPORT" | sed -n 's/.*"sessions":\([0-9]*\).*/\1/p')"
    B="$(printf '%s' "$REPORT" | sed -n 's/.*"built":\([0-9]*\).*/\1/p')"
    say "built:    $N session(s), ${B:-0} rebuilt" ;;
  *)
    say "build:    could not build the pages — $REPORT" ;;
esac
echo
say "done — open $OUT/index.html"
echo
