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

  function renderMessages(msgs) {
    var pair = pairBareTools(msgs), rows = [], promptN = 0;
    for (var i = 0; i < msgs.length; i++) {
      if (pair.consumed[i]) continue;           // shown inside the call that made it
      var m = msgs[i], ts = when(m.timestamp), at = ' id="m' + i + '"';
      var side = m.side ? " side" : "";

      if (m.role === "user") {
        if (m.side) {
          rows.push("<div" + at + ' class="m user side"><div class="who">Sub-agent ' +
            '<span class="ts">' + ts + '</span></div><div class="t">' + esc(m.text) + "</div></div>");
        } else {
          promptN++;
          rows.push("<div" + at + ' class="m user prompt" data-p="' + promptN +
            '"><div class="who"><span class="pn">#' + promptN + "</span>You " +
            '<span class="ts">' + ts + '</span></div><div class="t">' + esc(m.text) + "</div></div>");
        }
      } else if (m.role === "assistant") {
        var inner = "";
        if (m.thinking) {
          inner += '<details class="think" open><summary>thinking</summary><div class="t out">' +
                   esc(cap(m.thinking, 6000)) + "</div></details>";
        }
        if (m.text) inner += markdownish(m.text);
        var got = pair.paired[i] || [], tools = m.tools || [];
        for (var k = 0; k < tools.length; k++) {
          inner += renderTool(tools[k], k < got.length ? got[k] : null);
        }
        var who = m.side ? "Claude (sub-agent)" : "Claude";
        var empty = m.text ? "" : " notext";
        rows.push("<div" + at + ' class="m asst' + side + empty + '"><div class="who">' + who +
          ' <span class="ts">' + ts + "</span></div>" + inner + "</div>");
      } else if (m.role === "system") {
        rows.push("<div" + at + ' class="m sys"><div class="who">System ' +
          '<span class="ts">' + ts + '</span></div><div class="t">' +
          esc(cap(m.text, 1200)) + "</div></div>");
      } else if (m.text && m.text.trim()) {
        rows.push("<details" + at + ' class="m res' + side +
          '" open><summary>output</summary><pre class="code out">' + esc(m.text) + "</pre></details>");
      }
    }
    return rows.join("");
  }

  function countPrompts(msgs) {
    return msgs.filter(function (m) { return m.role === "user" && !m.side; }).length;
  }

  return {
    esc: esc, cap: cap, when: when, inline: inline, prose: prose,
    markdownish: markdownish, diffOps: diffOps, applyOps: applyOps,
    renderDiff: renderDiff, toolLabel: toolLabel, renderTool: renderTool,
    pairBareTools: pairBareTools, renderMessages: renderMessages,
    countPrompts: countPrompts, resumable: resumable, resumeCmd: resumeCmd,
    themeInit: themeInit
  };
})();

if (typeof module !== "undefined" && module.exports) module.exports = CH;
