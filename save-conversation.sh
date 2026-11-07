#!/bin/bash
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
  PAYLOAD=""
  IFS= read -r -t 2 -d '' PAYLOAD || true
  TRANSCRIPT="$(printf '%s' "$PAYLOAD" |
    sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
    sed 's|\\/|/|g')"
fi

# The Stop hook fires after every reply. Hooks run synchronously and a save of a
# long session takes seconds, so from there this relaunches itself detached and
# returns at once: nobody waits on it.
if [ "${1:-}" = "--background" ]; then
  CLAUDE_HTML_TRANSCRIPT="$TRANSCRIPT" nohup /bin/bash "$0" --try </dev/null >/dev/null 2>&1 &
  exit 0
fi
# The save at session end detaches as well, for a harder reason: Claude Code
# does not wait for a hook while it quits. One still running is cancelled
# ("SessionEnd hook failed: Hook cancelled"), and a save of a long session takes
# far longer than quitting does — so the save that matters most, the last one,
# was the one being killed, after holding the terminal up. Detached, quitting
# is instant and the save finishes on its own. Unlike the save after a reply it
# does not give way to another save in progress: it waits its turn.
EVENT="$(printf '%s' "$PAYLOAD" |
  sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
if [ "${1:-}" = "--detach" ] ||
   { [ -z "${1:-}" ] && [ "$EVENT" = "SessionEnd" ] && [ -z "${CLAUDE_HTML_DETACHED:-}" ]; }; then
  CLAUDE_HTML_DETACHED=1 CLAUDE_HTML_TRANSCRIPT="$TRANSCRIPT" \
    nohup /bin/bash "$0" </dev/null >/dev/null 2>&1 &
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
# shellcheck source=conf.sh
. "$HERE/conf.sh"
if [[ "$(pwd)" != "$ROOT" && "$(pwd)" != "$ROOT"/* ]]; then
  exit 0
fi

# The JavaScript this script carries is the same bytes under osascript and
# node. platform.sh picks which runs it, as it does for the command: node
# when a working one is here, osascript when not. Picked after the checks
# above, so a save that has nothing to do never pays for looking.
# shellcheck source=platform.sh
. "$HERE/platform.sh"
ch_pick_engine
run_js() { ch_js "$@"; }

# One save at a time: they share the pages. macOS has no flock, so the lock is a
# directory — mkdir creates it or fails, atomically — holding the owner's PID,
# so a lock left by a crashed run can be told apart from one still in use.
LOCK="$HOME/.claude/.claude-html.lock"
OWN_LOCK=0
acquire_lock() {
  local waited=0 pid
  while ! mkdir "$LOCK" 2>/dev/null; do
    pid="$(cat "$LOCK/pid" 2>/dev/null || true)"
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      rm -rf "$LOCK"; continue                  # its owner is gone
    fi
    if [ -z "$pid" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
      rm -rf "$LOCK"; continue                  # died before saying who it was
    fi
    [ "$MODE" = try ] && return 1
    waited=$((waited + 1))
    [ "$waited" -ge 100 ] && return 1           # fifty seconds, inside the hook's minute
    sleep 0.5
  done
  echo $$ > "$LOCK/pid"
  OWN_LOCK=1
}
release_lock() { [ "$OWN_LOCK" = 1 ] && rm -rf "$LOCK"; return 0; }

if ! acquire_lock; then
  # Busy and best effort: the running save covers this one. Busy for too long
  # at session end: saving without the lock beats losing the final save.
  [ "$MODE" = try ] && exit 0
fi
trap 'release_lock' EXIT

# The transform, in a JavaScript engine the machine already has. This was jq,
# but jq is Homebrew rather than macOS: a hook or a launchd job started with a
# minimal PATH cannot see it, and would archive nothing while appearing to
# work. osascript is in /usr/bin on every Mac; node carries it elsewhere.
# osascript insists on a .js extension, and appending one to a mktemp name
# would strand the file mktemp actually created — so make a directory.
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
  [ -x "$HERE/helper-build.sh" ] &&
    "$HERE/helper-build.sh" "$HERE/Claude HTML.app" --register --if-stale >/dev/null 2>&1 || true
  [ -f "$HERE/convert.js" ] || return 0
  # The build keeps a cache that only one build at a time may write: one
  # that runs without the lock does without it, and reads everything.
  local nocache=""
  [ "$OWN_LOCK" = 1 ] || nocache=',"cache":false'
  run_js "$HERE/convert.js" \
    "{\"root\":\"$ROOT\",\"out\":\"$OUT\",\"here\":\"$HERE\"$nocache}" >/dev/null 2>&1 || true
}

# A session that fails to archive is recorded, one file per session, so the
# index can show it and a later success can clear exactly its own entry.
ERRDIR="$OUT/.archive-errors"
json_str() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n\t' '  '; }
record_failure() {
  mkdir -p "$ERRDIR"
  printf '{"id":"%s","source":"%s","error":"archiving failed: %s","kind":"archive"}\n' \
    "$(json_str "$1")" "$(json_str "$2")" "$(json_str "${3:-no output}")" \
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
trap 'rm -rf "$ARCHIVE_TMP"; write_status; rebuild_pages; release_lock' EXIT
cat > "$ARCHIVER" <<'ARCHIVEREOF'
function run(argv) {
  var path = argv[0], sid = argv[1], project = argv[2];
  var sourceBytes = Number(argv[3] || 0);
  // The archive this one replaces, and where to keep what lets the next save
  // carry on from this one: both optional, and either may be gone or stale.
  var prevPath = argv[4] || "", statePath = argv[5] || "";

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
      try {
        h.seekToFileOffset(offset);
        var data = h.readDataToEndOfFile, n = Number(data.length);
        var s = $.NSString.alloc.initWithDataEncoding(data, 4);
        if (!s || s.isNil()) return null;
        var text = s.js;
        if (typeof text !== "string") return null;
        return { text: text, cut: n - utf8Length(text.slice(text.lastIndexOf("\n") + 1)) };
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

  // ── text ──
  function utf8Length(t) {
    var n = 0;
    for (var i = 0; i < t.length; i++) {
      var c = t.charCodeAt(i);
      if (c < 0x80) n += 1;
      else if (c < 0x800) n += 2;
      else if (c >= 0xD800 && c <= 0xDBFF && (t.charCodeAt(i + 1) & 0xFC00) === 0xDC00) { n += 4; i++; }
      else n += 3;
    }
    return n;
  }
  function hashText(t) {
    var h = 5381;
    for (var i = 0; i < t.length; i++) h = ((h << 5) + h + t.charCodeAt(i)) | 0;
    return (h >>> 0).toString(36);
  }

  // Long values are kept, but bounded: a pasted file should not make the
  // archive unopenable.
  function cap(s, n) {
    if (typeof s !== "string") return s;
    return s.length > n ? s.slice(0, n) + "\n…[truncated]" : s;
  }

  // The arguments worth keeping per tool. Anything else is dropped, so a new
  // tool with a huge payload cannot bloat the archive silently.
  function toolInput(inp) {
    if (!inp || typeof inp !== "object") return {};
    var out = {}, keep = {
      file_path: 0, command: 0, description: 0, pattern: 0, query: 0,
      url: 0, skill: 0
    };
    Object.keys(keep).forEach(function (k) {
      if (inp[k] != null) out[k] = inp[k];
    });
    ["old_string", "new_string", "content"].forEach(function (k) {
      if (inp[k] != null) out[k] = cap(String(inp[k]), 4000);
    });
    if (inp.prompt != null) out.prompt = cap(String(inp.prompt), 2000);
    return out;
  }

  function textOfResult(c) {
    if (typeof c === "string") return c;
    if (Array.isArray(c)) {
      return c.filter(function (x) { return x && x.type === "text"; })
              .map(function (x) { return x.text || ""; }).join("\n");
    }
    return "";
  }

  // The messages one record holds, empty ones left out. Each depends on its
  // own line alone, which is what lets a save read only what was appended.
  function messagesOf(e, into) {
    if (e.type !== "user" && e.type !== "assistant") return;
    var content = (e.message || {}).content, msgs = [];
    if (e.type === "user") {
      if (typeof content === "string") {
        // A prompt actually typed.
        msgs.push({ role: "user", timestamp: e.timestamp, text: content });
      } else if (Array.isArray(content)) {
        content.forEach(function (b) {
          if (!b || typeof b !== "object") return;
          if (b.type === "text") {
            msgs.push({ role: "user", timestamp: e.timestamp, text: b.text || "" });
          } else if (b.type === "tool_result") {
            msgs.push({
              role: "tool_result", timestamp: e.timestamp,
              text: cap(textOfResult(b.content), 4000)
            });
          }
        });
      }
    } else if (Array.isArray(content)) {
      var body = content.filter(function (b) { return b && b.type === "text"; })
                        .map(function (b) { return b.text || ""; }).join("\n");
      var tools = content.filter(function (b) { return b && b.type === "tool_use"; })
                         .map(function (b) {
                           return { name: b.name, input: toolInput(b.input) };
                         });
      var think = content.filter(function (b) { return b && b.type === "thinking"; })
                         .map(function (b) { return b.thinking || ""; }).join("\n\n");
      var m = { role: "assistant", timestamp: e.timestamp, text: body };
      if (tools.length) m.tools = tools;
      // Only when there is some: most thinking reaches the transcript
      // redacted to an empty string, and an empty field is just weight.
      if (think) m.thinking = cap(think, 6000);
      msgs.push(m);
    }
    msgs.forEach(function (x) {
      if ((x.text && x.text !== "") || (x.tools && x.tools.length) || x.thinking) into.push(x);
    });
  }

  // The same count as convert.js's usageLine, which the build trusts in
  // place of its own once the transcript is gone, so any difference here
  // would show as history changing. A long reply is several records under
  // one message id, each with the usage so far, so the last one wins.
  function usageLine(acc, e) {
    if (e.type !== "assistant" || !e.message || !e.message.usage) return;
    var u = e.message.usage;
    if (!(u.input_tokens || u.output_tokens ||
          u.cache_read_input_tokens || u.cache_creation_input_tokens)) return;
    var mid = e.message.id ? String(e.message.id) : "";
    acc.by[mid ? "m:" + mid : e.uuid ? "u:" + e.uuid : "r:" + (acc.n++)] = {
      mid: mid, hour: String(e.timestamp || "").slice(0, 13),
      model: e.message.model || "unknown",
      t: [u.input_tokens || 0, u.output_tokens || 0,
          u.cache_read_input_tokens || 0, u.cache_creation_input_tokens || 0, 1]
    };
  }

  // The cost, as convert.js's costLine works it out, for the same reason as
  // the tokens: once the transcript is gone the build has only this. The
  // records are running totals per model, written as a session exits, so
  // each becomes what it added since the last, under the hour of the last
  // record that had a time; a total that fell or a new startTime is a new
  // counter. Only this session's own records count — one carried over by a
  // resume or a fork is the other session's — and only the session's own
  // transcript has them: sub-agents spend on its counter. Micro-dollars, so
  // sums stay exact. part: some replies fall outside every counter.
  function costLine(c, e) {
    if (e.timestamp) c.last = String(e.timestamp);
    if (e.type === "assistant" && e.message && e.message.usage &&
        (!e.sessionId || e.sessionId === sid)) {
      var u = e.message.usage, at = Date.parse(e.timestamp);
      if ((u.input_tokens || u.output_tokens || u.cache_read_input_tokens ||
           u.cache_creation_input_tokens) && !isNaN(at)) {
        c.pending[e.message.id ? "m:" + e.message.id : "r:" + (c.n++)] = at;
      }
      return;
    }
    if (e.type !== "cost-state" || e.sessionId !== sid ||
        !e.modelUsage || typeof e.modelUsage !== "object") return;
    c.seen = true;
    var now = {}, start = Number(e.startTime) || 0, prev = c.prev;
    Object.keys(e.modelUsage).forEach(function (m) {
      var v = Math.round(Number((e.modelUsage[m] || {}).costUSD) * 1e6);
      if (v >= 0) now[m] = v;
    });
    var fresh = !prev || prev.start !== start;
    if (!fresh) {
      Object.keys(now).forEach(function (m) { if (now[m] < (prev.c[m] || 0)) fresh = true; });
    }
    Object.keys(c.pending).forEach(function (p) { if (c.pending[p] < start) c.part = true; });
    c.pending = {};
    if (e.hasUnknownModelCost) c.part = true;
    var hour = c.last.slice(0, 13);
    Object.keys(now).forEach(function (m) {
      var d = now[m] - (fresh ? 0 : prev.c[m] || 0);
      if (d <= 0) return;
      if (!/^\d{4}-\d\d-\d\dT\d\d$/.test(hour)) { c.part = true; return; }
      var h = c.cells[hour] = c.cells[hour] || {};
      h[m] = (h[m] || 0) + d;
    });
    if (!fresh) Object.keys(prev.c).forEach(function (m) { if (!(m in now)) now[m] = prev.c[m]; });
    c.prev = { start: start, c: now };
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
  var KEY = "1:" + hashText(String(run));
  var WINDOW = 4096;
  function fingerprint(off) {
    var w = Math.min(WINDOW, off);
    var parts = [bytesAt(path, 0, w), bytesAt(path, Math.max(0, Math.floor(off / 2) - (w >> 1)), w),
                 bytesAt(path, off - w, w)];
    for (var i = 0; i < parts.length; i++) if (parts[i] === null) return null;
    return off + ":" + parts.map(hashText).join(":");
  }
  function newScan() {
    return { off: 0, msgs: 0, started: null, usage: { by: {}, n: 0 },
             cost: { cells: {}, last: "", prev: null, pending: {}, part: false, seen: false, n: 0 } };
  }
  function scanChunk(st, text, messages) {
    text.split("\n").forEach(function (line) {
      if (!line) return;
      var e;
      try { e = JSON.parse(line); } catch (err) { return; }
      if (!e || typeof e !== "object") return;
      if (!st.started && e.timestamp) st.started = e.timestamp;
      messagesOf(e, messages);
      usageLine(st.usage, e);
      costLine(st.cost, e);
    });
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
      prev.format === 3 && prev.sourceBytes === state.sourceBytes &&
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
      String(readText(kids + "/" + f) || "").split("\n").forEach(function (line) {
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
  var usage = {}, replies = [];
  function emit(by, k) {
    var r = by[k];
    if (r.hour.length !== 13) return;
    var d = usage[r.hour] = usage[r.hour] || {};
    var a = d[r.model] = d[r.model] || [0, 0, 0, 0, 0];
    for (var i = 0; i < 5; i++) a[i] += r.t[i];
    var row = [r.mid, r.hour, r.model].concat(r.t.slice(0, 4));
    if (!r.mid) row.push(k);
    replies.push(row);
  }
  Object.keys(mainBy).forEach(function (k) { if (!(k in agentBy)) emit(mainBy, k); });
  var agentFrom = replies.length;
  Object.keys(agentBy).forEach(function (k) { emit(agentBy, k); });

  // As a sixth figure on the usage cell, after the tokens, as the build adds it.
  var cost = st.cost.seen ? st.cost.cells : null;
  var costPart = !!cost && (st.cost.part || Object.keys(st.cost.pending).length > 0);
  if (cost) {
    Object.keys(cost).forEach(function (hour) {
      var d = usage[hour] = usage[hour] || {};
      Object.keys(cost[hour]).forEach(function (m) {
        var a = d[m] = d[m] || [0, 0, 0, 0, 0];
        a[5] = (a[5] || 0) + cost[hour][m];
      });
    });
  }

  var archive = JSON.stringify({
    sourceBytes: sourceBytes,
    // 2: also thinking, usage and replies. 3: usage may carry the cost.
    // Read by the skip check below, which is why it sits near the top.
    format: 3,
    sessionId: sid,
    project: project,
    startedAt: startedAt,
    endedAt: messages.length ? messages[messages.length - 1].timestamp : null,
    messageCount: messages.length,
    promptCount: messages.filter(function (m) { return m.role === "user"; }).length,
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
  return archive;
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

PROJECT_PATH=$(pwd)

# Claude Code names project folders by replacing / with - in the path
PROJECT_FOLDER_NAME=$(echo "$PROJECT_PATH" | tr '/' '-')
SOURCE_DIR="$HOME/.claude/projects/$PROJECT_FOLDER_NAME"

# No directory of that name is not the end of it: a renamed project has no
# launch directory under the new name, and its sessions are found by cwd
# below instead. Bail only when nothing at all turns up.

# Output directory
CONV_DIR="$PROJECT_PATH/.claude/.claude-conversations"
mkdir -p "$CONV_DIR"

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

for jsonl in "${CANDIDATES[@]+"${CANDIDATES[@]}"}"; do
  [[ -f "$jsonl" ]] || continue

  SESSION_ID=$(basename "$jsonl" .jsonl)
  OUTPUT_FILE="$CONV_DIR/${SESSION_ID}.json"

  # Skip only if the archive was made from exactly this much transcript.
  # Transcripts only ever grow, so their size says whether anything was added.
  # A timestamp cannot: a reply appended while the archive is being written
  # leaves an archive newer than the transcript that now holds more, and the
  # save at session end would then keep an archive missing the last reply.
  # The size is taken before reading, so a file that grows mid-read is only
  # ever archived again, never skipped.
  # An archive in an older format is written again once, while its
  # transcript is still here to supply what that format did not keep.
  SIZE=$(size_of "$jsonl")
  if [[ -f "$OUTPUT_FILE" ]] && HEAD="$(head -c 200 "$OUTPUT_FILE")" &&
     [[ "$HEAD" == *'"format":3,'* ]] &&
     [[ "$(printf '%s' "$HEAD" |
       sed -n 's/.*"sourceBytes":\([0-9]*\).*/\1/p')" == "$SIZE" ]]; then
    continue
  fi

  # Written beside the archive and moved over it only once complete: a failed
  # run must leave the last good archive alone, since the transcript it came
  # from may already be gone. Not ending in .json keeps the build from reading
  # a half-written one.
  # Complete means it ends as the archiver's object ends. That rules out the
  # empty result of a transcript it cannot read, and the cut-off one a full
  # disk leaves, which osascript does not report as a failure.
  PARTIAL="$CONV_DIR/.${SESSION_ID}.json.partial"
  # What lets the next save read only what this one did not: kept with the
  # build's cache, which only a save holding the lock may write.
  STATE=""
  [ "$OWN_LOCK" = 1 ] && STATE="$OUT/.cache/$SESSION_ID.archive"
  if run_js "$ARCHIVER" "$jsonl" "$SESSION_ID" "$PROJECT_PATH" "$SIZE" "$OUTPUT_FILE" "$STATE" \
       > "$PARTIAL" 2>"$ARCHIVE_TMP/err" && [[ "$(tail -c 2 "$PARTIAL")" == *"}" ]] &&
     mv -f "$PARTIAL" "$OUTPUT_FILE"; then
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
if [ -f "$ARCHIVES_LIST" ] && compgen -G "$CONV_DIR/*.json" >/dev/null &&
   ! grep -qxF "$PROJECT_PATH" "$ARCHIVES_LIST"; then
  printf '%s\n' "$PROJECT_PATH" >> "$ARCHIVES_LIST" 2>/dev/null || true
fi

# Hook stdout lands in the transcript, so say one line, not one per session.
[ "$SAVED" -gt 0 ] && echo "Archived $SAVED session(s) to $CONV_DIR"

exit 0
