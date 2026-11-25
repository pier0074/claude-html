#!/usr/bin/env bash
# Save Claude conversation backup as clean JSON per session
# Called by the Stop hook after every reply (--background), and by PreCompact
# and SessionEnd
#
# Reads JSONL from ~/.claude/projects/<project-folder>/*.jsonl
# Produces one JSON file per session in $PROJECT/.claude/.claude-conversations/
# Skips sessions that already have an up-to-date backup (by mtime)
#
# The raw transcripts are deleted after cleanupPeriodDays (30 by default), so
# these archives are the permanent record. They therefore keep what the
# transcript knows and a reader would want back:
#   - prompts you typed, kept apart from tool results (both are type "user"
#     in the raw transcript, which is why an archive that calls them all
#     "user" cannot be rendered faithfully)
#   - the arguments of each tool call, so an Edit still says which file and
#     which text — tool names alone cannot answer "what changed?"
#   - thinking, bounded as the page bounds it, since the page built from the
#     transcript shows it and the one built from the archive should too
#   - tokens per hour and model, de-duplicated by message id across the
#     session and its sub-agents exactly as the build counts them, because
#     the dashboard's history is otherwise rewritten when a transcript goes
#   - what the session cost, where Claude Code recorded it, for the same
#     reason: it is written into the transcript and nowhere else

set -euo pipefail
# What it writes holds conversations: for its owner only.
umask 077

# BSD stat and GNU stat disagree about everything, including how to ask for
# a size in bytes. GNU goes first: BSD's -c genuinely fails, but GNU's -f
# means "filesystem status" and succeeds with the wrong answer entirely.
size_of() { stat -c %s "$1" 2>/dev/null || stat -f %z "$1"; }

# Claude Code hands every hook a JSON note on stdin naming the session and its
# transcript. With it, this session's transcript is known exactly; without it —
# run by hand — it has to be searched for, which means reading every transcript.
# Read before anything else: the detached copy below gets no stdin of its own.
TRANSCRIPT="${CLAUDE_HTML_TRANSCRIPT:-}"
PAYLOAD=""
if [ -z "$TRANSCRIPT" ] && [ ! -t 0 ]; then
  IFS= read -r -t 2 -d '' PAYLOAD || true
  TRANSCRIPT="$(printf '%s' "$PAYLOAD" |
    sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
    sed 's|\\/|/|g')"
fi

# The Stop hook fires after every reply. Hooks run synchronously and a save of a
# long session takes seconds, so from there this relaunches itself detached and
# returns at once: nobody waits on it.
if [ "${1:-}" = "--background" ]; then
  # A newer release, told to the person once per release, as a line Claude
  # Code shows them: a Stop hook's systemMessage, which the hooks reference
  # calls a "Warning message shown to the user", and which, unlike
  # additionalContext, is not handed to Claude. Only from what the daily
  # check left in the state file, with builtins and no network: this is the
  # part of the save Claude Code waits on.
  _msg=""
  _here="${BASH_SOURCE[0]%/*}"; [ "$_here" = "${BASH_SOURCE[0]}" ] && _here=.
  if [ -f "$HOME/.claude/.claude-html.update" ]; then
    _pwd="$PWD"; cd -P "$_here" 2>/dev/null && _here="$PWD"; cd "$_pwd" 2>/dev/null
    _ver=""; [ -f "$_here/VERSION" ] && read -r _ver < "$_here/VERSION"
    # shellcheck source=lib/version.sh
    if [ -f "$_here/lib/version.sh" ] && . "$_here/lib/version.sh" &&
       ch_update_notice "$_here" "$_ver" && [ "$CH_UP_TOLD" != "$CH_UP_NOTICE" ]; then
      _msg="claude-html $CH_UP_NOTICE is out · update with: claude-html --update"
      # Not noted (a full disk, a folder it may not write in), it is told
      # again next time; under set -e a failure here stopped every save.
      CH_UP_TOLD="$CH_UP_NOTICE"; ch_update_write || true
    fi
  fi
  # The owner's stop rules and API budget, told once each in the same
  # way: a rule about to apply or just started, a budget level reached.
  # Never the plan's own percentages, which Claude Code warns about itself.
  # Builtins only, unless there is something to tell.
  # shellcheck source=lib/limits.sh
  if [ -f "$_here/lib/limits.sh" ]; then
    # Its own rules for errors: what it cannot work out, it does not say.
    set +eu
    if . "$_here/lib/limits.sh" 2>/dev/null; then
      ch_lim_settings
      if [ -n "$CH_LIM_ON" ] && { [ "$CH_LIM_N" -gt 0 ] || [ "$CH_LIM_BC" -gt 0 ]; }; then
        _sid=""; _re='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9._-]{1,128})"'
        [[ "$PAYLOAD" =~ $_re ]] && _sid="${BASH_REMATCH[1]}"
        ch_lim_announce "$_sid" 2>/dev/null
        [ -n "${CH_ANN:-}" ] && while IFS= read -r _l; do
          [ -n "$_l" ] || continue
          _msg="${_msg:+$_msg\\n}⚠ claude-html · $_l"
          case "$_l" in your*) ch_lim_banner "Y${_l#y}" ;; *) ch_lim_banner "$_l" ;; esac
        done <<< "$CH_ANN"
      fi
    fi
    set -eu
  fi
  [ -n "$_msg" ] && printf '{"systemMessage":"%s"}\n' "$_msg"
  CLAUDE_HTML_TRANSCRIPT="$TRANSCRIPT" nohup "${BASH:-bash}" "$0" --try </dev/null >/dev/null 2>&1 &
  exit 0
fi
# The save at session end detaches as well, for a harder reason: Claude Code
# does not wait for a hook while it quits. One still running is cancelled
# ("SessionEnd hook failed: Hook cancelled"), and a save of a long session takes
# far longer than quitting does — so the save that matters most, the last one,
# was the one being killed, after holding the terminal up. Detached, quitting
# is instant and the save finishes on its own. Unlike the save after a reply it
# does not give way to another save in progress: it waits its turn.
# The save before a compaction detaches too: Claude Code waits for that hook,
# up to a minute of a full build, while the compaction only adds to the
# transcript - what it summarises stays in the file - so nothing is lost by
# saving just after instead.
EVENT="$(printf '%s' "$PAYLOAD" |
  sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
if [ "${1:-}" = "--detach" ] ||
   { [ -z "${1:-}" ] && { [ "$EVENT" = SessionEnd ] || [ "$EVENT" = PreCompact ]; } && [ -z "${CLAUDE_HTML_DETACHED:-}" ]; }; then
  CLAUDE_HTML_DETACHED=1 CLAUDE_HTML_TRANSCRIPT="$TRANSCRIPT" \
    nohup "${BASH:-bash}" "$0" </dev/null >/dev/null 2>&1 &
  exit 0
fi
# --try is best effort: if another save is running it gives up, because the
# next reply's save will carry this one's changes. Without it, wait — at session
# end this is the save that must not be lost.
MODE=wait
[ "${1:-}" = "--try" ] && MODE=try

# Only archive work under the projects root. Where that is, and where the
# pages go, is decided exactly as the claude-html command decides it.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/conf.sh
. "$HERE/lib/conf.sh"
# Its physical path too, as the command has it: the update notice is kept
# per clone, by that path. The projects root stays decided by the other.
HERE_P="$(cd -P "$HERE" && pwd)"
# Once a day, from a save nobody waits on (the copy the reply's hook
# detached, or the session end's), ask whether a newer release is out, for
# at most five seconds. Before the lock, so no other save waits on it
# either, and before the build at the end, which puts it on the index.
if { [ "$MODE" = try ] || [ -n "${CLAUDE_HTML_DETACHED:-}" ]; } && [ -f "$HERE/lib/update.sh" ]; then
  "${BASH:-bash}" "$HERE/lib/update.sh" "$HERE_P" --daily </dev/null >/dev/null 2>&1 || true
fi
# And once this save is over and has let go of the lock, the automatic
# update when one is due (CLAUDE_HTML_AUTO_UPDATE): update.sh decides from
# the state alone and, if so, starts it detached, from a copy of itself.
# Only from a save nobody waits on, as the daily check.
auto_update() {
  { [ "$MODE" = try ] || [ -n "${CLAUDE_HTML_DETACHED:-}" ]; } && [ -f "$HERE/lib/update.sh" ] || return 0
  "${BASH:-bash}" "$HERE/lib/update.sh" "$HERE_P" --auto-maybe </dev/null >/dev/null 2>&1 || true
}
if [[ "$(pwd)" != "$ROOT" && "$(pwd)" != "$ROOT"/* ]]; then
  auto_update
  exit 0
fi

# The JavaScript this script carries is the same bytes under osascript and
# node. platform.sh picks which runs it, as it does for the command: node
# when a working one is here, osascript when not. Picked after the checks
# above, so a save that has nothing to do never pays for looking.
# shellcheck source=lib/platform.sh
. "$HERE/lib/platform.sh"
ch_pick_engine
run_js() { ch_js "$@"; }

# One save at a time: they share the pages, and the build's cache. The lock
# is lock.sh's, the one the command and the update take turns through too.
# shellcheck source=lib/lock.sh
. "$HERE/lib/lock.sh"
OWN_LOCK=0
release_lock() { ch_lock_release; return 0; }
# A reply's save gives way at once; the session end's waits fifty seconds,
# inside the hook's minute (CLAUDE_HTML_LOCK_WAIT, for the tests).
WAIT=0; [ "$MODE" = try ] || WAIT="${CLAUDE_HTML_LOCK_WAIT:-50}"
if ch_lock_take "$WAIT"; then
  OWN_LOCK=1
elif [ "$MODE" = try ]; then
  # Busy and best effort: the running save covers this one. Said in
  # .last-save, with who holds the lock, so one that never lets go shows.
  [ -d "$OUT" ] && printf '%s mode=gave-way holder=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(ch_lock_holder)" \
    > "$OUT/.last-save" 2>/dev/null
  exit 0
fi
# Busy for too long at session end: saving without the lock beats losing the
# final save. Each archive is then written under a name of its own, and
# moved into place only if no newer one got there first.
trap 'release_lock' EXIT

# The transform, in a JavaScript engine the machine already has, written to a
# directory of its own: osascript insists on a .js extension.
# Rebuild the pages, so closing a session is all it takes to see it. Only what
# changed is rebuilt, which costs about a third of a second.
#
# It runs on the way out however the script leaves — there is nothing to
# archive, a project has no transcripts yet, jq-era files are missing — because
# another session may have changed even when this one had nothing to save. A
# failure here must never break the session that is ending, so it is swallowed;
# it is not lost either, since convert.js records it in .build-errors.json and
# the index shows a banner.
rebuild_pages() {
  # The helper app kept in step with its source, where there is one.
  ch_helper_refresh "$HERE" --if-stale || true
  [ -f "$HERE/build/convert.js" ] || return 0
  # The build keeps a cache that only one build at a time may write: one
  # that runs without the lock does without it, and reads everything.
  local nocache=""
  [ "$OWN_LOCK" = 1 ] || nocache=":cache false"
  # shellcheck disable=SC2086
  run_js "$HERE/build/convert.js" "$(ch_js_opts "$HERE_P" $nocache)" >/dev/null 2>&1 || true
  ch_private_out "$OUT"
}

# A session that fails to archive is recorded, one file per session, so the
# index can show it and a later success can clear exactly its own entry.
ERRDIR="$OUT/.archive-errors"
record_failure() {
  mkdir -p "$ERRDIR"
  { ch_json_obj id "$1" source "$2" error "archiving failed: ${3:-no output}" kind archive; echo; } \
    > "$ERRDIR/$1.json"
}

# What the last save did, so its behaviour can be checked after the fact — the
# save after a reply runs detached, where nobody sees its output.
FOUND=none; SAVED=0; CANDIDATES=()
write_status() {
  [ -d "$OUT" ] || return 0
  printf '%s mode=%s found=%s candidates=%s archived=%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$MODE" "$FOUND" "${#CANDIDATES[@]}" "$SAVED" \
    > "$OUT/.last-save" 2>/dev/null || true
}

ARCHIVE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dbarchive.XXXXXX")"
ARCHIVER="$ARCHIVE_TMP/archive.js"
trap 'rm -rf "$ARCHIVE_TMP"; write_status; rebuild_pages; release_lock; auto_update' EXIT
cat > "$ARCHIVER" <<'ARCHIVEREOF'
function run(argv) {
  var path = argv[0], sid = argv[1], project = argv[2];
  var sourceBytes = Number(argv[3] || 0);
  // The archive this one replaces, and where to keep what lets the next save
  // carry on from this one: both optional, and either may be gone or stale.
  var prevPath = argv[4] || "", statePath = argv[5] || "";
  // The redaction's signature, as the shell worked it out, and the owner's
  // own list. "off" is no redaction; no signature at all, as when a test
  // runs this alone, is the built-in rules, and an archive no save trusts.
  var rsig = argv[6] || "", listPath = argv[7] || "";
  // The format this release writes, from lib/version.sh, by the save.
  var FORMAT = Number(argv[8]) || 0;
  if (!FORMAT) throw new Error("no archive format given: nothing archived");
  // Where to say how many bytes the archive is, so the save can tell the
  // whole of it from a part: optional, as for a test that runs this alone.
  var lenPath = argv[9] || "";

  // ── the platform ──
  var JXA = typeof $ !== "undefined";
  var fm = JXA ? $.NSFileManager.defaultManager : null, nfs = JXA ? null : require("fs");
  function readText(p) {
    if (JXA) {
      if (!fm.fileExistsAtPath(p)) return null;
      var raw = $.NSString.stringWithContentsOfFileEncodingError(p, 4, null);
      var t = raw ? $.CFMakeCollectable(raw).js : null;
      return typeof t === "string" ? t : null;
    }
    try { return nfs.readFileSync(p, "utf8"); } catch (e) { return null; }
  }
  function listDir(dir) {
    if (JXA) {
      // A missing folder comes back as a nil object, which is truthy here.
      var items = fm.contentsOfDirectoryAtPathError(dir, null);
      var a = items ? $.CFMakeCollectable(items).js : null;
      return Array.isArray(a) ? a.map(function (x) { return x.js; }) : [];
    }
    try { return nfs.readdirSync(dir); } catch (e) { return []; }
  }
  // The size of every sub-agent transcript in a folder, in one call: through
  // the bridge, a few hundred of them one by one take most of a second.
  var sizes = {};
  function sizesIn(dir) {
    if (!JXA) return;
    var sh = Application.currentApplication();
    sh.includeStandardAdditions = true;
    var out = "";
    try {
      out = sh.doShellScript("/usr/bin/find -H '" + String(dir).replace(/'/g, "'\\''") + "' -maxdepth 1" +
        " -name 'agent-*.jsonl' -type f -exec /usr/bin/stat -f '%z %N' {} + 2>/dev/null; true",
        { alteringLineEndings: false });
    } catch (e) { out = ""; }
    out.split("\n").forEach(function (l) {
      var m = /^(\d+) (\/.*)$/.exec(l);
      if (m) sizes[m[2]] = Number(m[1]);
    });
  }
  function sizeOf(p) {
    if (p in sizes) return sizes[p];
    if (JXA) {
      if (!fm.fileExistsAtPath(p)) return -1;
      var at = fm.attributesOfItemAtPathError(p, null);
      var o = at ? $.CFMakeCollectable(at).js : null;
      return o && o.NSFileSize ? Number(o.NSFileSize.js) : -1;
    }
    try { return nfs.statSync(p).size; } catch (e) { return -1; }
  }
  // From a byte offset to the end, and where in it the last whole line ends.
  function readFrom(p, offset) {
    if (JXA) {
      var h = $.NSFileHandle.fileHandleForReadingAtPath(p);
      if (!h || h.isNil()) return null;
      // The whole lines decoded apart from an unfinished last one, which
      // may end inside a character, as convert.js reads them.
      try {
        h.seekToFileOffset(offset);
        var data = h.readDataToEndOfFile, n = Number(data.length);
        var loc = Number(data.rangeOfDataOptionsRange($("\n").dataUsingEncoding(4), 1, $.NSMakeRange(0, n)).location);
        var at = loc < n ? loc + 1 : 0;
        var dec = function (from, len) {
          var s = $.NSString.alloc.initWithDataEncoding(data.subdataWithRange($.NSMakeRange(from, len)), 4);
          var t = !s || s.isNil() ? null : s.js;
          return typeof t === "string" ? t : null;
        };
        var head = dec(0, at);
        if (head === null) return null;
        var tail = dec(at, n - at);
        return { text: head + (tail || ""), cut: at };
      } catch (e) { return null; } finally { h.closeFile; }
    }
    var fd;
    try { fd = nfs.openSync(p, "r"); } catch (e) { return null; }
    try {
      var parts = [], total = 0;
      for (;;) {
        var buf = Buffer.allocUnsafe(8 << 20);
        var got = nfs.readSync(fd, buf, 0, buf.length, offset + total);
        if (!got) break;
        parts.push(got < buf.length ? buf.subarray(0, got) : buf);
        total += got;
      }
      var all = parts.length === 1 ? parts[0] : Buffer.concat(parts, total);
      return { text: all.toString("utf8"), cut: all.lastIndexOf(10) + 1 };
    } catch (e) { return null; } finally { try { nfs.closeSync(fd); } catch (e) {} }
  }
  function bytesAt(p, start, len) {
    if (JXA) {
      var h = $.NSFileHandle.fileHandleForReadingAtPath(p);
      if (!h || h.isNil()) return null;
      try {
        h.seekToFileOffset(start);
        var data = h.readDataOfLength(len);
        return Number(data.length) === len ? data.base64EncodedStringWithOptions(0).js : null;
      } catch (e) { return null; } finally { h.closeFile; }
    }
    var fd;
    try { fd = nfs.openSync(p, "r"); } catch (e) { return null; }
    try {
      var buf = Buffer.alloc(len);
      var got = len ? nfs.readSync(fd, buf, 0, len, start) : 0;
      return got === len ? buf.toString("base64") : null;
    } catch (e) { return null; } finally { try { nfs.closeSync(fd); } catch (e) {} }
  }
  function digest(p) {
    if (JXA) {
      if (!fm.fileExistsAtPath(p)) return "";
      var sh = Application.currentApplication();
      sh.includeStandardAdditions = true;
      try {
        return sh.doShellScript("/sbin/md5 -q '" + String(p).replace(/'/g, "'\\''") + "'").trim();
      } catch (e) { return ""; }
    }
    try {
      return require("crypto").createHash("md5").update(nfs.readFileSync(p)).digest("hex");
    } catch (e) { return ""; }
  }
  function writeText(p, text) {
    if (JXA) {
      var dir = $(p).stringByDeletingLastPathComponent;
      fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(dir, true, $(), null);
      return !!$.NSString.alloc.initWithUTF8String(text).writeToFileAtomicallyEncodingError(p, true, 4, null);
    }
    try {
      nfs.mkdirSync(require("path").dirname(p), { recursive: true });
      nfs.writeFileSync(p + ".tmp" + process.pid, text, "utf8");
      nfs.renameSync(p + ".tmp" + process.pid, p);
      return true;
    } catch (e) { return false; }
  }
  function removeFile(p) {
    if (JXA) { fm.removeItemAtPathError(p, null); return; }
    try { nfs.unlinkSync(p); } catch (e) {}
  }

  // ── secrets ──
  // redact.js is appended to this script by the save, so the archive is
  // redacted by the very rules the pages are. Every string that can carry
  // what was said goes through it as it is read, before it is cut: a
  // secret the cut would halve is still seen whole.
  if (typeof claudeHtmlRedactor !== "function") throw new Error("redact.js is missing: nothing archived");
  var RED = claudeHtmlRedactor(rsig !== "off" && listPath ? readText(listPath) || "" : "", rsig !== "off", !JXA);

  // ── what a transcript says ──
  // parse.js is appended too, and reads every record as convert.js does:
  // the messages a page shows, cut and masked as it cuts and masks them,
  // the tokens and the cost. So once the transcript is gone, the page made
  // from this archive is the page that was made from the transcript.
  if (typeof claudeHtmlParse !== "function") throw new Error("parse.js is missing: nothing archived");
  var P = claudeHtmlParse(function () { return RED; });
  var hashText = P.hashText, usageLine = P.usageLine;
  function costLine(c, e) { P.costLine(c, e, sid); }
  function messagesOf(e, into) {
    P.messagesOf(e).forEach(function (m) { into.push(m); });
  }

  // ── carrying on from the last save ──
  // A transcript only grows, and reading 166 MB of it again after every
  // reply was most of a save. So beside the pages, in .cache/<id>.archive,
  // the archiver keeps how far it read — whole lines only — and what those
  // lines leave for later ones: how many messages they gave, when the
  // session started, the replies counted (one can straddle where it
  // stopped), the cost counter's last snapshot; and, for each sub-agent,
  // its size and the replies it added. The next save takes the messages
  // from the archive it replaces, reads on from that offset, and writes the
  // same bytes a save from nothing would. Anything that does not fit — this
  // script changed, the md5 or the archive does not match, the transcript
  // is shorter or different where it was sampled — is a read from the
  // start, and deleting the file is always safe.
  // The redaction's signature too: messages carried on from the last
  // archive were redacted by its rules and list, and must be these.
  var KEY = "3:" + FORMAT + ":" + hashText(String(run)) + ":" + hashText(String(claudeHtmlParse)) + ":" + rsig;
  var WINDOW = 4096;
  function fingerprint(off) {
    var w = Math.min(WINDOW, off);
    var parts = [bytesAt(path, 0, w), bytesAt(path, Math.max(0, Math.floor(off / 2) - (w >> 1)), w),
                 bytesAt(path, off - w, w)];
    for (var i = 0; i < parts.length; i++) if (parts[i] === null) return null;
    return off + ":" + parts.map(hashText).join(":");
  }
  function newScan() {
    return { off: 0, msgs: 0, lines: 0, started: null, peek: { cwd: null, title: null },
             usage: P.newReplies(), cost: P.newCost() };
  }
  // The title as the build finds it: Claude Code's own, said within the
  // first PEEK_LINES lines, or none.
  function scanChunk(st, text, messages) {
    var lines = text.split("\n");
    lines.forEach(function (line, j) {
      if (!line) return;
      var e;
      try { e = JSON.parse(line); } catch (err) { return; }
      if (!e || typeof e !== "object") return;
      if (!st.started && e.timestamp) st.started = e.timestamp;
      if (st.lines + j <= P.PEEK_LINES && !(st.peek.cwd && st.peek.title)) P.peekLine(st.peek, e);
      messagesOf(e, messages);
      usageLine(st.usage, e);
      costLine(st.cost, e);
    });
    st.lines += lines.length - 1;
    st.msgs = messages.length;
  }

  var state = null;
  if (statePath) {
    var sum = readText(statePath + ".md5");
    var raw = sum && sum.trim() === digest(statePath) ? readText(statePath) : null;
    try { state = raw ? JSON.parse(raw) : null; } catch (e) { state = null; }
    if (!state || typeof state !== "object" || state.key !== KEY || !state.agents ||
        typeof state.agents !== "object") state = null;
  }
  var prev = null;
  if (state && prevPath) {
    try { prev = JSON.parse(readText(prevPath) || "null"); } catch (e) { prev = null; }
  }
  var st = null, messages = [];
  if (state && prev && state.path === path && state.archive === prevPath && state.scan &&
      prev.format === FORMAT && prev.redact === rsig && prev.sourceBytes === state.sourceBytes &&
      prev.messageCount === state.messageCount && Array.isArray(prev.messages) &&
      prev.messages.length >= state.scan.msgs && typeof state.fp === "string" &&
      state.fp === fingerprint(state.scan.off)) {
    st = state.scan;
    messages = prev.messages.slice(0, st.msgs);
  }
  if (!st) st = newScan();
  prev = null;

  var got = readFrom(path, st.off);
  if (got === null) return "";
  var nl = got.text.lastIndexOf("\n");
  scanChunk(st, got.text.slice(0, nl + 1), messages);
  st.off += got.cut;
  // Kept as it stands now, before a last line still being written is read
  // on top of a copy of it.
  var keep = JSON.stringify(st), keptOff = st.off, tail = got.text.slice(nl + 1);
  // Of the bytes just read, before anything else happens to the file.
  var keptFp = fingerprint(keptOff);
  got = null;
  if (tail) {
    st = JSON.parse(keep);
    messages = messages.slice();
    scanChunk(st, tail, messages);
  }
  var startedAt = st.started, mainBy = st.usage.by;

  // Sub-agents spend tokens on the session's behalf and are filed beside it:
  // a gigabyte of them for one session here. A finished one never changes,
  // so one the size it was last time adds what it added then, and only one
  // that changed is read. A reply with neither a message id nor a uuid is
  // numbered as it is read, after the session's own, so its key is given
  // again in that order.
  var kids = path.replace(/\.jsonl$/, "") + "/subagents", agents = {}, agentOps = {};
  var names = listDir(kids).filter(function (f) { return /^agent-.*\.jsonl$/.test(f); }).sort();
  if (names.length) sizesIn(kids);
  var agentAcc = { by: {}, n: st.usage.n };
  names.forEach(function (f) {
    var size = sizeOf(kids + "/" + f), was = state && state.agents[f];
    agents[f] = size;
    var ops;
    if (was && size >= 0 && was.size === size && Array.isArray(was.ops)) {
      ops = was.ops;
    } else {
      var own = { by: {}, n: 0 };
      var got = readFrom(kids + "/" + f, 0);
      String(got ? got.text : "").split("\n").forEach(function (line) {
        if (line.indexOf('"usage"') < 0) return;
        var e; try { e = JSON.parse(line); } catch (err) { return; }
        if (e && typeof e === "object") usageLine(own, e);
      });
      ops = Object.keys(own.by).map(function (k) {
        return [k.indexOf("r:") === 0 ? null : k, own.by[k]];
      });
    }
    agentOps[f] = { size: size, ops: ops };
    ops.forEach(function (o) { agentAcc.by[o[0] === null ? "r:" + (agentAcc.n++) : o[0]] = o[1]; });
  });
  var agentBy = agentAcc.by;

  // Totals per UTC hour and model, plus each reply under its message id so
  // the build can still recognise one a resumed session copied. The session's
  // own replies come first and its sub-agents' after, from agentFrom on. A
  // reply without an id keeps the key it was counted under.
  // A cell has parse.js's seven figures (the cache write's 1-hour part and
  // its part of unknown duration among them); a reply row its tokens and
  // those two parts: [id, hour, model, input, output, cache read, cache
  // write, 1-hour, unknown].
  var usage = {}, replies = [];
  function emit(by, k) {
    var r = by[k];
    if (r.hour.length !== 13) return;
    var d = usage[r.hour] = usage[r.hour] || {};
    var a = d[r.model] = d[r.model] || [0, 0, 0, 0, 0, 0, 0];
    for (var i = 0; i < 7; i++) a[i] += r.t[i] || 0;
    var row = [r.mid, r.hour, r.model].concat(r.t.slice(0, 4), [r.t[5] || 0, r.t[6] || 0]);
    if (!r.mid) row.push(k);
    replies.push(row);
  }
  Object.keys(mainBy).forEach(function (k) { if (!(k in agentBy)) emit(mainBy, k); });
  var agentFrom = replies.length;
  Object.keys(agentBy).forEach(function (k) { emit(agentBy, k); });

  // As an eighth figure on the usage cell, after the tokens, as the build adds it.
  var cost = st.cost.seen ? st.cost.cells : null;
  var costPart = !!cost && (st.cost.part || Object.keys(st.cost.pending).length > 0);
  if (cost) {
    Object.keys(cost).forEach(function (hour) {
      var d = usage[hour] = usage[hour] || {};
      Object.keys(cost[hour]).forEach(function (m) {
        var a = d[m] = d[m] || [0, 0, 0, 0, 0, 0, 0];
        a[7] = (a[7] || 0) + cost[hour][m];
      });
    });
  }

  var archive = JSON.stringify({
    sourceBytes: sourceBytes,
    // CH_ARCHIVE_FORMAT, in lib/version.sh, says what each format added.
    // Read by the save's skip check, which is why both sit near the top.
    format: FORMAT,
    redact: rsig,
    sessionId: sid,
    project: project,
    // Claude Code's own title, as the page from the transcript has it.
    title: st.peek.title || "",
    startedAt: startedAt,
    endedAt: messages.length ? messages[messages.length - 1].timestamp : null,
    messageCount: messages.length,
    promptCount: messages.filter(function (m) { return m.role === "user" && !m.side; }).length,
    messages: messages,
    usage: usage,
    replies: replies,
    agentFrom: agentFrom,
    agentBytes: agents,
    // Only said when true, so an archive without it reads as it always did.
    costPart: costPart ? true : undefined
  });

  // Written now, though the archive is moved into place only after this
  // returns: if that fails, the archive left there does not match what this
  // says it is, and the next save reads from the start.
  // Not kept when the transcript was cut short or replaced during this save:
  // what was read no longer matches the file, so the next save starts over.
  if (statePath && (!keptFp || keptFp !== fingerprint(keptOff))) {
    removeFile(statePath + ".md5");
  } else if (statePath) {
    var kept = '{"key":' + JSON.stringify(KEY) + ',"path":' + JSON.stringify(path) +
      ',"archive":' + JSON.stringify(prevPath) + ',"sourceBytes":' + JSON.stringify(sourceBytes) +
      ',"messageCount":' + messages.length + ',"fp":' + JSON.stringify(keptFp) +
      ',"scan":' + keep + ',"agents":' + JSON.stringify(agentOps) + "}";
    var d = writeText(statePath, kept) ? digest(statePath) : "";
    if (d) writeText(statePath + ".md5", d + "\n");
    else removeFile(statePath + ".md5");
  }
  // Its length in UTF-8, the newline the engine ends it with included: what
  // the save must find in the file before it may replace the last archive.
  // Not said, nothing is moved.
  if (lenPath && !writeText(lenPath, String(utf8Length(archive) + 1) + "\n")) {
    throw new Error("could not note the archive's length: nothing archived");
  }
  return archive;
}
// Bytes in UTF-8. JSON.stringify leaves no lone surrogate, so each half of a
// pair is two of a character's four.
function utf8Length(s) {
  if (typeof Buffer !== "undefined") return Buffer.byteLength(s, "utf8");
  var rest = s.replace(/[\x00-\x7f]+/g, ""), n = s.length;
  for (var i = 0; i < rest.length; i++) {
    var c = rest.charCodeAt(i);
    n += c >= 0xD800 && c <= 0xDFFF ? 1 : c >= 0x800 ? 2 : 1;
  }
  return n;
}
// osascript calls run() by itself; node has to be asked.
if (typeof $ === "undefined" && typeof require !== "undefined" &&
    typeof module !== "undefined" && require.main === module) {
  // osascript ends its output with a newline, but prints nothing at all for an
  // empty result; a lone newline here would pass for an archive and replace a
  // good one.
  var result = run(process.argv.slice(2));
  if (result) process.stdout.write(result + "\n");
}
ARCHIVEREOF
# Which rules and which list: an archive made under others is made again.
# Worked out before either is read, so that one changed in between leaves
# the older signature, and the next save makes the archive again.
RSIG="$(ch_redact_sig "$HERE")"
# The redactor and the parse, after the archiver: a function declaration
# is there for run() wherever in the file it stands. Missing, the archiver
# refuses.
cat "$HERE/build/redact.js" "$HERE/build/parse.js" >> "$ARCHIVER" 2>/dev/null || true
# The archive format this release writes, from lib/version.sh: the archiver
# writes it, and the check below skips only what is in it already.
# shellcheck source=lib/version.sh
. "$HERE/lib/version.sh"

PROJECT_PATH=$(pwd)

# Claude Code names project folders by replacing / with - in the path
PROJECT_FOLDER_NAME=$(echo "$PROJECT_PATH" | tr '/' '-')
SOURCE_DIR="$HOME/.claude/projects/$PROJECT_FOLDER_NAME"

# No directory of that name is not the end of it: a renamed project has no
# launch directory under the new name, and its sessions are found by cwd
# below instead. Bail only when nothing at all turns up.

# Where a session's archive goes: the folder it was launched in, which its
# transcript states first, and the project it belongs to. A hook runs in
# the session's current folder, and Claude may have gone into app/src: that
# is no project of its own. Only when the launch folder is gone (a project
# renamed since) or outside the root does the folder this runs in decide.
launch_dir() {   # transcript
  local c
  c="$(head -c 262144 "$1" 2>/dev/null | grep -o '"cwd":"[^"\\]*"' | head -1 |
       sed 's/^"cwd":"//; s/"$//')" || c=""
  [ -n "$c" ] && [ -d "$c" ] && { [ "$c" = "$ROOT" ] || [[ "$c" == "$ROOT"/* ]]; } || return 1
  printf '%s' "$c"
}
# The archive folder: made for its owner only, and ignoring itself, so a
# project's git never takes a conversation into a commit. What a save that
# died half way left there goes after an hour.
conv_dir() {   # project folder
  local d="$1/.claude/.claude-conversations"
  mkdir -p "$d"
  ch_private "$d"
  [ -f "$d/.gitignore" ] || printf '# Written by claude-html: the conversations stay out of git.\n*\n' \
    > "$d/.gitignore" 2>/dev/null || true
  find "$d" -maxdepth 1 -name '.*.json.partial*' -mmin +60 -exec rm -f {} + 2>/dev/null
  printf '%s' "$d"
}
CONV_DIR=""
USED_DIRS=()

SAVED=0

# Transcripts are filed under the directory the session was LAUNCHED in, and
# that name never changes afterwards. Rename a project and its own sessions
# stop being found here. So take the sessions launched here, plus any whose
# recorded cwd says they were working here — which is what a renamed folder
# looks like from the inside.
CANDIDATES=()
for f in "$SOURCE_DIR"/*.jsonl; do
  [[ -f "$f" ]] && CANDIDATES+=("$f")
done
add_candidate() {
  local seen
  for seen in "${CANDIDATES[@]+"${CANDIDATES[@]}"}"; do
    [[ "$seen" == "$1" ]] && return 0
  done
  CANDIDATES+=("$1")
}
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  # The hook named this session's transcript, wherever it is filed — which is
  # the renamed-project case the search below exists for, without it having to
  # read every transcript on the machine after every reply.
  FOUND=hook
  add_candidate "$TRANSCRIPT"
else
  FOUND=search
  while IFS= read -r f; do
    [[ -n "$f" ]] && add_candidate "$f"
    # Not sub-agents: they live in <session>/subagents and record the same cwd,
    # so a recursive search sweeps them up as if each were a conversation.
  done < <(grep -rl --include='*.jsonl' "\"cwd\":\"$PROJECT_PATH\"" \
             "$HOME/.claude/projects" 2>/dev/null | grep -v '/subagents/')
fi

if [ ${#CANDIDATES[@]} -eq 0 ]; then
  exit 0
fi

# Whether the archive there now was made from more of the transcript than
# this save read: another save, one that ran without the lock, got further,
# and its archive stays.
newer_there() {   # archive, bytes this save read
  local was
  [ -f "$1" ] || return 1
  was="$(head -c 300 "$1" | sed -n 's/^{"sourceBytes":\([0-9][0-9]*\),.*/\1/p')"
  [ -n "$was" ] && [ "$was" -gt "$2" ]
}
# Whether the archive just written is the whole of what the archiver made:
# as many bytes as it said, made from as much transcript as this save read,
# and ending as its object ends. A full disk cuts it anywhere, just after a
# "}" too, and the engine still exits cleanly; moved over the last good
# archive, a part would replace it, and the size check would then skip it
# for good.
whole() {   # file, the archiver's length file, bytes this save read
  local want=""
  [ -f "$2" ] && read -r want < "$2"
  case "$want" in ''|*[!0-9]*) return 1 ;; esac
  [ "$(size_of "$1")" = "$want" ] &&
    [[ "$(head -c 40 "$1")" == "{\"sourceBytes\":$3,"* ]] &&
    [[ "$(tail -c 2 "$1")" == *"}" ]]
}
for jsonl in "${CANDIDATES[@]+"${CANDIDATES[@]}"}"; do
  [[ -f "$jsonl" ]] || continue

  SESSION_ID=$(basename "$jsonl" .jsonl)
  PROJ="$(launch_dir "$jsonl")" || PROJ="$PROJECT_PATH"
  CONV_DIR="$(conv_dir "$PROJ")"
  USED_DIRS+=("$PROJ")
  OUTPUT_FILE="$CONV_DIR/${SESSION_ID}.json"

  # Skip only if the archive was made from exactly this much transcript.
  # Transcripts only ever grow, so their size says whether anything was added.
  # A timestamp cannot: a reply appended while the archive is being written
  # leaves an archive newer than the transcript that now holds more, and the
  # save at session end would then keep an archive missing the last reply.
  # The size is taken before reading, so a file that grows mid-read is only
  # ever archived again, never skipped.
  # An archive in an older format is written again once, while its
  # transcript is still here to supply what that format did not keep —
  # and so is one redacted by other rules or another list, or not at all.
  SIZE=$(size_of "$jsonl")
  if [[ -f "$OUTPUT_FILE" ]] && HEAD="$(head -c 300 "$OUTPUT_FILE")" &&
     [[ "$HEAD" == *"\"format\":$CH_ARCHIVE_FORMAT,"* ]] &&
     [[ "$HEAD" == *"\"redact\":\"$RSIG\","* ]] &&
     [[ "$(printf '%s' "$HEAD" |
       sed -n 's/.*"sourceBytes":\([0-9]*\).*/\1/p')" == "$SIZE" ]]; then
    continue
  fi

  # Written beside the archive and moved over it only once complete: a failed
  # run must leave the last good archive alone, since the transcript it came
  # from may already be gone. Not ending in .json keeps the build from reading
  # a half-written one.
  # Complete means whole() says so: the length the archiver gave, which rules
  # out the empty result of a transcript it cannot read, and the cut-off one
  # a full disk leaves, which osascript does not report as a failure.
  # A name of its own: two saves of one session, one without the lock, must
  # never write the same file, or the one still writing spoils the other's.
  PARTIAL="$CONV_DIR/.${SESSION_ID}.json.partial.$$.$RANDOM"
  # What lets the next save read only what this one did not: kept with the
  # build's cache, which only a save holding the lock may write.
  STATE=""
  [ "$OWN_LOCK" = 1 ] && STATE="$OUT/.cache/$SESSION_ID.archive"
  rm -f "$ARCHIVE_TMP/len"
  if run_js "$ARCHIVER" "$jsonl" "$SESSION_ID" "$PROJ" "$SIZE" "$OUTPUT_FILE" "$STATE" \
       "$RSIG" "$CLAUDE_HTML_REDACT_FILE" "$CH_ARCHIVE_FORMAT" "$ARCHIVE_TMP/len" \
       > "$PARTIAL" 2>"$ARCHIVE_TMP/err" && whole "$PARTIAL" "$ARCHIVE_TMP/len" "$SIZE" &&
     { newer_there "$OUTPUT_FILE" "$SIZE" || mv -f "$PARTIAL" "$OUTPUT_FILE"; }; then
    rm -f "$PARTIAL"
    rm -f "$ERRDIR/$SESSION_ID.json"
  else
    rm -f "$PARTIAL"
    record_failure "$SESSION_ID" "$jsonl" "$(head -c 300 "$ARCHIVE_TMP/err" 2>/dev/null || true)"
    continue
  fi

  SAVED=$((SAVED + 1))
done

# The build finds a nested project's archives through this list once its
# transcripts have expired, so a folder holding archives is put on it for good.
# Only on a list that exists: a missing one tells the build to walk the root,
# and starting one here with this folder alone would stop that walk for ever.
ARCHIVES_LIST="$HOME/.claude/claude-html.archives"
for d in "${USED_DIRS[@]+"${USED_DIRS[@]}"}"; do
  if [ -f "$ARCHIVES_LIST" ] && compgen -G "$d/.claude/.claude-conversations/*.json" >/dev/null &&
     ! grep -qxF "$d" "$ARCHIVES_LIST"; then
    printf '%s\n' "$d" >> "$ARCHIVES_LIST" 2>/dev/null || true
  fi
done

# Hook stdout lands in the transcript, so say one line, not one per session.
[ "$SAVED" -gt 0 ] && echo "Archived $SAVED session(s) to $CONV_DIR"

exit 0
