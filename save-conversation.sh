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
# Thinking blocks are still skipped: large, and private by intent.

set -euo pipefail

# The JavaScript this script carries runs through whichever engine the machine
# has: osascript on macOS, where nothing needs installing, node elsewhere —
# and a machine running Claude Code has node. The scripts themselves are the
# same bytes under either.
run_js() {
  if [ -z "${CLAUDE_HTML_FORCE_NODE:-}" ] && command -v osascript >/dev/null 2>&1; then osascript -l JavaScript "$@"
  else node "$@"; fi
}
# BSD stat and GNU stat disagree about everything, including how to ask for
# a size in bytes. GNU goes first: BSD's -c genuinely fails, but GNU's -f
# means "filesystem status" and succeeds with the wrong answer entirely.
size_of() { stat -c %s "$1" 2>/dev/null || stat -f %z "$1"; }

# Claude Code hands every hook a JSON note on stdin naming the session and its
# transcript. With it, this session's transcript is known exactly; without it —
# run by hand — it has to be searched for, which means reading every transcript.
# Read before anything else: the detached copy below gets no stdin of its own.
TRANSCRIPT="${CLAUDE_HTML_TRANSCRIPT:-}"
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
# --try is best effort: if another save is running it gives up, because the
# next reply's save will carry this one's changes. Without it, wait — at session
# end this is the save that must not be lost.
MODE=wait
[ "${1:-}" = "--try" ] && MODE=try

# Only archive work under the projects root. Set CLAUDE_HTML_ROOT to point
# somewhere other than ~/Sites.
_env_root="${CLAUDE_HTML_ROOT:-}"
CONF="${CLAUDE_HTML_CONF:-$HOME/.claude/claude-html.conf}"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"
ROOT="${_env_root:-${CLAUDE_HTML_ROOT:-$HOME/Sites}}"
ROOT="${ROOT/#\~/$HOME}"
if [[ "$(pwd)" != "$ROOT" && "$(pwd)" != "$ROOT"/* ]]; then
  exit 0
fi
OUT="${CLAUDE_HTML_OUT:-$ROOT/claude-html}"
OUT="${OUT/#\~/$HOME}"

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
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rebuild_pages() {
  [ -x "$HERE/helper-build.sh" ] &&
    "$HERE/helper-build.sh" "$HERE/Claude HTML.app" --register --if-stale >/dev/null 2>&1 || true
  [ -f "$HERE/convert.js" ] || return 0
  run_js "$HERE/convert.js" \
    "{\"root\":\"$ROOT\",\"out\":\"$OUT\",\"here\":\"$HERE\"}" >/dev/null 2>&1 || true
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

  var text;
  if (typeof $ !== "undefined") {
    var raw = $.NSString.stringWithContentsOfFileEncodingError(path, 4, null);
    if (!raw) return "";
    text = $.CFMakeCollectable(raw).js;
  } else {
    try { text = require("fs").readFileSync(path, "utf8"); } catch (e) { return ""; }
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

  var messages = [], startedAt = null;
  text.split("\n").forEach(function (line) {
    if (!line.trim()) return;
    var e;
    try { e = JSON.parse(line); } catch (err) { return; }
    if (!startedAt && e.timestamp) startedAt = e.timestamp;
    if (e.type !== "user" && e.type !== "assistant") return;

    var content = (e.message || {}).content;
    if (e.type === "user") {
      if (typeof content === "string") {
        // A prompt actually typed.
        messages.push({ role: "user", timestamp: e.timestamp, text: content });
      } else if (Array.isArray(content)) {
        content.forEach(function (b) {
          if (!b || typeof b !== "object") return;
          if (b.type === "text") {
            messages.push({ role: "user", timestamp: e.timestamp, text: b.text || "" });
          } else if (b.type === "tool_result") {
            messages.push({
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
      var m = { role: "assistant", timestamp: e.timestamp, text: body };
      if (tools.length) m.tools = tools;
      messages.push(m);
    }
  });

  messages = messages.filter(function (m) {
    return (m.text && m.text !== "") || (m.tools && m.tools.length);
  });

  return JSON.stringify({
    sourceBytes: sourceBytes,
    sessionId: sid,
    project: project,
    startedAt: startedAt,
    endedAt: messages.length ? messages[messages.length - 1].timestamp : null,
    messageCount: messages.length,
    promptCount: messages.filter(function (m) { return m.role === "user"; }).length,
    messages: messages
  });
}
// osascript calls run() by itself; node has to be asked.
if (typeof $ === "undefined" && typeof require !== "undefined" &&
    typeof module !== "undefined" && require.main === module) {
  process.stdout.write(run(process.argv.slice(2)) + "\n");  // osascript ends its output with one
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
  SIZE=$(size_of "$jsonl")
  if [[ -f "$OUTPUT_FILE" ]] && [[ "$(head -c 200 "$OUTPUT_FILE" |
       sed -n 's/.*"sourceBytes":\([0-9]*\).*/\1/p')" == "$SIZE" ]]; then
    continue
  fi

  # An empty result counts as a failure too: the archiver returns nothing for a
  # transcript it cannot read, and an empty archive written here would be newer
  # than its source and so never retried.
  if run_js "$ARCHIVER" "$jsonl" "$SESSION_ID" "$PROJECT_PATH" "$SIZE" \
       > "$OUTPUT_FILE" 2>"$ARCHIVE_TMP/err" && [ -s "$OUTPUT_FILE" ]; then
    rm -f "$ERRDIR/$SESSION_ID.json"
  else
    rm -f "$OUTPUT_FILE"
    record_failure "$SESSION_ID" "$jsonl" "$(head -c 300 "$ARCHIVE_TMP/err" 2>/dev/null || true)"
    continue
  fi

  SAVED=$((SAVED + 1))
done

# Hook stdout lands in the transcript, so say one line, not one per session.
[ "$SAVED" -gt 0 ] && echo "Archived $SAVED session(s) to $CONV_DIR"

exit 0
