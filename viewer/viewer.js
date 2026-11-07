// The renderer. Runs in the browser, over the JSON embedded in the page.
//
// Every function here is pure: messages in, HTML strings out. Nothing touches
// a file or a global beyond the element it is handed, so the whole thing can
// be tested under Node as well as run in a page.

var CH = (function () {
  "use strict";

  // ── text ──────────────────────────────────────────────────────────

  function esc(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;").replace(/'/g, "&#x27;");
  }

  function cap(s, n) {
    s = s == null ? "" : String(s);
    // Count code points, not UTF-16 units: Python does, and slicing by units
    // can cut an emoji in half and leave a lone surrogate behind.
    var chars = Array.from(s);
    if (chars.length <= n) return s;
    return chars.slice(0, n).join("") +
           "\n…[truncated, " + (chars.length - n) + " more characters]";
  }

  function when(ts) {
    if (!ts) return "";
    var d = new Date(ts);
    if (isNaN(d.getTime())) return "";
    return ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2);
  }

  // Escape first, then put back the two inline marks worth having.
  function inline(text) {
    var t = esc(text);
    t = t.replace(/`([^`\n]+)`/g, '<code class="ic">$1</code>');
    t = t.replace(/\*\*([^*\n]+)\*\*/g, "<strong>$1</strong>");
    return t;
  }

  // Headings, bullet lists, and paragraphs that keep their line breaks.
  // Deliberately not a Markdown engine: the terminal does not render one
  // either, and a half-working one would misrepresent what was said.
  function prose(text) {
    var out = [], para = [], items = [];

    function flushPara() {
      if (para.length) {
        out.push('<div class="t">' + inline(para.join("\n")) + "</div>");
        para = [];
      }
    }
    function flush() {
      if (items.length) {
        out.push("<ul>" + items.map(function (i) {
          return "<li>" + inline(i) + "</li>";
        }).join("") + "</ul>");
        items = [];
      }
      flushPara();
    }

    var lines = String(text == null ? "" : text).split("\n");
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var h = /^(#{1,6})\s+(.*)$/.exec(line);
      var b = /^\s*[-*]\s+(.+)$/.exec(line);
      if (h) {
        flush();
        out.push('<div class="h">' + inline(h[2]) + "</div>");
      } else if (b) {
        flushPara();
        items.push(b[1]);
      } else {
        if (items.length && line.trim()) flush();
        else if (items.length) continue;
        para.push(line);
      }
    }
    flush();
    return out.join("");
  }

  // Fenced code blocks become <pre>; everything else goes through prose().
  function markdownish(text) {
    text = String(text == null ? "" : text);
    var out = [], re = /```(\w*)\n([\s\S]*?)```/g, last = 0, m;
    while ((m = re.exec(text)) !== null) {
      var before = text.slice(last, m.index);
      if (before.trim()) out.push(prose(before.replace(/^\n+|\n+$/g, "")));
      out.push('<pre class="code">' + esc(m[2]) + "</pre>");
      last = m.index + m[0].length;
    }
    var tail = text.slice(last);
    if (tail.trim()) out.push(prose(tail.replace(/^\n+|\n+$/g, "")));
    return out.join("") || prose(text);
  }

  // ── diff ──────────────────────────────────────────────────────────

  // Longest common subsequence over lines. The strings being diffed are the
  // arguments of one Edit — a median of 13 lines, 125 at the worst — so the
  // quadratic table is a few thousand cells and the simple algorithm is the
  // right one. Returns operations in order: the edit script.
  function diffOps(a, b) {
    var n = a.length, m = b.length, i, j;
    var lcs = [];
    for (i = 0; i <= n; i++) lcs.push(new Array(m + 1).fill(0));
    for (i = n - 1; i >= 0; i--) {
      for (j = m - 1; j >= 0; j--) {
        lcs[i][j] = a[i] === b[j] ? lcs[i + 1][j + 1] + 1
                                  : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
      }
    }
    var ops = [];
    i = 0; j = 0;
    while (i < n && j < m) {
      if (a[i] === b[j]) { ops.push({ op: " ", text: a[i] }); i++; j++; }
      else if (lcs[i + 1][j] >= lcs[i][j + 1]) { ops.push({ op: "-", text: a[i] }); i++; }
      else { ops.push({ op: "+", text: b[j] }); j++; }
    }
    while (i < n) { ops.push({ op: "-", text: a[i] }); i++; }
    while (j < m) { ops.push({ op: "+", text: b[j] }); j++; }
    return ops;
  }

  // Applying the diff to the old text must reproduce the new text exactly.
  // That property, not agreement with any particular implementation, is what
  // makes a diff correct — two valid diffs can align differently.
  function applyOps(ops) {
    return ops.filter(function (o) { return o.op !== "-"; })
              .map(function (o) { return o.text; }).join("\n");
  }

  // Long runs of unchanged lines are elided, the way a unified diff does.
  function renderDiff(oldS, newS, path, context) {
    var ctx = context === undefined ? 2 : context;
    var ops = diffOps(String(oldS || "").split("\n"), String(newS || "").split("\n"));
    if (!ops.some(function (o) { return o.op !== " "; })) return "";

    var keep = new Array(ops.length).fill(false);
    ops.forEach(function (o, i) {
      if (o.op === " ") return;
      for (var k = Math.max(0, i - ctx); k <= Math.min(ops.length - 1, i + ctx); k++) keep[k] = true;
    });

    var rows = [], gap = false;
    for (var i = 0; i < ops.length; i++) {
      if (!keep[i]) { gap = true; continue; }
      if (gap) { rows.push('<div class="dl hunk">@@</div>'); gap = false; }
      var cls = ops[i].op === "+" ? "add" : ops[i].op === "-" ? "del" : "ctx";
      rows.push('<div class="dl ' + cls + '">' + esc(ops[i].op + ops[i].text) + "</div>");
    }
    return '<div class="diff"><div class="dp">' + esc(path) + "</div>" + rows.join("") + "</div>";
  }

  // One way of writing a token count, so the index, a session page and the
  // dashboard never disagree about what 1.7 M means.
  function fmtTokens(n) {
    n = Number(n) || 0;
    if (n >= 1e9) return (n / 1e9).toFixed(2) + " B";
    if (n >= 1e6) return (n / 1e6).toFixed(1) + " M";
    if (n >= 1e3) return (n / 1e3).toFixed(1) + " k";
    return String(Math.round(n));
  }

  // One way of writing a cost, for the same reason. It takes micro-dollars,
  // which is how the build keeps them, and says "—" for a cost that is not
  // known: a session Claude Code recorded nothing for did not cost $0.00.
  // Cents up to a thousand dollars, whole dollars past it; short drops the
  // cents from ten dollars up, for a narrow column.
  function fmtMoney(micro, short) {
    if (micro === null || micro === undefined || micro === "" || isNaN(Number(micro))) return "—";
    // Rounded from the whole micro-dollars, not from a float of dollars:
    // 9.995 as a float is 9.99499…, and would round the wrong way.
    micro = Number(micro);
    if (micro > 0 && micro < 5000) return "<$0.01";
    var cents = Math.round(micro / 1e4);
    if (cents < 100000 && !(short && cents >= 1000)) {
      return "$" + Math.floor(cents / 100) + "." + (cents % 100 < 10 ? "0" : "") + (cents % 100);
    }
    var s = String(Math.round(micro / 1e6)), out = "";
    while (s.length > 3) { out = "," + s.slice(-3) + out; s = s.slice(0, -3); }
    return "$" + s + out;
  }

  // ── the usage week ─────────────────────────────────────
  // Anthropic's weekly allowance resets on a day and hour fixed per account,
  // not on a calendar Monday, so the dashboard's weeks can be anchored to it:
  // "tue 09:00" means a week runs Tuesday 9am to Tuesday 9am, local time.
  var DOW = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6 };

  function parseReset(spec) {
    var m = /^\s*(sun|mon|tue|wed|thu|fri|sat)[a-z]*[\s,]+(\d{1,2})(?::(\d{2}))?\s*$/i
      .exec(String(spec || ""));
    if (!m) return { dow: 1, hour: 0, minute: 0, spec: "mon 00:00" };
    var r = { dow: DOW[m[1].toLowerCase()], hour: +m[2], minute: +(m[3] || 0) };
    r.spec = m[1].toLowerCase() + " " + ("0" + r.hour).slice(-2) + ":" +
             ("0" + r.minute).slice(-2);
    return r;
  }

  // The start of the reset-week containing `date`. Everything is local time,
  // and stepping by whole days keeps the wall-clock hour across a daylight
  // saving change — 9am stays 9am, which is what a reset means.
  function weekStart(date, reset) {
    var s = new Date(date.getTime());
    s.setHours(reset.hour, reset.minute, 0, 0);
    s.setDate(s.getDate() - ((s.getDay() - reset.dow + 7) % 7));
    if (s.getTime() > date.getTime()) s.setDate(s.getDate() - 7);
    return s;
  }

  // ── theme ─────────────────────────────────────────────────────────
  // The pages follow the system appearance; this button lets you insist.
  // auto -> light -> dark -> auto, remembered per browser.
  function themeInit(btn) {
    var KEY = "ch-theme", ORDER = ["auto", "light", "dark"];
    var LABEL = { auto: "\u25d0", light: "\u2600", dark: "\u263e" };
    var cur = "auto";
    try { cur = localStorage.getItem(KEY) || "auto"; } catch (e) {}
    if (ORDER.indexOf(cur) < 0) cur = "auto";
    function apply() {
      if (cur === "auto") document.documentElement.removeAttribute("data-theme");
      else document.documentElement.setAttribute("data-theme", cur);
      if (btn) {
        btn.textContent = LABEL[cur];
        btn.title = "theme: " + cur + (cur === "auto" ? " (follows the system)" : "") +
                    " \u2014 click to change";
      }
    }
    if (btn) btn.addEventListener("click", function () {
      cur = ORDER[(ORDER.indexOf(cur) + 1) % ORDER.length];
      try { localStorage.setItem(KEY, cur); } catch (e) {}
      apply();
    });
    apply();
  }

  // ── tools ─────────────────────────────────────────────────────────

  function toolLabel(name, inp) {
    inp = inp || {};
    switch (name) {
      case "Bash": return inp.description || inp.command || "";
      case "Read": case "Write": case "Edit": case "NotebookEdit":
        return inp.file_path || "";
      case "Grep": return String((inp.pattern || "") + "  " + (inp.path || inp.glob || "")).trim();
      case "Glob": return inp.pattern || "";
      case "WebFetch": case "WebSearch": return inp.url || inp.query || "";
      case "Task": case "Agent":
        return String((inp.description || "") + "  " + (inp.subagent_type || "")).trim();
      case "Skill": return inp.skill || "";
      case "TodoWrite":
        var todos = inp.todos || [];
        var done = todos.filter(function (t) { return t.status === "completed"; }).length;
        return done + "/" + todos.length + " done";
      default: return inp.description || inp.file_path || "";
    }
  }

  // The oldest archives kept a tool's name and nothing else. The arguments
  // cannot be recovered, but the output of the call can, so show that.
  function renderTool(t, result) {
    if (typeof t === "string") {
      if (result && result.trim()) {
        var flat = result.split(/\s+/).join(" ");
        if (flat.length <= 90) {
          return '<div class="tool oldfmt"><span class="tn">' + esc(t) +
                 '</span><span class="td">' + esc(flat) + "</span></div>";
        }
        return '<details class="tool" open><summary><span class="tn">' + esc(t) +
               '</span><span class="td">' + esc(flat.slice(0, 90)) +
               '…</span></summary><pre class="code out">' + esc(cap(result, 6000)) +
               "</pre></details>";
      }
      return '<div class="tool oldfmt"><span class="tn">' + esc(t) +
             '</span><span class="td">arguments and output not recorded</span></div>';
    }

    var name = t.name || "?", inp = t.input || {}, body = "";
    if (name === "Edit" && inp.old_string !== undefined) {
      body = renderDiff(inp.old_string, inp.new_string, inp.file_path);
    } else if (name === "Write") {
      body = '<div class="dp">' + esc(inp.file_path) + '</div><pre class="code">' +
             esc(cap(inp.content, 2000)) + "</pre>";
    } else if (name === "Bash") {
      body = '<pre class="code">' + esc(inp.command) + "</pre>";
    } else if (name === "TodoWrite") {
      body = "<ul>" + (inp.todos || []).map(function (td) {
        return "<li>" + (td.status === "completed" ? "✓" : "·") + " " + esc(td.content) + "</li>";
      }).join("") + "</ul>";
    } else if (Object.keys(inp).length) {
      body = '<pre class="code out">' + esc(JSON.stringify(inp, null, 2).slice(0, 1500)) + "</pre>";
    }
    return '<details class="tool" open' + (t.id ? ' data-tid="' + esc(t.id) + '"' : "") +
           '><summary><span class="tn">' + esc(name) +
           '</span><span class="td">' + esc(toolLabel(name, inp)) + "</span></summary>" +
           body + "</details>";
  }

  // An assistant turn is followed by one result per call, in order, so the run
  // of tool_result messages after it belongs to the calls that made them.
  function pairBareTools(msgs) {
    var paired = {}, consumed = {};
    for (var i = 0; i < msgs.length; i++) {
      var tools = msgs[i].tools || [];
      if (msgs[i].role !== "assistant") continue;
      if (!tools.some(function (t) { return typeof t === "string"; })) continue;
      var found = [], j = i + 1;
      while (j < msgs.length && found.length < tools.length) {
        if (msgs[j].role !== "tool_result") break;
        found.push(msgs[j].text || "");
        consumed[j] = true;
        j++;
      }
      paired[i] = found;
    }
    return { paired: paired, consumed: consumed };
  }

  // ── a session ─────────────────────────────────────────────────────

  function resumable(meta) {
    return meta.kind !== "web" && !!meta.cwd;
  }

  function resumeCmd(meta, home) {
    var cwd = String(meta.cwd || "~");
    if (home && cwd.indexOf(home) === 0) cwd = "~" + cwd.slice(home.length);
    return "cd " + cwd + " && claude --resume " + meta.id;
  }

  // Which message each row shows and which prompt number it carries, worked
  // out once for the whole conversation and cheaply: no HTML is built here.
  // A row is then rendered only when the page needs it, so a long session
  // pays for the rows on screen and not for the fifteen thousand that are not.
  function planRows(msgs) {
    var pair = pairBareTools(msgs), msg = [], prompt = [], n = 0;
    for (var i = 0; i < msgs.length; i++) {
      if (pair.consumed[i]) continue;           // shown inside the call that made it
      var m = msgs[i];
      if (m.role === "user") {
        msg.push(i);
        prompt.push(m.side ? 0 : ++n);
      } else if (m.role === "assistant" || m.role === "system" ||
                 (m.text && m.text.trim())) {
        msg.push(i);
        prompt.push(0);
      }
    }
    return { msg: msg, prompt: prompt, pair: pair };
  }

  function renderRow(msgs, plan, r) {
    var i = plan.msg[r], m = msgs[i], ts = when(m.timestamp), at = ' id="m' + i + '"';
    var side = m.side ? " side" : "";

    if (m.role === "user") {
      if (m.side) {
        return "<div" + at + ' class="m user side"><div class="who">Sub-agent ' +
          '<span class="ts">' + ts + '</span></div><div class="t">' + esc(m.text) + "</div></div>";
      }
      return "<div" + at + ' class="m user prompt" data-p="' + plan.prompt[r] +
        '"><div class="who"><span class="pn">#' + plan.prompt[r] + "</span>You " +
        '<span class="ts">' + ts + '</span></div><div class="t">' + esc(m.text) + "</div></div>";
    }
    if (m.role === "assistant") {
      var inner = "";
      if (m.thinking) {
        inner += '<details class="think" open><summary>thinking</summary><div class="t out">' +
                 esc(cap(m.thinking, 6000)) + "</div></details>";
      }
      if (m.text) inner += markdownish(m.text);
      var got = plan.pair.paired[i] || [], tools = m.tools || [];
      for (var k = 0; k < tools.length; k++) {
        inner += renderTool(tools[k], k < got.length ? got[k] : null);
      }
      var who = m.side ? "Claude (sub-agent)" : "Claude";
      var empty = m.text ? "" : " notext";
      return "<div" + at + ' class="m asst' + side + empty + '"><div class="who">' + who +
        ' <span class="ts">' + ts + "</span></div>" + inner + "</div>";
    }
    if (m.role === "system") {
      return "<div" + at + ' class="m sys"><div class="who">System ' +
        '<span class="ts">' + ts + '</span></div><div class="t">' +
        esc(cap(m.text, 1200)) + "</div></div>";
    }
    return "<details" + at + ' class="m res' + side +
      '" open><summary>output</summary><pre class="code out">' + esc(m.text) + "</pre></details>";
  }

  // Every row at once: what a short conversation, and the tests, want.
  function renderRows(msgs) {
    var plan = planRows(msgs), rows = [];
    for (var r = 0; r < plan.msg.length; r++) rows.push(renderRow(msgs, plan, r));
    return rows;
  }

  // ── a row that is not on the page yet ───────────────────────────
  // A row that has not been rendered still has to take up about the room it
  // will, or the scrollbar lies and everything shifts as the real rows land.
  // These are guesses from the text alone, in pixels, at the page's own type
  // sizes; cpl is how many characters of body text fit on one line. Each
  // guess is replaced by the measured height once the row has been on screen.
  // Two figures, because Conversation mode hides most of what is in a row.
  function linesIn(s, cpl) {
    s = s == null ? "" : String(s);
    if (!s) return 0;
    var n = 0, from = 0, nl;
    while ((nl = s.indexOf("\n", from)) > -1) {
      n += Math.max(1, Math.ceil((nl - from) / cpl));
      from = nl + 1;
    }
    return n + Math.max(1, Math.ceil((s.length - from) / cpl));
  }

  function estimateRow(msgs, plan, r, cpl) {
    var i = plan.msg[r], m = msgs[i], text = m.text || "";
    var cc = Math.round(cpl * 1.2);              // code is set smaller
    var WHO = 27, GAP = 20, LINE = 24, CODE = 18.75, BOX = 32;
    if (m.role === "user") {
      if (m.side) return [GAP + WHO + 4 + LINE * linesIn(text, cpl), GAP + WHO + 4 + LINE * linesIn(text, cpl)];
      var p = GAP + 14 + 25 + WHO + 4 + 25.6 * linesIn(text, Math.round(cpl * 0.94) - 2);
      return [p, p - 8];
    }
    if (m.role === "system") {
      var y = GAP + WHO + 21 * linesIn(cap(text, 1200), Math.round(cpl * 1.15));
      return [y, y];
    }
    if (m.role !== "assistant") {
      return [GAP + 24 + BOX + CODE * linesIn(text, cc), 0];
    }
    var talk = text ? GAP + WHO + LINE * linesIn(text, cpl) + 8 : 0, all = talk || GAP + WHO;
    if (m.thinking) all += 36 + 21.6 * linesIn(cap(m.thinking, 6000), Math.round(cpl * 1.1));
    var got = plan.pair.paired[i] || [], tools = m.tools || [];
    for (var k = 0; k < tools.length; k++) {
      var t = tools[k], h = 30;
      if (typeof t === "string") {
        var res = k < got.length ? got[k] : "";
        if (res && res.length > 90) h += BOX + CODE * linesIn(cap(res, 6000), cc);
      } else {
        var inp = t.input || {};
        if (t.name === "Edit" && inp.old_string !== undefined) {
          h += 30 + 21 * Math.min(40, linesIn(inp.old_string, cc) + linesIn(inp.new_string, cc));
        } else if (t.name === "Write") {
          h += 30 + BOX + CODE * linesIn(cap(inp.content, 2000), cc);
        } else if (t.name === "Bash") {
          h += BOX + CODE * linesIn(inp.command, cc);
        } else if (t.name === "TodoWrite") {
          h += 22 * (inp.todos || []).length + 14;
        } else {
          var keys = 0;
          for (var key in inp) if (Object.prototype.hasOwnProperty.call(inp, key)) keys++;
          if (keys) h += BOX + CODE * Math.min(40, keys + 2);
        }
      }
      all += h;
    }
    return [all, talk];
  }

  // ── find, over rows that may not be on the page ────────────────
  // Find has to count and reach matches in rows the page has not built, so it
  // searches the row's HTML string instead of the DOM. To agree exactly with
  // what the DOM will hold, the text is cut where the DOM would cut it into
  // text nodes — at every tag, joined by a character no search can contain —
  // and read the way the HTML parser reads it. Text inside what Conversation
  // mode hides is kept apart, so each mode counts only what it shows.
  var HIDDEN_CLASS = /(^|\s)(tool|res|think|notext)(\s|$)/;
  var ENTITY = { "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#x27;": "'" };

  function rowText(html) {
    var all = [], talk = [], stack = [], hidden = false, afterPre = false;
    var re = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>/g, last = 0, m;
    function text(s) {
      if (!s) return;
      // The parser drops one newline straight after <pre>, folds CR LF and
      // a lone CR to LF, and turns NUL into U+FFFD.
      if (afterPre && s.charAt(0) === "\n") s = s.slice(1);
      s = s.replace(/&(amp|lt|gt|quot|#x27);/g, function (e) { return ENTITY[e]; })
           .replace(/\r\n?/g, "\n").replace(/\u0000/g, "\ufffd");
      if (!s) return;
      all.push(s);
      if (!hidden) talk.push(s);
    }
    while ((m = re.exec(html)) !== null) {
      text(html.slice(last, m.index));
      last = re.lastIndex;
      if (m[1]) {
        hidden = stack.length ? stack.pop() : false;
        afterPre = false;
      } else {
        stack.push(hidden);
        var cls = /\bclass="([^"]*)"/.exec(m[3]);
        if (cls && HIDDEN_CLASS.test(cls[1])) hidden = true;
        afterPre = m[2].toLowerCase() === "pre";
      }
    }
    text(html.slice(last));
    return { all: all.join("\u0000"), talk: talk.join("\u0000") };
  }

  // Which prompt you are under: the last whose top has reached the line y.
  // Prompts are never hidden and their tops only grow down the page, so it is
  // found by halving. At the very end of the page the last prompts cannot
  // scroll up to that line, and halving would name one above them, so » would
  // read "1 / 2"; there, given view as the [top, bottom] that can be seen, it
  // is a prompt in view — the current one if it is showing, else the last.
  function promptUnder(count, topOf, y, current, view) {
    var lo = 0, hi = count - 1, n = 0;
    while (lo <= hi) {
      var mid = (lo + hi) >> 1;
      if (topOf(mid) <= y) { n = mid; lo = mid + 1; }
      else hi = mid - 1;
    }
    if (!view || !count) return n;
    var seen = function (k) { var t = topOf(k); return t >= view[0] && t < view[1]; };
    if (current >= 0 && current < count && seen(current)) return current;
    for (var k = count - 1; k > n; k--) if (seen(k)) return k;
    return n;
  }

  // Non-overlapping, left to right: the order find steps through them.
  function countIn(hay, needle, limit) {
    if (!needle) return 0;
    var n = 0, at = hay.indexOf(needle);
    while (at > -1 && n < limit) { n++; at = hay.indexOf(needle, at + needle.length); }
    return n;
  }

  // Whether a keypress is the browser's find shortcut that a windowed page
  // should take for its own find: ⌘F on a mac, Ctrl+F elsewhere, nothing
  // added. A short page has every row in the DOM, so the browser's own find
  // sees it all and is left alone. Pressed again while the page's field has
  // focus, it goes to the browser, so its own find is one more press away.
  function ownsFindKey(e, mac, windowed, inField) {
    if (!windowed || inField || e.altKey || e.shiftKey) return false;
    if (mac ? !e.metaKey || e.ctrlKey : !e.ctrlKey || e.metaKey) return false;
    return e.key === "f" || e.key === "F";
  }

  function renderMessages(msgs) { return renderRows(msgs).join(""); }

  function countPrompts(msgs) {
    return msgs.filter(function (m) { return m.role === "user" && !m.side; }).length;
  }

  return {
    esc: esc, cap: cap, when: when, inline: inline, prose: prose,
    markdownish: markdownish, diffOps: diffOps, applyOps: applyOps,
    renderDiff: renderDiff, toolLabel: toolLabel, renderTool: renderTool,
    pairBareTools: pairBareTools, renderMessages: renderMessages,
    renderRows: renderRows, planRows: planRows, renderRow: renderRow,
    estimateRow: estimateRow, linesIn: linesIn, rowText: rowText, countIn: countIn,
    promptUnder: promptUnder, ownsFindKey: ownsFindKey,
    countPrompts: countPrompts, resumable: resumable, resumeCmd: resumeCmd,
    themeInit: themeInit, parseReset: parseReset, weekStart: weekStart,
    fmtTokens: fmtTokens, fmtMoney: fmtMoney
  };
})();

if (typeof module !== "undefined" && module.exports) module.exports = CH;
