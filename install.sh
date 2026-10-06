#!/bin/bash
# Install claude-html. Run it from wherever you cloned this.
set -euo pipefail

# osascript on macOS, node elsewhere: the JavaScript is the same under both.
if [ -z "${CLAUDE_HTML_FORCE_NODE:-}" ] && command -v osascript >/dev/null 2>&1; then
  run_js() { osascript -l JavaScript "$@"; }; MAC=true
else
  run_js() { node "$@"; }; MAC=false
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HOME/.claude/claude-html.conf"
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
  ~/.claude/claude-html.conf   the two directories above
  ~/.claude/settings.json      adds hooks that save after every reply and at
                               session end, keeping anything already there
  ~/.local/bin/claude-html     a symlink, so you can type claude-html
  Claude HTML.app              beside this script: handles the index's delete
                               links, and asks before it does anything

Needs nothing extra: osascript on macOS, node on Linux — the machine has one.

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
OUT="${OUT:-$HERE}"
ROOT="${ROOT:-$(dirname "$HERE")}"
OUT="$(expand "$OUT")"; OUT="${OUT%/}"
ROOT="$(expand "$ROOT")"; ROOT="${ROOT%/}"
mkdir -p "$OUT"

mkdir -p "$HOME/.claude"
cat > "$CONF" <<EOF
# Written by install.sh. An environment variable of the same name wins.
CLAUDE_HTML_ROOT="$ROOT"
CLAUDE_HTML_OUT="$OUT"
EOF
echo
say "pages:    $OUT"
say "projects: $ROOT"

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
if [ "$MAC" != true ]; then
  say "delete:   the helper app is macOS-only — the bin on the index does nothing here"
elif "$HERE/helper-build.sh" "$HERE/Claude HTML.app" --register >/dev/null 2>&1; then
  say "delete:   $HERE/Claude HTML.app"
else
  say "delete:   could not build the helper — the bin on the index will do nothing"
fi

# ── 5. build ────────────────────────────────────────────────────────
echo
REPORT="$(run_js "$HERE/convert.js" "$(cat <<EOF
{"root":"$ROOT","out":"$OUT","here":"$HERE"}
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
