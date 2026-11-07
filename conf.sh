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
unset _conf_env_root _conf_env_out _conf_env_week _conf_env_engine
