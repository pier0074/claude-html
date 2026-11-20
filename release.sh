# Sourced: release numbers, and the notice that a newer one is out.
#
#   . "$HERE/release.sh"
#
# The Stop hook sources this after every reply, so reading what is here
# starts no command, reads no file but the state and the conf, and never
# goes to the network: the network is update.sh's, once a day, from a save
# nobody waits on. Writing the state (ch_update_write) takes a mkdir and a mv.

# Where releases come from. update.sh finds the remote whose URL this is;
# the tests point it at a repository of their own.
CH_RELEASE_URL="https://github.com/pier0074/claude-html"
# What the daily check last saw: when (seconds), the newest release, which
# clone it was for (its physical path) and the newest one Claude Code has
# already been told about.
CH_UPDATE_STATE="$HOME/.claude/.claude-html.update"

# The archive format this release writes, in one place: the save hands it
# to the archiver and skips an archive already in it, and update.sh reads
# it from a release's own copy of this file to say what going back costs.
#   2  also thinking, usage and replies     3  usage may carry the cost
#   4  redacted, by the rules and list its signature names
#   5  read through parse.js, as the pages are: the messages a page shows,
#      Claude Code's title, and the side remarks marked as such
CH_ARCHIVE_FORMAT=5

# Whether git can be run without anything popping up. On a Mac without
# Apple's developer tools, /usr/bin/git is a stand-in that offers, in a
# dialog, to install them: from a save after every reply, that would be a
# dialog after every reply. Another git on PATH (Homebrew's) is a real one.
ch_git_ok() {
  _g="$(command -v git 2>/dev/null)" || return 1
  [ -n "$_g" ] || return 1
  if [ "$_g" = /usr/bin/git ] && [ "${CLAUDE_HTML_UNAME:-$(uname -s 2>/dev/null)}" = Darwin ]; then
    xcode-select -p >/dev/null 2>&1 || return 1
  fi
  return 0
}

# A release number, X.Y.Z, without the v.
ch_is_ver() {
  local re='^[0-9]+\.[0-9]+\.[0-9]+$'
  [[ "$1" =~ $re ]]
}
# Whether $1 is a later release than $2, by number: 3.10.0 is after 3.9.0.
ch_ver_gt() {
  ch_is_ver "$1" && ch_is_ver "$2" || return 1
  local a1="${1%%.*}" a3="${1##*.}" b1="${2%%.*}" b3="${2##*.}" a2 b2
  a2="${1#*.}"; a2="${a2%.*}"; b2="${2#*.}"; b2="${b2%.*}"
  [ $((10#$a1)) -ne $((10#$b1)) ] && { [ $((10#$a1)) -gt $((10#$b1)) ]; return; }
  [ $((10#$a2)) -ne $((10#$b2)) ] && { [ $((10#$a2)) -gt $((10#$b2)) ]; return; }
  [ $((10#$a3)) -gt $((10#$b3)) ]
}

# The state, into CH_UP_CHECKED, CH_UP_NEWEST, CH_UP_HERE and CH_UP_TOLD.
ch_update_read() {
  CH_UP_CHECKED=0; CH_UP_NEWEST=""; CH_UP_HERE=""; CH_UP_TOLD=""
  [ -f "$CH_UPDATE_STATE" ] || return 1
  local k v
  while IFS='=' read -r k v || [ -n "$k" ]; do
    case "$k" in
      checked) case "$v" in ''|*[!0-9]*) ;; *) CH_UP_CHECKED="$v" ;; esac ;;
      newest) ch_is_ver "$v" && CH_UP_NEWEST="$v" ;;
      here) CH_UP_HERE="$v" ;;
      told) ch_is_ver "$v" && CH_UP_TOLD="$v" ;;
    esac
  done < "$CH_UPDATE_STATE"
  return 0
}
# Written whole beside it and moved over it, so a reader never sees half.
ch_update_write() {
  mkdir -p "${CH_UPDATE_STATE%/*}" 2>/dev/null
  local tmp="$CH_UPDATE_STATE.tmp.$$"
  printf 'checked=%s\nnewest=%s\nhere=%s\ntold=%s\n' \
    "$CH_UP_CHECKED" "$CH_UP_NEWEST" "$CH_UP_HERE" "$CH_UP_TOLD" > "$tmp" 2>/dev/null &&
    mv -f "$tmp" "$CH_UPDATE_STATE" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
}

# Whether the daily check and its notice are off: CLAUDE_HTML_UPDATE_CHECK
# from the environment, else from the conf (read line by line, not
# sourced: the Stop hook calls this), else on.
ch_update_setting() {
  if [ -n "${CLAUDE_HTML_UPDATE_CHECK+x}" ]; then
    CH_UP_SETTING="$CLAUDE_HTML_UPDATE_CHECK"; return 0
  fi
  CH_UP_SETTING=on
  local conf="${CLAUDE_HTML_CONF:-$HOME/.claude/claude-html.conf}" line v
  [ -f "$conf" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line#export }"
    case "$line" in
      CLAUDE_HTML_UPDATE_CHECK=*)
        v="${line#CLAUDE_HTML_UPDATE_CHECK=}"; v="${v%%#*}"
        v="${v%"${v##*[![:space:]]}"}"; v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"
        CH_UP_SETTING="$v" ;;
    esac
  done < "$conf"
}
ch_update_is_off() {
  case "$1" in [Oo][Ff][Ff]|0|[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]) return 0 ;; esac
  return 1
}

# The release to tell about, into CH_UP_NOTICE, for the clone at $1 (its
# physical path) running $2: only one the daily check saw for this very
# clone, only when it is later, and never with the check off.
ch_update_notice() {
  CH_UP_NOTICE=""
  ch_update_setting
  ch_update_is_off "$CH_UP_SETTING" && return 1
  ch_update_read || return 1
  [ -n "$CH_UP_NEWEST" ] && [ "$CH_UP_HERE" = "$1" ] && ch_ver_gt "$CH_UP_NEWEST" "$2" || return 1
  CH_UP_NOTICE="$CH_UP_NEWEST"
}
