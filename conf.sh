# Sourced, not run: where the pages go and which projects are watched.
#
#   HERE=<the clone>; . "$HERE/conf.sh"    sets CONF, ROOT and OUT
#
# One rule for every script that needs these, because the hook and the
# command once answered differently and built two sets of pages: a variable
# in the environment wins over the conf, and the conf wins over the default.
# The default is what install.sh would have written — the pages in the clone,
# the projects beside it — so a missing conf changes nothing but the file.

# A path made whole: ~ for the home folder, a relative one from the folder
# this is run in, without a trailing slash. What install.sh writes in the
# conf has been through this, so every caller reads the same folder.
ch_abs_path() {
  _p="${1/#\~/$HOME}"
  case "$_p" in /*) ;; *) _p="$PWD/${_p#./}" ;; esac
  [ "$_p" = / ] || _p="${_p%/}"
  printf '%s' "$_p"
}

# A switch's value that means off, one way for every setting.
ch_is_off() {
  case "$1" in [Oo][Ff][Ff]|0|[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]) return 0 ;; esac
  return 1
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
# The daily look for a new release, and its notice: on, or off. Exported:
# the build reads it to decide whether the index mentions one.
export CLAUDE_HTML_UPDATE_CHECK="${_conf_env_update:-${CLAUDE_HTML_UPDATE_CHECK:-on}}"
unset _conf_env_update _conf_env_root _conf_env_out _conf_env_week _conf_env_engine _conf_env_redact _conf_env_redact_file _conf_env_guard _conf_env_guard_dialog
