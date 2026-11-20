# Sourced, not run: where the pages go and which projects are watched.
#
#   HERE=<the clone>; . "$HERE/conf.sh"    sets CONF, ROOT and OUT
#
# One rule for every script that needs these, because the hook and the
# command once answered differently and built two sets of pages: a variable
# in the environment wins over the conf, and the conf wins over the default.
# The default is what install.sh would have written — the pages in the clone,
# the projects beside it — so a missing conf changes nothing but the file.

CONF="${CLAUDE_HTML_CONF:-$HOME/.claude/claude-html.conf}"
# Taken before the conf is read, because reading it overwrites them.
_conf_env_root="${CLAUDE_HTML_ROOT:-}"
_conf_env_out="${CLAUDE_HTML_OUT:-}"
_conf_env_week="${CLAUDE_HTML_WEEK_RESET:-}"
_conf_env_engine="${CLAUDE_HTML_ENGINE:-}"
_conf_env_redact="${CLAUDE_HTML_REDACT:-}"
_conf_env_redact_file="${CLAUDE_HTML_REDACT_FILE:-}"
_conf_env_guard="${CLAUDE_HTML_GUARD:-}"
_conf_env_guard_dialog="${CLAUDE_HTML_GUARD_DIALOG:-}"
_conf_env_update="${CLAUDE_HTML_UPDATE_CHECK:-}"
# shellcheck disable=SC1090
if [ -f "$CONF" ]; then . "$CONF"; fi
ROOT="${_conf_env_root:-${CLAUDE_HTML_ROOT:-$(dirname "$HERE")}}"
OUT="${_conf_env_out:-${CLAUDE_HTML_OUT:-$HERE}}"
ROOT="${ROOT/#\~/$HOME}"; [ "$ROOT" = / ] || ROOT="${ROOT%/}"
OUT="${OUT/#\~/$HOME}"; [ "$OUT" = / ] || OUT="${OUT%/}"
# Made whole, since node does its work from / and not from here.
case "$ROOT" in /*) ;; *) ROOT="$PWD/$ROOT" ;; esac
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
# convert.js reads this from the environment, and a sourced conf only sets a
# shell variable — so hand it over explicitly.
export CLAUDE_HTML_WEEK_RESET="${_conf_env_week:-${CLAUDE_HTML_WEEK_RESET:-}}"
# Which engine does the data work is platform.sh's to decide; a choice made
# in the conf reaches it the same way as one made in the environment.
CLAUDE_HTML_ENGINE="${_conf_env_engine:-${CLAUDE_HTML_ENGINE:-}}"
# Secrets are masked in everything written unless this says off; the
# owner's own list of strings and regexes to mask is a file. Both reach
# convert.js and the archiver through the environment.
export CLAUDE_HTML_REDACT="${_conf_env_redact:-${CLAUDE_HTML_REDACT:-on}}"
CLAUDE_HTML_REDACT_FILE="${_conf_env_redact_file:-${CLAUDE_HTML_REDACT_FILE:-$HOME/.claude/claude-html.redact}}"
CLAUDE_HTML_REDACT_FILE="${CLAUDE_HTML_REDACT_FILE/#\~/$HOME}"
case "$CLAUDE_HTML_REDACT_FILE" in /*) ;; *) CLAUDE_HTML_REDACT_FILE="$PWD/$CLAUDE_HTML_REDACT_FILE" ;; esac
export CLAUDE_HTML_REDACT_FILE
# The guard: on (prompts and commands), prompt (prompts only), or off.
CLAUDE_HTML_GUARD="${_conf_env_guard:-${CLAUDE_HTML_GUARD:-on}}"
# Whether it asks in a dialog when someone is at the screen, or always in
# words, as the next prompt.
CLAUDE_HTML_GUARD_DIALOG="${_conf_env_guard_dialog:-${CLAUDE_HTML_GUARD_DIALOG:-on}}"
# The daily look for a new release, and its notice: on, or off. Exported:
# the build reads it to decide whether the index mentions one.
export CLAUDE_HTML_UPDATE_CHECK="${_conf_env_update:-${CLAUDE_HTML_UPDATE_CHECK:-on}}"
unset _conf_env_update _conf_env_root _conf_env_out _conf_env_week _conf_env_engine _conf_env_redact _conf_env_redact_file _conf_env_guard _conf_env_guard_dialog
