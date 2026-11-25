// The status line as statusline.sh draws it, for the Settings page's
// preview: the same items, forms, bar, colours and fitting, from figures
// already worked out. statusline.sh is what Claude Code runs (bash and its
// builtins only); this is its twin in JavaScript, and the tests hold the
// two to the same line for the same figures and settings.
//
//   var SL = claudeHtmlStatusline();
//   SL.settings(values)          the settings from their conf values ("" = default)
//   SL.render(settings, data)    {text, html, normal, condensed}: the line as
//                                it would be, as text and as HTML with the colours
//   SL.model(id, displayName)    {normal, condensed}: Opus 5.5 / Op5.5
//
// data: {mode: "plan"|"budget"|"none", five: {tenths, label}, week: {tenths,
// label}, stop: {pct, from, hit}, session: "$1.12", today: "$8.40",
// ctx: tenths, model: {id, name}, project: {name, branch}, budget: {known,
// period, spent, spentMicro, amount, tenths, label, unit}, updated: "3.7.1"}.
function claudeHtmlStatusline() {
  "use strict";
  var ITEMS = ["five", "week", "session", "today", "ctx", "model", "project", "stop", "budget"];
  var DEFAULT = ["five", "week", "stop", "budget"];
  var COLORS = ["auto", "level", "green", "cyan", "blue", "magenta", "yellow", "red", "grey"];
  var FIXED = COLORS.slice(2);

  function settings(v) {
    v = v || {};
    var s = { items: null, form: "auto", width: 100, bar: 10, from: 0, color: "level" };
    var raw = String(v.items || "").toLowerCase().replace(/,/g, " ").trim();
    if (raw) {
      s.items = [];
      raw.split(/\s+/).forEach(function (i) { if (ITEMS.indexOf(i) > -1 && s.items.indexOf(i) < 0) s.items.push(i); });
    }
    var f = String(v.form || "").toLowerCase();
    if (f === "normal" || f === "condensed") s.form = f;
    if (/^([2-9]\d|[1-3]\d\d|400)$/.test(String(v.width || ""))) s.width = +v.width;
    if (/^(5|20)$/.test(String(v.bar || ""))) s.bar = +v.bar;
    if (/^(\d|[1-9]\d|100)$/.test(String(v.from || ""))) s.from = +v.from;
    // level, auto (no colour: the terminal's own), or one basic colour;
    // on and off, from an earlier 3.7.0, are level and auto.
    var c = String(v.color || "").toLowerCase();
    if (/^(auto|off|0|no|false)$/.test(c)) s.color = "";
    else if (FIXED.indexOf(c) > -1 || c === "gray") s.color = c === "gray" ? "grey" : c;
    if (v.columns && /^\d{2,4}$/.test(String(v.columns)) && +v.columns - 4 < s.width) s.width = +v.columns - 4;
    return s;
  }

  // claude-opus-5-5 is Opus 5.5 (Op5.5); claude-3-5-sonnet-20241022 Sonnet 3.5.
  function model(id, dn) {
    var fam = "", ver = "", ok = true;
    String(id || "").replace(/\[.*$/, "").replace(/^claude-/, "").split("-").forEach(function (t) {
      if (!ok || !t) return;
      if (/^\d{1,2}$/.test(t)) ver += (ver ? "." : "") + t;
      else if (/^\d{8}$/.test(t)) return;
      else if (/[^a-z]/.test(t)) { fam = ""; ver = ""; ok = false; }
      else if (fam) { fam = ""; ok = false; }
      else fam = t;
    });
    if (ok && fam && ver) { var u = fam.charAt(0).toUpperCase() + fam.slice(1); return { normal: u + " " + ver, condensed: u.slice(0, 2) + ver }; }
    dn = String(dn || "").replace(/[\u0000-\u001f\u007f]/g, "");
    if (dn) return { normal: dn.slice(0, 16), condensed: dn.replace(/ /g, "").slice(0, 6) };
    return null;
  }

  // "16:30" stays; "Tue 08:00" is "Tu08", "Tue 08:30" "Tu08:30".
  function short(l) {
    var m = /^(\S{3}) (\d\d):(\d\d)$/.exec(l || "");
    if (!m) return l || "";
    return m[1].slice(0, 2) + m[2] + (m[3] === "00" ? "" : ":" + m[3]);
  }

  // A piece of the line: its text, and its colour (g, a, r, d, a fixed
  // colour's name, or none).
  function P(t, c) { return { t: t, c: c || "" }; }
  function level(s, tenths) {
    if (!s.color) return "";
    if (s.color !== "level") return s.color;
    return tenths >= 950 ? "r" : tenths >= 800 ? "a" : "g";
  }
  function bar(s, tenths) {
    var t = Math.max(0, Math.min(1000, tenths)), halves = Math.floor(t * s.bar / 500), full = Math.floor(halves / 2), out = "", i = 0;
    for (; i < full; i++) out += "█";
    if (halves % 2) { out += "▌"; i++; }
    for (; i < s.bar; i++) out += "░";
    return out;
  }
  function round(tenths) { return Math.floor((tenths + 5) / 10); }
  function win(s, nl, cl, tenths, label) {
    var r = round(tenths), c = level(s, tenths);
    var n = [P(nl + " "), P((r >= s.from ? bar(s, tenths) + " " : "") + r + " %", c)];
    if (label) n.push(P(" "), P("↻" + label, "d"));
    var k = [P(cl + ":"), P(r + "%", c)];
    if (label) k.push(P(" "), P("↻" + short(label), "d"));
    return { n: n, k: k };
  }

  function other(s, d, i) {
    switch (i) {
      case "session": return d.session ? { n: [P("this session " + d.session)], k: [P("ses" + d.session)] } : null;
      case "today": return d.today ? { n: [P("today " + d.today)], k: [P("today" + d.today)] } : null;
      case "ctx":
        if (typeof d.ctx !== "number") return null;
        var r = round(d.ctx), c = level(s, d.ctx);
        return { n: [P("ctx "), P(r + " %", c)], k: [P("ctx"), P(r + "%", c)] };
      case "model":
        var m = d.model && model(d.model.id, d.model.name);
        return m ? { n: [P(m.normal)], k: [P(m.condensed)] } : null;
      case "project":
        var p = d.project;
        if (!p || !p.name) return null;
        return { n: [P(p.name + (p.branch ? " · " + p.branch : ""))], k: [P(p.name.slice(0, 2) + (p.branch ? "." + p.branch : ""))] };
    }
    return null;
  }

  function parts(s, d) {
    var list = s.items || DEFAULT, out = [], prefix = d.mode === "plan" ? "plan" : d.mode === "budget" ? "budget" : "claude-html";
    function add(x) { if (x) out.push(x); }
    if (d.mode === "plan") {
      list.forEach(function (i) {
        if (i === "five" && d.five) add(win(s, "5 h", "5h", d.five.tenths, d.five.label));
        else if (i === "week" && d.week) add(win(s, "week", "wk", d.week.tenths, d.week.label));
        else if (i === "stop" && d.week && d.stop) {
          var c = s.color === "level" && d.stop.hit ? "a" : "";
          add({ n: [P("stop at " + d.stop.pct + " % from " + d.stop.from, c)], k: [P("stop" + d.stop.pct + "%", c)] });
        } else if (["five", "week", "stop", "budget"].indexOf(i) < 0) add(other(s, d, i));
      });
    } else if (d.mode === "budget") {
      (s.items ? list : list.concat(["session"])).forEach(function (i) {
        if (i === "budget" && d.budget) {
          var b = d.budget;
          if (b.known) {
            var r = round(b.tenths), c = level(s, b.tenths);
            add({ n: [P(b.period + " " + b.spent + " of $" + b.amount + " "), P((r >= s.from ? bar(s, b.tenths) + " " : "") + r + " %", c),
                      P(" "), P("↻" + b.label, "d")],
                  k: [P("$" + Math.floor(b.spentMicro / 1e6) + "/" + String(b.amount).split(".")[0], c)] });
          } else {
            add({ n: [P("$" + b.amount + " per " + b.unit + ", no total yet: claude-html counts it at the next save")],
                  k: [P("$?/" + String(b.amount).split(".")[0])] });
          }
        } else if (["five", "week", "stop", "budget"].indexOf(i) < 0) add(other(s, d, i));
      });
    } else {
      list.forEach(function (i) { if (["five", "week", "stop", "budget"].indexOf(i) < 0) add(other(s, d, i)); });
      if (!out.length && !s.items) add(other(s, d, "session"));
    }
    if (d.updated) out.push({ n: [P("updated to " + d.updated, "d")], k: [P("↑" + d.updated, "d")] });
    return { prefix: prefix, parts: out };
  }
  function width(ps) { return ps.reduce(function (n, p) { return n + Array.from(p.t).length; }, 0); }

  // The line in a form: k items condensed from the end, the prefix dropped or not.
  function compose(x, k, drop) {
    var n = x.parts.length, out = drop ? [] : [P(x.prefix, "d")];
    x.parts.forEach(function (p, i) {
      if (out.length) out.push(P(" "), P("·", "d"), P(" "));
      out = out.concat(i >= n - k ? p.k : p.n);
    });
    return out;
  }
  function fit(s, x) {
    var n = x.parts.length;
    if (s.form === "normal") return compose(x, 0, false);
    if (s.form === "condensed") return compose(x, n, n > 0);
    for (var k = 0; k <= n; k++) { var l = compose(x, k, false); if (width(l) <= s.width) return l; }
    return compose(x, n, n > 0);
  }
  function text(ps) { return ps.map(function (p) { return p.t; }).join(""); }
  function html(ps) {
    var esc = function (t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); };
    return ps.map(function (p) { return p.c ? '<span class="sl-' + p.c + '">' + esc(p.t) + "</span>" : esc(p.t); }).join("");
  }
  function render(s, d) {
    var x = parts(s, d), l = fit(s, x), n = x.parts.length;
    return { text: text(l), html: html(l), width: width(l),
             normal: text(compose(x, 0, false)), condensed: text(compose(x, n, n > 0)),
             normalHtml: html(compose(x, 0, false)), condensedHtml: html(compose(x, n, n > 0)) };
  }
  return { ITEMS: ITEMS, DEFAULT: DEFAULT, settings: settings, render: render, model: model, short: short };
}

if (typeof module !== "undefined" && module.exports) module.exports = claudeHtmlStatusline;
