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
