# Sourced, not run: what kind of machine this is, and which of its own tools
# does each job claude-html needs done outside the browser.
#
#   . "$HERE/lib/platform.sh"; ch_detect
#
# Nothing is installed and nothing is assumed. Each capability goes to the
# best tool the machine already has, the desktop's own first, and a job with
# no tool for it is reported as unavailable rather than half done. POSIX sh,
# because the link handler is run by whatever shell the desktop hands it to.
#
# What it reads can be pointed elsewhere, which is how the tests fake a whole
# distribution on any machine:
#   CLAUDE_HTML_UNAME         what uname -s would say
#   CLAUDE_HTML_OS_RELEASE    the os-release file (default /etc/os-release)
#   CLAUDE_HTML_PROC_VERSION  the kernel's version string (default /proc/version)
#
# After ch_detect:
#   CH_OS          darwin | linux | other
#   CH_ID CH_ID_LIKE CH_VERSION_ID CH_PRETTY    from os-release
#   CH_DE          gnome | kde | xfce | mate | cinnamon | lxqt | lxde | budgie | other | none
#   CH_DE_RAW      what the session said, for people to read
#   CH_SESSION     wayland | x11 | headless | aqua
#   CH_WSL         yes | no
#   CH_TERM        the terminal to open, or empty      CH_TERM_KIND  how to talk to it
#   CH_OPENER      xdg-open | gio | wslview | open | empty
#   CH_TRASH       gio | kioclient | kioclient5 | trash-put | spec | finder
#   CH_DIALOG      zenity | kdialog | yad | xmessage | osascript | terminal | none

ch_have() { command -v "$1" >/dev/null 2>&1; }

# The first of its arguments that is a command here.
ch_first() {
  for _c in "$@"; do
    if ch_have "$_c"; then printf '%s' "$_c"; return 0; fi
  done
  return 1
}

ch_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# One argument, quoted for sh so that nothing in it is special any more.
ch_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
ch_quote_args() {
  _sep=""
  for _a in "$@"; do printf '%s%s' "$_sep" "$(ch_quote "$_a")"; _sep=" "; done
}

# A string as JSON writes one, quotes included: a folder's name may hold
# a quote, a backslash or a line break, and must reach the JavaScript whole.
ch_json_str() {
  printf '%s' "$1" | LC_ALL=C awk 'BEGIN { ORS = ""; printf "\"" }
    { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, "\\r")
      if (NR > 1) printf "\\n"; print }
    END { printf "\"" }'
}
# An object from pairs of arguments, each value a string; a key written
# :key takes its value as it is (true, false, a number).
#   ch_json_obj id "$ID" :force true    {"id":"…","force":true}
ch_json_obj() {
  _o="{"; _s=""
  while [ $# -ge 2 ]; do
    case "$1" in
      :*) _o="$_o$_s$(ch_json_str "${1#:}"):$2" ;;
      *) _o="$_o$_s$(ch_json_str "$1"):$(ch_json_str "$2")" ;;
    esac
    _s=","; shift 2
  done
  printf '%s}' "$_o"
}
# The options every run of convert.js starts from - where the projects
# are, where the pages go, which clone - and its own after them.
#   ch_js_opts <clone> [key value]…
# With them, what the plan line and the Limits & budget section show, as
# limits.sh works it out (bash's, in a shell of its own: what it cannot
# work out, it leaves out, and the build goes on).
ch_js_opts() {
  _h="$1"; shift
  _lj=""
  if [ -f "$_h/lib/limits.sh" ]; then
    _lj="$(bash -c 'set +eu; . "$1/lib/platform.sh" && . "$1/lib/limits.sh" && ch_lim_json' _ "$_h" 2>/dev/null)" || _lj=""
    case "$_lj" in '{'*'}') set -- "$@" :limits "$_lj" ;; esac
  fi
  # And what the Settings page shows that only the shell knows (settings.sh,
  # bash's, in this shell's copy: where each setting comes from is conf.sh's).
  if [ -f "$_h/lib/settings.sh" ] && [ -n "${BASH_VERSION:-}" ]; then
    _sj="$(set +eu; HERE="$_h"; . "$_h/lib/settings.sh" && ch_settings_json "$_h" 2>/dev/null)" || _sj=""
    case "$_sj" in '{'*'}') set -- "$@" :settings "$_sj" ;; esac
  fi
  ch_json_obj root "$ROOT" out "$OUT" here "$_h" "$@"
}

# os-release is shell syntax, but it is not ours to run: read the three keys
# that matter as plain text and take their quotes off.
ch_os_release_value() {
  sed -n "s/^$1=//p" "$2" 2>/dev/null | head -n 1 |
    sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

ch_detect() {
  case "${CLAUDE_HTML_UNAME:-$(uname -s 2>/dev/null)}" in
    Darwin) CH_OS=darwin ;;
    Linux) CH_OS=linux ;;
    *) CH_OS=other ;;
  esac

  CH_ID=""; CH_ID_LIKE=""; CH_VERSION_ID=""; CH_PRETTY=""
  _rel="${CLAUDE_HTML_OS_RELEASE:-/etc/os-release}"
  # The spec's own fallback, for systems that only ship the vendor copy.
  [ -n "${CLAUDE_HTML_OS_RELEASE:-}" ] || [ -r "$_rel" ] || _rel=/usr/lib/os-release
  if [ "$CH_OS" != darwin ] && [ -r "$_rel" ]; then
    CH_ID="$(ch_os_release_value ID "$_rel")"
    CH_ID_LIKE="$(ch_os_release_value ID_LIKE "$_rel")"
    CH_VERSION_ID="$(ch_os_release_value VERSION_ID "$_rel")"
    CH_PRETTY="$(ch_os_release_value PRETTY_NAME "$_rel")"
  fi

  CH_WSL=no
  _pv="${CLAUDE_HTML_PROC_VERSION:-/proc/version}"
  if [ "$CH_OS" = linux ]; then
    if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft "$_pv" 2>/dev/null; then CH_WSL=yes; fi
  fi

  # The desktop names itself in more than one way, and not every session
  # sets the standard variable: older ones only leave their own behind.
  CH_DE_RAW="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-}}}"
  if [ -z "$CH_DE_RAW" ]; then
    if [ "${KDE_FULL_SESSION:-}" = true ]; then CH_DE_RAW=KDE
    elif [ -n "${GNOME_DESKTOP_SESSION_ID:-}" ]; then CH_DE_RAW=GNOME
    elif [ -n "${MATE_DESKTOP_SESSION_ID:-}" ]; then CH_DE_RAW=MATE
    fi
  fi
  _de="$(ch_lower "$CH_DE_RAW")"
  case "$_de" in
    "") CH_DE=none ;;
    *kde*|*plasma*) CH_DE=kde ;;
    *cinnamon*) CH_DE=cinnamon ;;
    *budgie*) CH_DE=budgie ;;
    *gnome*|*unity*|*pop*) CH_DE=gnome ;;
    *xfce*) CH_DE=xfce ;;
    *mate*) CH_DE=mate ;;
    *lxqt*) CH_DE=lxqt ;;
    *lxde*) CH_DE=lxde ;;
    *) CH_DE=other ;;
  esac

  if [ "$CH_OS" = darwin ]; then CH_SESSION=aqua
  elif [ -n "${WAYLAND_DISPLAY:-}" ]; then CH_SESSION=wayland
  elif [ -n "${DISPLAY:-}" ]; then CH_SESSION=x11
  else CH_SESSION=headless
  fi

  ch_pick_tools
}

ch_pick_tools() {
  CH_TERM=""; CH_TERM_KIND=""; CH_OPENER=""; CH_TRASH=""; CH_DIALOG=""
  if [ "$CH_OS" = darwin ]; then
    CH_TERM=Terminal; CH_TERM_KIND=macos; CH_OPENER=open; CH_TRASH=finder; CH_DIALOG=osascript
    return 0
  fi

  # ── terminal ──
  # Someone who set $TERMINAL has said which one they want. Then the
  # desktop's own, then Debian's alternatives link, then any at all.
  if [ "$CH_SESSION" != headless ]; then
    if [ -n "${TERMINAL:-}" ] && ch_have "$TERMINAL"; then
      CH_TERM="$TERMINAL"
    else
      case "$CH_DE" in
        gnome) _native="ptyxis kgx gnome-terminal" ;;
        kde) _native="konsole" ;;
        xfce) _native="xfce4-terminal" ;;
        mate) _native="mate-terminal" ;;
        cinnamon) _native="gnome-terminal" ;;
        budgie) _native="tilix gnome-terminal" ;;
        lxqt) _native="qterminal lxterminal" ;;
        lxde) _native="lxterminal" ;;
        *) _native="" ;;
      esac
      # shellcheck disable=SC2086
      CH_TERM="$(ch_first $_native x-terminal-emulator gnome-terminal kgx ptyxis konsole \
        xfce4-terminal mate-terminal lxterminal qterminal tilix kitty alacritty foot \
        wezterm xterm)" || CH_TERM=""
    fi
  fi
  # Without a Linux display, WSL can still open a Windows Terminal tab that
  # runs back inside this distribution.
  if [ -z "$CH_TERM" ] && [ "$CH_WSL" = yes ] && ch_have wt.exe; then CH_TERM=wt.exe; fi
  [ -n "$CH_TERM" ] && CH_TERM_KIND="$(basename "$CH_TERM")"

  # ── opener ──
  if [ "$CH_WSL" = yes ] && ch_have wslview; then CH_OPENER=wslview
  elif [ "$CH_SESSION" != headless ]; then
    if ch_have xdg-open; then CH_OPENER=xdg-open
    elif ch_have gio; then CH_OPENER=gio
    fi
  fi

  # ── trash ──
  # Moving to the trash needs no display, so a server gets one too. The last
  # resort is the freedesktop.org spec itself, done by delete.js: a folder
  # and a small text file, which every desktop's trash reads.
  case "$CH_DE" in kde) _native="kioclient kioclient5" ;; *) _native="" ;; esac
  # shellcheck disable=SC2086
  CH_TRASH="$(ch_first $_native gio kioclient kioclient5 trash-put)" || CH_TRASH=spec

  # ── asking first ──
  if [ "$CH_SESSION" != headless ]; then
    case "$CH_DE" in kde) _native="kdialog" ;; *) _native="" ;; esac
    # shellcheck disable=SC2086
    CH_DIALOG="$(ch_first $_native zenity kdialog yad)" || CH_DIALOG=""
    if [ -z "$CH_DIALOG" ] && [ -n "${DISPLAY:-}" ] && ch_have xmessage; then CH_DIALOG=xmessage; fi
  fi
  if [ -z "$CH_DIALOG" ]; then
    if [ -n "$CH_TERM" ]; then CH_DIALOG=terminal; else CH_DIALOG=none; fi
  fi
  return 0
}

# ── the engine for the data work ──────────────────────────────────────
# convert.js and the archiver are the same bytes under osascript and node,
# and node runs them about four times faster. So node does that work when a
# working one is already here, and osascript, which every Mac has, when it
# is not. Nothing is installed for it and nothing requires it on macOS. The
# actions behind the index's links are not data work: on a Mac they stay on
# osascript whatever this picks, since they need the Finder and the helper.
#
#   ch_pick_engine; ch_js convert.js '{…}'
#
# After ch_pick_engine:
#   CH_ENGINE        osascript | node
#   CH_NODE          the node it found, or empty
#   CH_NODE_VERSION  that node's version
#   CH_ENGINE_WHY    one line saying why, for --doctor
#   CH_ENGINE_NOTE   set when CLAUDE_HTML_ENGINE asked for what cannot be had
#
# CLAUDE_HTML_ENGINE=osascript|node chooses. A choice that is not one of the
# two, or not available here, is set aside with a note and the save goes on:
# a setting must never be the reason a conversation is not kept.
# CLAUDE_HTML_FORCE_NODE=1, the tests' switch, pretends osascript is absent.

# The oldest node the scripts run on: fs.rmSync is the newest thing they use.
CH_NODE_MIN=14.14

# How long the check of one node may take, in seconds. It runs on every
# save, so one that hangs must not hold the save up.
CH_NODE_PROBE_LIMIT="${CH_NODE_PROBE_LIMIT:-5}"

# node, run from / and not from the project, so a version manager cannot
# pick a node by the project's files, and told not to fetch one either.
# Every path handed to it is a full one.
ch_node_run() {
  (cd / && VOLTA_BYPASS=1 MISE_NOT_FOUND_AUTO_INSTALL=false exec "$@")
}

# Asked to run, not only found: a node that cannot start, or one too old for
# the code, is not one. Prints its version when it will do. macOS has no
# timeout command, so a watcher in the background stops one that hangs.
ch_node_version() {
  [ -n "$1" ] && [ -x "$1" ] || return 1
  (cd / && VOLTA_BYPASS=1 MISE_NOT_FOUND_AUTO_INSTALL=false exec "$1" -e \
    'if (typeof require("fs").rmSync !== "function") process.exit(3);
    process.stdout.write(process.versions.node)') 2>/dev/null &
  _pid=$!
  ( _n=0
    while [ "$_n" -lt $((CH_NODE_PROBE_LIMIT * 10)) ]; do
      sleep 0.1; kill -0 "$_pid" 2>/dev/null || exit 0; _n=$((_n + 1))
    done
    kill "$_pid" ) >/dev/null 2>&1 &
  wait "$_pid"
}

# A version manager's stand-in for node, which picks a version by the folder
# it is run from - and Volta and mise download one that is missing. Nothing
# may be installed by a save, so these are passed over for the real ones.
ch_node_shim() {
  case "$1" in
    */.volta/bin/*|*/.asdf/shims/*|*/mise/shims/*|*/rtx/shims/*) return 0 ;;
  esac
  if [ -n "${VOLTA_HOME:-}" ]; then case "$1" in "$VOLTA_HOME"/bin/*) return 0 ;; esac; fi
  if [ -n "${ASDF_DATA_DIR:-}" ]; then case "$1" in "$ASDF_DATA_DIR"/shims/*) return 0 ;; esac; fi
  case "$(readlink "$1" 2>/dev/null)" in *volta-shim*) return 0 ;; esac
  return 1
}

# A hook can run with a thinner PATH than a terminal - Claude Code started
# from the Dock has only the system's - so after PATH come the folders node
# is usually installed in: for the version managers, the folders of the
# versions they installed, not their shims. The tests point
# CLAUDE_HTML_NODE_DIRS (folders, colon-separated) at fakes instead.
ch_node_dirs() {
  if [ -n "${CLAUDE_HTML_NODE_DIRS+set}" ]; then printf '%s' "$CLAUDE_HTML_NODE_DIRS"; return 0; fi
  printf '%s' "/opt/homebrew/bin:/usr/local/bin:/usr/bin:$HOME/.local/bin"
  printf '%s' ":$HOME/.local/share/fnm/aliases/default/bin"
  for _d in "$HOME/.nvm/versions/node"/*/bin "${VOLTA_HOME:-$HOME/.volta}/tools/image/node"/*/bin \
            "${ASDF_DATA_DIR:-$HOME/.asdf}/installs/nodejs"/*/bin "$HOME/.local/share/mise/installs/node"/*/bin; do
    [ -d "$_d" ] && printf ':%s' "$_d"
  done
  return 0
}

# One candidate: taken if it runs and is new enough, and tried only once.
ch_try_node() {
  case "$1" in /*) ;; *) return 1 ;; esac
  case "$_seen" in *":$1:"*) return 1 ;; esac
  _seen="$_seen$1:"
  ch_node_shim "$1" && return 1
  if _v="$(ch_node_version "$1")" && [ -n "$_v" ]; then
    CH_NODE="$1"; CH_NODE_VERSION="$_v"; return 0
  fi
  return 1
}

ch_find_node() {
  CH_NODE=""; CH_NODE_VERSION=""; _seen=":"
  ch_try_node "$(command -v node 2>/dev/null || true)" && return 0
  _dirs="$(ch_node_dirs)"
  _ifs="$IFS"; IFS=":"
  set -f
  # shellcheck disable=SC2086
  set -- $_dirs
  set +f; IFS="$_ifs"
  for _d in "$@"; do
    ch_try_node "$_d/node" && return 0
  done
  return 1
}

ch_pick_engine() {
  CH_ENGINE=""; CH_ENGINE_WHY=""; CH_ENGINE_NOTE=""; CH_NODE=""; CH_NODE_VERSION=""
  CH_OSASCRIPT=""
  if [ -z "${CLAUDE_HTML_FORCE_NODE:-}" ]; then
    if ch_have osascript; then CH_OSASCRIPT=osascript
    elif [ -x /usr/bin/osascript ]; then CH_OSASCRIPT=/usr/bin/osascript
    fi
  fi
  _want="${CLAUDE_HTML_ENGINE:-}"; _tried=""
  case "$_want" in
    "") ;;
    osascript)
      if [ -n "$CH_OSASCRIPT" ]; then
        CH_ENGINE=osascript; CH_ENGINE_WHY="chosen by CLAUDE_HTML_ENGINE=osascript"; return 0
      fi
      CH_ENGINE_NOTE="CLAUDE_HTML_ENGINE=osascript, but there is no osascript here" ;;
    node)
      if ch_find_node; then
        CH_ENGINE=node; CH_ENGINE_WHY="chosen by CLAUDE_HTML_ENGINE=node"; return 0
      fi
      _tried=yes
      CH_ENGINE_NOTE="CLAUDE_HTML_ENGINE=node, but no working node $CH_NODE_MIN or later was found" ;;
    *) CH_ENGINE_NOTE="CLAUDE_HTML_ENGINE=$_want is neither osascript nor node, so it is ignored" ;;
  esac
  if [ -z "$_tried" ] && ch_find_node; then
    CH_ENGINE=node; CH_ENGINE_WHY="node is here, and is the faster of the two"
  elif [ -n "$CH_OSASCRIPT" ]; then
    CH_ENGINE=osascript
    CH_ENGINE_WHY="no working node $CH_NODE_MIN or later here, so the system's own osascript"
  else
    # Nothing that works: say so. ch_js refuses to run, rather than try a
    # node already found wanting.
    CH_ENGINE=node
    CH_ENGINE_WHY="no working node $CH_NODE_MIN or later and no osascript: the pages cannot be built until there is one"
  fi
  return 0
}

# Runs one of the data scripts with the engine picked, or says why it
# cannot, as --doctor does.
ch_js() {
  if [ "$CH_ENGINE" = osascript ]; then "$CH_OSASCRIPT" -l JavaScript "$@"
  elif [ -n "$CH_NODE" ]; then ch_node_run "$CH_NODE" "$@"
  else echo "claude-html: $CH_ENGINE_WHY" >&2; return 127; fi
}

ch_engine_line() {
  case "$CH_ENGINE" in
    osascript) printf '%s' "osascript   $CH_ENGINE_WHY" ;;
    *) if [ -n "$CH_NODE" ]; then printf '%s' "node $CH_NODE_VERSION ($CH_NODE)   $CH_ENGINE_WHY"
       else printf '%s' "node   $CH_ENGINE_WHY"; fi ;;
  esac
}

# ── yours alone ───────────────────────────────────────────────────────
# Everything claude-html writes holds conversations, so it is written for
# its owner only (umask 077 in every script), as Claude Code keeps its own
# transcripts. What an earlier release wrote readable by others is made so
# too: only the files and folders it writes in the pages folder, never
# anything else kept there, and every archive folder it writes to.
CH_PAGE_FILES="index.html usage.html settings.html defaults.js sessions search resume .cache .manifest.json .build-errors.json
  .archive-errors .last-save .last-open .last-resume"
# Of a path and what is under it, what others may read, write or enter:
# printed, or (with -exec) made the owner's alone.
ch_loose() {   # path [find action…]
  [ -e "$1" ] || return 0
  _p="$1"; shift
  [ $# -gt 0 ] || set -- -print
  find "$_p" \( -perm -040 -o -perm -020 -o -perm -010 -o -perm -004 -o -perm -002 -o -perm -001 \) \
    ! -type l "$@" 2>/dev/null
}
ch_private() { ch_loose "$1" -exec chmod go-rwx {} +; return 0; }
ch_private_out() {   # the pages folder
  for _f in $CH_PAGE_FILES; do ch_private "$1/$_f"; done
}
ch_loose_out() {   # the pages folder: how many of its own files others can reach
  for _f in $CH_PAGE_FILES; do ch_loose "$1/$_f"; done | wc -l | tr -d ' '
}

# ── git ────────────────────────────────────────────────────────────
# ch_git_ok is version.sh's: source it first.
# Archive folders git would take into a commit: under a work tree, and not
# ignored. One per line. Asks nothing of a git that cannot run quietly.
ch_archives_tracked() {   # project folders…
  ch_git_ok || return 0
  for _d in "$@"; do
    [ -d "$_d/.claude/.claude-conversations" ] || continue
    git -C "$_d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
    git -C "$_d" check-ignore -q ".claude/.claude-conversations/x.json" 2>/dev/null ||
      printf '%s\n' "$_d/.claude/.claude-conversations"
  done
}

# ── the redaction's signature ─────────────────────────────────────────
# Which rules and which own list an archive was redacted by, as convert.js
# and the archiver work it out: "off", or the md5 of redact.js and of the
# list ("" for a list that is not there). The save compares it with the
# one an archive records, without starting a JavaScript engine to ask.
ch_md5() {
  [ -f "$1" ] && [ -r "$1" ] || return 0
  if ch_have md5sum; then md5sum < "$1" 2>/dev/null | cut -d' ' -f1
  elif [ -x /sbin/md5 ]; then /sbin/md5 -q "$1" 2>/dev/null
  else md5 -q "$1" 2>/dev/null; fi
}
ch_redact_off() {
  case "$(ch_lower "${CLAUDE_HTML_REDACT:-}")" in off|0|no|false) return 0 ;; esac
  return 1
}
ch_redact_sig() {
  if ch_redact_off; then printf off; return 0; fi
  printf 'on:%s:%s' "$(ch_md5 "$1/build/redact.js")" "$(ch_md5 "${CLAUDE_HTML_REDACT_FILE:-$HOME/.claude/claude-html.redact}")"
}

# ── the guard's question ──────────────────────────────────────────────
# Whether someone is at this machine to answer a dialog: a desktop, not a
# session over ssh, and not switched off with CLAUDE_HTML_GUARD_DIALOG=off.
# Call after ch_detect.
ch_can_ask() {
  case "$(ch_lower "${CLAUDE_HTML_GUARD_DIALOG:-on}")" in off|0|no|false) return 1 ;; esac
  [ -z "${SSH_CONNECTION:-}${SSH_TTY:-}" ] || return 1
  case "$CH_DIALOG" in
    osascript)
      # A login session at the screen, not one started for ssh or cron.
      [ -n "${CH_DRY:-}" ] || [ "$(launchctl managername 2>/dev/null)" = Aqua ] ;;
    zenity|kdialog|yad|xmessage) return 0 ;;
    *) return 1 ;;
  esac
}

# How long the windows wait — the guard's, the stop window, the limits'
# confirmation — before they close as Cancel: CLAUDE_HTML_GUARD_WAIT, read
# here and nowhere else (the JavaScript is handed the seconds). Written 45,
# 45s, 2m or 1m30s, from 30 seconds to 60 minutes; the hooks' own timeout,
# 3660, is past the longest. Into _WS, in seconds; returns 1 for what is
# not a wait, 2 for one out of range. No command is started: the hook runs
# this on every prompt that holds something.
CH_WAIT_DEFAULT=60; CH_WAIT_MIN=30; CH_WAIT_MAX=3600
ch_wait_secs() {   # text
  _WS=""; _wt="$1"
  _wt="${_wt#"${_wt%%[![:space:]]*}"}"; _wt="${_wt%"${_wt##*[![:space:]]}"}"
  _wm=0; _wx=0
  case "$_wt" in
    ''|*[!0-9mMsS]*) return 1 ;;
    [0-9]*[mM][0-9]*[sS]) _wm="${_wt%%[mM]*}"; _wx="${_wt#*[mM]}"; _wx="${_wx%[sS]}" ;;
    [0-9]*[mM]) _wm="${_wt%[mM]}" ;;
    [0-9]*[sS]) _wx="${_wt%[sS]}" ;;
    *) _wx="$_wt" ;;
  esac
  for _wd in "$_wm" "$_wx"; do
    case "$_wd" in ''|*[!0-9]*) return 1 ;; esac
    [ "${#_wd}" -le 5 ] || return 2
  done
  # Without their leading zeros, which arithmetic would read as octal.
  while :; do case "$_wm" in 0?*) _wm="${_wm#0}" ;; *) break ;; esac; done
  while :; do case "$_wx" in 0?*) _wx="${_wx#0}" ;; *) break ;; esac; done
  # 1m30s, never 1m90s.
  case "$_wt" in *[mM]*[sS]) [ "$_wx" -lt 60 ] || return 1 ;; esac
  _wv=$((_wm * 60 + _wx))
  [ "$_wv" -ge "$CH_WAIT_MIN" ] && [ "$_wv" -le "$CH_WAIT_MAX" ] || return 2
  _WS="$_wv"
}
# The wait in force, into CH_GUARD_LIMIT: the setting, or the default when
# it is not set, or not a wait — then CH_GUARD_WAIT_BAD holds what it said,
# for --guard status and --doctor to report. CLAUDE_HTML_GUARD_TEST_LIMIT,
# whole seconds, wins over both, without the bounds: the tests' own.
ch_guard_wait() {
  CH_GUARD_LIMIT="$CH_WAIT_DEFAULT"; CH_GUARD_WAIT_BAD=""
  if [ -n "${CLAUDE_HTML_GUARD_WAIT:-}" ]; then
    if ch_wait_secs "$CLAUDE_HTML_GUARD_WAIT"; then CH_GUARD_LIMIT="$_WS"
    else CH_GUARD_WAIT_BAD="$CLAUDE_HTML_GUARD_WAIT"; fi
  fi
  case "${CLAUDE_HTML_GUARD_TEST_LIMIT:-}" in ''|*[!0-9]*) ;; *) CH_GUARD_LIMIT="$CLAUDE_HTML_GUARD_TEST_LIMIT" ;; esac
}

# The windows' time limit, in words: 60 is "1 minute".
ch_span() {
  _s="${1:-$CH_WAIT_DEFAULT}"
  if [ $((_s % 60)) = 0 ]; then
    [ "$_s" = 60 ] && echo "1 minute" || echo "$((_s / 60)) minutes"
  else
    [ "$_s" = 1 ] && echo "1 second" || echo "$_s seconds"
  fi
}

# A text for a window's box, in a file of its own in a folder made by
# mktemp, both readable by their owner only: the window is never given it
# as an argument. Prints the file's path; the caller removes its folder.
# CH_DRY makes nothing and prints where it would be.
ch_box_file() {   # text
  if [ -n "${CH_DRY:-}" ]; then printf '%s/chguard.XXXXXX/box' "${TMPDIR:-/tmp}"; return 0; fi
  _bd="$(mktemp -d "${TMPDIR:-/tmp}/chguard.XXXXXX")" || return 1
  ( umask 077; printf '%s' "$1" > "$_bd/box" ) || { rm -rf "$_bd"; return 1; }
  printf '%s/box' "$_bd"
}

# Four choices, Cancel picked already, and one button, OK: Return is OK,
# Escape and any failure are Cancel. It waits CH_GUARD_LIMIT seconds (see
# ch_guard_wait), well inside the hooks' own timeout; past it the window closes
# and the answer is "timeout". Prints cancel, allow, safe, stop, timeout, or
# nothing when no dialog could be shown. Its arguments name the kinds of
# secret, never one; for a command, its first line, masked.
#
# What was found, in its context, and the whole command are in files in
# <private dir> (guard.js writes them): found, command and details.txt.
# The Mac window shows them in boxes under disclosure arrows, closed until
# clicked. zenity, yad, kdialog and xmessage take their text as arguments,
# where a secret must never go, so there it is a Details button (a fifth
# choice for kdialog) that opens the file in the tool's own text window,
# then the question again, within the same time limit.
#
# CH_DRY prints the command instead, and the details window's on a second
# line, for the tests.
#   ch_choose prompt|bash <project> <found> [<command>] [<private dir>]
ch_guard_wait
ch_choose() {
  _kind="$1"; _proj="$2"; _found="$3"; _cmd="${4:-}"; _dd="${5:-}"
  if [ "$_kind" = bash ]; then
    _verb=run; _head="Claude's command has been interrupted"; _where="a command from Claude"
  else
    _verb=send; _head="Your prompt has been interrupted"; _where="your prompt in Claude Code"
  fi
  [ -n "$_proj" ] && _where="$_where  ·  project $_proj"
  _det=""; [ -n "$_dd" ] && [ -f "$_dd/details.txt" ] && _det="$_dd/details.txt"
  _c1="Cancel — do not $_verb"
  _c2="Allow once — it is sensitive, $_verb it this time only"
  _c3="Safe — it is not sensitive, $_verb it and never ask again"
  _c4="Stop — turn this check off"
  _text="$_head
Sensitive information detected

Where:  $_where
Found:  $_found"
  [ -n "$_cmd" ] && _text="$_text
Command:  $_cmd"
  _text="$_text
"
  [ -n "$_det" ] && _text="$_text
Details shows what was found and the whole command, on this screen only."
  _text="$_text
Closes after $(ch_span "$CH_GUARD_LIMIT") — counts as Cancel."
  case "$CH_DIALOG" in
    # A window of osascript's own, whichever engine does the data work:
    # AppleScript's dialogs have no radio buttons. It counts down itself.
    osascript) set -- osascript -l JavaScript "$CH_HERE/mac/dialog.js" --limit "$CH_GUARD_LIMIT"
               if [ -n "$_dd" ] && [ -f "$_dd/found" ]; then set -- "$@" --box Found: "$_dd/found"; fi
               if [ -n "$_dd" ] && [ -f "$_dd/command" ]; then set -- "$@" --pre Command: "$_dd/command"; fi
               set -- "$@" "$_kind" "$_proj" "$_found"
               [ -z "$_cmd" ] || set -- "$@" "$_cmd" ;;
    # zenity, yad and kdialog keep a Cancel button of their own, which
    # answers as the Cancel choice does. Their look is the desktop's.
    zenity) set -- zenity --list --radiolist --title=claude-html --no-markup --text="$_text" \
              --ok-label=OK ${_det:+"--extra-button=Details"} --column=" " --column=Choice \
              TRUE "$_c1" FALSE "$_c2" FALSE "$_c3" FALSE "$_c4" ;;
    yad) set -- yad --list --radiolist --title=claude-html --text="$(printf "%s" "$_text" | sed -e "s/&/\\&amp;/g" -e "s/</\\&lt;/g" -e "s/>/\\&gt;/g")" --print-column=2 --separator= \
           ${_det:+"--button=Details:2"} --button=OK:0 --column=" " --column=Choice TRUE "$_c1" FALSE "$_c2" FALSE "$_c3" FALSE "$_c4" ;;
    kdialog) set -- kdialog --title claude-html --ok-label OK --radiolist "$(printf "%s" "$_text" | sed -e "s/</‹/g" -e "s/>/›/g")" \
               cancel "$_c1" on allow "$_c2" off safe "$_c3" off stop "$_c4" off \
               ${_det:+details} ${_det:+"Details — show what was found and the whole command"} ${_det:+off} ;;
    # No radio buttons: four buttons, Cancel the default.
    xmessage) set -- xmessage -center -title claude-html \
                -buttons "Cancel:1,Allow once:2,Safe:3,Stop:4${_det:+,Details:5}" -default Cancel "$_text" ;;
    *) return 1 ;;
  esac
  if [ -n "${CH_DRY:-}" ]; then ch_quote_args "$@"; echo; [ -z "$_det" ] || ch_details "$_det"; return 0; fi
  # What this window will not read is not left waiting beside it.
  if [ -n "$_dd" ]; then
    if [ "$CH_DIALOG" = osascript ]; then rm -f "$_dd/details.txt"; else rm -f "$_dd/found" "$_dd/command"; fi
  fi
  _end=$(( $(date +%s) + CH_GUARD_LIMIT ))
  while :; do
    _left=$(( _end - $(date +%s) )); [ "$_left" -gt 0 ] || { echo timeout; return 0; }
    ch_dialog_wait "$_left" "$@" || return 1
    if [ "$_ans" = timeout ]; then echo timeout; return 0; fi
    [ -n "$_det" ] && ch_details_asked || break
    _left=$(( _end - $(date +%s) )); [ "$_left" -gt 0 ] || { echo timeout; return 0; }
    ch_details "$_det" "$_left"
    if [ "$_ans" = timeout ]; then echo timeout; return 0; fi
  done
  if [ "$CH_DIALOG" = xmessage ]; then
    case "$_rc" in 1) _ans=cancel ;; 2) _ans=allow ;; 3) _ans=safe ;; 4) _ans=stop ;; *) _ans="" ;; esac
  fi
  # Their own Cancel button, or the window closed, is exit 1 and no output.
  if [ -z "$_ans" ] && [ "$_rc" = 1 ] && [ "$CH_DIALOG" != osascript ]; then _ans=cancel; fi
  # Nothing at all — the tool failed — prints nothing: the caller asks in
  # words instead.
  case "$_ans" in
    cancel|Cancel*) echo cancel ;; allow|Allow*) echo allow ;; safe|Safe*) echo safe ;; stop|Stop*) echo stop ;;
  esac
  return 0
}

# Whether the answer was "show me the details", each tool its own way.
ch_details_asked() {
  case "$CH_DIALOG" in
    zenity) [ "$_ans" = Details ] ;;
    yad) [ "$_rc" = 2 ] ;;
    kdialog) [ "$_ans" = details ] ;;
    xmessage) [ "$_rc" = 5 ] ;;
    *) return 1 ;;
  esac
}

# The details, in the tool's own text window, from the private file: the
# tool reads the file, nothing of it is an argument.
#   ch_details <file> [<seconds left>]
ch_details() {
  _dl="${2:-$CH_GUARD_LIMIT}"
  case "$CH_DIALOG" in
    zenity) set -- zenity --text-info --title=claude-html --filename="$1" --width=720 --height=460 ;;
    yad) set -- yad --text-info --title=claude-html --filename="$1" --width=720 --height=460 --button=Back:0 ;;
    kdialog) set -- kdialog --title claude-html --textbox "$1" 720 460 ;;
    xmessage) set -- xmessage -center -title claude-html -buttons Back:0 -default Back -file "$1" ;;
    *) return 1 ;;
  esac
  if [ -n "${CH_DRY:-}" ]; then ch_quote_args "$@"; echo; return 0; fi
  ch_dialog_wait "$_dl" "$@"
}

# A dialog run with a time limit: its output into _ans (or "timeout" when
# it was closed for want of an answer) and its status into _rc. Both files
# made by mktemp, in a folder of their own: a name another user of a shared
# /tmp could guess is one they could make first. The Mac window counts
# down and closes itself at the limit; it is closed from here only a few
# seconds after, should it not have.
#   ch_dialog_wait <seconds> <command…>
ch_dialog_wait() {
  _lim="$1"; shift
  [ "$CH_DIALOG" = osascript ] && _lim=$((_lim + 5))
  _dir="$(mktemp -d "${TMPDIR:-/tmp}/chguard.XXXXXX")" || return 1
  _out="$_dir/answer"; _late="$_dir/late"
  "$@" >"$_out" 2>/dev/null &
  _pid=$!
  # Past the limit it is closed, and that is noted, so the answer is known
  # to be "nobody", not "Cancel".
  ( _n=0
    while [ "$_n" -lt $((_lim * 10)) ]; do
      sleep 0.1; kill -0 "$_pid" 2>/dev/null || exit 0; _n=$((_n + 1))
    done
    : > "$_late"; kill "$_pid" ) >/dev/null 2>&1 &
  _watch=$!
  wait "$_pid"; _rc=$?
  wait "$_watch" 2>/dev/null
  _ans="$(tr -d '\n' < "$_out")"
  [ -f "$_late" ] && _ans=timeout
  rm -rf "$_dir"
  return 0
}

# The stop window of a limit rule or the API budget: the guard's window,
# its four choices Cancel, Allow once, Allow until the reset and Stop, the
# first picked already, one OK, the same time limit. <box> is what the
# second row's arrow opens on a Mac (the rules or the budget as the conf
# holds them); nothing secret, so elsewhere it is in the text. Prints
# cancel, allow, until, stop, timeout, or nothing when no dialog could be shown.
#   ch_choose_limit <head> <key1> <value1> <key2> <value2> <choice3> <choice4> [<box>]
ch_choose_limit() {
  _c1="Cancel — do not send"; _c2="Allow once — send this prompt only"; _c3="$6"; _c4="$7"; _box="${8:-}"; _k2="$4"
  _text="Your prompt has been interrupted
$1

$2  $3
$4  $5
"
  [ -n "$_box" ] && _text="$_text
$_box
"
  _text="$_text
Closes after $(ch_span "$CH_GUARD_LIMIT") — counts as Cancel."
  _bf=""
  case "$CH_DIALOG" in
    osascript) set -- --limit "$CH_GUARD_LIMIT" limits "$1" "$2" "$3" "$4" "$5" "$6" "$7"
               if [ -n "$_box" ]; then
                 _bf="$(ch_box_file "$_box")" || _bf=""
                 [ -z "$_bf" ] || set -- --box "$_k2" "$_bf" "$@"
               fi
               set -- osascript -l JavaScript "$CH_HERE/mac/dialog.js" "$@" ;;
    zenity) set -- zenity --list --radiolist --title=claude-html --no-markup --text="$_text" \
              --ok-label=OK --column=" " --column=Choice \
              TRUE "$_c1" FALSE "$_c2" FALSE "$_c3" FALSE "$_c4" ;;
    yad) set -- yad --list --radiolist --title=claude-html --text="$(printf "%s" "$_text" | sed -e "s/&/\\&amp;/g" -e "s/</\\&lt;/g" -e "s/>/\\&gt;/g")" --print-column=2 --separator= \
           --button=OK:0 --column=" " --column=Choice TRUE "$_c1" FALSE "$_c2" FALSE "$_c3" FALSE "$_c4" ;;
    kdialog) set -- kdialog --title claude-html --ok-label OK --radiolist "$(printf "%s" "$_text" | sed -e "s/</‹/g" -e "s/>/›/g")" \
               cancel "$_c1" on allow "$_c2" off until "$_c3" off stop "$_c4" off ;;
    xmessage) set -- xmessage -center -title claude-html \
                -buttons "Cancel:1,Allow once:2,Until the reset:3,Stop:4" -default Cancel "$_text" ;;
    *) return 1 ;;
  esac
  if [ -n "${CH_DRY:-}" ]; then ch_quote_args "$@"; echo; return 0; fi
  ch_dialog_wait "$CH_GUARD_LIMIT" "$@"; _st=$?
  [ -z "$_bf" ] || rm -rf "${_bf%/box}"
  [ "$_st" = 0 ] || return 1
  if [ "$_ans" = timeout ]; then echo timeout; return 0; fi
  if [ "$CH_DIALOG" = xmessage ]; then
    case "$_rc" in 1) _ans=cancel ;; 2) _ans=allow ;; 3) _ans=until ;; 4) _ans=stop ;; *) _ans="" ;; esac
  fi
  if [ -z "$_ans" ] && [ "$_rc" = 1 ] && [ "$CH_DIALOG" != osascript ]; then _ans=cancel; fi
  case "$_ans" in
    cancel|Cancel*) echo cancel ;; allow|Allow\ once*) echo allow ;; until|Allow\ until*) echo until ;; stop|Stop*) echo stop ;;
  esac
  return 0
}

# One confirmation window at a time, by a folder made for it: 0 when it was
# made, 3 when one younger than eleven minutes (the longest wait and some)
# is there, as another window still asking; 1 when it cannot be made.
# The caller removes it when the window closes.
ch_ask_take() {   # folder
  mkdir "$1" 2>/dev/null && return 0
  [ -z "$(find "$1" -maxdepth 0 -mmin -11 2>/dev/null)" ] || return 3
  rm -rf "$1"; mkdir "$1" 2>/dev/null || return 1
}

# Asks before something is changed, Cancel the default, in this desktop's
# own way: a window of osascript's on a Mac, zenity, kdialog, yad or
# xmessage elsewhere. <box key> and <box text>: on a Mac, an arrow on that
# row opens the text in a box (the exact lines that will be written);
# elsewhere the text is in the question. Prints apply, cancel or timeout;
# returns 1 when no dialog can be shown here at all.
#   ch_confirm <title> <subtitle> <rows: key<TAB>value per line> <button> [<box key> <box text>]
ch_confirm() {
  _bk="${5:-}"; _box="${6:-}"
  _text="$1
$2

$(printf '%s\n' "$3" | awk -F'\t' '{ if ($1 != "") printf "%s  %s\n", $1, $2; else printf "      %s\n", $2 }')
"
  [ -n "$_box" ] && _text="$_text
Written to the file:
$_box
"
  _text="$_text
Closes after $(ch_span "$CH_GUARD_LIMIT") — nothing changed."
  _bf=""
  case "$CH_DIALOG" in
    osascript) set -- --limit "$CH_GUARD_LIMIT" confirm "$1" "$2" "$3"
               if [ -n "$_box" ] && [ -n "$_bk" ]; then
                 _bf="$(ch_box_file "$_box")" || _bf=""
                 [ -z "$_bf" ] || set -- --box "$_bk" "$_bf" "$@"
               fi
               set -- osascript -l JavaScript "$CH_HERE/mac/dialog.js" "$@" ;;
    zenity) set -- zenity --question --no-markup --default-cancel --title=claude-html \
              --ok-label="$4" --cancel-label=Cancel --text="$_text" ;;
    kdialog) set -- kdialog --title claude-html --continue-label "$4" \
               --warningcontinuecancel "$(printf "%s" "$_text" | sed -e "s/</‹/g" -e "s/>/›/g")" ;;
    yad) set -- yad --title=claude-html --text="$(printf "%s" "$_text" | sed -e "s/&/\\&amp;/g" -e "s/</\\&lt;/g" -e "s/>/\\&gt;/g")" \
           --button="Cancel:1" --button="$4:0" ;;
    xmessage) set -- xmessage -center -title claude-html -buttons "Cancel:1,$4:0" -default Cancel "$_text" ;;
    *) return 1 ;;
  esac
  if [ -n "${CH_DRY:-}" ]; then ch_quote_args "$@"; echo; return 0; fi
  ch_dialog_wait "$CH_GUARD_LIMIT" "$@"; _st=$?
  [ -z "$_bf" ] || rm -rf "${_bf%/box}"
  [ "$_st" = 0 ] || { echo cancel; return 0; }
  if [ "$_ans" = timeout ]; then echo timeout; return 0; fi
  if [ "$CH_DIALOG" = osascript ]; then
    [ "$_ans" = apply ] && echo apply || echo cancel
  else
    # Anything but a clear yes - a closed window, a tool that failed - is a no.
    [ "$_rc" = 0 ] && echo apply || echo cancel
  fi
  return 0
}

# Prints the command line instead of running it when CH_DRY is set, which is
# what --doctor shows and what the tests compare.
ch_run() {
  if [ -n "${CH_DRY:-}" ]; then ch_quote_args "$@"; echo; return 0; fi
  "$@"
}

# Open a terminal window that runs a command. Every terminal spells "run
# this" its own way; some take the command as separate words, which is safe
# as it is, and some take one string they split themselves, which gets every
# word quoted first.
ch_term_run() {
  [ -n "$CH_TERM" ] || return 127
  case "$CH_TERM_KIND" in
    gnome-terminal|kgx) set -- "$CH_TERM" -- "$@" ;;
    ptyxis) set -- "$CH_TERM" --new-window -- "$@" ;;
    xfce4-terminal|mate-terminal) set -- "$CH_TERM" -x "$@" ;;
    lxterminal|qterminal|tilix) set -- "$CH_TERM" -e "$(ch_quote_args "$@")" ;;
    kitty|foot) set -- "$CH_TERM" "$@" ;;
    wezterm) set -- "$CH_TERM" start -- "$@" ;;
    wt.exe)
      # Windows Terminal reads a semicolon as "and another tab", so a path
      # with one in it is not handed over at all.
      case "$*" in *";"*) return 2 ;; esac
      if [ -n "${WSL_DISTRO_NAME:-}" ]; then set -- "$CH_TERM" wsl.exe -d "$WSL_DISTRO_NAME" -- "$@"
      else set -- "$CH_TERM" wsl.exe -- "$@"; fi ;;
    # konsole, alacritty, xterm, Debian's x-terminal-emulator (whose policy
    # requires -e) and a $TERMINAL we know nothing else about.
    *) set -- "$CH_TERM" -e "$@" ;;
  esac
  ch_run "$@"
}

# Open a file as a double-click would, with the opener picked: on Debian,
# /usr/bin/open is openvt, so a command named open is no proof of a Mac.
ch_open_file() {   # path
  case "$CH_OPENER" in
    open) set -- /usr/bin/open "$1" ;;
    gio) set -- gio open "$1" ;;
    xdg-open|wslview) set -- "$CH_OPENER" "$1" ;;
    *) return 1 ;;
  esac
  ch_run "$@" >/dev/null 2>&1
}

# How a file goes to the trash with the tool picked, for --doctor to show.
# delete.js does the moving; this only describes it.
ch_trash_line() {
  case "$CH_TRASH" in
    gio) echo "gio trash -- <file>" ;;
    kioclient|kioclient5) echo "$CH_TRASH --noninteractive move <file> trash:/" ;;
    trash-put) echo "trash-put -- <file>" ;;
    spec) echo "claude-html itself, by the freedesktop.org Trash spec, into $(ch_trash_home)" ;;
    finder) echo "the Finder's Trash (NSFileManager), Put Back restores" ;;
  esac
}

ch_trash_home() { printf '%s/Trash' "${XDG_DATA_HOME:-$HOME/.local/share}"; }

# ── the helper app, on a Mac ────────────────────────────────────────
# Built, or rebuilt when its source is newer, by the command, the save and
# the installer alike, and only where it can be: a Mac (as uname says),
# with osascript, and not when told to register nothing - macOS registers
# an app by itself soon after one appears, so to build one is to register
# it. Says whether there was one to build.
#   ch_helper_refresh <clone> [--if-stale]
ch_helper_can() {
  [ "${CLAUDE_HTML_UNAME:-$(uname -s 2>/dev/null)}" = Darwin ] || return 1
  [ -z "${CLAUDE_HTML_FORCE_NODE:-}" ] && ch_have osascript || return 1
  [ -z "${CLAUDE_HTML_NO_REGISTER:-}" ]
}
ch_helper_refresh() {
  ch_helper_can && [ -x "$1/mac/helper-build.sh" ] || return 1
  "$1/mac/helper-build.sh" "$1/Claude HTML.app" --register ${2:+"$2"} >/dev/null 2>&1
}

# ── the link handler, on Linux ─────────────────────────────────────────
# A desktop file in the user's own applications folder that claims the
# claude-html scheme, pointing at handler.sh in this clone.
CH_HANDLER_NAME=claude-html-handler.desktop
ch_handler_file() { printf '%s/applications/%s' "${XDG_DATA_HOME:-$HOME/.local/share}" "$CH_HANDLER_NAME"; }

# Whether links can be routed here at all, and if not, why not.
ch_links_status() {
  if [ "$CH_OS" = darwin ]; then echo "handled by Claude HTML.app"; return 0; fi
  if [ "$CH_OS" != linux ]; then echo "unavailable: not Linux or macOS"; return 1; fi
  if [ "$CH_WSL" = yes ] && [ "$CH_SESSION" = headless ]; then
    echo "unavailable: WSL without a Linux desktop - the browser runs on Windows and cannot reach this"
    return 1
  fi
  if [ "$CH_SESSION" = headless ]; then echo "unavailable: no display"; return 1; fi
  if [ -f "$(ch_handler_file)" ]; then echo "registered ($(ch_handler_file))"; return 0; fi
  if ! ch_have xdg-mime; then echo "unavailable: no xdg-mime to register a handler with"; return 1; fi
  echo "not registered yet - ./install.sh registers it"
  return 0
}

# A value as a desktop file's Exec= wants one argument: in double quotes,
# with ", `, $ and \ escaped; then % doubled, since %u and friends are codes;
# then the backslashes doubled again, because every value in the file is
# unescaped once before Exec's own quoting is read.
ch_desktop_arg() {
  printf '"%s"' "$(printf '%s' "$1" | sed -e 's/[\\"`$]/\\&/g' -e 's/%/%%/g' -e 's/\\/\\\\/g')"
}

# Is this a folder that will be gone soon? A handler registered from one
# would outlive it, and every link would then launch nothing.
ch_is_temp() {
  case "$1/" in
    /tmp/*|/var/tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*|/dev/shm/*) return 0 ;;
  esac
  if [ -n "${TMPDIR:-}" ]; then
    case "$1/" in "${TMPDIR%/}"/*) return 0 ;; esac
  fi
  return 1
}

# Register handler.sh for claude-html:// links. Prints one line saying what
# happened; returns non-zero if it did not.
ch_register_handler() {
  _here="$1"
  if [ -n "${CLAUDE_HTML_NO_REGISTER:-}" ]; then echo "not registered: CLAUDE_HTML_NO_REGISTER is set"; return 1; fi
  if ch_is_temp "$_here"; then echo "not registered: $_here is a temporary folder"; return 1; fi
  case "$_here" in *'
'*) echo "not registered: the clone's path has a line break in it"; return 1 ;; esac
  if ! ch_links_status >/dev/null; then echo "not registered: $(ch_links_status)"; return 1; fi
  ch_have xdg-mime || { echo "not registered: no xdg-mime"; return 1; }
  _f="$(ch_handler_file)"
  mkdir -p "$(dirname "$_f")" || { echo "not registered: cannot write $(dirname "$_f")"; return 1; }
  {
    echo "[Desktop Entry]"
    echo "Type=Application"
    echo "Version=1.0"
    echo "Name=claude-html links"
    echo "Comment=Opens, resumes or deletes a conversation from the claude-html index"
    echo "Exec=$(ch_desktop_arg "$_here/linux/handler.sh") %u"
    echo "Terminal=false"
    echo "NoDisplay=true"
    echo "MimeType=x-scheme-handler/claude-html;"
  } > "$_f.tmp.$$" && mv -f "$_f.tmp.$$" "$_f" || { echo "not registered: cannot write $_f"; return 1; }
  chmod +x "$_here/linux/handler.sh" 2>/dev/null || true
  xdg-mime default "$CH_HANDLER_NAME" x-scheme-handler/claude-html >/dev/null 2>&1 ||
    { echo "not registered: xdg-mime refused"; return 1; }
  if ch_have update-desktop-database; then
    update-desktop-database "$(dirname "$_f")" >/dev/null 2>&1 || true
  fi
  echo "registered $_f"
}

ch_unregister_handler() {
  _f="$(ch_handler_file)"
  [ -f "$_f" ] || return 1
  rm -f "$_f"
  # xdg-mime can set a default but not take one back, so our own line comes
  # out of mimeapps.list by hand and every other line stays.
  _m="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
  if [ -f "$_m" ] && grep -q "^x-scheme-handler/claude-html=" "$_m"; then
    grep -v "^x-scheme-handler/claude-html=$CH_HANDLER_NAME" "$_m" > "$_m.tmp.$$" &&
      cat "$_m.tmp.$$" > "$_m"; rm -f "$_m.tmp.$$"
  fi
  if ch_have update-desktop-database; then
    update-desktop-database "$(dirname "$_f")" >/dev/null 2>&1 || true
  fi
  echo "removed $_f"
}

# What --doctor prints: everything detected, and what each job maps to.
ch_doctor() {
  _na=""
  echo "claude-html doctor"
  echo
  case "$CH_OS" in
    darwin) echo "  system    macOS $(sw_vers -productVersion 2>/dev/null)" ;;
    *) printf '  system    %s' "$CH_OS"
       [ -n "$CH_ID" ] && printf ' · %s %s' "$CH_ID" "$CH_VERSION_ID"
       [ -n "$CH_ID_LIKE" ] && printf ' (like %s)' "$CH_ID_LIKE"
       [ -n "$CH_PRETTY" ] && printf ' · %s' "$CH_PRETTY"
       echo ;;
  esac
  echo "  desktop   $CH_DE${CH_DE_RAW:+ ($CH_DE_RAW)}"
  echo "  session   $CH_SESSION${XDG_SESSION_TYPE:+ (XDG_SESSION_TYPE=$XDG_SESSION_TYPE)}"
  echo "  wsl       $CH_WSL"
  echo
  if [ "$CH_OS" = darwin ]; then
    echo "  terminal  Terminal    $(CH_DRY=1 ch_run /usr/bin/open '<launcher>.command')"
  elif [ -n "$CH_TERM" ]; then
    echo "  terminal  $CH_TERM    $(CH_DRY=1 ch_term_run sh '<launcher>')"
  else
    echo "  terminal  none        resume prints the command to run instead"; _na="$_na terminal"
  fi
  if [ -n "$CH_OPENER" ]; then echo "  opener    $CH_OPENER"
  else echo "  opener    none        open prints where the project is instead"; _na="$_na opener"; fi
  echo "  trash     $CH_TRASH    $(ch_trash_line)"
  case "$CH_DIALOG" in
    none) echo "  dialog    none        a delete link is refused rather than done unasked"; _na="$_na dialog" ;;
    terminal) echo "  dialog    terminal    a delete link asks in a terminal window" ;;
    *) echo "  dialog    $CH_DIALOG" ;;
  esac
  _ls="$(ch_links_status)" || _na="$_na links"
  echo "  links     $_ls"
  # Which engine reads the transcripts and builds the pages, and why.
  if [ -n "${CH_ENGINE:-}" ]; then
    echo "  engine    $(ch_engine_line)"
    [ -z "$CH_ENGINE_NOTE" ] || echo "  note      $CH_ENGINE_NOTE"
  fi
  echo
  if [ -n "$_na" ]; then echo "  unavailable:$_na"; else echo "  unavailable: nothing"; fi
}
