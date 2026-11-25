// What a transcript says, one record at a time: the messages a page shows,
// the tokens each reply used, what the session cost, and its title. One
// file, read by both of the programs that read transcripts, so the page a
// session gets from its archive, once the transcript has expired, is the
// page it had while the transcript was there:
//
//   convert.js         loads it with new Function, as it loads redact.js
//   the archiver       has it appended, as redact.js is, by the save
//
//   var P = claudeHtmlParse(function () { return RED; });
//   P.messagesOf(record)  →  [message, …]
//
// The redactor is asked for each time, not kept: a command that counts what
// it masks swaps in a fresh one between sessions. Plain JavaScript, the
// same under osascript and node, and nothing here touches a file.

function claudeHtmlParse(redactor) {
  "use strict";

  function red(s) { return redactor().text(s); }

  // How much of a long text is kept, here and so in every archive: what
  // the page shows of a tool's output and of thinking, and a bound on each
  // string of a tool's input, so a tool with a huge payload cannot make a
  // page or an archive unopenable.
  var RESULT_CAP = 6000, THINK_CAP = 6000, INPUT_CAP = 20000;

  // ── text ──
  function cap(s, n) {
    s = s == null ? "" : String(s);
    // Count code points, not UTF-16 units: slicing by units can cut an
    // emoji in half and leave a lone surrogate behind. A string no longer
    // than n units has no more than n code points. A longer one is counted
    // without being split into an array of characters, which under
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

  // A long text about to be cut: only what is kept needs reading, and
  // enough after it that a secret the cut would halve is still seen whole —
  // longer than any password, URL or name=value a rule matches. What is
  // longer still, a key block or a long token, is masked from where it
  // starts: the text as cut is looked at once more, and what is left of a
  // token right before the cut, or of a key block, goes.
  var RED_MARGIN = 1024;
  function capRed(s, n) {
    s = s == null ? "" : String(s);
    var r = null;
    if (s.length > n + RED_MARGIN) {
      var head = red(s.slice(0, n + RED_MARGIN));
      if (head.length >= n + RED_MARGIN / 2) r = head + s.slice(n + RED_MARGIN);
    }
    if (r === null) r = red(s);
    var c = cap(r, n);
    return c === r ? r : red(c);
  }

  function hashText(t) {
    var h = 5381;
    for (var i = 0; i < t.length; i++) h = ((h << 5) + h + t.charCodeAt(i)) | 0;
    return (h >>> 0).toString(36);
  }

  // Injected by the harness, not typed by anyone.
  var SYSTEM_BLOCK = /<system-reminder>[\s\S]*?<\/system-reminder>/g;
  var COMMAND_BLOCK = /<command-(name|message|args)>[\s\S]*?<\/command-\1>/g;
  function cleanUserText(text) {
    return String(text == null ? "" : text)
      .replace(SYSTEM_BLOCK, "").replace(COMMAND_BLOCK, "").trim();
  }

  // A tool's output, or an export's: its text, and a picture as [image].
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

  // A tool's input, masked, every string in it bounded. Masked whole first,
  // so a key that says secret still masks its value; what a cut leaves of a
  // token is masked again.
  function boundInput(v, depth) {
    if (typeof v === "string") {
      var c = cap(v, INPUT_CAP);
      return c === v ? v : red(c);
    }
    if (!v || typeof v !== "object" || depth > 64) return v;
    if (Array.isArray(v)) {
      for (var i = 0; i < v.length; i++) v[i] = boundInput(v[i], depth + 1);
    } else {
      for (var k in v) {
        if (Object.prototype.hasOwnProperty.call(v, k)) v[k] = boundInput(v[k], depth + 1);
      }
    }
    return v;
  }
  function toolInput(inp) {
    return boundInput(redactor().value(inp && typeof inp === "object" ? inp : {}), 0);
  }

  // ── messages ──
  // The messages one record holds, as a page shows them. Each depends on
  // its own line alone, which is what lets a save or a build read only what
  // was appended. Harness context (isMeta) is no turn of anyone's, and the
  // harness's own tags are not what was typed.
  function messagesOf(e) {
    var msgs = [];
    var t = e.type, ts = e.timestamp, side = !!e.isSidechain;
    var content = (e.message || {}).content;
    if (t === "user") {
      if (e.isMeta) return msgs;
      if (typeof content === "string") {
        var text1 = red(cleanUserText(content));
        if (text1) msgs.push({ role: "user", timestamp: ts, side: side, text: text1 });
      } else if (Array.isArray(content)) {
        content.forEach(function (b) {
          if (!b || typeof b !== "object") return;
          if (b.type === "text") {
            var tx = red(cleanUserText(b.text));
            if (tx) msgs.push({ role: "user", timestamp: ts, side: side, text: tx });
          } else if (b.type === "image") {
            msgs.push({ role: "user", timestamp: ts, side: side, text: "[image]" });
          } else if (b.type === "tool_result") {
            msgs.push({ role: "tool_result", timestamp: ts, side: side,
                        text: capRed(blocksToText(b.content), RESULT_CAP) });
          }
        });
      }
    } else if (t === "assistant" && Array.isArray(content)) {
      var text2 = red(content.filter(function (b) { return b && b.type === "text"; })
                             .map(function (b) { return b.text || ""; }).join("\n"));
      var think = capRed(content.filter(function (b) { return b && b.type === "thinking"; })
                                .map(function (b) { return b.thinking || ""; }).join("\n\n"), THINK_CAP);
      var tools = content.filter(function (b) { return b && b.type === "tool_use"; })
                         .map(function (b) {
                           return { id: b.id, name: b.name, input: toolInput(b.input) };
                         });
      if (text2 || tools.length || think) {
        msgs.push({ role: "assistant", timestamp: ts, side: side,
                    text: text2, thinking: think, tools: tools });
      }
    }
    return msgs;
  }

  // Where the session ran and what Claude Code titled it: both are stated
  // early, so only the first PEEK_LINES lines are looked at for them.
  var PEEK_LINES = 400;
  function peekLine(p, e) {
    p.cwd = p.cwd || e.cwd || null;
    p.title = p.title || red(e.aiTitle) || null;
  }

  // ── tokens ──
  // Per hour and model, from the records' own usage. The hour, not the day,
  // because a usage week can start at 9am and because these timestamps are
  // UTC — the page converts them to local time itself. A long reply is
  // written as several records sharing one message id, each carrying the
  // usage so far, so the last record per id wins. One accumulator serves a
  // session and all its sub-agents, so a reply in both is still one reply.
  //
  // A reply's figures, and so every usage cell's (USAGE_VERSION 5):
  //   0 input  1 output  2 cache read  3 cache write (5-minute and 1-hour
  //   together)  4 replies  5 of the cache write, 1-hour  6 of the cache
  //   write, split unknown (a record that does not say which; priced as
  //   5-minute)  [7 the cost Claude Code recorded, micro-dollars, on a cell
  //   that has one]
  // prices.js names them (T) and prices them.
  //
  // A reply priced by a rule of its own is filed under its model with a
  // suffix, as the price list files it: "/fast" when the reply says it ran
  // in fast mode (usage.speed), and "/over-100k" for a Haiku 5.5 prompt
  // over 100,000 tokens, cache reads and writes included, which the
  // pricing page prices higher per request. Per request is why it is
  // decided here: an hour's sums can no longer tell.
  var LONG_PROMPT = [[/^claude-haiku-5-5(-\d{8})?$/, 100000, "/over-100k"]];
  function newReplies() { return { by: {}, n: 0 }; }
  function usageLine(acc, e) {
    if (e.type !== "assistant" || !e.message || !e.message.usage) return;
    var u = e.message.usage;
    // Synthetic records (model "<synthetic>") carry no tokens; all zeros
    // would only add noise rows to the dashboard.
    if (!(u.input_tokens || u.output_tokens ||
          u.cache_read_input_tokens || u.cache_creation_input_tokens)) return;
    var mid = e.message.id ? String(e.message.id) : "";
    var inp = Number(u.input_tokens) || 0, read = Number(u.cache_read_input_tokens) || 0;
    var write = Number(u.cache_creation_input_tokens) || 0, hour1 = 0, unsplit = write;
    // The split, where the record gives one; without it, the whole write is
    // of unknown duration.
    var cc = u.cache_creation;
    if (cc && typeof cc === "object" &&
        (cc.ephemeral_5m_input_tokens != null || cc.ephemeral_1h_input_tokens != null)) {
      hour1 = Math.min(write, Number(cc.ephemeral_1h_input_tokens) || 0);
      unsplit = Math.max(0, write - hour1 - (Number(cc.ephemeral_5m_input_tokens) || 0));
    }
    var model = e.message.model ? String(e.message.model) : "unknown";
    if (u.speed === "fast") model += "/fast";
    else {
      for (var i = 0; i < LONG_PROMPT.length; i++) {
        if (LONG_PROMPT[i][0].test(model) && inp + read + write > LONG_PROMPT[i][1]) {
          model += LONG_PROMPT[i][2];
          break;
        }
      }
    }
    acc.by[mid ? "m:" + mid : e.uuid ? "u:" + e.uuid : "r:" + (acc.n++)] = {
      mid: mid,
      hour: String(e.timestamp || "").slice(0, 13),   // 2026-10-21T14, UTC
      model: model,
      // One per message id, so "tokens per reply" means what it says.
      t: [inp, Number(u.output_tokens) || 0, read, write, 1, hour1, unsplit]
    };
  }

  // ── cost ──
  // From Claude Code's own "cost-state" records: the dollars it worked out
  // at API list prices, per model, as a running total for the whole session,
  // written when a session exits, with no timestamp. Each becomes what was
  // added since the one before, filed under the hour of the last record that
  // had a time. A total that fell, or a new startTime, is a new counter. Only
  // this session's own records count — one carried over by a resume or a
  // fork is the other session's — and only its own transcript has them:
  // sub-agents spend on its counter. Micro-dollars, so sums stay exact.
  // "part": some replies fall outside every counter, so the figure is a floor.
  // "from": when the first counter began (ms), so the build can tell a
  // copied reply, from before it, from one this session's money covers.
  // Plain data throughout, so it can be kept between saves and carried on.
  function newCost() {
    return { cells: {}, last: "", prev: null, pending: {}, part: false, seen: false, n: 0, from: 0 };
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
    if (start > 0 && (!c.from || start < c.from)) c.from = start;
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

  return {
    PEEK_LINES: PEEK_LINES,
    cap: cap, capRed: capRed, hashText: hashText,
    cleanUserText: cleanUserText, blocksToText: blocksToText,
    messagesOf: messagesOf, peekLine: peekLine,
    newReplies: newReplies, usageLine: usageLine, newCost: newCost, costLine: costLine
  };
}
