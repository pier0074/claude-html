# Sourced, not run: what kind of machine this is, and which of its own tools
# does each job claude-html needs done outside the browser.
#
#   . "$HERE/platform.sh"; ch_detect
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
  printf 'on:%s:%s' "$(ch_md5 "$1/redact.js")" "$(ch_md5 "${CLAUDE_HTML_REDACT_FILE:-$HOME/.claude/claude-html.redact}")"
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

# Four choices, Cancel picked already, and one button, OK: Return is OK,
# Escape and any failure are Cancel. It waits CH_GUARD_LIMIT seconds, ten
# minutes, well inside the hooks' own timeout; past it the window closes
# and the answer is "timeout". Prints cancel, allow, safe, stop, timeout, or
# nothing when no dialog could be shown. It names the kinds of secret,
# never one. CH_DRY prints the command instead, for the tests.
#   ch_choose prompt|bash <project> <found>
CH_GUARD_LIMIT="${CLAUDE_HTML_GUARD_TEST_LIMIT:-600}"
ch_choose() {
  _kind="$1"; _proj="$2"; _found="$3"
  if [ "$_kind" = bash ]; then
    _verb=run; _head="Claude's command has been interrupted"; _where="a command from Claude"
  else
    _verb=send; _head="Your prompt has been interrupted"; _where="your prompt in Claude Code"
  fi
  [ -n "$_proj" ] && _where="$_where  ·  project $_proj"
  _c1="Cancel — do not $_verb"
  _c2="Allow once — it is sensitive, $_verb it this time only"
  _c3="Safe — it is not sensitive, $_verb it and never ask again"
  _c4="Stop — turn this check off"
  _text="$_head
Sensitive information detected

Where:  $_where
Found:  $_found"
  case "$CH_DIALOG" in
    # A window of osascript's own, whichever engine does the data work:
    # AppleScript's dialogs have no radio buttons.
    osascript) set -- osascript -l JavaScript "$CH_HERE/dialog.js" "$_kind" "$_proj" "$_found" ;;
    # zenity, yad and kdialog keep a Cancel button of their own, which
    # answers as the Cancel choice does. Their look is the desktop's.
    zenity) set -- zenity --list --radiolist --title=claude-html --no-markup --text="$_text" \
              --ok-label=OK --column=" " --column=Choice \
              TRUE "$_c1" FALSE "$_c2" FALSE "$_c3" FALSE "$_c4" ;;
    yad) set -- yad --list --radiolist --title=claude-html --text="$_text" --print-column=2 --separator= \
           --button=OK:0 --column=" " --column=Choice TRUE "$_c1" FALSE "$_c2" FALSE "$_c3" FALSE "$_c4" ;;
    kdialog) set -- kdialog --title claude-html --ok-label OK --radiolist "$_text" \
               cancel "$_c1" on allow "$_c2" off safe "$_c3" off stop "$_c4" off ;;
    # No radio buttons: four buttons, Cancel the default.
    xmessage) set -- xmessage -center -title claude-html \
                -buttons "Cancel:1,Allow once:2,Safe:3,Stop:4" -default Cancel "$_text" ;;
    *) return 1 ;;
  esac
  if [ -n "${CH_DRY:-}" ]; then ch_quote_args "$@"; echo; return 0; fi
  _out="$(mktemp "${TMPDIR:-/tmp}/chguard.XXXXXX")" || return 1
  "$@" >"$_out" 2>/dev/null &
  _pid=$!
  # Past the limit it is closed, and that is noted, so the answer is known
  # to be "nobody", not "Cancel".
  rm -f "$_out.late"
  ( _n=0
    while [ "$_n" -lt $((CH_GUARD_LIMIT * 10)) ]; do
      sleep 0.1; kill -0 "$_pid" 2>/dev/null || exit 0; _n=$((_n + 1))
    done
    : > "$_out.late"; kill "$_pid" ) >/dev/null 2>&1 &
  _watch=$!
  wait "$_pid"; _rc=$?
  wait "$_watch" 2>/dev/null
  _ans="$(tr -d '\n' < "$_out")"; rm -f "$_out"
  if [ -f "$_out.late" ]; then rm -f "$_out.late"; echo timeout; return 0; fi
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
    echo "Exec=$(ch_desktop_arg "$_here/handler.sh") %u"
    echo "Terminal=false"
    echo "NoDisplay=true"
    echo "MimeType=x-scheme-handler/claude-html;"
  } > "$_f.tmp.$$" && mv -f "$_f.tmp.$$" "$_f" || { echo "not registered: cannot write $_f"; return 1; }
  chmod +x "$_here/handler.sh" 2>/dev/null || true
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
