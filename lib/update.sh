#!/usr/bin/env bash
# Moving a clone from one release to another, and the daily look for a new one.
#
#   update.sh <clone> <env> go [X.Y.Z] [--yes]   claude-html --update [X.Y.Z]
#   update.sh <clone> <env> status               claude-html --update status
#   update.sh <clone> <env> list                 claude-html --update list
#   update.sh <clone> --daily                    from a detached save, at most daily
#   update.sh <clone> --auto-maybe               after a detached save: starts --auto when it is due
#   update.sh <clone> --auto                     the automatic update itself, detached, from a copy
#   update.sh <clone> --doctor-line              the line --doctor shows
#
# <env> is what CLAUDE_HTML_UPDATE_CHECK was in the environment before the
# conf was read: "unset", or "set:<value>".
#
# claude-html runs the update from a copy of this file outside the clone:
# the move rewrites the clone, this file with it, and bash reads a script as
# it goes.
#
# A release is a commit on the public repository's main, tagged vX.Y.Z; a
# clone is a release checkout when it came from there and its HEAD is one of
# those commits. Anything else - a development checkout, whose history is not
# that line, or a copy that is not a clone at all - is never fetched for nor
# moved: it is told how it is updated instead.
set -uo pipefail
umask 077

HERE="${1:-}"; shift || true
[ -n "$HERE" ] && [ -d "$HERE" ] || { echo "update.sh: which clone?" >&2; exit 2; }
HERE="$(cd -P "$HERE" && pwd)"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=version.sh
. "$SELF/version.sh"

# No prompt for a password, ever: a fetch that would ask fails instead.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=5}"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
g() { git -C "$HERE" "$@"; }
TAGRE='^v[0-9]+\.[0-9]+\.[0-9]+$'
CLONE_HINT="git clone $CH_RELEASE_URL ~/claude-html && cd ~/claude-html && ./install.sh"

# Runs a command for at most $1 seconds. macOS has no timeout command, so a
# watcher in the background stops it, as platform.sh does for the node probe.
with_limit() {
  local secs="$1" pid w rc; shift
  "$@" &
  pid=$!
  ( _n=0
    while [ "$_n" -lt $((secs * 10)) ]; do
      sleep 0.1; kill -0 "$pid" 2>/dev/null || exit 0; _n=$((_n + 1))
    done
    kill "$pid" ) >/dev/null 2>&1 &
  w=$!
  wait "$pid"; rc=$?
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  return "$rc"
}

# A repository's address as something two spellings of it agree on: the
# https, ssh and scp forms of one GitHub repository, with or without .git,
# are the same; a local path is its physical path.
norm_url() {
  local u="$1"
  while [ "${u%/}" != "$u" ]; do u="${u%/}"; done
  u="${u%.git}"
  case "$u" in
    file://*) u="${u#file://}" ;;
  esac
  case "$u" in
    /*|./*|../*)
      [ -d "$u" ] && u="$(cd -P "$u" 2>/dev/null && pwd)"
      [ -d "$u.git" ] && u="$(cd -P "$u.git" 2>/dev/null && pwd)" && u="${u%.git}"
      printf '%s' "$u"; return ;;
    *://*) u="${u#*://}"; u="${u#*@}" ;;
    *@*:*) u="${u#*@}"; u="${u%%:*}/${u#*:}" ;;
  esac
  printf '%s' "$u" | tr '[:upper:]' '[:lower:]'
}

# ── which kind of copy this is ───────────────────────────────────────
# Decided from what is on disk alone, before anything is fetched. Sets
# KIND to release, dev, noclone or nogit, and R to the release remote.
KIND=""; R=""; WHY=""
classify() {
  # Not a clone at all is known from the disk, before git is asked anything.
  if [ ! -e "$HERE/.git" ]; then KIND=noclone; return; fi
  if ! ch_git_ok; then KIND=nogit; return; fi
  local top
  top="$(g rev-parse --show-toplevel 2>/dev/null)" || top=""
  [ -n "$top" ] && top="$(cd -P "$top" 2>/dev/null && pwd)"
  if [ "$top" != "$HERE" ]; then KIND=noclone; return; fi
  local want r u
  want="$(norm_url "${CLAUDE_HTML_UPDATE_REMOTE:-$CH_RELEASE_URL}")"
  for r in $(g remote 2>/dev/null); do
    u="$(g config --get "remote.$r.url" 2>/dev/null)" || continue
    if [ "$(norm_url "$u")" = "$want" ]; then R="$r"; break; fi
  done
  KIND=dev
  if [ -z "$R" ]; then WHY="it does not come from $CH_RELEASE_URL"; return; fi
  if ! g rev-parse -q --verify "refs/remotes/$R/main" >/dev/null 2>&1; then
    WHY="it has no copy of the release line ($R/main)"; return
  fi
  if ! g merge-base --is-ancestor HEAD "refs/remotes/$R/main" 2>/dev/null; then
    WHY="its HEAD is not a release"; return
  fi
  KIND=release
}
refuse_kind() {
  case "$KIND" in
    nogit) echo "git is not installed, so this copy cannot update itself; re-install from a clone: $CLONE_HINT" >&2 ;;
    noclone) echo "$HERE is not a git clone (a downloaded copy?), so it cannot update itself; re-install from a clone: $CLONE_HINT" >&2 ;;
    dev) echo "this is a development checkout ($WHY); update it with git" >&2 ;;
  esac
  exit 1
}

INSTALLED="$(cat "$HERE/VERSION" 2>/dev/null | tr -d '[:space:]')"
[ -n "$INSTALLED" ] || INSTALLED=unknown

# The releases, from the tags: vX.Y.Z only, and only on the remote's main.
# RELEASES is "X.Y.Z commit" per line; NEWEST the highest number.
RELEASES=""; NEWEST=""
read_releases() {
  local t c v
  RELEASES=""; NEWEST=""
  while IFS= read -r t; do
    [[ "$t" =~ $TAGRE ]] || continue
    c="$(g rev-parse -q --verify "refs/tags/$t^{commit}" 2>/dev/null)" || continue
    g merge-base --is-ancestor "$c" "refs/remotes/$R/main" 2>/dev/null || continue
    v="${t#v}"
    RELEASES="$RELEASES$v $c
"
    if [ -z "$NEWEST" ] || ch_ver_gt "$v" "$NEWEST"; then NEWEST="$v"; fi
  done < <(g for-each-ref --format='%(refname:short)' refs/tags 2>/dev/null)
}
commit_of() { printf '%s' "$RELEASES" | awk -v v="$1" '$1 == v { print $2; exit }'; }
release_list() { printf '%s' "$RELEASES" | awk '{ print $1 }' | tr '\n' ' ' | sed 's/ $//; s/ /, /g'; }

# The release remote's main and tags, with short limits and no questions.
fetch_releases() {
  local err
  err="$(mktemp "${TMPDIR:-/tmp}/claude-html-fetch.XXXXXX")"
  if ! with_limit 60 git -C "$HERE" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 \
       fetch --quiet --tags --no-recurse-submodules "$R" "+refs/heads/main:refs/remotes/$R/main" \
       </dev/null >/dev/null 2>"$err"; then
    echo "could not reach the releases ($(g config --get "remote.$R.url")): $(head -c 200 "$err" | tr '\n' ' ' | sed 's/ *$//')" >&2
    rm -f "$err"; return 1
  fi
  rm -f "$err"
  read_releases
  [ -n "$NEWEST" ] || { echo "the release repository has no releases (no vX.Y.Z tag on main)" >&2; return 1; }
}

# The changelog entries after $1 up to $2, from release $2's own changelog.
# A heading's number is compared as every release number is, by ch_ver_gt.
changelog_between() {
  local line v on=false
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '## '*)
        v="${line#'## '}"; v="${v%%[[:space:]]*}"; on=false
        ch_ver_gt "$v" "$1" && ! ch_ver_gt "$v" "$2" && on=true ;;
    esac
    [ "$on" = true ] && printf '%s\n' "$line"
  done < <(g show "v$2:CHANGELOG.md" 2>/dev/null)
  return 0
}

# The archive format a release writes: CH_ARCHIVE_FORMAT in its own
# lib/version.sh (release.sh at the top, for a release from before the
# folders), or, for a release from before that line, the number in its
# save script.
archive_format() {
  local f
  f="$( { g show "v$1:lib/version.sh" || g show "v$1:release.sh"; } 2>/dev/null |
    sed -n 's/^CH_ARCHIVE_FORMAT=\([0-9][0-9]*\).*/\1/p' | head -1)"
  [ -n "$f" ] || f="$(g show "v$1:save-conversation.sh" 2>/dev/null |
    sed -n 's/^[[:space:]]*format:[[:space:]]*\([0-9][0-9]*\),.*/\1/p' | head -1)"
  printf '%s' "$f"
}

# The state the daily check keeps, brought up to date from a fetch made by hand.
remember_newest() {
  ch_update_setting; ch_update_is_off "$CH_UP_SETTING" && return 0
  ch_update_read
  CH_UP_CHECKED="$(date +%s)"; CH_UP_NEWEST="$NEWEST"; CH_UP_HERE="$HERE"
  ch_update_write
}

# How the check is set: the environment wins over the conf.
ENVSPEC="unset"
check_line() {
  local conf_v env_v
  conf_v="$(unset CLAUDE_HTML_UPDATE_CHECK; ch_update_setting; printf '%s' "$CH_UP_SETTING")"
  if ch_update_is_off "$conf_v"; then printf 'the daily check is off'; else printf 'the daily check is on'; fi
  case "$ENVSPEC" in
    set:*)
      env_v="${ENVSPEC#set:}"
      if { ch_update_is_off "$env_v" && ! ch_update_is_off "$conf_v"; } ||
         { ! ch_update_is_off "$env_v" && ch_update_is_off "$conf_v"; }; then
        printf ' in the conf, but CLAUDE_HTML_UPDATE_CHECK=%s in the environment wins: it is %s here' \
          "$env_v" "$(ch_update_is_off "$env_v" && echo off || echo on)"
      fi ;;
  esac
}
last_line() {
  ch_update_read
  if [ "$CH_UP_HERE" = "$HERE" ] && [ "${CH_UP_CHECKED:-0}" -gt 0 ]; then
    printf 'last checked %s' "$(date -r "$CH_UP_CHECKED" '+%Y-%m-%d %H:%M' 2>/dev/null ||
                                 date -d "@$CH_UP_CHECKED" '+%Y-%m-%d %H:%M' 2>/dev/null)"
  else
    printf 'not checked yet'
  fi
}

# ── the daily check ──────────────────────────────────────────────────
# From the detached part of a save only. Errors are silent, the network is
# asked at most once a day and for five seconds, and only for a release
# checkout; what it learns goes into the state, so nothing else ever needs
# the network.
daily() {
  ch_update_setting; ch_update_is_off "$CH_UP_SETTING" && return 0
  ch_update_read
  local now; now="$(date +%s)"
  if [ "$CH_UP_HERE" = "$HERE" ] && [ $((now - ${CH_UP_CHECKED:-0})) -lt 86400 ] &&
     [ $((now - ${CH_UP_CHECKED:-0})) -ge 0 ]; then return 0; fi
  classify
  # Any other kind of copy is looked at once a day too, not after every
  # reply: its check is recorded, with nothing found.
  if [ "$KIND" != release ]; then
    ch_update_read
    [ "$CH_UP_HERE" = "$HERE" ] || { CH_UP_NEWEST=""; CH_UP_TOLD=""; }
    CH_UP_CHECKED="$now"; CH_UP_HERE="$HERE"
    ch_update_write
    return 0
  fi
  local out newest="" t v
  out="$(mktemp "${TMPDIR:-/tmp}/claude-html-tags.XXXXXX")" || return 0
  # A release is a tag on main. Without fetching, that is known of a tag
  # at main's last commit, or at a commit already here and on main; a tag
  # elsewhere, or at a commit not here, is no release to tell about.
  local c tip=""
  if with_limit 5 git -C "$HERE" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=5 \
       ls-remote "$R" </dev/null >"$out" 2>/dev/null; then
    tip="$(awk '$2 == "refs/heads/main" { print $1; exit }' "$out")"
    # The commit a tag names: the peeled line of an annotated one wins.
    while read -r c t; do
      case "$t" in refs/tags/*) ;; *) continue ;; esac
      t="${t#refs/tags/}"
      case "$t" in *'^{}') t="${t%^\{\}}" ;; *) grep -q "	refs/tags/$t^{}$" "$out" && continue ;; esac
      [[ "$t" =~ $TAGRE ]] || continue
      if [ "$c" != "$tip" ]; then
        g merge-base --is-ancestor "$c" "refs/remotes/$R/main" 2>/dev/null || continue
      fi
      v="${t#v}"
      if [ -z "$newest" ] || ch_ver_gt "$v" "$newest"; then newest="$v"; fi
    done < "$out"
  fi
  rm -f "$out"
  # Asked, whatever the answer: offline, the next try is tomorrow. Read
  # again first: a reply's hook may have told of a release meanwhile.
  ch_update_read
  [ "$CH_UP_HERE" = "$HERE" ] || { CH_UP_NEWEST=""; CH_UP_TOLD=""; }
  CH_UP_CHECKED="$now"; CH_UP_HERE="$HERE"
  [ -n "$newest" ] && CH_UP_NEWEST="$newest"
  ch_update_write
  return 0
}

doctor_line() {
  classify
  ch_update_setting
  if [ "$KIND" != release ]; then
    case "$KIND" in
      dev) printf '%s · development checkout: no checks, update it with git\n' "$INSTALLED" ;;
      *) printf '%s · not a git clone: no checks\n' "$INSTALLED" ;;
    esac
    return
  fi
  if ch_update_is_off "$CH_UP_SETTING"; then printf '%s · checks off\n' "$INSTALLED"; return; fi
  ch_update_read
  local newest="$INSTALLED"
  [ "$CH_UP_HERE" = "$HERE" ] && [ -n "$CH_UP_NEWEST" ] && newest="$CH_UP_NEWEST"
  printf '%s · newest known %s · %s\n' "$INSTALLED" "$newest" "$(last_line)"
}

# ── the automatic update ─────────────────────────────────────────────
# CLAUDE_HTML_AUTO_UPDATE=on: a newer release the daily check saw is
# installed as claude-html --update installs it, at a moment nobody waits
# on. --auto-maybe is run by a save that nobody waits on either (the copy
# the reply's hook detached, or the session end's), after it has let go of
# the lock; it asks no network and decides from the state alone, then
# starts --auto, detached, from a copy of these files outside the clone.
# --auto then takes the saves' lock without waiting: a save running puts
# it off to the next save's end. Never a major release (said, not
# installed), never a clone that is not at a release (a development
# checkout, or one with a dev/ folder, as the owner's own is), and a
# failure is rolled back, as any update's is, and tried again a day later.
AUTO=""; AUTO_TMP=""; AUTO_LOG="$HOME/.claude/.claude-html.autoupdate.log"
# HEAD at a release: a vX.Y.Z tag on the release line, and no dev/ folder,
# which only a development checkout has.
at_release() {
  [ -d "$HERE/dev" ] && return 1
  classify; [ "$KIND" = release ] || return 1
  local t
  for t in $(g tag --points-at HEAD 2>/dev/null); do [[ "$t" =~ $TAGRE ]] && return 0; done
  return 1
}
auto_due() {
  ch_update_setting; ch_update_is_off "$CH_UP_SETTING" && return 1
  ch_update_auto_on || return 1
  ch_update_read || return 1
  [ "$CH_UP_HERE" = "$HERE" ] && [ -n "$CH_UP_NEWEST" ] && ch_ver_gt "$CH_UP_NEWEST" "$INSTALLED" || return 1
  if ch_ver_major_gt "$CH_UP_NEWEST" "$INSTALLED"; then
    # Told, not installed: the notice says it is out, as ever.
    [ "$CH_UP_HELD" = "$CH_UP_NEWEST" ] || { CH_UP_HELD="$CH_UP_NEWEST"; ch_update_write; }
    return 1
  fi
  local now; now="$(date +%s)"
  if [ "$CH_UP_FAILED" = "$CH_UP_NEWEST" ] && [ $((now - CH_UP_FAILEDAT)) -lt 86400 ] && [ $((now - CH_UP_FAILEDAT)) -ge 0 ]; then
    return 1
  fi
  at_release
}
auto_maybe() {
  auto_due || return 0
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-html-autoupdate.XXXXXX")" || return 0
  cp "$SELF/update.sh" "$SELF/version.sh" "$SELF/lock.sh" "$tmp/" 2>/dev/null || { rm -rf "$tmp"; return 0; }
  # Its own session, its output to a log, nothing on a terminal.
  CH_AUTO_TMP="$tmp" nohup "${BASH:-bash}" "$tmp/update.sh" "$HERE" --auto </dev/null >/dev/null 2>&1 &
  return 0
}

case "${1:-}" in
  --daily) daily; exit 0 ;;
  --doctor-line) doctor_line; exit 0 ;;
  --auto-maybe) auto_maybe; exit 0 ;;
  --auto)
    exec >"$AUTO_LOG" 2>&1
    echo "automatic update, $(date '+%Y-%m-%d %H:%M:%S'), from $INSTALLED"
    # Its copy goes when it ends, however it ends.
    case "${CH_AUTO_TMP:-}" in */claude-html-autoupdate.*) AUTO_TMP="$CH_AUTO_TMP" ;; esac
    trap '[ -z "${AUTO_TMP:-}" ] || rm -rf "$AUTO_TMP"' EXIT
    auto_due || { echo "nothing to do"; exit 0; }
    AUTO=1; set -- unset go ;;
esac
ENVSPEC="${1:-unset}"; shift || true
ACTION="${1:-go}"; shift || true
WANT=""; YES=false
for a in "$@"; do
  case "$a" in
    --yes|-y) YES=true ;;
    *) WANT="${a#v}" ;;
  esac
done

# ── status: what is installed and what is out; changes nothing ───────
if [ "$ACTION" = status ]; then
  classify
  if [ "$KIND" != release ]; then
    case "$KIND" in
      dev) echo "installed $INSTALLED · development checkout ($WHY): update it with git" ;;
      noclone) echo "installed $INSTALLED · not a git clone: re-install from a clone to update ($CLONE_HINT)" ;;
      nogit) echo "installed $INSTALLED · git is not installed: re-install from a clone to update ($CLONE_HINT)" ;;
    esac
    echo "$(check_line)"
    exit 0
  fi
  fetch_releases || { echo "installed $INSTALLED · $(check_line) · $(last_line)"; exit 1; }
  remember_newest
  if ch_ver_gt "$NEWEST" "$INSTALLED"; then
    echo "installed $INSTALLED · newest $NEWEST"
    echo
    changelog_between "$INSTALLED" "$NEWEST" | sed 's/^/  /'
    echo
    echo "claude-html --update goes to $NEWEST"
  else
    echo "$INSTALLED is the newest release"
  fi
  echo "$(check_line) · $(last_line)"
  exit 0
fi

# ── list: every release there is; changes nothing ────────────────────
if [ "$ACTION" = list ]; then
  classify
  if [ "$KIND" != release ]; then
    [ "$KIND" = dev ] && { echo "installed $INSTALLED · development checkout ($WHY): it has no releases to list; update it with git"; exit 0; }
    refuse_kind
  fi
  fetch_releases || exit 1
  remember_newest
  printf '%s' "$RELEASES" | while read -r v c; do
    [ -n "$v" ] || continue
    printf '%s %s %s\n' "$v" "$c" "$(g log -1 --format=%cd --date=short "$c" 2>/dev/null)"
  done | awk '{ split($1, p, "."); printf "%010d%010d%010d %s\n", p[1], p[2], p[3], $0 }' |
    sort -r | while read -r _ v c d; do
      mark=" "; note=""
      [ "$v" = "$INSTALLED" ] && { mark="*"; note="installed"; }
      [ "$v" = "$NEWEST" ] && note="${note:+$note, }newest"
      printf '%s %-7s %s%s\n' "$mark" "$v" "$d" "${note:+   $note}"
    done
  exit 0
fi

# ── the move ─────────────────────────────────────────────────────────
# 1. a release checkout, or nothing is touched, nor fetched
classify
[ "$KIND" = release ] || refuse_kind
# 2. what there is
# What the automatic update leaves in the state when it ends: tried again
# a day later after a failure; installed, said for a day.
auto_failed() {
  [ -n "$AUTO" ] || return 0
  ch_update_read
  CH_UP_FAILED="${TARGET:-$CH_UP_NEWEST}"; CH_UP_FAILEDAT="$(date +%s)"; CH_UP_DEFERRED=""
  [ -z "${AUTO_WAS:-}" ] || { CH_UP_AUTO="${AUTO_WAS%% *}"; CH_UP_AUTOAT="${AUTO_WAS#* }"; }
  ch_update_write
}
fetch_releases || { echo "nothing was changed" >&2; auto_failed; exit 1; }
remember_newest
TARGET="${WANT:-$NEWEST}"
if [ -n "$AUTO" ] && ch_ver_major_gt "$TARGET" "$INSTALLED"; then
  echo "$TARGET is a major release: not installed by itself; claude-html --update installs it"
  ch_update_read; CH_UP_HELD="$TARGET"; ch_update_write
  exit 0
fi
if [ -n "$WANT" ] && [ -z "$(commit_of "$WANT")" ]; then
  if g rev-parse -q --verify "refs/tags/v$WANT" >/dev/null 2>&1; then
    echo "v$WANT is a tag, but not a release: it is not on the release line ($R/main); nothing was changed" >&2
  else
    echo "there is no release $WANT (there are: $(release_list)); nothing was changed" >&2
  fi
  exit 1
fi
TCOMMIT="$(commit_of "$TARGET")"
# 3. say it
if [ "$TARGET" = "$INSTALLED" ] || [ "$TCOMMIT" = "$(g rev-parse HEAD)" ]; then
  if [ -z "$WANT" ]; then echo "$INSTALLED is the newest release"; else echo "$TARGET is already installed"; fi
  exit 0
fi
echo "installed $INSTALLED · newest $NEWEST"
BACK=false
if ch_ver_gt "$TARGET" "$INSTALLED"; then
  ENTRIES="$(changelog_between "$INSTALLED" "$TARGET")"
  [ -z "$ENTRIES" ] || { echo; printf '%s\n' "$ENTRIES" | sed 's/^/  /'; }
else
  BACK=true; ENTRIES=""
fi
echo

# 4. nothing of the owner's may be in the way
CHANGED="$(g status --porcelain --untracked-files=no 2>/dev/null)"
if [ -n "$CHANGED" ]; then
  N="$(printf '%s\n' "$CHANGED" | wc -l | tr -d ' ')"
  FILES="$(printf '%s\n' "$CHANGED" | cut -c4- | head -3 | tr '\n' ' ' | sed 's/ $//; s/ /, /g')"
  echo "$N file(s) of the release are changed here ($FILES): commit, stash or undo them first; nothing was changed" >&2
  auto_failed
  exit 1
fi

# 5. going back is allowed, after saying what it costs
if [ "$BACK" = true ]; then
  NEWF="$(archive_format "$INSTALLED")"; OLDF="$(archive_format "$TARGET")"
  echo "Going back from $INSTALLED to $TARGET."
  if [ -n "$NEWF" ] && { [ -z "$OLDF" ] || [ "$OLDF" -lt "$NEWF" ]; }; then
    KNOWS="only older formats"; [ -z "$OLDF" ] || KNOWS="format $OLDF and older"
    echo "  $TARGET cannot read the archives $INSTALLED writes (archive format $NEWF; $TARGET knows $KNOWS):"
    echo "  sessions whose transcripts are gone will be missing from its pages."
  else
    echo "  An older release may not read what a newer one wrote; both write archive format ${NEWF:-?}."
  fi
  case "$TARGET" in
    1.*|2.*)
      echo "  $TARGET has no --update: to come back, run"
      echo "    cd $(printf '%q' "$HERE") && git checkout main && git pull && ./install.sh" ;;
    *) echo "  To come back: claude-html --update" ;;
  esac
  if [ "$YES" != true ]; then
    if [ ! -t 0 ]; then
      echo "going back needs a yes, and there is no terminal to ask in: run it again with --yes; nothing was changed" >&2
      exit 1
    fi
    printf 'Go back to %s? [y/N] ' "$TARGET"
    answer=""; read -r answer || answer=""
    case "$answer" in y|Y|yes|YES) ;; *) echo "nothing was changed"; exit 1 ;; esac
  fi
fi

# A save must not run while the scripts it runs are being replaced: take
# its lock, waiting as the command does, and give up politely. Said once,
# so a pause is not taken for a hang. lock.sh is the copy beside this one,
# or the clone's for a copy made by an older command.
# shellcheck source=lock.sh
if [ -f "$SELF/lock.sh" ]; then . "$SELF/lock.sh"; else . "$HERE/lib/lock.sh"; fi
release_lock() { ch_lock_release; }
trap 'release_lock; [ -z "${AUTO_TMP:-}" ] || rm -rf "$AUTO_TMP"' EXIT
_lw="${CLAUDE_HTML_UPDATE_LOCK_WAIT:-60}"
if [ -n "$AUTO" ]; then
  # A save running: put off to the next save's end, which tries again.
  if ! ch_lock_take 0; then
    echo "a save is running: put off until the next one ends"
    ch_update_read; CH_UP_DEFERRED="$TARGET"; ch_update_write
    exit 0
  fi
elif ! ch_lock_take "$_lw" "a save is running; waiting for it to finish (up to $_lw s)…"; then
  echo "a save is still running; try again in a moment — nothing was changed" >&2
  exit 1
fi

# Where it started, to come back to if anything fails from here on.
START_COMMIT="$(g rev-parse HEAD)"
START_BRANCH="$(g symbolic-ref -q --short HEAD 2>/dev/null || true)"
SETTINGS="$HOME/.claude/settings.json"
LOG="$(mktemp "${TMPDIR:-/tmp}/claude-html-update.XXXXXX")"
our_hooks() {
  awk '/^ *"[A-Za-z]+": \[/ && !/"hooks"/ { ev = $1 }
       /save-conversation\.sh|guard\.sh/ { print ev, $0 }' "$SETTINGS" 2>/dev/null
}
HOOKS_BEFORE="$(our_hooks)"

install_here() { (cd "$HERE" && bash ./install.sh) </dev/null >"$LOG" 2>&1; }
# A build as the hook makes one, by the scripts now in the clone; pages
# made by other scripts, rules or viewers are rebuilt by its own checks.
BUILT=0
build_here() {
  local report
  report="$( HERE="$HERE"
    . "$HERE/$LIB/conf.sh" && . "$HERE/$LIB/platform.sh" && ch_pick_engine &&
    ch_js "$HERE/$BUILD/convert.js" "$(ch_js_opts "$HERE")" 2>&1 )" || {
    printf '%s\n' "$report" >> "$LOG"; return 1; }
  case "$report" in '{"error"'*|'') printf '%s\n' "$report" >> "$LOG"; return 1 ;; esac
  BUILT="$(printf '%s' "$report" | sed -n 's/.*"built":\([0-9]*\).*/\1/p')"
  return 0
}
roll_back() {
  local what="$1"
  if [ -n "$START_BRANCH" ]; then
    g checkout -q --detach "$START_COMMIT" && g branch -f "$START_BRANCH" "$START_COMMIT" &&
      g checkout -q "$START_BRANCH"
  else
    g checkout -q --detach "$START_COMMIT"
  fi
  local back=$?
  echo "the update to $TARGET failed: $what" >&2
  tail -n 5 "$LOG" 2>/dev/null | sed 's/^/  /' >&2
  if [ "$back" = 0 ] && [ "$(g rev-parse HEAD)" = "$START_COMMIT" ]; then
    if install_here; then echo "back on $INSTALLED, its install run again" >&2
    else echo "back on $INSTALLED, but its install failed too: run ./install.sh in $HERE" >&2; fi
  else
    echo "and it could not go back to $INSTALLED (${START_BRANCH:-$START_COMMIT}): see git -C $HERE status" >&2
  fi
  rm -f "$LOG"
  auto_failed
  exit 1
}

# 6. move: to main for the newest, to the tag for a given release. Only
# moves that refuse to overwrite a change.
# The newest is main's last commit; were it ever not, it is gone to as a
# given release is.
PIN="$WANT"
[ -z "$PIN" ] && [ "$TCOMMIT" != "$(g rev-parse "refs/remotes/$R/main")" ] && PIN="$TARGET"
if [ -z "$PIN" ]; then
  if [ "$START_BRANCH" = main ]; then
    g merge -q --ff-only "refs/remotes/$R/main" >>"$LOG" 2>&1 || roll_back "main could not be fast-forwarded to $R/main"
  elif g rev-parse -q --verify refs/heads/main >/dev/null 2>&1; then
    { g checkout -q main && g merge -q --ff-only "refs/remotes/$R/main"; } >>"$LOG" 2>&1 ||
      roll_back "main could not be fast-forwarded to $R/main"
  else
    { g checkout -q -b main "refs/remotes/$R/main" &&
      g branch -q --set-upstream-to="$R/main" main; } >>"$LOG" 2>&1 || roll_back "could not check out main"
  fi
else
  g checkout -q --detach "v$TARGET" >>"$LOG" 2>&1 || roll_back "could not check out v$TARGET"
fi
[ "$(g rev-parse HEAD)" = "$TCOMMIT" ] || roll_back "the clone is not at v$TARGET after the move"
NOW="$(cat "$HERE/VERSION" 2>/dev/null | tr -d '[:space:]')"

# 7. the new release's own install, which keeps the conf and its choices
install_here || roll_back "its install.sh failed"
INSTALL_REBUILT="$(sed -n 's/.*built: *[0-9]* session(s), \([0-9]*\) rebuilt.*/\1/p' "$LOG" | tail -1)"

# Said for a day from now, on the index this build makes and on the status
# line: written before the build, put back if it fails.
if [ -n "$AUTO" ]; then
  ch_update_read; AUTO_WAS="$CH_UP_AUTO $CH_UP_AUTOAT"
  CH_UP_AUTO="${NOW:-$TARGET}"; CH_UP_AUTOAT="$(date +%s)"; CH_UP_DEFERRED=""; CH_UP_FAILED=""; CH_UP_FAILEDAT=0
  ch_update_write
fi

# 8. a build, which rebuilds what the new scripts would make differently.
# Where its scripts are is the release's own: in folders, or, for one from
# before them, at the top of the clone.
LIB=lib BUILD=build
[ -f "$HERE/lib/platform.sh" ] || LIB=. BUILD=.
if [ -f "$HERE/$LIB/platform.sh" ] && grep -q '^ch_js()' "$HERE/$LIB/platform.sh"; then
  build_here || roll_back "its first build failed"
fi
release_lock

# 9. say what happened
echo "Updated $INSTALLED → ${NOW:-$TARGET}."
REBUILT=$(( ${INSTALL_REBUILT:-0} + ${BUILT:-0} ))
echo "$REBUILT session(s) rebuilt"
printf '%s\n' "$ENTRIES" | grep 'After updating:' | sed 's/^[-*[:space:]]*//'
[ "$HOOKS_BEFORE" = "$(our_hooks)" ] ||
  echo "Its hooks changed: they apply to Claude Code sessions started from now on."
rm -f "$LOG"
exit 0
