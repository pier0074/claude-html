// What tokens cost at list price, from the dated price file (prices.tsv):
// one line per model and per price period, in USD per million tokens. Read
// by the build, which loads it with new Function as it loads parse.js, and
// by the token page, which carries this same file, so a figure on the page
// and one in the index are worked out by the same lines.
//
//   var PR = claudeHtmlPrices(text_of_prices_tsv);
//   PR.cellCost("claude-opus-5-5", "2026-10-21T14", cell)   → micro-dollars, or null
//   PR.total(usage, { since: ms, until: ms })               → { calc, recorded, … }
//
// A usage cell is the build's: [input, output, cache read, cache write,
// replies, of it 1-hour, of it split unknown, (recorded cost)], T below.
// Hours are UTC, "YYYY-MM-DDTHH", as the build keys them. Plain JavaScript,
// the same under osascript, node and a browser, and nothing here reads a
// file or the clock.

function claudeHtmlPrices(text) {
  "use strict";

  // Where each figure of a usage cell is.
  var T = { IN: 0, OUT: 1, READ: 2, WRITE: 3, REPLIES: 4, WRITE_1H: 5, UNSPLIT: 6, COST: 7 };
  var COLUMNS = ["model", "from", "to", "input", "output", "cache_read",
                 "cache_write_5m", "cache_write_1h", "source", "checked"];
  var PRICES = ["input", "output", "cache_read", "cache_write_5m", "cache_write_1h"];
  var DAY = /^\d{4}-\d\d-\d\d$/;

  // A price as written, "0.125", in thousandths of a dollar per million
  // tokens: read from the digits, never through a float, so 0.125 is 125
  // under every engine.
  function milli(s) {
    s = String(s == null ? "" : s).replace(/^\s+|\s+$/g, "");
    if (!/^\d+(\.\d{1,3})?$/.test(s)) return null;
    var p = s.split(".");
    return Number(p[0]) * 1000 + Number(((p[1] || "") + "000").slice(0, 3));
  }

  var lines = [], errors = [], byModel = {};
  String(text == null ? "" : text).split("\n").forEach(function (raw, i) {
    var l = raw.replace(/\r$/, "");
    if (!l.replace(/\s+/g, "") || /^\s*#/.test(l)) return;
    var f = l.split("\t");
    if (f[0] === "model") return;                 // the heading
    var bad = function (why) { errors.push("line " + (i + 1) + ": " + why); };
    if (f.length < 8) return bad("fewer than the 8 columns a price needs");
    var o = { model: f[0].replace(/^\s+|\s+$/g, ""), from: (f[1] || "").trim(), to: (f[2] || "").trim(),
              source: (f[8] || "").trim(), checked: (f[9] || "").trim() };
    if (!o.model) return bad("no model");
    if (!DAY.test(o.from)) return bad("from is not a day (YYYY-MM-DD)");
    if (o.to && (!DAY.test(o.to) || o.to < o.from)) return bad("to is not a day on or after from");
    if (o.checked && !DAY.test(o.checked)) return bad("checked is not a day (YYYY-MM-DD)");
    for (var k = 0; k < PRICES.length; k++) {
      o[PRICES[k]] = milli(f[3 + k]);
      if (o[PRICES[k]] === null) return bad(PRICES[k] + " is not a price");
    }
    o.id = o.model + "@" + o.from;
    var same = byModel[o.model] = byModel[o.model] || [];
    for (var j = 0; j < same.length; j++) {
      var a = same[j];
      if (!(o.to && o.to < a.from) && !(a.to && a.to < o.from)) {
        return bad(o.model + " " + o.from + " overlaps the line from " + a.from);
      }
    }
    same.push(o);
    lines.push(o);
  });
  Object.keys(byModel).forEach(function (m) {
    byModel[m].sort(function (a, b) { return a.from < b.from ? -1 : a.from > b.from ? 1 : 0; });
  });
  var checked = "";
  lines.forEach(function (l) { if (l.checked > checked) checked = l.checked; });

  // The line a model id is priced by: its own, or, for a dated id
  // (claude-haiku-4-5-20251001), the line of the id without the date. A
  // suffix the build added (/fast) stays. Nothing else is guessed: an id
  // with no line is not priced.
  function idOf(model) {
    model = String(model);
    if (byModel.hasOwnProperty(model)) return model;
    var bare = model.replace(/-\d{8}(?=\/|$)/, "");
    return byModel.hasOwnProperty(bare) ? bare : null;
  }
  // Today's line: the open one, or the last there is.
  function current(model) {
    var id = idOf(model);
    if (id === null) return null;
    var ls = byModel[id];
    for (var i = 0; i < ls.length; i++) if (!ls[i].to) return ls[i];
    return ls[ls.length - 1];
  }
  // The line in force at an hour: the one whose from..to (whole UTC days,
  // both included) holds its day. Before the first line, or in a gap,
  // there is none. today: today's line instead, whenever the hour was.
  function lineAt(model, hour, today) {
    if (today) return current(model);
    var id = idOf(model);
    if (id === null) return null;
    var day = String(hour).slice(0, 10), ls = byModel[id];
    for (var i = 0; i < ls.length; i++) {
      if (ls[i].from <= day && (!ls[i].to || day <= ls[i].to)) return ls[i];
    }
    return null;
  }

  function tokens(t) {
    return (Number(t[0]) || 0) + (Number(t[1]) || 0) + (Number(t[2]) || 0) + (Number(t[3]) || 0);
  }
  // A cell at a line's prices, in micro-dollars: tokens times dollars per
  // million is micro-dollars, and with the prices in thousandths the sum is
  // whole until the one rounding at the end. A write of unknown duration is
  // priced as a 5-minute one.
  function priceCell(line, t) {
    var write = Number(t[T.WRITE]) || 0;
    var hour1 = Math.min(write, Number(t[T.WRITE_1H]) || 0);
    var sum = (Number(t[T.IN]) || 0) * line.input + (Number(t[T.OUT]) || 0) * line.output +
              (Number(t[T.READ]) || 0) * line.cache_read +
              (write - hour1) * line.cache_write_5m + hour1 * line.cache_write_1h;
    return Math.round(sum / 1000);
  }
  function cellCost(model, hour, t, today) {
    var line = lineAt(model, hour, today);
    return line ? priceCell(line, t) : null;
  }

  // Every cell of a usage ({hour: {model: cell}}) whose hour starts in
  // [since, until), both in ms and either left out for no bound. calc is
  // the calculated cost of what could be priced; unpriced counts the
  // tokens that could not, by model; recorded is Claude Code's own cost
  // over the same cells, null when no cell has one; unsplit, the cache
  // writes of unknown duration among them. Kept apart, never added up.
  function total(usage, opts) {
    opts = opts || {};
    var out = { calc: 0, priced: 0, unpriced: 0, unpricedBy: {}, recorded: null, unsplit: 0 };
    Object.keys(usage || {}).forEach(function (hour) {
      var at = Date.parse(hour + ":00:00Z");
      if (isNaN(at)) return;
      if (opts.since != null && at < opts.since) return;
      if (opts.until != null && at >= opts.until) return;
      Object.keys(usage[hour]).forEach(function (m) {
        var t = usage[hour][m], c = cellCost(m, hour, t, opts.today), n = tokens(t);
        if (t.length > T.COST && t[T.COST] != null) out.recorded = (out.recorded || 0) + Number(t[T.COST]);
        out.unsplit += Number(t[T.UNSPLIT]) || 0;
        if (c === null) {
          if (n) { out.unpriced += n; out.unpricedBy[m] = (out.unpricedBy[m] || 0) + n; }
          return;
        }
        out.calc += c;
        out.priced += n;
      });
    });
    return out;
  }

  // The hour key of a moment, as the build files it.
  function hourKey(ms) { return new Date(ms).toISOString().slice(0, 13); }

  return {
    T: T, COLUMNS: COLUMNS, lines: lines, errors: errors, checked: checked,
    models: function () { return Object.keys(byModel).sort(); },
    history: function (id) { return (byModel[id] || []).slice(); },
    idOf: idOf, current: current, lineAt: lineAt,
    priceCell: priceCell, cellCost: cellCost, total: total, tokens: tokens, hourKey: hourKey
  };
}
