# Sourced, not run: where the pages go and which projects are watched.
#
#   HERE=<the clone>; . "$HERE/lib/conf.sh"    sets CONF, ROOT and OUT
#
# One rule for every script that needs these, because the hook and the
# command once answered differently and built two sets of pages: a variable
# in the environment wins over the conf, and the conf wins over the default.
# The default is what install.sh would have written — the pages in the clone,
# the projects beside it — so a missing conf changes nothing but the file.

# ch_is_off, ch_conf_get and the rest every lib file shares.
case "${BASH_SOURCE[0]}" in */*) _ch_lib="${BASH_SOURCE[0]%/*}" ;; *) _ch_lib=. ;; esac
# shellcheck source=lib/common.sh
. "$_ch_lib/common.sh"

# A path made whole: ~ for the home folder, a relative one from the folder
# this is run in, without a trailing slash. What install.sh writes in the
# conf has been through this, so every caller reads the same folder.
ch_abs_path() {
  _p="${1/#\~/$HOME}"
  case "$_p" in /*) ;; *) _p="$PWD/${_p#./}" ;; esac
  [ "$_p" = / ] || _p="${_p%/}"
  printf '%s' "$_p"
}

# A value as the conf holds it: in double quotes, which keep a space, with
# the four characters still special in them escaped.
ch_conf_value() { printf '"%s"' "$(printf '%s' "$1" | sed 's/[\\"$`]/\\&/g')"; }
# One line of the conf, changed where it stands, or added on a line of its
# own: the rest of the file, comments and all, as it was. Copied back, not
# moved, so a conf kept as a symlink stays one.
ch_conf_set() {   # key value
  mkdir -p "$(dirname "$CONF")"; [ -f "$CONF" ] || : > "$CONF"
  local tmp="$CONF.tmp.$$" line
  line="$1=$(ch_conf_value "$2")"
  if grep -Eq "^[[:space:]]*(export[[:space:]]+)?$1=" "$CONF"; then
    KEY="$1" LINE="$line" awk '
      $0 ~ "^[[:space:]]*(export[[:space:]]+)?" ENVIRON["KEY"] "=" { print ENVIRON["LINE"]; next } { print }' \
      "$CONF" > "$tmp" && cat "$tmp" > "$CONF"; rm -f "$tmp"
  else
    # An editor that saves without a final newline would otherwise have the
    # new line glued onto the user's last one, spoiling both.
    [ -z "$(tail -c 1 "$CONF")" ] || echo >> "$CONF"
    printf '%s\n' "$line" >> "$CONF"
  fi
}

# A line of the conf taken out, every line that sets the key, so the
# default applies again: the rest as it was, copied back as ch_conf_set does.
ch_conf_unset() {   # key
  [ -f "$CONF" ] || return 0
  grep -Eq "^[[:space:]]*(export[[:space:]]+)?$1=" "$CONF" || return 0
  local tmp="$CONF.tmp.$$"
  KEY="$1" awk '$0 !~ "^[[:space:]]*(export[[:space:]]+)?" ENVIRON["KEY"] "="' "$CONF" > "$tmp" &&
    cat "$tmp" > "$CONF"; rm -f "$tmp"
}

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
_conf_env_guard_wait="${CLAUDE_HTML_GUARD_WAIT:-}"
_conf_env_update="${CLAUDE_HTML_UPDATE_CHECK:-}"
# The limits' settings (limits.sh reads them): taken whole, set or not, so
# one set to nothing in the environment still wins over the conf.
for _conf_lk in CLAUDE_HTML_LIMITS CLAUDE_HTML_LIMIT_RULES CLAUDE_HTML_BUDGET CLAUDE_HTML_BUDGET_WARN CLAUDE_HTML_LIMIT_NOTIFY; do
  eval "if [ -n \"\${$_conf_lk+x}\" ]; then _conf_env_has_$_conf_lk=1; _conf_env_val_$_conf_lk=\"\$$_conf_lk\"; else _conf_env_has_$_conf_lk=; fi"
done
# Where each setting comes from, for claude-html --config and the Settings
# page: CH_SRC_<key> is environment, conf or default. Every setting is in
# lib/settings.tsv; one set in the environment (the limits' even when set to
# nothing, as above) wins, and is put back after the conf is read.
_conf_set_tsv="$HERE/lib/settings.tsv"; _conf_envset=" "; CH_SET_KEYS=""
if [ -f "$_conf_set_tsv" ]; then
  while IFS='	' read -r _conf_k _conf_rest; do
    case "$_conf_k" in CLAUDE_HTML_*|CH_*) ;; *) continue ;; esac
    CH_SET_KEYS="$CH_SET_KEYS $_conf_k"
    case " CLAUDE_HTML_LIMITS CLAUDE_HTML_LIMIT_RULES CLAUDE_HTML_BUDGET CLAUDE_HTML_BUDGET_WARN CLAUDE_HTML_LIMIT_NOTIFY " in
      *" $_conf_k "*) [ -n "${!_conf_k+x}" ] ;;
      *) [ -n "${!_conf_k:-}" ] ;;
    esac && { _conf_envset="$_conf_envset$_conf_k "; eval "_conf_ev_$_conf_k=\${!_conf_k}"; }
  done < "$_conf_set_tsv"
fi
# shellcheck disable=SC1090
if [ -f "$CONF" ]; then . "$CONF"; fi
for _conf_k in $CH_SET_KEYS; do
  case "$_conf_envset" in
    *" $_conf_k "*) eval "CH_SRC_$_conf_k=environment; $_conf_k=\$_conf_ev_$_conf_k; unset _conf_ev_$_conf_k" ;;
    *) if [ -n "${!_conf_k:-}" ]; then eval "CH_SRC_$_conf_k=conf"; else eval "CH_SRC_$_conf_k=default"; fi ;;
  esac
done
# The two read from the environment by the build: a plain line in the conf
# reaches it too, not only one written with export.
[ -z "${CLAUDE_HTML_PRICES:-}" ] || export CLAUDE_HTML_PRICES
[ -z "${CLAUDE_HTML_EXPORT:-}" ] || export CLAUDE_HTML_EXPORT
ROOT="${_conf_env_root:-${CLAUDE_HTML_ROOT:-$(dirname "$HERE")}}"
OUT="${_conf_env_out:-${CLAUDE_HTML_OUT:-$HERE}}"
# Made whole, since node does its work from / and not from here. Only a
# path from the environment can still be relative: install.sh writes the
# conf's whole.
ROOT="$(ch_abs_path "$ROOT")"
OUT="$(ch_abs_path "$OUT")"
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
# How long its windows wait (platform.sh reads it, in ch_guard_wait), and
# where that came from, for claude-html --guard wait.
CLAUDE_HTML_GUARD_WAIT="${_conf_env_guard_wait:-${CLAUDE_HTML_GUARD_WAIT:-}}"
if [ -n "$_conf_env_guard_wait" ]; then CH_GUARD_WAIT_FROM=environment
elif [ -n "$CLAUDE_HTML_GUARD_WAIT" ]; then CH_GUARD_WAIT_FROM=conf
else CH_GUARD_WAIT_FROM=default; fi
# The daily look for a new release, and its notice: on, or off. Exported:
# the build reads it to decide whether the index mentions one.
export CLAUDE_HTML_UPDATE_CHECK="${_conf_env_update:-${CLAUDE_HTML_UPDATE_CHECK:-on}}"
for _conf_lk in CLAUDE_HTML_LIMITS CLAUDE_HTML_LIMIT_RULES CLAUDE_HTML_BUDGET CLAUDE_HTML_BUDGET_WARN CLAUDE_HTML_LIMIT_NOTIFY; do
  eval "[ -z \"\$_conf_env_has_$_conf_lk\" ] || $_conf_lk=\"\$_conf_env_val_$_conf_lk\"; unset _conf_env_has_$_conf_lk _conf_env_val_$_conf_lk"
done
unset _conf_k _conf_rest _conf_envset _conf_set_tsv _conf_lk _conf_env_update _conf_env_root _conf_env_out _conf_env_week _conf_env_engine _conf_env_redact _conf_env_redact_file _conf_env_guard _conf_env_guard_dialog _conf_env_guard_wait
