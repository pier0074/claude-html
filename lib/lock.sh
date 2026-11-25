# Sourced, not run: the one lock every save, build and update takes turns
# through, so two never write the same pages, cache or clone at once.
#
#   . "$HERE/lib/lock.sh"
#   ch_lock_take <seconds> [<what to say while waiting>]   0: taken, 1: not
#   ch_lock_release                                        only if taken here
#   ch_lock_holder                                         the holder's pid
#
# macOS has no flock, so the lock is a directory: mkdir makes it or fails,
# atomically. Inside, who holds it: the pid, and when that process started,
# as ps says - a pid alone is reused after a reboot or a kill -9, and a lock
# whose pid now names some other process would stop every save for good.
# A lock is someone else's while that very process runs, and for at most
# CH_LOCK_STALE_MIN minutes; past that, or once its process is gone, it is
# left over. A left-over lock is taken away by one waiter at a time, under a
# second lock, and only after checking again that it is the same one: two
# waiters can never both take one away, nor one take away a lock another
# has just made.
#
# The lock's own pid file is written too: releases before 3.1.3 read that,
# and an update starts from one of them.
#
# The owner line keeps the start time as ps prints it in local time, which
# is what releases before 3.7.3 compare. Local time depends on the time
# zone: a waiter in another one, or either side of a daylight-saving
# change, read a live lock as left over. So the lock also holds "started",
# the start of the process told apart in a way no clock setting changes:
# on Linux, its start in ticks since boot and which boot that is (the start
# time ps derives drifts as NTP corrects the boot time); elsewhere the
# start time in UTC. A lock with no "started" was written by an older
# release, and is judged as it always was.

CH_LOCK="$HOME/.claude/.claude-html.lock"
CH_LOCK_STALE_MIN=30
CH_LOCK_OWN=0
CH_LOCK_ME=""

# When a process started, as ps prints it, in one locale whoever asks.
ch_proc_start() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//'; }

# Which start of a process this is, the same in every time zone and after
# any change to the clock; empty when it cannot be told.
ch_proc_key() {
  if [ -r "/proc/$1/stat" ] && [ -r /proc/sys/kernel/random/boot_id ]; then
    # Field 22, counted after the name in brackets, which may hold spaces.
    _lk="$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f20)"
    _lb="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
    case "$_lk" in ''|*[!0-9]*) ;; *) [ -n "$_lb" ] && { printf 'boot %s tick %s' "$_lb" "$_lk"; return 0; } ;; esac
  fi
  _lk="$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//')"
  [ -n "$_lk" ] && printf 'utc %s' "$_lk"
  return 0
}

ch_lock_owner() {
  if [ -f "$CH_LOCK/owner" ]; then cat "$CH_LOCK/owner" 2>/dev/null
  else cat "$CH_LOCK/pid" 2>/dev/null; fi
}
ch_lock_holder() { _o="$(ch_lock_owner)"; printf '%s' "${_o%% *}"; }

# Whether the lock, as its owner line says, is left over.
ch_lock_stale() {
  _pid="${1%% *}"; _start=""
  case "$1" in *" "*) _start="${1#* }" ;; esac
  if [ -z "$_pid" ]; then
    # Made, and nothing said yet: a moment's work, unless it is old.
    [ -n "$(find "$CH_LOCK" -maxdepth 0 -mmin +2 2>/dev/null)" ]; return
  fi
  kill -0 "$_pid" 2>/dev/null || return 0
  if [ -f "$CH_LOCK/started" ]; then
    _lw="$(cat "$CH_LOCK/started" 2>/dev/null)"; _now="$(ch_proc_key "$_pid")"
    [ -n "$_lw" ] && [ -n "$_now" ] && [ "$_now" != "$_lw" ] && return 0
  elif [ -n "$_start" ]; then
    _now="$(ch_proc_start "$_pid")"
    [ -n "$_now" ] && [ "$_now" != "$_start" ] && return 0
  fi
  [ -n "$(find "$CH_LOCK" -maxdepth 0 -mmin +"$CH_LOCK_STALE_MIN" 2>/dev/null)" ]
}

# Takes a left-over lock away, if it still is the one judged left over.
ch_lock_reclaim() {
  _r="$CH_LOCK.reclaim"
  # A reclaim that died half way is itself left over after a minute.
  if ! mkdir "$_r" 2>/dev/null; then
    [ -n "$(find "$_r" -maxdepth 0 -mmin +1 2>/dev/null)" ] && rmdir "$_r" 2>/dev/null
    return 1
  fi
  if [ "$(ch_lock_owner)" = "$1" ] && ch_lock_stale "$1"; then
    _g="$CH_LOCK.gone.$$"
    mv "$CH_LOCK" "$_g" 2>/dev/null && rm -rf "$_g"
  fi
  rmdir "$_r" 2>/dev/null
  return 0
}

ch_lock_take() {
  _limit=$(( ${1:-0} * 2 )); _say="${2:-}"; _waited=0
  mkdir -p "${CH_LOCK%/*}" 2>/dev/null
  while ! mkdir "$CH_LOCK" 2>/dev/null; do
    _o="$(ch_lock_owner)"
    if ch_lock_stale "$_o"; then ch_lock_reclaim "$_o" && continue; fi
    [ "$_waited" -ge "$_limit" ] && return 1
    [ "$_waited" = 0 ] && [ -n "$_say" ] && printf '%s\n' "$_say" >&2
    sleep 0.5
    _waited=$((_waited + 1))
  done
  CH_LOCK_ME="$$ $(ch_proc_start $$)"
  # "started" before the owner line: a waiter that finds the owner finds it.
  ch_proc_key $$ > "$CH_LOCK/started.tmp" && mv -f "$CH_LOCK/started.tmp" "$CH_LOCK/started"
  printf '%s\n' "$CH_LOCK_ME" > "$CH_LOCK/owner.tmp" && mv -f "$CH_LOCK/owner.tmp" "$CH_LOCK/owner"
  printf '%s\n' "$$" > "$CH_LOCK/pid"
  CH_LOCK_OWN=1
  return 0
}

ch_lock_release() {
  if [ "$CH_LOCK_OWN" = 1 ] && [ "$(ch_lock_owner)" = "$CH_LOCK_ME" ]; then rm -rf "$CH_LOCK"; fi
  CH_LOCK_OWN=0
  return 0
}
