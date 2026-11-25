// The Settings page's script, run against a stand-in document: what it
// draws for the guard's safe values, the own list, the status line and
// the Limits & budget panel, and the link and command a click makes.
// No browser: each element is a record of what was written into it.
//
//   node tests/settingspage.test.js
"use strict";
var fs = require("fs"), path = require("path"), vm = require("vm");
var HERE = path.resolve(__dirname, "..");
var check = require("./lib.js").checkEq;
function src(f) { return fs.readFileSync(path.join(HERE, f), "utf8"); }

// ── a stand-in document ──────────────────────────────────────────────
function El(id) {
  var e = { id: id, innerHTML: "", textContent: "", hidden: false, style: {}, disabled: false, href: "", attrs: {}, ev: {},
    classList: { toggle: function (c, on) { e.cls[c] = on; }, contains: function (c) { return !!e.cls[c]; } }, cls: {},
    setAttribute: function (k, v) { e.attrs[k] = v; }, getAttribute: function (k) { return e.attrs[k]; }, removeAttribute: function (k) { delete e.attrs[k]; },
    addEventListener: function (t, f) { (e.ev[t] = e.ev[t] || []).push(f); },
    contains: function () { return false; }, parentNode: { replaceChild: function () {} },
    kids: {}, querySelector: function (sel) { return e.kids[sel] || (e.kids[sel] = El(id + " " + sel)); } };
  return e;
}
function page(data) {
  var els = {}, doc = {
    getElementById: function (id) {
      if (!els[id]) { els[id] = El(id); if (id === "settings-data") els[id].textContent = JSON.stringify(data); }
      return els[id];
    },
    addEventListener: function () {}, activeElement: null, documentElement: El("html"), body: El("body")
  };
  // The groups' root finds nothing drawn in it: no input to refocus, no
  // folded list to keep open.
  var ctx = { document: doc, window: {}, navigator: { clipboard: { writeText: function () { return { then: function () {} }; } } },
    localStorage: { getItem: function () { return null; }, setItem: function () {}, removeItem: function () {}, key: function () { return null; }, length: 0 },
    location: { pathname: "/Users/you/code/claude-html/settings.html" }, setTimeout: setTimeout, console: console };
  ctx.window = ctx; vm.createContext(ctx);
  ["viewer/viewer.js", "viewer/plan.js", "build/settings.js", "build/statusline.js", "viewer/settings.js"].forEach(function (f) {
    vm.runInContext(src(f).replace(/if \(typeof module[^\n]*\n?$/, ""), ctx, { filename: f });
  });
  var groups = els.groups;
  groups.querySelector = function () { return null; };
  return {
    els: els, html: function () { return els.groups.innerHTML; },
    click: function (attrs, id) {
      var t = { id: id || "", disabled: false, attrs: attrs,
        matches: function (sel) { return sel === ".seg button[data-k]" ? "data-k" in attrs : false; },
        hasAttribute: function (k) { return k in attrs; }, getAttribute: function (k) { return attrs[k]; } };
      els.groups.ev.click.forEach(function (f) { f({ target: t }); });
    },
    link: function () { return els.bapply.href; }, command: function () { return els.bcopy.attrs["data-c"]; }
  };
}

var FP = "0123456789abcdef";
var base = {
  desc: src("lib/settings.tsv"), actions: true, home: "/Users/you", root: "/Users/you/code", here: "/Users/you/code/claude-html",
  values: { CLAUDE_HTML_LIMIT_RULES: { v: "fri 20:00 80%", src: "conf" }, CLAUDE_HTML_BUDGET_WARN: { v: "70 90", src: "environment" } },
  shell: { fp: FP, conf: "/Users/you/.claude/claude-html.conf", here: "/Users/you/code/claude-html", version: "3.7.0", engine: { name: "node" }, os: "darwin" },
  redact: { on: true, exists: true, own: 2, safe: 3, ignored: 0,
            safeList: [{ id: "f4a87185", kind: "github", date: "2026-11-19" }, { id: "03bd3e9f", kind: "jwt", date: "2026-11-20" },
                       { id: "9c0e1a77", kind: "", date: "" }] },
  update: { installed: "3.7.0" }, hooks: null,
  limits: { on: true, rules: [{ day: "fri", time: "20:00", pct: 80, start: 1 }], budget: null, warn: [70, 90], notify: false,
            week: { reset: 2000000000 }, plan: null, now: 1900000000 }
};
var P = page(base), H = P.html();

// ── the guard's safe values ──────────────────────────────────────────
check("each safe value: its kind, its date and its id, with forget beside it",
  ["github", "2026-11-19", "f4a87185", "jwt", "03bd3e9f"].every(function (w) { return H.indexOf(w) > -1; }) +
  " " + (H.match(/data-forget="/g) || []).length, "true 3");
check("  a line without a kind: kind unknown", /<span class="sk2">kind unknown<\/span><span class="sdt"><\/span><code class="sid"[^>]*>9c0e1a77/.test(H), true);
check("  folded in a details, its summary the count", /<details class="safe"><summary>3 safe values<\/summary>/.test(H), true);
P.click({ "data-forget": "03bd3e9f" });
check("forget one: the link names its id alone", P.link(), "claude-html://settings/v1/" + FP + "/forget-safe=03bd3e9f");
check("  the command the same", P.command(), "claude-html --config forget-safe 03bd3e9f");
check("  marked in the list, the list left open", /<li class="gone"><span class="sk2">jwt/.test(P.html()) + " " + /<details class="safe" open>/.test(P.html()), "true true");
P.click({ "data-forget": "9c0e1a77" });
check("  two: both, in the order of the clicks", P.link(), "claude-html://settings/v1/" + FP + "/forget-safe=03bd3e9f/forget-safe=9c0e1a77");
P.click({ "data-forget": "03bd3e9f" });
check("  clicked again: kept", P.link(), "claude-html://settings/v1/" + FP + "/forget-safe=9c0e1a77");
P.click({}, "forget");
check("forget them all: one change, the ids gone", P.link(), "claude-html://settings/v1/" + FP + "/forget-safe");

// ── the own list ─────────────────────────────────────────────────────
P = page(base); H = P.html();
check("the own list: its count, never its contents, and edit through the settings link",
  /2 entries in the list \(what it says is never shown\)<\/p><p class="sx"><a class="go" href="claude-html:\/\/settings\/v1\/0123456789abcdef\/edit-list"/.test(H), true);
check("  and the command beside it", H.indexOf('data-c="claude-html --config edit-list"') > -1, true);
var noact = JSON.parse(JSON.stringify(base)); noact.actions = false;
check("  no link handler here: the command only", /edit-list"/.test(page(noact).html().replace('data-c="claude-html --config edit-list"', "")), false);

// ── the Limits & budget group ────────────────────────────────────────
check("Limits: the four read-only rows are gone", H.indexOf("set in the panel above") + " " +
  ["CLAUDE_HTML_LIMIT_RULES", "CLAUDE_HTML_BUDGET_WARN", "CLAUDE_HTML_LIMIT_NOTIFY"].map(function (k) {
    return H.indexOf('data-row="' + k + '"'); }).join(" "), "-1 -1 -1 -1");
var lb = P.els.limits.kids[".lb"].innerHTML;
check("  the panel's rows say where each value comes from, and link to SETUP.md",
  (lb.match(/<span class="lm"><div class="sm">/g) || []).length + " " + (lb.match(/SETUP\.md#limits-and-budget/g) || []).length, "4 4");
check("  rules from the conf, warnings from the environment, budget and banner the default",
  (lb.match(/badge (conf|environment|default)/g) || []).join(","), "badge conf,badge default,badge environment,badge default");
check("  the environment said, as on any other row", /CLAUDE_HTML_BUDGET_WARN set in the environment this page was built in/.test(H), true);

// ── the status line ──────────────────────────────────────────────────
check("Status line: the items, those on first, in order", (H.match(/data-sli="(\w+)" data-do="toggle" aria-pressed="(true|false)"/g) || [])
  .map(function (x) { var m = /"(\w+)".*"(true|false)"/.exec(x); return m[1] + (m[2] === "true" ? "+" : "-"); }).join(" "),
  "five+ week+ stop+ budget+ session- today- ctx- model- project-");
check("  the model labelled Agent", /<span class="sln">Agent<\/span><code class="slk">model<\/code>/.test(H), true);
check("  the preview, as it fits 100 columns: the line of the defaults",
  H.indexOf("as it fits 100 columns") > -1 && H.indexOf('<code class="term"><span class="sl-d">plan</span> <span class="sl-d">·</span> 5 h <span class="sl-g">██████░░░░ 62 %</span>') > -1, true);
P.click({ "data-sli": "ctx", "data-do": "toggle" });
check("turn ctx on: the items set, in the link and the command", P.link() + " | " + P.command(),
  "claude-html://settings/v1/" + FP + "/STATUSLINE_ITEMS=five%20week%20stop%20budget%20ctx | claude-html --config set 'STATUSLINE_ITEMS=five week stop budget ctx'");
P.click({ "data-sli": "ctx", "data-do": "up" });
P.click({ "data-sli": "five", "data-do": "down" });
check("  moved up, and the 5-hour window down", P.link(), "claude-html://settings/v1/" + FP + "/STATUSLINE_ITEMS=week%20five%20stop%20ctx%20budget");
check("  the preview follows", P.html().indexOf("ctx <span class=\"sl-g\">41 %</span>") > -1, true);
P.click({ "data-sli": "ctx", "data-do": "toggle" }); P.click({ "data-sli": "five", "data-do": "up" });
check("  back as it was: no change left", P.els.bar.hidden, true);
["five", "week", "stop", "budget"].forEach(function (i) { P.click({ "data-sli": i, "data-do": "toggle" }); });
check("  all off: none", P.link(), "claude-html://settings/v1/" + FP + "/STATUSLINE_ITEMS=none");
P = page(base);
P.click({ "data-k": "CLAUDE_HTML_STATUSLINE_FORM", "data-v": "condensed" });
check("condensed chosen: the preview's first line condensed", /<code class="term">5h:<span class="sl-g">62%<\/span>/.test(P.html()), true);

// The colours: one row of buttons, a dot before each fixed one's name.
P = page(base); H = P.html();
var row = /<span class="seg colors"[^>]*>([\s\S]*?)<\/span><\/div>/.exec(H);
check("Colours: one row, auto, level (on), then the terminal's colours, each fixed one with its dot",
  row && (row[1].match(/data-v="(\w+)"/g) || []).map(function (x) { return x.slice(8, -1); }).join(" ") + " | " +
  (row[1].match(/<i class="sw sl-\w+"/g) || []).length + " | " + /data-v="level" class="on"/.test(row[1]),
  "auto level green cyan blue magenta yellow red grey | 7 | true");
P.click({ "data-k": "CLAUDE_HTML_STATUSLINE_COLOR", "data-v": "cyan" });
check("  cyan chosen: the preview's figures in it, the link the setting", /<span class="sl-cyan">██████░░░░ 62 %<\/span>/.test(P.html()) + " " + P.link(),
  "true claude-html://settings/v1/" + FP + "/STATUSLINE_COLOR=cyan");
P.click({ "data-k": "CLAUDE_HTML_STATUSLINE_COLOR", "data-v": "auto" });
check("  auto: no colour on a figure", /<span class="sl-(g|a|r|cyan)">/.test(P.html().split('id="slpreview"')[1]), false);
var old = JSON.parse(JSON.stringify(base)); old.values.CLAUDE_HTML_STATUSLINE_COLOR = { v: "off", src: "conf" };
check("  off in the conf, from an earlier 3.7.0: shown as auto", /data-v="auto" class="on"/.test(page(old).html()), true);

require("./lib.js").done();
