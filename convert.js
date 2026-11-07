// Build every session page, the index, and the search index.
//
// One file, two runtimes. On macOS it runs through /usr/bin/osascript, so a
// machine needs nothing but the system; anywhere else it runs under node,
// which a machine running Claude Code already has. Everything below the
// platform block is plain JavaScript, identical in both.
//
//   osascript -l JavaScript convert.js '{"root":"…","out":"…","force":false}'
//   node convert.js '{"root":"…","out":"…","force":false}'
//
// This file does the data work only — reading transcripts, repairing archives
// that mislabelled their roles, pairing tool calls with their output — and
// hands the result to the browser as JSON. Nothing here emits markup.

function run(argv) {
  "use strict";

  var opt = JSON.parse(argv[0] || "{}");

  // ── the platform ────────────────────────────────────────────────────
  // Everything either runtime is asked for, in one block: sixteen functions,
  // whether the machine is a mac, and the name of the system, which decides
  // what kind of launcher a double-click can run. Both are the machine's, not
  // the engine's: node on a Mac must write what osascript writes there.
  var JXA = typeof $ !== "undefined";
  var MAC, env, defaultHome, read, write, list, mtime, sig, isDir, exists, chmodx, remove;
  var findArchiveDirs, readFrom, bytesAt, digest, statAll;
  var SYSTEM = JXA ? "darwin" : process.platform;

  if (JXA) {
    MAC = true;
    var fm = $.NSFileManager.defaultManager;
    env = function (name) {
      var v = $.NSProcessInfo.processInfo.environment.objectForKey(name);
      try { return v && v.js ? v.js : null; } catch (e) { return null; }
    };
    defaultHome = function () { return $.NSHomeDirectory().js; };
    read = function (path) {
      // A missing file gives an ObjC nil that is truthy in JavaScript and
      // whose .js is undefined, so check first and guard the unwrap.
      if (!fm.fileExistsAtPath(path)) return null;
      try {
        var s = $.NSString.stringWithContentsOfFileEncodingError(path, 4, null);
        var text = s ? $.CFMakeCollectable(s).js : null;
        return typeof text === "string" ? text : null;
      } catch (e) { return null; }
    };
    write = function (path, text) {
      var dir = $.NSString.alloc.initWithUTF8String(path).stringByDeletingLastPathComponent;
      fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(dir, true, $(), null);
      return $.NSString.alloc.initWithUTF8String(text)
        .writeToFileAtomicallyEncodingError(path, true, 4, null);
    };
    list = function (dir) {
      if (!fm.fileExistsAtPath(dir)) return [];
      var items = fm.contentsOfDirectoryAtPathError(dir, null);
      if (!items) return [];
      return $.CFMakeCollectable(items).js.map(function (x) { return x.js; }).sort();
    };
    // Every transcript, sub-agent and .meta.json under a folder, stat'ed in
    // one go. Through the bridge each costs over a millisecond, and a save
    // stats nine hundred of them; find and stat do them all in a fifth of a
    // second. sig and mtime answer from it, and ask the bridge for anything
    // it does not hold. The time is cut to the millisecond from the digits,
    // as the bridge cuts it, so both give the same answer.
    var statMemo = {};
    statAll = function (root) {
      var sh = Application.currentApplication();
      sh.includeStandardAdditions = true;
      var out = "";
      try {
        // -H: a projects folder that is a link to one is still searched.
        out = sh.doShellScript("/usr/bin/find -H '" + String(root).replace(/'/g, "'\\''") + "' -maxdepth 4" +
          " \\( -name '*.jsonl' -o -name '*.meta.json' \\) -type f" +
          " -exec /usr/bin/stat -f '%z %Fm %N' {} + 2>/dev/null; true", { alteringLineEndings: false });
      } catch (e) { out = ""; }
      out.split("\n").forEach(function (l) {
        var m = /^(\d+) (\d+)(?:\.(\d+))? (\/.*)$/.exec(l);
        if (m) statMemo[m[4]] = [m[1], Number(m[2]) * 1000 + Number(((m[3] || "") + "000").slice(0, 3))];
      });
    };
    // A missing file's attributes are a nil, which is truthy here: ask first.
    mtime = function (path) {
      if (statMemo[path]) return Math.round(statMemo[path][1] / 1000);
      if (!fm.fileExistsAtPath(path)) return 0;
      var at = fm.attributesOfItemAtPathError(path, null);
      if (!at) return 0;
      var d = $.CFMakeCollectable(at).js.NSFileModificationDate;
      return d ? Math.round(d.js.getTime() / 1000) : 0;
    };
    sig = function (path) {
      if (statMemo[path]) return statMemo[path][0] + ":" + statMemo[path][1];
      if (!fm.fileExistsAtPath(path)) return "";
      var at = fm.attributesOfItemAtPathError(path, null);
      if (!at) return "";
      var a = $.CFMakeCollectable(at).js;
      var d = a.NSFileModificationDate;
      return (a.NSFileSize ? a.NSFileSize.js : 0) + ":" + (d ? d.js.getTime() : 0);
    };
    isDir = function (path) {
      var ref = Ref();
      return fm.fileExistsAtPathIsDirectory(path, ref) && ref[0];
    };
    exists = function (path) { return !!fm.fileExistsAtPath(path); };
    chmodx = function (path) {
      fm.setAttributesOfItemAtPathError({ NSFilePosixPermissions: 0o755 }, path, null);
    };
    remove = function (path) { fm.removeItemAtPathError(path, null); };
    // A transcript from a byte offset to its end: what was appended since the
    // last build. Also where the last whole line ends, in bytes, which is
    // where the next build will start. Text that is not UTF-8 is refused, as
    // read refuses it, so the two ways of reading a file always agree.
    readFrom = function (path, offset) {
      var h = $.NSFileHandle.fileHandleForReadingAtPath(path);
      if (!h || h.isNil()) return null;
      try {
        h.seekToFileOffset(offset);
        var data = h.readDataToEndOfFile, n = Number(data.length);
        var s = $.NSString.alloc.initWithDataEncoding(data, 4);
        if (!s || s.isNil()) return null;
        var text = s.js;
        if (typeof text !== "string") return null;
        return { text: text, bytes: n, cut: n - utf8Length(text.slice(text.lastIndexOf("\n") + 1)) };
      } catch (e) { return null; } finally { h.closeFile; }
    };
    // Exactly len bytes from start, as base64, or null when the file is
    // shorter: a fingerprint of what a cache was made from.
    bytesAt = function (path, start, len) {
      var h = $.NSFileHandle.fileHandleForReadingAtPath(path);
      if (!h || h.isNil()) return null;
      try {
        h.seekToFileOffset(start);
        var data = h.readDataOfLength(len);
        if (Number(data.length) !== len) return null;
        return data.base64EncodedStringWithOptions(0).js;
      } catch (e) { return null; } finally { h.closeFile; }
    };
    // The md5 of a file, by the system's own md5: hashing a long string in
    // JavaScript here takes a second where node takes a twentieth of one.
    digest = function (path) {
      if (!fm.fileExistsAtPath(path)) return "";
      var sh = Application.currentApplication();
      sh.includeStandardAdditions = true;
      try {
        return sh.doShellScript("/sbin/md5 -q '" + String(path).replace(/'/g, "'\\''") + "'").trim();
      } catch (e) { return ""; }
    };
    // Every folder within depth levels of root holding an archive folder.
    // One find, not a walk through the bridge: listing each directory from
    // here costs most of a millisecond, and the same walk took thirty seconds
    // over a real projects folder where find takes a fraction of one.
    findArchiveDirs = function (root, depth, skipNames, skipPath) {
      var sh = Application.currentApplication();
      sh.includeStandardAdditions = true;
      var q = function (t) { return "'" + String(t).replace(/'/g, "'\\''") + "'"; };
      // Run from inside root, so every pattern sees "./…" and a root that
      // itself sits under a .claude folder, or has glob characters in its
      // name, cannot match them.
      var prune = skipNames.map(function (n) { return "-name " + q(n); })
        .concat(["\\( -name '.*' ! -name .claude ! -name .claude-conversations \\)",
                 "\\( -path '*/.claude/*' ! -name .claude-conversations \\)"]);
      if (skipPath.indexOf(root + "/") === 0) prune.push("-path " + q("." + skipPath.slice(root.length)));
      var out = "";
      try {
        out = sh.doShellScript("cd " + q(root) + " && /usr/bin/find . -mindepth 1 -maxdepth " + (depth + 2) +
          " \\( " + prune.join(" -o ") + " \\) -prune" +
          " -o -type d -path '*/.claude/.claude-conversations' -print -prune 2>/dev/null; true",
          { alteringLineEndings: false });
      } catch (e) { out = ""; }
      return out.split("\n").filter(Boolean).map(function (p) {
        return (root + p.slice(1)).slice(0, -"/.claude/.claude-conversations".length);
      }).sort();
    };
  } else {
    // The engine is not the machine: node on a mac still has the helper,
    // and saying otherwise hides delete and open buttons that would work.
    MAC = process.platform === "darwin";
    var nfs = require("fs"), npath = require("path");
    var stat = function (p) { try { return nfs.statSync(p); } catch (e) { return null; } };
    env = function (name) { return process.env[name] || null; };
    defaultHome = function () { return require("os").homedir(); };
    read = function (path) {
      try { return nfs.readFileSync(path, "utf8"); } catch (e) { return null; }
    };
    write = function (path, text) {
      // Atomic for the same reason the JXA side is: a page being read while
      // half written is a broken page, and saves can overlap a build.
      try {
        nfs.mkdirSync(npath.dirname(path), { recursive: true });
        var tmp = path + ".tmp" + process.pid;
        nfs.writeFileSync(tmp, text, "utf8");
        nfs.renameSync(tmp, path);
        return true;
      } catch (e) { return false; }
    };
    list = function (dir) {
      try { return nfs.readdirSync(dir).sort(); } catch (e) { return []; }
    };
    mtime = function (path) {
      var st = stat(path);
      return st ? Math.round(st.mtimeMs / 1000) : 0;
    };
    sig = function (path) {
      // The same shape the JXA side produces: bytes, then milliseconds. Date
      // truncates to the millisecond there, so truncate here too, or the two
      // runtimes would call the same file two different files.
      var st = stat(path);
      return st ? st.size + ":" + Math.floor(st.mtimeMs) : "";
    };
    isDir = function (path) {
      var st = stat(path);
      return !!st && st.isDirectory();
    };
    exists = function (path) { return !!stat(path); };
    chmodx = function (path) {
      try { nfs.chmodSync(path, 0o755); } catch (e) {}
    };
    remove = function (path) {
      try { nfs.rmSync(path, { recursive: true, force: true }); } catch (e) {}
    };
    // stat costs nothing here, so there is nothing to gather up front.
    statAll = function () {};
    readFrom = function (path, offset) {
      var fd;
      try { fd = nfs.openSync(path, "r"); } catch (e) { return null; }
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
        // Found in the bytes, not the text: a character cut off by a write
        // in progress decodes to more bytes than it was.
        return { text: all.toString("utf8"), bytes: total, cut: all.lastIndexOf(10) + 1 };
      } catch (e) { return null; } finally { try { nfs.closeSync(fd); } catch (e) {} }
    };
    bytesAt = function (path, start, len) {
      var fd;
      try { fd = nfs.openSync(path, "r"); } catch (e) { return null; }
      try {
        var buf = Buffer.alloc(len);
        var got = len ? nfs.readSync(fd, buf, 0, len, start) : 0;
        return got === len ? buf.toString("base64") : null;
      } catch (e) { return null; } finally { try { nfs.closeSync(fd); } catch (e) {} }
    };
    digest = function (path) {
      try {
        return require("crypto").createHash("md5").update(nfs.readFileSync(path)).digest("hex");
      } catch (e) { return ""; }
    };
    // The same answer as the find above, from directory entries that already
    // say which are folders, so nothing is stat'ed twice.
    findArchiveDirs = function (root, depth, skipNames, skipPath) {
      var out = [];
      var walk = function (dir, d) {
        var ents;
        try { ents = nfs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return; }
        ents.forEach(function (e) {
          if (!e.isDirectory()) return;
          var p = dir + "/" + e.name;
          if (e.name === ".claude") {
            if (isDir(p + "/.claude-conversations")) out.push(dir);
            return;
          }
          if (d >= depth || e.name.charAt(0) === "." || skipNames.indexOf(e.name) > -1 ||
              p === skipPath) return;
          walk(p, d + 1);
        });
      };
      walk(root, 0);
      return out.sort();
    };
  }

  // NSHomeDirectory reads the user record and ignores $HOME, so on its own it
  // would look in the real home even when the environment says otherwise —
  // wrong under a test harness, a redirected HOME, or another user's launchd.
  var HOME = opt.home || env("HOME") || defaultHome();
  var ROOT = opt.root || (HOME + "/Sites");
  var OUT = opt.out || (ROOT + "/claude-html");
  var PROJECTS = opt.projects || (HOME + "/.claude/projects");
  var HERE = opt.here || (HOME + "/.claude/scripts");
  var FORCE = !!opt.force;
  // Anthropic's weekly allowance resets on a day and hour fixed per account,
  // so the dashboard's weeks are anchored to whatever this says. Calendar
  // weeks unless someone sets their own.
  var WEEK_RESET = opt.weekReset || env("CLAUDE_HTML_WEEK_RESET") || "mon 00:00";
  // The dashboard says its weeks match the plan's only when someone said so:
  // the calendar default is a guess, not the plan.
  var WEEK_RESET_SET = !!(opt.weekReset || env("CLAUDE_HTML_WEEK_RESET"));
  var ONLY = opt.only || "";
  // Deleting, opening and resuming from a page are claude-html:// links,
  // which only work where something receives them: the helper app on macOS,
  // and on Linux the desktop handler install.sh registers. Without one the
  // pages leave those controls out rather than offer dead ones.
  // CLAUDE_HTML_UNAME is platform.sh's: what the tests set to fake a Linux.
  var OS = opt.os || ({ Linux: "linux", Darwin: "darwin" })[env("CLAUDE_HTML_UNAME")] || SYSTEM;
  var ACTIONS = typeof opt.actions === "boolean" ? opt.actions
    : OS === "darwin" ? true
    : exists((env("XDG_DATA_HOME") || HOME + "/.local/share") +
             "/applications/claude-html-handler.desktop");
  // The documentation promises this variable, and an export kept outside
  // Downloads and the projects folder is otherwise never found.
  var EXPORT = opt.exportPath || env("CLAUDE_HTML_EXPORT") || "";

  // Every id this program turns into a file name. An id is also a path
  // component, so one from outside — a claude.ai export is anyone's file in
  // Downloads — is only trusted once it has this shape.
  var SESSION_ID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

  // ── text ────────────────────────────────────────────────────────────
  function cap(s, n) {
    s = s == null ? "" : String(s);
    // Count code points, not UTF-16 units: Python does, and slicing by units
    // can cut an emoji in half and leave a lone surrogate behind. A string no
    // longer than n units has no more than n code points. A longer one is
    // counted without being split into an array of characters, which under
    // osascript cost a second for every few megabytes of tool output: the
    // pairs are found by the regex engine, and only the n kept are walked.
    if (s.length <= n) return s;
    var pairs = s.match(/[\uD800-\uDBFF][\uDC00-\uDFFF]/g);
    var total = s.length - (pairs ? pairs.length : 0);
    if (total <= n) return s;
    var at = 0;
    for (var k = 0; k < n; k++) {
      var c = s.charCodeAt(at);
      at += c >= 0xD800 && c <= 0xDBFF && (s.charCodeAt(at + 1) & 0xFC00) === 0xDC00 ? 2 : 1;
    }
    return s.slice(0, at) + "\n…[truncated, " + (total - n) + " more characters]";
  }

  // Bytes the text takes in UTF-8. Only ever asked of the end of a read,
  // after its last line break: a loop over characters is slow under osascript.
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

  // Injected by the harness, not typed by anyone.
  var SYSTEM_BLOCK = /<system-reminder>[\s\S]*?<\/system-reminder>/g;
  var COMMAND_BLOCK = /<command-(name|message|args)>[\s\S]*?<\/command-\1>/g;

  function cleanUserText(text) {
    return String(text == null ? "" : text)
      .replace(SYSTEM_BLOCK, "").replace(COMMAND_BLOCK, "").trim();
  }

  var HARNESS = ["Launching skill:", "Base directory for this skill:",
    "Caveat: The messages below", "[Request interrupted",
    "This session is being continued from a previous",
    "API Error", "safeguards flagged this message"];

  function looksLikeHarness(text) {
    var head = String(text == null ? "" : text).replace(/^\s+/, "").slice(0, 200);
    return HARNESS.some(function (p) { return head.indexOf(p) > -1; });
  }

  function blocksToText(content) {
    if (typeof content === "string") return content;
    if (!Array.isArray(content)) return "";
    return content.map(function (b) {
      if (!b || typeof b !== "object") return "";
      if (b.type === "text") return b.text || "";
      if (b.type === "image") return "[image]";
      return "";
    }).filter(Boolean).join("\n");
  }

  // ── project naming ──────────────────────────────────────────────────
  function basename(p) {
    var parts = String(p).replace(/\/+$/, "").split("/");
    return parts[parts.length - 1] || String(p);
  }

  function projectFromCwd(cwd) {
    if (!cwd) return "?";
    var c = String(cwd).replace(/\/+$/, "");
    if (c === HOME.replace(/\/+$/, "")) return "~";
    if (c === ROOT.replace(/\/+$/, "")) return basename(ROOT);
    return basename(c);
  }

  // Claude encodes "/" as "-", which cannot be undone when the name itself
  // contains a hyphen. Only a fallback: the cwd inside the file is truth.
  function cwdFromDirname(name) {
    return "/" + String(name).replace(/^-+|-+$/g, "").replace(/-/g, "/");
  }

  // ── transcripts ─────────────────────────────────────────────────────
  // A line that is JSON but not an object — a bare null, a number — is not a
  // record, and every reader below may take e.type for granted.
  function eachLine(text, fn) {
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i]) continue;
      var e;
      try { e = JSON.parse(lines[i]); } catch (err) { continue; }
      if (!e || typeof e !== "object") continue;
      if (fn(e, i) === false) return;
    }
  }

  // Where the session ran and what Claude Code titled it, from the first 401
  // lines: both are stated early, and a long transcript is not read for them.
  var PEEK_LINES = 400;
  function peekLine(p, e) {
    p.cwd = p.cwd || e.cwd || null;
    p.title = p.title || e.aiTitle || null;
  }

  function peek(text) {
    var p = { cwd: null, title: null };
    eachLine(text, function (e, i) {
      if (i > PEEK_LINES || (p.cwd && p.title)) return false;
      peekLine(p, e);
    });
    return p;
  }

  // Tokens, per hour and model, from a transcript's own records. The hour,
  // not the day, because a usage week can start at 9am and because these
  // timestamps are UTC — the page converts them to local time itself. A long reply
  // is written as several records sharing one message id, each carrying the
  // usage so far — so the last record per id wins, or one reply would be
  // counted several times. Columns: input, output, cache read, cache write.
  // One accumulator serves a session and all its sub-agents, so a reply that
  // turns up in both is still one reply.
  function newReplies() { return { by: {}, n: 0 }; }

  // One record's part in it. Every reader of a transcript goes a line at a
  // time, so a build can carry on from where the last one stopped.
  function usageLine(acc, e) {
    if (e.type !== "assistant" || !e.message || !e.message.usage) return;
    var u = e.message.usage;
    // Synthetic records (model "<synthetic>") carry no tokens; all zeros
    // would only add noise rows to the dashboard.
    if (!(u.input_tokens || u.output_tokens ||
          u.cache_read_input_tokens || u.cache_creation_input_tokens)) return;
    var mid = e.message.id ? String(e.message.id) : "";
    acc.by[mid ? "m:" + mid : e.uuid ? "u:" + e.uuid : "r:" + (acc.n++)] = {
      mid: mid,
      hour: String(e.timestamp || "").slice(0, 13),   // 2026-10-21T14, UTC
      model: e.message.model || "unknown",
      // input, output, cache read, cache write, and the reply itself — one
      // per message id, so "tokens per reply" means what it says.
      t: [u.input_tokens || 0, u.output_tokens || 0,
          u.cache_read_input_tokens || 0, u.cache_creation_input_tokens || 0, 1]
    };
  }

  // A sub-agent's replies, as the session's accumulator would take them in:
  // each key once, where it first appeared, holding its last record. A reply
  // with neither a message id nor a uuid is numbered by the accumulator, so
  // its key is left for replay to give it, in the same order as reading would.
  function usageOps(acc) {
    return Object.keys(acc.by).map(function (k) {
      return [k.indexOf("r:") === 0 ? null : k, acc.by[k]];
    });
  }
  function replay(acc, ops) {
    ops.forEach(function (o) { acc.by[o[0] === null ? "r:" + (acc.n++) : o[0]] = o[1]; });
  }

  // What the session cost, from Claude Code's own "cost-state" records: the
  // dollars it worked out at API list prices, per model. Only recent versions
  // write them, and only as a running total for the whole session — written
  // when a session exits, with no timestamp — so each one is turned into the
  // amount added since the one before, filed under the hour of the last
  // record that had a time. A total that fell, or a new startTime, is a new
  // counter, which starts again from nothing. Sub-agents spend on the
  // session's counter, so only the session's own transcript is read, and a
  // record whose sessionId is another session's is a copy carried over by a
  // resume or a fork: that session counts it, this one must not.
  // Kept in micro-dollars, whole numbers, so adding them up never drifts.
  // "part" says some of the session's replies fall outside every counter —
  // before the first began, or after the last was written — so the figure is
  // a floor, not the whole.
  //
  // Read a line at a time into a state that a later build carries on from:
  // the last time seen, the previous snapshot and its startTime, the replies
  // since it, all plain data, so it survives being kept between saves.
  function newCost() {
    return { cells: {}, last: "", prev: null, pending: {}, part: false, seen: false, n: 0 };
  }

  function costLine(c, e, sid) {
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
    Object.keys(c.pending).forEach(function (k) { if (c.pending[k] < start) c.part = true; });
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
    // A model missing from this record has not been taken back.
    if (!fresh) Object.keys(prev.c).forEach(function (m) { if (!(m in now)) now[m] = prev.c[m]; });
    c.prev = { start: start, c: now };
  }

  function costOf(c) {
    if (!c.seen) return null;
    return { cells: c.cells, part: c.part || Object.keys(c.pending).length > 0 };
  }

  // Cost goes in as a sixth figure on the hour and model it landed on. A cell
  // with no sixth figure is one whose cost is not known, which is not the same
  // as a cost of nothing.
  function addCost(usage, cost) {
    Object.keys(cost.cells).forEach(function (hour) {
      var d = usage[hour] = usage[hour] || {};
      Object.keys(cost.cells[hour]).forEach(function (m) {
        var a = d[m] = d[m] || [0, 0, 0, 0, 0];
        a[5] = (a[5] || 0) + cost.cells[hour][m];
      });
    });
    return usage;
  }

  function countedReplies(acc) {
    return Object.keys(acc.by).map(function (k) { return acc.by[k]; })
      .filter(function (r) { return r.hour.length === 13; });
  }

  function usageOf(acc) {
    var hours = {};
    countedReplies(acc).forEach(function (r) {
      var d = hours[r.hour] = hours[r.hour] || {};
      var a = d[r.model] = d[r.model] || [0, 0, 0, 0, 0];
      for (var i = 0; i < r.t.length; i++) a[i] += r.t[i];
    });
    return hours;
  }

  // A resumed or forked session starts with a copy of the records it came
  // from, message ids and usage included, so the dashboard has to recognise a
  // reply it has already counted in another session. Message ids are kept as
  // fixed-width 53-bit hashes: a third of their length, and a collision among
  // a hundred thousand replies is a one-in-a-million event.
  var KEY_WIDTH = 11;
  function replyKey(id) {
    var h1 = 0xdeadbeef, h2 = 0x41c6ce57;
    for (var i = 0; i < id.length; i++) {
      var c = id.charCodeAt(i);
      h1 = Math.imul(h1 ^ c, 2654435761);
      h2 = Math.imul(h2 ^ c, 1597334677);
    }
    h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
    h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
    var s = (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(36);
    while (s.length < KEY_WIDTH) s = "0" + s;
    return s;
  }

  function eachKey(keys, fn) {
    keys = String(keys || "");
    for (var i = 0; i + KEY_WIDTH <= keys.length; i += KEY_WIDTH) fn(keys.substr(i, KEY_WIDTH));
  }

  function subUsage(into, r) {
    var a = into[r[0]] && into[r[0]][r[1]];
    // Only ever take back what was put in: a hash that collided must not
    // drive a bucket below zero.
    if (!a) return;
    for (var i = 0; i < 5; i++) if ((a[i] || 0) < (r[i + 2] || 0)) return;
    for (var j = 0; j < 5; j++) a[j] -= r[j + 2] || 0;
    // Cost is never per reply, so a copy takes none back — and a cell that
    // still holds some is kept, empty of tokens or not.
    if (!(a[0] || a[1] || a[2] || a[3] || a[4] || a.length > 5)) delete into[r[0]][r[1]];
    if (!Object.keys(into[r[0]]).length) delete into[r[0]];
  }

  // Usage read back from an archive, which is a file anyone can edit: only
  // the shape the dashboard adds up is let through.
  function cleanUsage(u) {
    var out = {};
    if (!u || typeof u !== "object") return out;
    Object.keys(u).forEach(function (slot) {
      if (!/^\d{4}-\d\d-\d\dT\d\d$/.test(slot) || !u[slot] || typeof u[slot] !== "object") return;
      Object.keys(u[slot]).forEach(function (m) {
        var a = u[slot][m];
        if (!Array.isArray(a)) return;
        var row = [0, 0, 0, 0, 0];
        for (var i = 0; i < 5; i++) row[i] = Number(a[i]) > 0 ? Number(a[i]) : 0;
        // The cost, when there is one; five figures is an archive from
        // before cost was kept, and says nothing about it.
        if (a.length > 5 && Number(a[5]) >= 0) row[5] = Math.round(Number(a[5]));
        (out[slot] = out[slot] || {})[m] = row;
      });
    });
    return out;
  }

  function addUsage(into, from) {
    Object.keys(from || {}).forEach(function (slot) {
      var d = into[slot] = into[slot] || {};
      Object.keys(from[slot]).forEach(function (m) {
        var a = d[m] = d[m] || [0, 0, 0, 0, 0];
        for (var i = 0; i < from[slot][m].length; i++) a[i] = (a[i] || 0) + from[slot][m][i];
      });
    });
  }

  // The messages one record holds. Each depends on its own line alone, which
  // is what lets a build parse only what was appended.
  function messagesOf(e) {
    var msgs = [];
    var t = e.type, ts = e.timestamp, side = !!e.isSidechain;
    var content = (e.message || {}).content;
    if (t === "user") {
      if (e.isMeta) return msgs;            // harness context, not a turn
      if (typeof content === "string") {
        var text1 = cleanUserText(content);
        if (text1) msgs.push({ role: "user", timestamp: ts, side: side, text: text1 });
      } else if (Array.isArray(content)) {
        content.forEach(function (b) {
          if (!b || typeof b !== "object") return;
          if (b.type === "text") {
            var tx = cleanUserText(b.text);
            if (tx) msgs.push({ role: "user", timestamp: ts, side: side, text: tx });
          } else if (b.type === "image") {
            msgs.push({ role: "user", timestamp: ts, side: side, text: "[image]" });
          } else if (b.type === "tool_result") {
            msgs.push({ role: "tool_result", timestamp: ts, side: side,
                        text: cap(blocksToText(b.content), 6000) });
          }
        });
      }
    } else if (t === "assistant" && Array.isArray(content)) {
      var text2 = content.filter(function (b) { return b && b.type === "text"; })
                         .map(function (b) { return b.text || ""; }).join("\n");
      var think = content.filter(function (b) { return b && b.type === "thinking"; })
                         .map(function (b) { return b.thinking || ""; }).join("\n\n");
      var tools = content.filter(function (b) { return b && b.type === "tool_use"; })
                         .map(function (b) {
                           return { id: b.id, name: b.name, input: b.input || {} };
                         });
      if (text2 || tools.length || think) {
        msgs.push({ role: "assistant", timestamp: ts, side: side,
                    text: text2, thinking: think, tools: tools });
      }
    }
    return msgs;
  }

  function fromJsonl(text) {
    var msgs = [];
    eachLine(text, function (e) {
      messagesOf(e).forEach(function (m) { msgs.push(m); });
    });
    return msgs;
  }

  // ── archives ────────────────────────────────────────────────────────
  // Archives written before the writer separated the two filed tool output as
  // something the user said, which made a 49-prompt session read as 1,125.
  // The transcripts they came from are gone, so the roles are inferred from
  // turn order: a result can only follow the call that produced it.
  function repairArchiveRoles(msgs) {
    if (msgs.some(function (m) { return m.role === "tool_result"; })) {
      return { messages: msgs, inferred: false };
    }
    var out = [], changed = false, afterTools = false;
    msgs.forEach(function (m) {
      if (m.role === "user") {
        if (afterTools) { m = Object.assign({}, m, { role: "tool_result" }); changed = true; }
        else if (looksLikeHarness(m.text)) { m = Object.assign({}, m, { role: "system" }); changed = true; }
      }
      out.push(m);
      afterTools = m.role === "tool_result" ||
                   (m.role === "assistant" && !!(m.tools && m.tools.length));
    });
    return { messages: out, inferred: changed };
  }

  // ── claude.ai exports ───────────────────────────────────────────────
  // An export keeps a reply's tool calls, their results and the text around
  // them in one message, in the order they happened. Cut it at each result,
  // as a transcript is, so every result follows the call that produced it.
  function fromExportChat(c) {
    var msgs = [];
    (c.chat_messages || []).forEach(function (x) {
      var who = x.sender === "human" ? "user" : "assistant";
      var ts = x.created_at, blocks = x.content || [];
      var anyText = blocks.some(function (b) { return b && b.type === "text" && b.text; });
      var seg = null, first = true;
      function open() {
        if (!seg) seg = { text: [], think: [], tools: [] };
        return seg;
      }
      function close() {
        var s = open(), text = s.text.filter(Boolean).join("\n");
        seg = null;
        // The message's own text and attachments belong to its first part.
        if (first) {
          first = false;
          if (!anyText) text = x.text || "";
          (x.files || []).concat(x.attachments || []).forEach(function (a) {
            text = (text + "\n[attached: " + (a.file_name || a.file_kind || "file") + "]").trim();
          });
        }
        if (who === "user") {
          if (text.trim()) msgs.push({ role: "user", timestamp: ts, side: false, text: text });
        } else if (text || s.tools.length || s.think.length) {
          msgs.push({ role: "assistant", timestamp: ts, side: false, text: text,
                      thinking: s.think.join("\n\n"), tools: s.tools });
        }
      }
      blocks.forEach(function (b) {
        if (!b || typeof b !== "object") return;
        if (b.type === "text") open().text.push(b.text || "");
        else if (b.type === "thinking") open().think.push(b.thinking || "");
        else if (b.type === "tool_use") {
          open().tools.push({ id: b.id, name: b.name, input: b.input || {} });
        } else if (b.type === "tool_result") {
          var content = b.content;
          if (Array.isArray(content)) content = blocksToText(content);
          if (typeof content === "string" && content.trim()) {
            if (seg || first) close();
            msgs.push({ role: "tool_result", timestamp: ts, side: false, text: cap(content, 6000) });
          }
        }
      });
      if (seg || first) close();
    });
    return msgs;
  }

  function findExports() {
    if (EXPORT) return exists(EXPORT) ? [EXPORT] : [];
    var found = [];
    [HOME + "/Downloads", ROOT].forEach(function (base) {
      var direct = base + "/conversations.json";
      if (exists(direct)) found.push(direct);
      list(base).forEach(function (name) {
        var p = base + "/" + name + "/conversations.json";
        if (exists(p)) found.push(p);
      });
    });
    return found;
  }

  // A chat whose export had not changed is listed from the manifest, without its
  // content, so a chat that must be rebuilt anyway is read back from the export.
  // Parsed once per run: rebuilding several chats must not re-read the file each.
  var exportCache = {};
  function chatFromExport(path, id) {
    if (!(path in exportCache)) {
      var text = read(path), chats = [];
      try { chats = text ? JSON.parse(text) : []; } catch (e) { chats = []; }
      exportCache[path] = {};
      (Array.isArray(chats) ? chats : []).forEach(function (c) {
        if (c && SESSION_ID.test(String(c.uuid))) exportCache[path][c.uuid] = c;
      });
    }
    var c = exportCache[path][id];
    if (!c) throw new Error("no longer in " + path);
    return c;
  }

  // A session's sub-agents live beside it, in <session id>/subagents: each is a
  // transcript of its own, with a .meta.json naming the Task call that spawned
  // it. They belong to their conversation and are not conversations of their
  // own — eighty-nine megabytes of them for one session here, which is also why
  // each gets a page rather than being folded into the parent's.
  function subagents(dir, id) {
    var home = dir + "/" + id + "/subagents", out = [];
    if (!isDir(home)) return out;
    list(home).forEach(function (f) {
      if (!/^agent-.*\.jsonl$/.test(f)) return;
      var path = home + "/" + f;
      out.push({
        agentId: f.replace(/^agent-/, "").replace(/\.jsonl$/, ""),
        path: path,
        metaPath: path.replace(/\.jsonl$/, ".meta.json"),
        sig: sig(path)
      });
    });
    return out;
  }

  // ── discovery ───────────────────────────────────────────────────────
  // A slash command reaches the transcript wrapped in tags of Claude Code's
  // own — <command-name>/compact</command-name> and the rest. As a title that
  // is unreadable, and it is never what the session was about: take the
  // command's name, and prefer a real prompt further down if there is one.
  function clean(text) {
    var t = String(text || "").replace(/\u001b\[[0-9;]*[A-Za-z]/g, "");
    // What a local command printed is recorded as though you had typed it.
    // It is output, not a prompt, and never a title.
    if (/^\s*<local-command-stdout>/.test(t)) return "";
    var name = /<command-name>\s*([^<]*)<\/command-name>/.exec(t);
    if (name) {
      var args = /<command-args>\s*([^<]*)<\/command-args>/.exec(t);
      return (name[1].trim() + " " + (args ? args[1].trim() : "")).trim();
    }
    return t.replace(/<\/?command-[a-z]+>/g, " ").split(/\s+/).join(" ").trim();
  }

  // The first prompt that is not a slash command, or failing that the first
  // slash command: worked out a message at a time, so a build that reads only
  // what was appended still knows it.
  function newFirst() { return { done: false, value: "", fallback: "" }; }
  function firstStep(f, m) {
    if (f.done || m.role !== "user" || m.side) return;
    var t = clean(m.text);
    if (!t) return;
    if (t.charAt(0) === "/") { f.fallback = f.fallback || t; return; }
    f.value = t.slice(0, 110);
    f.done = true;
  }
  function firstOf(f) { return f.done ? f.value : f.fallback.slice(0, 110); }

  function firstPrompt(msgs) {
    var f = newFirst();
    for (var i = 0; i < msgs.length && !f.done; i++) firstStep(f, msgs[i]);
    return firstOf(f);
  }

  // The hook archives into whatever folder under the root a session ran in,
  // however deep. Walking the root for them is not affordable on every save:
  // under osascript every directory listed costs most of a millisecond, and a
  // real projects folder took between two and twenty-eight seconds. So look
  // one level down, in the root itself, in every folder a session is known to
  // have worked in, and in every folder listed in ARCHIVES.
  //
  // That list lives outside the pages folder on purpose. The manifest knows
  // where sessions worked, but it goes with the pages: a fresh output folder
  // or a lost manifest would forget a nested project whose transcripts have
  // expired, and its archives would never be read again. The hook adds a
  // folder when it writes an archive there, the build adds any it finds, and
  // only when the list is missing, or a rebuild is forced, is the root walked.
  var ARCHIVES = HOME + "/.claude/claude-html.archives";
  // The walk's bounds: projects up to three folders below the root, as in
  // root/group/client/site, and never into the folders that hold thousands
  // of directories and no conversations. Over a real projects folder of
  // 47,000 directories that is about four seconds, once; a level deeper
  // more than doubled it and found nothing more.
  var WALK_DEPTH = 3;
  var WALK_SKIP = ["node_modules", "vendor", "bower_components", "Pods", "venv",
                   "__pycache__", "target", "dist", "build"];

  function readArchiveList() {
    var text = read(ARCHIVES);
    if (text === null) return null;
    return text.split("\n").map(function (l) { return l.replace(/\/+$/, ""); })
      .filter(function (l) { return l.charAt(0) === "/"; });
  }

  function walkForArchives() {
    return findArchiveDirs(ROOT.replace(/\/+$/, ""), WALK_DEPTH, WALK_SKIP, OUT.replace(/\/+$/, ""));
  }

  // Rewritten only when it changed, and merged with what is on disk at that
  // moment, so a folder the hook appended while this build ran is kept.
  function saveArchiveList(add, drop) {
    var now = readArchiveList() || [], seen = {}, out = [];
    now.concat(add).forEach(function (d) {
      if (seen[d] || drop[d]) return;
      seen[d] = true; out.push(d);
    });
    write(ARCHIVES, out.length ? out.join("\n") + "\n" : "");
  }

  function underRoot(dir) {
    var r = ROOT.replace(/\/+$/, "");
    dir = String(dir || "").replace(/\/+$/, "");
    return dir === r || dir.indexOf(r + "/") === 0;
  }

  function scanArchives(cwd, found, scanned) {
    cwd = String(cwd).replace(/\/+$/, "");
    if (scanned[cwd] || !underRoot(cwd)) return;
    scanned[cwd] = true;
    var dir = cwd + "/.claude/.claude-conversations";
    if (!isDir(dir)) return;
    scanned[cwd] = "archives";
    list(dir).forEach(function (f) {
      if (!/\.json$/.test(f)) return;
      var id = f.replace(/\.json$/, ""), path = dir + "/" + f, when = mtime(path);
      var prior = found[id];
      if (prior && (prior.kind !== "archive" || prior.mtime >= when)) return;
      found[id] = { id: id, project: projectFromCwd(cwd), cwd: cwd, title: "",
                    path: path, kind: "archive", mtime: when, sig: sig(path) };
    });
  }

  // Export chats refused for an id that is not one, reported with the build.
  var rejected = [];

  function discover(known, force) {
    var found = {}, scanned = {};
    statAll(PROJECTS);

    // archives, oldest source; the newest copy wins where there are several
    scanArchives(ROOT, found, scanned);
    list(ROOT).forEach(function (name) {
      if (name.charAt(0) !== ".") scanArchives(ROOT + "/" + name, found, scanned);
    });
    Object.keys(known).forEach(function (id) {
      if (known[id].cwd) scanArchives(known[id].cwd, found, scanned);
    });
    // Folders another root's build listed are kept, not scanned: they are
    // not this build's to judge. Only one that has vanished is let go.
    var listedDirs = readArchiveList(), dropDirs = {}, onList = {};
    (listedDirs || []).forEach(function (d) {
      onList[d] = true;
      if (!isDir(d + "/.claude/.claude-conversations")) dropDirs[d] = true;
      else scanArchives(d, found, scanned);
    });
    if (listedDirs === null || force) {
      walkForArchives().forEach(function (d) { scanArchives(d, found, scanned); });
    }

    // transcripts win, being richer
    list(PROJECTS).forEach(function (name) {
      var dir = PROJECTS + "/" + name;
      if (!isDir(dir)) return;
      list(dir).forEach(function (f) {
        if (!/\.jsonl$/.test(f)) return;
        var id = f.replace(/\.jsonl$/, ""), path = dir + "/" + f;
        var when = mtime(path), sg = sig(path);
        var kids = subagents(dir, id);
        if (kids.length) {
          sg += "|" + kids.map(function (k) { return k.sig; }).join(",");
        }
        var entry;
        var cached = known[id];
        if (!force && cached && cached.sig === sg && cached.kind !== "web") {
          // Its page is already current, so nothing in the file can have
          // changed. Reading a hundred megabytes to re-learn the project name
          // is the whole cost of a build where nothing happened.
          entry = { id: id, project: cached.project, cwd: cached.cwd,
                    title: cached.title || "", path: path, kind: "transcript",
                    mtime: when, sig: sg, agents: kids, cached: true };
        } else {
          // Changed, and so about to be built. Where it ran and its title are
          // stated in its first lines, which the cache has already read: a
          // build after one more reply need not read 166 MB to find them.
          var k = force ? null : keptFor(id, path), st = k && k.scan && k.scan.st;
          var pk = st && (st.lines > PEEK_LINES || (st.peek.cwd && st.peek.title)) ? st.peek : null;
          var text = pk ? "" : read(path);
          if (text === null) {
            // Unreadable, perhaps only for a moment. Keep it listed from what is
            // known, so the build reports it — dropping it here would have its
            // page pruned as if the session no longer existed.
            if (!cached) return;
            entry = { id: id, project: cached.project, cwd: cached.cwd,
                      title: cached.title || "", path: path, kind: "transcript",
                      mtime: when, sig: sg, agents: kids };
          } else {
            var p = pk || peek(text);
            var cwd = p.cwd || cwdFromDirname(name);
            entry = { id: id, project: projectFromCwd(cwd), cwd: cwd,
                      title: p.title || "", path: path, kind: "transcript",
                      mtime: when, sig: sg, agents: kids };
          }
        }
        // The transcript stays under the directory the session was launched
        // in, and the cwd inside it says the same, so after a rename both
        // still name the old folder. The archive was written by a hook
        // running in the project as it is now, which makes it the authority
        // on where the work lives — while the transcript stays the better
        // source for the content, being uncapped.
        var prior = found[id];
        if (prior && prior.kind === "archive") {
          entry.project = prior.project;
          entry.cwd = prior.cwd;
        }
        found[id] = entry;
      });
    });

    // A folder first seen in this run may hold archives of sessions whose
    // transcripts are already gone. They never displace a transcript.
    Object.keys(found).forEach(function (id) {
      if (found[id].kind === "transcript" && found[id].cwd) {
        scanArchives(found[id].cwd, found, scanned);
      }
    });

    var newDirs = Object.keys(scanned).filter(function (d) {
      return scanned[d] === "archives" && !onList[d];
    });
    if (listedDirs === null || newDirs.length || Object.keys(dropDirs).length) {
      saveArchiveList(newDirs, dropDirs);
    }

    // claude.ai conversations
    findExports().forEach(function (path) {
      var when = mtime(path), sg = sig(path);
      if (!force && exportsUnchanged(known, path, sg)) {
        Object.keys(known).forEach(function (id) {
          var e = known[id];
          if (e.kind === "web" && e.source === path) {
            found[id] = { id: id, project: e.project, cwd: "", title: e.title || "",
                          path: path, kind: "web", url: e.url, mtime: e.mtime,
                          sig: e.sig, source: path, sourceSig: sg, cached: true };
          }
        });
        return;
      }
      var text = read(path);
      if (text === null) return;
      var chats;
      try { chats = JSON.parse(text); } catch (e) { return; }
      if (!Array.isArray(chats)) return;
      chats.forEach(function (c) {
        if (!c || !c.uuid || !(c.chat_messages && c.chat_messages.length)) return;
        if (typeof c.uuid !== "string" || !SESSION_ID.test(c.uuid)) {
          rejected.push({ id: "?", source: path,
                          error: "not a claude.ai conversation id, skipped: " +
                                 JSON.stringify(String(c.uuid).slice(0, 80)) });
          return;
        }
        var chatWhen = c.updated_at || c.created_at;
        found[c.uuid] = {
          id: c.uuid, project: "claude.ai", cwd: "", title: c.name || "",
          path: path, kind: "web", chat: c,
          url: "https://claude.ai/chat/" + c.uuid,
          source: path, sourceSig: sg, sig: sg + ":" + (chatWhen || ""),
          mtime: chatWhen ? Math.round(new Date(chatWhen).getTime() / 1000) : when
        };
      });
    });

    return Object.keys(found)
      .filter(function (k) { return !HIDDEN[k] && k.indexOf("agent-") !== 0; })
      .map(function (k) { return found[k]; })
      .sort(function (a, b) { return b.mtime - a.mtime; });
  }

  // An export is one file holding many chats, so it is skipped as a whole:
  // if the file itself has not changed, none of its conversations have.
  function exportsUnchanged(known, path, sg) {
    var seen = false;
    for (var id in known) {
      if (known[id].kind === "web" && known[id].source === path) {
        seen = true;
        if (known[id].sourceSig !== sg) return false;
      }
    }
    return seen;
  }

  // ── search ──────────────────────────────────────────────────────────
  // The conversation, not the machinery: tool output is nearly half the text
  // and a match inside a command dump is rarely the one you wanted.
  // The rows of the message at index i: each depends on that message alone.
  function searchRowsOf(m, i) {
    var rows = [];
    if (m.role !== "user" && m.role !== "assistant") return rows;
    // Seconds, not the ISO string: a result shows when it was said and the
    // list is ordered by it, and this is a few bytes against several MB.
    var when = 0;
    if (m.timestamp) {
      var t = new Date(m.timestamp).getTime();
      if (!isNaN(t)) when = Math.round(t / 1000);
    }
    [["t", m.text], ["k", m.thinking]].forEach(function (pair) {
      var text = String(pair[1] == null ? "" : pair[1]).split(/\s+/).join(" ").trim();
      if (!text) return;
      rows.push([i, m.role === "assistant" ? pair[0] : "u", text, when]);
    });
    return rows;
  }

  // One small script per session. A save then rewrites only the session that
  // changed; a single search file meant rewriting every conversation's text —
  // 3.7 MB — after every reply. U+2028/2029 are escaped: legal in JSON, not in
  // the string literals of older JavaScript engines.
  //
  // Written from rows already in JSON, joined by commas: an array's JSON is
  // its elements' JSON so joined, so a long session's rows can be kept as
  // text between saves and only the new ones turned into it.
  function rowJson(r) {
    return JSON.stringify(r).replace(/\u2028/g, "\\u2028").replace(/\u2029/g, "\\u2029");
  }

  function searchText(id, rowsJson) {
    return "CH_SEARCH(" + JSON.stringify(id) + ",[" + rowsJson + "]);\n";
  }

  function rowsJsonOf(msgs) {
    var out = [];
    msgs.forEach(function (m, i) {
      searchRowsOf(m, i).forEach(function (r) { out.push(rowJson(r)); });
    });
    return out.join(",");
  }

  // ── pages ───────────────────────────────────────────────────────────
  // Every placeholder is filled in one pass. Replacing them one after another
  // would let a conversation that quotes a placeholder — this project's own
  // sessions do — have a later replacement land inside its own data.
  var PLACEHOLDER = /\/\*\{\{(css|data|viewer|page|index|usage)\}\}\*\//g;

  function fill(template, parts) {
    return template.replace(PLACEHOLDER, function (m, key) {
      return Object.prototype.hasOwnProperty.call(parts, key) ? parts[key] : m;
    });
  }

  // The data sits inside a script element, where "</script" ends it early and
  // "<!--" followed by "<script" stops the element's own end tag from ending
  // it. Escaping every "<" rules out both, and JSON.parse gives it back.
  function embed(value) {
    return JSON.stringify(value).replace(/</g, "\\u003c");
  }

  var assets = {};
  function asset(name) {
    if (!(name in assets)) assets[name] = read(HERE + "/viewer/" + name) || "";
    return assets[name];
  }

  // The page's data is its meta, its messages and its sub-agents. The
  // messages come as their JSON joined by commas — what embedding the whole
  // object would have written between the brackets — so a long session's
  // can be kept between saves and only the new ones encoded.
  function pageText(meta, msgsJson, agents) {
    return fill(asset("page.html"), {
      css: asset("session.css"),
      data: '{"meta":' + embed(meta) + ',"messages":[' + msgsJson + '],"agents":' +
            embed(agents || []) + "}",
      viewer: asset("viewer.js"),
      page: asset("page.js")
    });
  }

  // A page built whole, as a sub-agent's, an archive's or an export's is:
  // one encoding of the whole is faster than one per message, and the same.
  function sessionPage(meta, msgs, agents) {
    return fill(asset("page.html"), {
      css: asset("session.css"),
      data: embed({ meta: meta, messages: msgs, agents: agents || [] }),
      viewer: asset("viewer.js"),
      page: asset("page.js")
    });
  }

  function usagePage(byProject, coverage) {
    return fill(asset("usage.html"), {
      css: asset("index.css"),
      data: embed({ byProject: byProject, weekReset: WEEK_RESET, weekResetSet: WEEK_RESET_SET,
                    coverage: coverage || {} }),
      viewer: asset("viewer.js"),
      usage: asset("usage.js")
    });
  }

  function indexPage(entries, errors) {
    return fill(asset("index.html"), {
      css: asset("index.css"),
      // Opening a folder, deleting and resuming go through the macOS helper,
      // so elsewhere the index hides them rather than offer dead controls.
      // When it was built, in seconds, so a hook that has stopped firing shows.
      data: embed({ sessions: entries, home: HOME, root: ROOT, errors: errors,
                    built: Math.round(Date.now() / 1000), actions: ACTIONS, mac: MAC }),
      viewer: asset("viewer.js"),
      index: asset("index.js")
    });
  }

  // Each sub-agent gets a page of its own, beside its parent's, and the parent
  // is given only what it needs to link to it.
  //
  // A finished sub-agent never changes, and one session here had 322 of them,
  // a gigabyte, all read and their pages written again after every reply that
  // touched none of them. So each is kept, in the parent's cache, under a key
  // made of everything its page is made from — its transcript's size and
  // time, its .meta.json's, what it shows of the parent, the viewer — with
  // the summary the parent lists and the replies it adds to the parent's
  // count. While the key holds and its page is there, it is not read again.
  // kept: the last build's, by agent id; now: this build's, filled in here.
  function buildAgents(s, parentMeta, usageAcc, kept, now) {
    var out = [], ids = {};
    (s.agents || []).forEach(function (a) {
      ids[a.agentId] = true;
      var rel = s.id + "/agent-" + a.agentId + ".html", page = OUT + "/sessions/" + rel;
      var key = JSON.stringify([a.sig, sig(a.metaPath), parentMeta.project, parentMeta.open || "",
                                parentMeta.title || "", s.id, VIEWER]);
      var k = kept && kept[a.agentId];
      if (k && k.key === key && (k.out === null || exists(page))) {
        replay(usageAcc, k.ops);
        if (k.out) out.push(k.out);
        now[a.agentId] = k;
        return;
      }
      var text = read(a.path);
      if (text === null) return;
      // One pass for the messages and the replies, each line parsed once.
      var msgs = [], own = newReplies();
      eachLine(text, function (e) {
        messagesOf(e).forEach(function (m) { msgs.push(m); });
        usageLine(own, e);
      });
      if (!msgs.length) { now[a.agentId] = { key: key, out: null, ops: [] }; return; }
      var ops = usageOps(own);
      replay(usageAcc, ops);
      var info = {};
      try { info = JSON.parse(read(a.metaPath) || "{}") || {}; } catch (e) { info = {}; }
      // Its own time, not the parent's: the parent's changes with every reply,
      // and would have every sub-agent's page written again with it.
      write(page, sessionPage({
        id: a.agentId, project: parentMeta.project, cwd: "", kind: "sub-agent",
        open: parentMeta.open || "",
        title: info.description || "a sub-agent",
        mtime: Math.round(Number(String(a.sig).split(":")[1] || 0) / 1000),
        sig: a.sig, viewer: VIEWER, up: "../../index.html",
        agentType: info.agentType || "", model: info.model || "",
        parent: { id: s.id, title: parentMeta.title || "",
                  href: "../" + s.id + ".html" }
      }, msgs, []));
      var item = {
        id: a.agentId, href: rel, toolUseId: info.toolUseId || "",
        description: info.description || "", agentType: info.agentType || "",
        model: info.model || "", messages: msgs.length,
        prompts: msgs.filter(function (m) { return m.role === "user"; }).length
      };
      out.push(item);
      now[a.agentId] = { key: key, out: item, ops: ops };
    });
    // A page whose transcript is gone is not one a build from nothing would
    // have, so it goes; one that could not be read this time stays.
    list(OUT + "/sessions/" + s.id).forEach(function (f) {
      var m = /^agent-(.*)\.html$/.exec(f);
      if (m && !ids[m[1]]) remove(OUT + "/sessions/" + s.id + "/" + f);
    });
    return out;
  }

  // ── launchers ───────────────────────────────────────────────────────
  function resumable(meta) { return meta.kind !== "web" && !!meta.cwd; }

  // What a double-click runs: a .command, which Terminal opens, on macOS;
  // elsewhere a .desktop file, which file managers launch in a terminal, and
  // a plain .sh for the ones that prefer a script.
  var LAUNCHERS = OS === "darwin" ? [".command"] : [".sh", ".desktop"];

  function launcherStem(meta) {
    var stem = String(meta.project || "").replace(/[^A-Za-z0-9_.-]/g, "_");
    return OUT + "/resume/" + stem + "-" + meta.id;
  }

  // Single quotes keep everything literal, $ and backticks and line breaks
  // included; double quotes, which this used, would have run a $(…) in a
  // folder's name on every double-click.
  function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

  // A desktop file's Exec= is quoted twice over: each argument in double
  // quotes with " ` $ \ escaped, % doubled because %u and friends are codes,
  // and then the whole value escaped once more as every value in the file is.
  function deskValue(s) {
    return String(s).replace(/\\/g, "\\\\").replace(/\n/g, "\\n")
      .replace(/\t/g, "\\t").replace(/\r/g, "\\r");
  }
  function deskArg(s) {
    return '"' + String(s).replace(/["`$\\]/g, "\\$&").replace(/%/g, "%%") + '"';
  }

  function writeLaunchers(meta) {
    var stem = launcherStem(meta), id = meta.id;
    LAUNCHERS.forEach(function (ext) {
      var p = stem + ext, text;
      if (ext === ".desktop") {
        // The folder goes in as an argument, never as part of the script.
        var title = String(meta.title || meta.project || id).replace(/[\x00-\x1f\x7f]+/g, " ");
        if (title.length > 80) title = title.slice(0, 79) + "\u2026";
        text = "[Desktop Entry]\nType=Application\nVersion=1.0\n" +
          "Name=" + deskValue("Resume: " + title) + "\n" +
          "Comment=" + deskValue("claude --resume " + id + " in " + meta.cwd) + "\n" +
          "Path=" + deskValue(meta.cwd) + "\n" +
          "Terminal=true\n" +
          "Exec=" + deskValue(["bash", "-c", 'cd -- "$1" && exec claude --resume "$2"',
                               "claude-html", meta.cwd, id].map(deskArg).join(" ")) + "\n";
      } else {
        text = (ext === ".sh" ? "#!/bin/sh\n" : "#!/bin/bash\n") +
          "cd -- " + shq(meta.cwd) + " || exit 1\nexec claude --resume " + id + "\n";
      }
      write(p, text);
      chmodx(p);
    });
  }

  function removeLaunchers(meta) {
    [".command", ".sh", ".desktop"].forEach(function (ext) {
      remove(launcherStem(meta) + ext);
    });
  }

  // ── pruning ─────────────────────────────────────────────────────────
  // Only files this program wrote are ever removed, and it knows them by name.
  // The pages directory may be one you already keep things in.

  function prune(keep) {
    var gone = 0;
    list(OUT + "/sessions").forEach(function (f) {
      if (!/\.html$/.test(f)) return;
      var id = f.replace(/\.html$/, "");
      if (SESSION_ID.test(id) && !(id in keep)) { remove(OUT + "/sessions/" + f); gone++; }
    });
    list(OUT + "/sessions").forEach(function (f) {
      // A folder of sub-agent pages belongs to the session it is named after.
      if (!SESSION_ID.test(f) || !isDir(OUT + "/sessions/" + f)) return;
      if (!(f in keep)) { remove(OUT + "/sessions/" + f); gone++; }
    });
    // Sub-agents were briefly listed as sessions of their own, which left a
    // page and a search file apiece.
    ["sessions", "search"].forEach(function (d) {
      list(OUT + "/" + d).forEach(function (f) {
        if (f.indexOf("agent-") === 0) { remove(OUT + "/" + d + "/" + f); gone++; }
      });
    });
    // Pages used to sit beside the index. Any left there are from that layout.
    list(OUT).forEach(function (f) {
      if (f === "index.html" || !/\.html$/.test(f)) return;
      var id = f.replace(/\.html$/, "");
      if (SESSION_ID.test(id)) { remove(OUT + "/" + f); gone++; }
    });
    list(OUT + "/resume").forEach(function (f) {
      var m = /^(.*)(\.command|\.sh|\.desktop)$/.exec(f);
      if (!m) return;
      var id = m[1].slice(-36);
      if (!SESSION_ID.test(id)) return;
      var entry = keep[id];
      if (!entry) { remove(OUT + "/resume/" + f); gone++; return; }
      // Renaming a project leaves a launcher pointing at a path that is gone,
      // and a launcher of another system's kind is one nothing here runs.
      var wanted = launcherStem({ id: id, project: entry.project });
      if (!resumable(entry) || OUT + "/resume/" + m[1] !== wanted ||
          LAUNCHERS.indexOf(m[2]) < 0) {
        remove(OUT + "/resume/" + f); gone++;
      }
    });
    list(OUT + "/search").forEach(function (f) {
      var m = /^(.*)\.(js|json)$/.exec(f);
      if (!m || !SESSION_ID.test(m[1])) return;
      // .json is the old fragment format, only ever assembled into the single
      // search file; nothing reads it now.
      if (m[2] === "json" || !(m[1] in keep)) { remove(OUT + "/search/" + f); gone++; }
    });
    // The cache is only of transcripts, ours and the archiver's; anything
    // else in it is a write that never finished. Not counted as removed:
    // nobody looks in there. A conversation that is gone takes its cache
    // with it even in a build that does without the cache, since the cache
    // holds its text; the rest is left to a build that may write there.
    list(CACHE).forEach(function (f) {
      var m = /^(.*)\.(build|archive)(\.md5)?$/.exec(f);
      var gone = m && SESSION_ID.test(m[1]) && !keep[m[1]];
      if (gone || (USE_CACHE && (!m || !keep[m[1]] || keep[m[1]].kind !== "transcript"))) {
        remove(CACHE + "/" + f);
      }
    });
    return gone;
  }

  // Conversations hidden from the index — claude.ai chats, which live on
  // claude.ai, so deleting the local copy would last only until the next
  // export. One id per line; delete a line to bring a chat back.
  var HIDDEN = {};
  (read(opt.hidden || HOME + "/.claude/claude-html.hidden") || "").split("\n")
    .forEach(function (l) { l = l.trim(); if (l) HIDDEN[l] = true; });

  // Pages carry the viewer inside them, so a page is only current if it was built
  // with the viewer as it is now. Without this, updating the tool would leave
  // every existing page on the old viewer until its conversation next changed.
  function hashText(t) {
    var h = 5381;
    for (var i = 0; i < t.length; i++) h = ((h << 5) + h + t.charCodeAt(i)) | 0;
    return (h >>> 0).toString(36);
  }
  // Whether the page may offer link actions is part of it too, so installing
  // the Linux handler brings them to every page, not only the next one built.
  var VIEWER = hashText(["page.html", "session.css", "viewer.js", "page.js"]
    .map(asset).join("\u0000") + (ACTIONS ? "" : "\u0000no-actions"));
  // The shape of meta.usage. A change here makes every cached entry stale,
  // which is the only way a rebuild can notice the numbers are keyed
  // differently than they were.
  // 3: each entry also lists its replies, so the dashboard can count a reply
  // shared by a resumed session and its source once.
  // 4: a cell may carry a sixth figure, the cost in micro-dollars.
  var USAGE_VERSION = 4;

  // ── the parse, kept between saves ───────────────────────────────────
  // A transcript only ever grows, and one here reached 166 MB: reading all of
  // it after every reply, to add one, was most of a save. So what the build
  // makes of a transcript is kept in .cache/<id>.build — the messages and
  // search rows already in JSON, how far it had read, and everything a line
  // can leave behind for later ones: the replies counted so far (a reply is
  // several records under one id, the last one winning, and they can fall
  // either side of where the last build stopped), the cost counter's last
  // snapshot and startTime, the first prompt, the line count the title is
  // looked for within. The next build reads from that offset on and carries
  // on, and the result is the same bytes a build from nothing would write.
  //
  // Only whole lines are kept. A last line still being written is read on
  // top of a copy, every time, until it ends.
  //
  // The cache is a convenience and nothing more: it is used only while it
  // provably fits — this program's own source and USAGE_VERSION in its key,
  // its md5 in .cache/<id>.build.md5, the transcript at least as long as
  // where it stopped and the same bytes at three places before it — and
  // anything else is a build from the start. Deleting .cache is always safe.
  var CACHE = OUT + "/.cache";
  // Off for a build that may run beside another: the command when a save
  // holds the lock. Two builds writing one cache could leave each other's
  // halves; without it, a build is what it always was, whole and safe.
  var USE_CACHE = opt.cache !== false;
  var CACHE_KEY = "1:" + USAGE_VERSION + ":" + hashText(String(run));
  var WINDOW = 4096;

  // The start, the middle and the end of the bytes a cache was made from.
  // Transcripts are appended to, never rewritten; this catches one replaced.
  function fingerprint(path, off) {
    var w = Math.min(WINDOW, off);
    var parts = [bytesAt(path, 0, w), bytesAt(path, Math.max(0, Math.floor(off / 2) - (w >> 1)), w),
                 bytesAt(path, off - w, w)];
    for (var i = 0; i < parts.length; i++) if (parts[i] === null) return null;
    return off + ":" + parts.map(hashText).join(":");
  }

  function newScan() {
    return { off: 0, lines: 0, count: 0, prompts: 0, first: newFirst(),
             peek: { cwd: null, title: null }, usage: newReplies(), cost: newCost() };
  }

  // Lines into a scan: { st, msgs, rows }, the last two JSON text.
  function scanChunk(sc, text, sid) {
    var st = sc.st, lines = text.split("\n"), mj = [], rj = [];
    function add(m) {
      var i = st.count++;
      mj.push(embed(m));
      searchRowsOf(m, i).forEach(function (r) { rj.push(rowJson(r)); });
      if (m.role === "user" && !m.side) st.prompts++;
      firstStep(st.first, m);
    }
    for (var j = 0; j < lines.length; j++) {
      if (!lines[j]) continue;
      var e;
      try { e = JSON.parse(lines[j]); } catch (err) { continue; }
      if (!e || typeof e !== "object") continue;
      if (st.lines + j <= PEEK_LINES && !(st.peek.cwd && st.peek.title)) peekLine(st.peek, e);
      messagesOf(e).forEach(add);
      usageLine(st.usage, e);
      costLine(st.cost, e, sid);
    }
    st.lines += lines.length - 1;
    if (mj.length) sc.msgs += (sc.msgs ? "," : "") + mj.join(",");
    if (rj.length) sc.rows += (sc.rows ? "," : "") + rj.join(",");
  }

  // The transcript as it is now: the kept scan carried on with what was
  // appended, or one from the start. keep is the state to save, whole lines
  // only, as JSON taken before anything else adds to it; fin is the one to
  // build from.
  function scanTranscript(s, kept) {
    var base = kept && kept.scan, from = base ? base.st.off : 0;
    var got = readFrom(s.path, from);
    if (got === null) return null;
    var sc = base ? base : { st: newScan(), msgs: "", rows: "" };
    var nl = got.text.lastIndexOf("\n");
    scanChunk(sc, got.text.slice(0, nl + 1), s.id);
    sc.st.off = from + got.cut;
    // Taken as soon as the bytes are read, so it describes what was scanned
    // and not what the file became while the pages were being written.
    var fp = fingerprint(s.path, sc.st.off);
    var keep = JSON.stringify(sc.st), fin = sc, tail = got.text.slice(nl + 1);
    if (tail) {
      fin = { st: JSON.parse(keep), msgs: sc.msgs, rows: sc.rows };
      scanChunk(fin, tail, s.id);
    }
    return { keep: keep, off: sc.st.off, fp: fp, msgs: sc.msgs, rows: sc.rows, fin: fin };
  }

  function cacheFile(id) { return CACHE + "/" + id + ".build"; }

  // What the last build kept, checked: { scan, agents }, scan null when the
  // transcript no longer matches it. Read once per run, by discover or the
  // build, whichever asks first.
  var keptMemo = {};
  function keptFor(id, path) {
    if (!USE_CACHE) return null;
    if (!(id in keptMemo)) keptMemo[id] = loadKept(id, path);
    return keptMemo[id];
  }

  function loadKept(id, path) {
    var file = cacheFile(id);
    var sum = read(file + ".md5");
    if (!sum || sum.trim() !== digest(file)) return null;
    var raw = read(file);
    if (raw === null) return null;
    var nl = raw.indexOf("\n"), h;
    if (nl < 0) return null;
    try { h = JSON.parse(raw.slice(0, nl)); } catch (e) { return null; }
    if (!h || typeof h !== "object" || h.key !== CACHE_KEY || h.id !== id ||
        !Array.isArray(h.lens) || raw.length !== nl + 1 + h.lens[0] + h.lens[1] ||
        !h.agents || typeof h.agents !== "object") return null;
    var k = { scan: null, agents: h.agents };
    // No fingerprint is no match: one of a file now shorter is null too.
    if (h.path === path && h.scan && typeof h.scan.off === "number" &&
        typeof h.fp === "string" && h.fp === fingerprint(path, h.scan.off)) {
      k.scan = { st: h.scan, msgs: raw.substr(nl + 1, h.lens[0]),
                 rows: raw.substr(nl + 1 + h.lens[0]) };
    }
    return k;
  }

  // Written whole and then its md5, each atomically: a build stopped between
  // the two leaves an md5 that does not match, which reads as no cache.
  // Not kept at all when the transcript was cut short or replaced while it
  // was being built: what was read no longer matches the file.
  function saveKept(id, path, sc, agents) {
    var file = cacheFile(id);
    if (!sc.fp || sc.fp !== fingerprint(path, sc.off)) { remove(file + ".md5"); return; }
    var head = '{"key":' + JSON.stringify(CACHE_KEY) + ',"id":' + JSON.stringify(id) +
      ',"path":' + JSON.stringify(path) + ',"fp":' + JSON.stringify(sc.fp) +
      ',"scan":' + sc.keep + ',"lens":[' + sc.msgs.length + "," + sc.rows.length + "]" +
      ',"agents":' + JSON.stringify(agents) + "}";
    var d = write(file, head + "\n" + sc.msgs + sc.rows) ? digest(file) : "";
    if (d) write(file + ".md5", d + "\n");
    else remove(file + ".md5");
  }

  // ── build ───────────────────────────────────────────────────────────
  var manifest = {};
  var raw = read(OUT + "/.manifest.json");
  if (raw) { try { manifest = JSON.parse(raw); } catch (e) { manifest = {}; } }

  var sessions = discover(manifest, FORCE);
  if (ONLY) {
    sessions = sessions.filter(function (s) { return s.id.indexOf(ONLY) === 0; });
    if (!sessions.length) return JSON.stringify({ error: "no session matching " + ONLY });
  }
  var everything = !ONLY;
  var force = FORCE || !!ONLY;   // naming a session is a request to rebuild it

  var fresh = everything ? {} : JSON.parse(JSON.stringify(manifest));
  var errors = rejected.slice(), built = 0, skipped = 0;

  // The counted replies of every session built in this run, and their keys,
  // for the shared ones to be taken from below. null for carried numbers,
  // which brought none.
  var rowsOf = {};

  // again: build it even though its page is current — to settle what it
  // shares with other sessions, below.
  function buildOne(s, again) {
    var page = OUT + "/sessions/" + s.id + ".html";
    // Every id becomes a file name. Those from a file name already are one,
    // and export ids were checked on the way in, but nothing is written
    // outside the pages directory on the strength of either.
    if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(s.id)) {
      errors.push({ id: "?", source: s.path, error: "not a usable session id, skipped" });
      return;
    }
    var cached = manifest[s.id];
    if (!again && !force && cached && exists(page) &&
        exists(OUT + "/search/" + s.id + ".js") &&
        cached.sig === s.sig && cached.viewer === VIEWER &&
        cached.uv === USAGE_VERSION) {
      fresh[s.id] = cached;
      skipped++;
      // A launcher of the other system's kind was pruned, or one was deleted
      // by hand: the page is current, but there is nothing to double-click.
      if (resumable(cached) && !exists(launcherStem(cached) + LAUNCHERS[0])) writeLaunchers(cached);
      return;
    }
    try {
      var msgs = null, kind = s.kind, replies = newReplies(), archived = null, carried = null;
      var cost = null, costPart = false, sc = null, kept = null;
      var count, prompts, first;
      if (s.kind === "transcript") {
        kept = force ? null : keptFor(s.id, s.path);
        delete keptMemo[s.id];
        sc = scanTranscript(s, kept);
        if (sc === null) throw new Error("cannot read " + s.path);
        var st = sc.fin.st;
        replies = st.usage;
        cost = costOf(st.cost);
        if (cost) costPart = cost.part;
        count = st.count;
        prompts = st.prompts;
        first = firstOf(st.first);
      } else if (s.kind === "web") {
        msgs = fromExportChat(s.chat || chatFromExport(s.path, s.id));
      } else {
        var arch = read(s.path);
        if (arch === null) throw new Error("cannot read " + s.path);
        var parsed = JSON.parse(arch);
        var fixed = repairArchiveRoles(parsed.messages || []);
        msgs = fixed.messages;
        if (fixed.inferred) kind = "archive (inferred)";
        // Tokens are recorded nowhere but the transcript. An archive written
        // since the archiver started keeping them has them; for an older one
        // the last build's numbers are the only copy left, so they are kept
        // rather than the session dropping out of the dashboard's history.
        if (parsed.usage && typeof parsed.usage === "object") {
          archived = cleanUsage(parsed.usage);
          costPart = parsed.costPart === true;
          (Array.isArray(parsed.replies) ? parsed.replies : []).forEach(function (r) {
            if (!Array.isArray(r) || !r[0] || String(r[1] || "").length !== 13) return;
            replies.by["m:" + r[0]] = {
              mid: String(r[0]), hour: String(r[1]), model: String(r[2] || "unknown"),
              t: [Number(r[3]) || 0, Number(r[4]) || 0, Number(r[5]) || 0, Number(r[6]) || 0, 1]
            };
          });
        } else if (cached && cached.usage && (cached.uv === USAGE_VERSION || cached.uv === 3)) {
          // Version 3 numbers are version 4 numbers without a cost, so the
          // only copy of an old archive's tokens survives the upgrade.
          carried = cached;
          costPart = cached.costPart === true;
        }
      }
      if (msgs) {
        count = msgs.length;
        prompts = msgs.filter(function (m) { return m.role === "user" && !m.side; }).length;
        first = firstPrompt(msgs);
      }
      if (!count) {
        // Transcripts only grow. One that had a page and now yields nothing
        // has not emptied: its format has moved on from this parser, and the
        // page it had is the better thing to show until the parser catches up.
        if (manifest[s.id]) throw new Error("no messages could be read from it any more");
        return;                                       // nothing to show
      }

      var meta = { id: s.id, project: s.project, cwd: s.cwd, kind: kind,
                   title: s.title || first, mtime: s.mtime, sig: s.sig,
                   viewer: VIEWER,
                   // What the project crumb opens, when there is a folder to
                   // open: the same link the index's project name carries.
                   open: (ACTIONS && s.cwd && kind !== "web") ? s.id : "",
                   up: "../index.html", home: HOME };
      if (s.url) meta.url = s.url;
      if (s.source) { meta.source = s.source; meta.sourceSig = s.sourceSig; }

      var nowAgents = {};
      var agents = buildAgents(s, meta, replies, kept && kept.agents, nowAgents);
      var usage = archived || (carried ? cleanUsage(carried.usage) : usageOf(replies));
      if (cost) addCost(usage, cost);
      meta.uv = USAGE_VERSION;
      if (Object.keys(usage).length) {
        meta.usage = usage;
        // The same numbers as one row, which is all the index and the page
        // header need: input, output, cache read, cache write, replies, and
        // the cost when any cell knows it.
        var tok = [0, 0, 0, 0, 0];
        Object.keys(usage).forEach(function (slot) {
          Object.keys(usage[slot]).forEach(function (m) {
            var u = usage[slot][m];
            for (var i = 0; i < 5; i++) tok[i] += u[i] || 0;
            if (u.length > 5) tok[5] = (tok[5] || 0) + u[5];
          });
        });
        meta.tok = tok;
        if (tok.length > 5 && costPart) meta.costPart = true;
        // Which models did the work, biggest first — two words in the header.
        // One that only shows up in the cost (the small calls Claude Code
        // makes for itself, never written as replies) did none of it.
        var per = {};
        Object.keys(usage).forEach(function (slot) {
          Object.keys(usage[slot]).forEach(function (m) {
            var u = usage[slot][m];
            per[m] = (per[m] || 0) + u[0] + u[1] + u[2] + u[3];
          });
        });
        meta.models = Object.keys(per).filter(function (m) { return per[m] > 0; })
          .sort(function (a, b) { return per[b] - per[a]; });
      }
      write(page, sc ? pageText(meta, sc.fin.msgs, agents) : sessionPage(meta, msgs, agents));
      write(OUT + "/search/" + s.id + ".js", searchText(s.id, sc ? sc.fin.rows : rowsJsonOf(msgs)));
      if (resumable(meta)) writeLaunchers(meta);
      else removeLaunchers(meta);

      meta.prompts = prompts;
      delete meta.home;
      meta.agents = agents.length;
      // Kept in the manifest only, after the page is written: the page has
      // no use for them.
      var keys = [], recs = [];
      countedReplies(replies).forEach(function (r) {
        if (!r.mid) return;
        keys.push(replyKey(r.mid));
        recs.push(r);
      });
      if (keys.length) meta.ids = keys.join("");
      rowsOf[s.id] = { keys: keys, recs: recs };
      // Carried numbers bring the replies they were counted from, or a
      // resumed copy elsewhere would be counted twice.
      if (carried) {
        if (carried.ids) meta.ids = carried.ids;
        if (carried.shared) meta.shared = carried.shared;
        rowsOf[s.id] = null;
      }
      fresh[s.id] = meta;
      if (sc && USE_CACHE) saveKept(s.id, s.path, sc, nowAgents);
      built++;
    } catch (e) {
      // A session that will not build is reported, never quietly missing — and
      // keeps its last good page and its place on the index. Without this it
      // would fall out of the list and be pruned, so one failed attempt would
      // cost a page that was fine a moment ago.
      errors.push({ id: s.id, source: s.path, error: String(e.message || e) });
      if (manifest[s.id]) fresh[s.id] = manifest[s.id];
    }
  }

  sessions.forEach(function (s) { buildOne(s, false); });

  // A reply copied into a resumed or forked session is counted once on the
  // dashboard, and every session holding a copy keeps it in full — the hour
  // and model it counted it under — so whichever copy is not counted can be
  // taken back out. Which replies those are is settled here, once all the
  // sessions are known. Worked out as each session was built, it depended on
  // which had been built before it, and a build from nothing disagreed with
  // one made a reply at a time. A session whose page is current but whose
  // shared replies have changed — a new fork of it has appeared — is built
  // again, from its cache, to have its own copies at hand.
  // Only when something could have changed it: a session built, or one gone.
  var sameSet = Object.keys(fresh).length === Object.keys(manifest).length &&
    Object.keys(fresh).every(function (id) { return id in manifest; });
  if (built || !sameSet) (function settleShared() {
    var owner = {}, bySid = {};
    Object.keys(fresh).forEach(function (id) {
      eachKey(fresh[id].ids, function (k) {
        var o = owner[k];
        owner[k] = (o === undefined || o === id) ? id : "*";
      });
    });
    sessions.forEach(function (s) { bySid[s.id] = s; });
    Object.keys(fresh).forEach(function (id) {
      if (rowsOf[id] === null) return;          // carried: kept as it came
      var want = [], seen = {};
      eachKey(fresh[id].ids, function (k) {
        if (owner[k] === "*" && !seen[k]) { seen[k] = true; want.push(k); }
      });
      if (!rowsOf[id]) {
        if (Object.keys(fresh[id].shared || {}).join() === want.join()) return;
        if (!bySid[id]) return;
        buildOne(bySid[id], true);
        if (!rowsOf[id]) return;
      }
      var e = fresh[id], rows = rowsOf[id], shared = {};
      for (var i = 0; i < rows.keys.length; i++) {
        var r = rows.recs[i];
        if (seen[rows.keys[i]]) shared[rows.keys[i]] = [r.hour, r.model].concat(r.t);
      }
      delete e.shared;
      if (want.length) {
        e.shared = {};
        want.forEach(function (k) { e.shared[k] = shared[k]; });
      }
    });
  })();

  // Finding nothing at all, where pages were built before, means this run lost
  // sight of the sessions far more often than that every one was deleted — a
  // moved folder, a wrong HOME. Pruning on that would empty the site and call
  // it success, so keep what was there and say why. The pages are counted on
  // disk, not in the manifest: a lost manifest must not make them fair game.
  var lostSight = false;
  if (everything && !Object.keys(fresh).length) {
    var had = list(OUT + "/sessions").filter(function (f) {
      return /\.html$/.test(f) && SESSION_ID.test(f.replace(/\.html$/, ""));
    });
    if (had.length) {
      lostSight = true;
      fresh = JSON.parse(JSON.stringify(manifest));
      errors.push({ id: "?", source: PROJECTS,
                    error: "no sessions found, though " + had.length +
                           " pages exist; nothing was removed" });
    }
  }

  // The index and the search file describe every session, so they are written
  // from everything known, not only from what this run touched.
  var order = Object.keys(fresh)
    .filter(function (id) { return exists(OUT + "/sessions/" + id + ".html"); })
    .sort(function (a, b) { return (fresh[b].mtime || 0) - (fresh[a].mtime || 0); });

  var live = {};
  sessions.forEach(function (s) { live[s.id] = s.sig; });

  var entries = order.map(function (id) {
    var e = JSON.parse(JSON.stringify(fresh[id]));
    delete e.usage;                 // the dashboard reads them, the index need not
    delete e.ids;
    delete e.shared;
    // A page built before its source changed is showing an old conversation.
    e.stale = live[id] !== undefined && live[id] !== e.sig;
    return e;
  });

  var removed = everything && !lostSight ? prune(fresh) : 0;

  // The single search file this replaced is no longer read by anything.
  remove(OUT + "/search-index.js");
  write(OUT + "/.manifest.json", JSON.stringify(fresh));
  // Archiving happens in the hook, before any of this. Its failures are left as
  // one file per session, so a later success clears exactly its own.
  var shown = errors.slice();
  list(OUT + "/.archive-errors").forEach(function (f) {
    if (!/\.json$/.test(f)) return;
    var t = read(OUT + "/.archive-errors/" + f);
    if (!t) return;
    try { var o = JSON.parse(t); if (o) shown.push(o); } catch (e) {}
  });
  write(OUT + "/index.html", indexPage(entries, shown));
  // The token dashboard: every session's usage lives in the manifest, so a
  // build where nothing changed still writes it whole.
  // A reply copied into a resumed or forked session counts once, for the
  // session changed least recently, and the copies are taken back out. That is
  // usually the one it came from, but a source still in use after the fork
  // hands the shared replies to the fork, and their project with them: no
  // record says which copy is the original.
  var sharedUsage = {}, counted = {}, repeats = {};
  order.forEach(function (id) {
    var sh = fresh[id].shared || {};
    Object.keys(sh).forEach(function (k) { if (!sharedUsage[k]) sharedUsage[k] = sh[k]; });
  });
  order.slice().reverse().forEach(function (id) {
    if (!fresh[id].usage) return;
    var own = fresh[id].shared || {};
    eachKey(fresh[id].ids, function (k) {
      if (!counted[k]) { counted[k] = true; return; }
      // The session's own copy first: it names the hour and model this
      // session added it under, should a copy ever have been stamped later.
      var r = own[k] || sharedUsage[k];
      if (r) (repeats[id] = repeats[id] || []).push(r);
    });
  });
  var byProject = {};
  order.forEach(function (id) {
    if (!fresh[id].usage) return;
    var key = fresh[id].project || "unknown";
    var into = byProject[key] = byProject[key] || {};
    addUsage(into, fresh[id].usage);
    (repeats[id] || []).forEach(function (r) { subUsage(into, r); });
  });
  Object.keys(byProject).forEach(function (key) {
    if (!Object.keys(byProject[key]).length) delete byProject[key];
  });
  // How much of it has a cost at all, per project, so the page can say so
  // plainly: sessions with tokens, those with a cost, and those whose cost
  // covers only part of what they did.
  var coverage = {};
  order.forEach(function (id) {
    var e = fresh[id];
    if (!e.usage || !e.tok) return;
    var c = coverage[e.project || "unknown"] = coverage[e.project || "unknown"] || [0, 0, 0];
    c[0]++;
    if (e.tok.length > 5) c[1]++;
    if (e.tok.length > 5 && e.costPart) c[2]++;
  });
  write(OUT + "/usage.html", usagePage(byProject, coverage));
  if (errors.length) write(OUT + "/.build-errors.json", JSON.stringify(errors));
  else remove(OUT + "/.build-errors.json");

  return JSON.stringify({
    sessions: order.length, built: built, skipped: skipped,
    removed: removed, errors: shown, out: OUT
  });
}

// osascript calls run() by itself; node has to be asked.
if (typeof $ === "undefined" && typeof require !== "undefined" &&
    typeof module !== "undefined" && require.main === module) {
  process.stdout.write(run(process.argv.slice(2)) + "\n");
}
