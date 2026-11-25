// The token dashboard. The data is project -> UTC hour -> model -> [input,
// output, cache read, cache write, replies, of the write 1-hour, of the
// write split unknown, cost]; everything on the page is an aggregate of
// that, converted to local time here, and the period buttons decide how
// wide a bucket is. The cost, in micro-dollars, is there only where Claude
// Code recorded one: a cell of seven figures has none. Beside it, never
// added to it, the calculated cost: the tokens at the price file's lines
// (prices.js, the build's own), of their hour or of today.
//
// Hours, not days, because a usage week can start at 9am — and because a
// record at 23:00 UTC already belongs to the next day in most of Europe.
(function () {
  "use strict";

  CH.themeInit(document.getElementById("theme"));

  var data = JSON.parse(document.getElementById("usage-data").textContent) || {};
  // The plan line and the Limits & budget section (plan.js), whatever the
  // usage below holds.
  if (typeof CHPlan !== "undefined") { CHPlan.mount(data); CHPlan.copyButtons(); }
  var byProject = data.byProject || {};
  var projects = Object.keys(byProject);

  var esc = CH.esc, fmt = CH.fmtTokens, money = CH.fmtMoney;
  // A sum: the seven figures of a cell, then the recorded cost, the
  // calculated one and the tokens no price line covers. Both costs start
  // as null, not 0: a sum that no known cost went into is unknown, and must
  // read "—" rather than "$0.00".
  var COLS = 7, REC = 7, CALC = 8, MISS = 9;
  function zero() { return [0, 0, 0, 0, 0, 0, 0, null, null, 0]; }
  function add(into, from) {
    for (var i = 0; i < COLS; i++) into[i] += from[i] || 0;
    [REC, CALC].forEach(function (k) {
      if (from[k] !== null && from[k] !== undefined) into[k] = (into[k] || 0) + from[k];
    });
    into[MISS] += from[MISS] || 0;
  }
  function cost(t) { return t[REC] === null || t[REC] === undefined ? null : t[REC]; }
  function calc(t) { return t[CALC] === null || t[CALC] === undefined ? null : t[CALC]; }

  // The price file, read by the build's own prices.js; none, and the page
  // shows what was recorded alone.
  var PR = typeof claudeHtmlPrices === "function" && typeof data.prices === "string"
    ? claudeHtmlPrices(data.prices) : null;
  var priceAt = "then";
  priceAt = CH.pref("prices", "then");
  if (!/^(then|now)$/.test(priceAt)) priceAt = "then";
  // Tokens only: the fifth column counts replies and must never be summed in.
  function total(t) { return t[0] + t[1] + t[2] + t[3]; }

  function shortModel(m) { return String(m).replace(/^claude-/, "").replace(/-20\d{6}$/, ""); }

  var reset = CH.parseReset(data.weekReset);
  function pad(n) { return (n < 10 ? "0" : "") + n; }
  function ymd(d) {
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
  }
  function ymdhm(d) { return ymd(d) + " " + pad(d.getHours()) + ":" + pad(d.getMinutes()); }

  // ── flatten once; every view is a regrouping of these ──────────────
  var rows = [];                       // {at: local Date, model, project, t}
  projects.forEach(function (p) {
    Object.keys(byProject[p]).forEach(function (hour) {
      var at = new Date(hour + ":00:00Z");          // the key is UTC
      if (isNaN(at.getTime())) return;
      Object.keys(byProject[p][hour]).forEach(function (m) {
        var c = byProject[p][hour][m], t = zero();
        for (var i = 0; i < COLS; i++) t[i] = Number(c[i]) || 0;
        if (c.length > REC && c[REC] !== null) t[REC] = Number(c[REC]) || 0;
        rows.push({ at: at, hour: hour, model: m, project: p, t: t });
      });
    });
  });
  // Nothing to chart: the sentence that says so, and not an empty chart over
  // two tables of headings.
  if (!rows.length) {
    document.getElementById("empty").hidden = false;
    document.getElementById("dash").hidden = true;
    return;
  }
  // Each cell's calculated cost, at the price of its hour or at today's.
  function reprice() {
    rows.forEach(function (r) {
      var c = PR ? PR.cellCost(r.model, r.hour, r.t, priceAt === "now") : null;
      r.t[CALC] = c;
      r.t[MISS] = c === null ? total(r.t) : 0;
    });
  }
  reprice();
  var allDays = rows.map(function (r) { return ymd(r.at); }).sort();
  var firstDay = allDays[0], lastDay = allDays[allDays.length - 1];
  // The calendar from the first day to the last, not the days that had
  // anything: three active days a month apart are two months of history.
  var spanDays = Math.round((startOf(lastDay) - startOf(firstDay)) / 864e5) + 1;

  // Models in a fixed order — biggest first — so a model keeps its colour
  // across every view and the legend never shuffles.
  var modelTotals = {};
  rows.forEach(function (r) {
    modelTotals[r.model] = (modelTotals[r.model] || 0) + total(r.t);
  });
  var models = Object.keys(modelTotals).sort(function (a, b) {
    return modelTotals[b] - modelTotals[a];
  });
  var colour = {};
  models.forEach(function (m, i) { colour[m] = "var(--m" + ((i % 6) + 1) + ")"; });

  // The same numbers can be split by model or by project; everything that
  // draws asks the dimension what the parts are and what colour each is.
  var projectTotals = {};
  rows.forEach(function (r) {
    projectTotals[r.project] = (projectTotals[r.project] || 0) + total(r.t);
  });
  var projectOrder = Object.keys(projectTotals).sort(function (a, b) {
    return projectTotals[b] - projectTotals[a];
  });
  var projectColour = {};
  projectOrder.forEach(function (k, i) { projectColour[k] = "var(--m" + ((i % 6) + 1) + ")"; });

  var DIMS = {
    model: { of: function (r) { return r.model; }, parts: models,
             colour: colour, name: shortModel, heading: "Model", all: "all models" },
    project: { of: function (r) { return r.project; }, parts: projectOrder,
               colour: projectColour, name: function (k) { return k; },
               heading: "Project", all: "all projects" }
  };
  var dimName = "model";
  dimName = CH.pref("breakdown", "model");
  if (!DIMS[dimName]) dimName = "model";
  function dim() { return DIMS[dimName]; }

  // ── the filter ─────────────────────────────────────────────────────
  // A model, a project, or one of each. It is a narrowing of the rows, not a
  // view of its own, so it outlives a change of period or breakdown, and
  // every number on the page passes through the same keep().
  var FILTER_KEY = "ch-usage-filter";
  var filter = {};
  try { filter = JSON.parse(localStorage.getItem(FILTER_KEY) || "{}") || {}; } catch (e) {}
  function keep(r) {
    return (!filter.model || r.model === filter.model) &&
           (!filter.project || r.project === filter.project);
  }
  // What was stored may name a model or project whose transcripts have since
  // gone; a filter that matches nothing would leave the page blank, so it
  // drops itself instead.
  function sanitise(f) {
    var out = {};
    if (f && typeof f.model === "string" && modelTotals.hasOwnProperty(f.model)) out.model = f.model;
    if (f && typeof f.project === "string" && projectTotals.hasOwnProperty(f.project)) out.project = f.project;
    return out;
  }
  function saveFilter() {
    try {
      if (filter.model || filter.project) localStorage.setItem(FILTER_KEY, JSON.stringify(filter));
      else localStorage.removeItem(FILTER_KEY);
    } catch (e) {}
  }
  filter = sanitise(filter);
  if (!rows.some(keep)) filter = {};
  saveFilter();

  // Clicking a name filters to it; clicking the one already chosen lets go.
  // A model the chosen project never used would empty the page, so that
  // click starts a fresh filter rather than combining with the old one.
  function toggle(key, value) {
    if (filter[key] === value) delete filter[key];
    else {
      filter[key] = value;
      if (!rows.some(keep)) { filter = {}; filter[key] = value; }
    }
    saveFilter();
    draw();
  }

  // A name that filters: the button keeps the cell a plain table cell.
  function nameButton(key, value, label, colour) {
    var on = filter[key] === value;
    return '<button type="button" class="fk' + (on ? " on" : "") + '" data-fk="' + key +
      '" data-fv="' + esc(value) + '" title="' +
      esc(on ? "show every " + key + " again" : "show only " + label) + '">' +
      '<i style="background:' + colour + '"></i>' + esc(label) + "</button>";
  }

  function chips() {
    var el = document.getElementById("filt");
    var html = ["model", "project"].filter(function (k) { return filter[k]; }).map(function (k) {
      return '<button type="button" class="chip" data-fk="' + k + '" data-fv="' + esc(filter[k]) +
        '" title="remove this filter">' + k + " <b>" + esc(DIMS[k].name(filter[k])) +
        '</b> <span class="x">×</span></button>';
    }).join("");
    el.hidden = !html;
    el.innerHTML = html ? "filtered ·" + html : "";
  }

  // ── buckets ────────────────────────────────────────────────────────
  // Keyed by their own start in local time, so sorting the keys sorts the
  // buckets and the label is already in the key.
  var SPANS = {
    // step: from a bucket's start, a time that is surely inside the next
    // one, whatever daylight saving does to the length of a day.
    week: {
      key: function (at) { return ymdhm(CH.weekStart(at, reset)); },
      label: function (k) { return "week of " + k; },
      xl: function (k) { return k.slice(5, 10); },
      step: 7.5 * 864e5
    },
    month: {
      key: function (at) { return ymd(at).slice(0, 7); },
      label: function (k) { return k; },
      xl: function (k) { return k; },
      step: 32 * 864e5
    },
    day: {
      key: function (at) { return ymd(at); },
      label: function (k) { return k; },
      xl: function (k) { return k.slice(5); },
      step: 1.5 * 864e5
    }
  };

  // A key back into the moment its bucket starts. All three key shapes are
  // prefixes of "YYYY-MM-DD HH:MM", read as local time like they were made.
  function startOf(k) {
    var n = k.split(/[- :]/).map(Number);
    return new Date(n[0], n[1] - 1, n[2] || 1, n[3] || 0, n[4] || 0);
  }
  // The bucket right before this one, whether or not anything happened in
  // it: the card compares a week with the week before, not with the last
  // week that happened to have data.
  function prevKey(span, k) { return span.key(new Date(startOf(k).getTime() - 60000)); }
  // Every bucket from the first to the last, the empty ones too, so a month
  // with nothing in it is a gap on the chart and not two bars side by side.
  function allKeys(span, keys) {
    if (!keys.length) return [];
    var out = [keys[0]], last = keys[keys.length - 1];
    while (out[out.length - 1] < last && out.length < 5000) {
      out.push(span.key(new Date(startOf(out[out.length - 1]).getTime() + span.step)));
    }
    return out;
  }

  function group(keyOf) {
    var out = {};
    rows.forEach(function (r) {
      if (!keep(r)) return;
      var k = keyOf(r);
      var b = out[k] = out[k] || { t: zero(), parts: {} };
      add(b.t, r.t);
      var pk = dim().of(r);
      add(b.parts[pk] = b.parts[pk] || zero(), r.t);
    });
    return out;
  }

  // ── rendering ──────────────────────────────────────────────────────
  var period = "week";
  period = CH.pref("period", "week");
  if (!/^(week|month|all)$/.test(period)) period = "week";

  function chart(buckets, keys, span) {
    var peak = 0;
    keys.forEach(function (k) { if (buckets[k]) peak = Math.max(peak, total(buckets[k].t)); });
    document.getElementById("ymax").textContent = peak ? "peak " + fmt(peak) + " tokens" : "";
    document.getElementById("chart").innerHTML = keys.map(function (k) {
      var b = buckets[k];
      // A period with nothing in it: room on the axis, nothing to click.
      if (!b) return '<div class="col" title="' + esc(span.label(k)) + ' · nothing"></div>';
      var sum = total(b.t);
      var d = dim();
      var segs = d.parts.filter(function (m) { return b.parts[m]; }).map(function (m) {
        var v = total(b.parts[m]);
        return '<i style="height:' + (100 * v / (sum || 1)) + "%;background:" + d.colour[m] + '"></i>';
      }).join("");
      var tip = [span.label(k), fmt(sum) + " tokens", b.t[4] + (b.t[4] === 1 ? " reply" : " replies")]
        .concat(cost(b.t) === null ? [] : ["≈ " + money(cost(b.t))])
        .concat(calc(b.t) === null ? [] : [approx(b.t[MISS] ? "≥ " : "≈ ", calc(b.t)) + " calculated"])
        .join(" · ");
      return '<button type="button" class="col" data-k="' + esc(k) + '" title="' + esc(tip) +
        '" aria-label="' + esc(tip) + '">' +
        '<span class="stack" style="height:' + Math.max(0.6, 100 * sum / (peak || 1)) + '%">' +
        segs + "</span></button>";
    }).join("");
    // Seventy daily labels in the width of a page is a grey smear; print
    // every nth, counting back from the newest so the latest always shows,
    // and few enough that each has the forty pixels it needs.
    var width = document.getElementById("chart").clientWidth || 1000;
    var every = Math.max(Math.ceil(keys.length / 26), Math.ceil(keys.length * 40 / width));
    document.getElementById("xaxis").innerHTML = keys.map(function (k, i) {
      var show = (keys.length - 1 - i) % every === 0;
      return '<div class="xl">' + (show ? esc(span.xl(k)) : "") + "</div>";
    }).join("");
    // Only what the filter leaves, so every entry is a click that shows something.
    var d2 = dim(), seen = {};
    keys.forEach(function (k) {
      if (buckets[k]) Object.keys(buckets[k].parts).forEach(function (m) { seen[m] = 1; });
    });
    document.getElementById("legend").innerHTML = d2.parts.filter(function (m) {
      return seen[m];
    }).map(function (m) {
      return nameButton(dimName, m, d2.name(m), d2.colour[m]);
    }).join("");
  }

  function cell(v) { return '<td class="num">' + fmt(v) + "</td>"; }
  // Approximate wherever it is written: what Claude Code recorded is its
  // own sum at list prices, as the cards and the index say. Where it
  // recorded nothing, the calculated cost, marked as such: "≥" when some of
  // the tokens have no price line.
  // "≥" for a floor: a total holding a session some of whose replies fall
  // outside what Claude Code recorded, as that session's own page says.
  function costCell(t, floor) {
    if (cost(t) !== null) {
      return '<td class="num"' + (floor ? ' title="some replies fall outside what Claude Code recorded, so at least this"' : "") +
        ">" + (floor ? "≥ " : "≈ ") + money(cost(t)) + "</td>";
    }
    if (calc(t) === null) return '<td class="num d">—</td>';
    return '<td class="num cc" title="' + esc(calcTitle(t)) + '">' + approx(t[MISS] ? "≥ " : "≈ ", calc(t)) +
      ' <span class="cm">calc</span></td>';
  }
  // "<$0.01" already says how near it is.
  function approx(sign, micro) {
    var m = money(micro);
    return m.charAt(0) === "<" ? m : sign + m;
  }
  function calcTitle(t) {
    return "calculated from the price file, at " +
      (priceAt === "now" ? "today's prices" : "the price of the time") +
      (t[MISS] ? "; some of these tokens have no price line, so at least this" : "") +
      " — Claude Code recorded no cost here";
  }
  function numbers(t, floor) {
    return cell(t[0]) + cell(t[1]) + cell(t[2]) + cell(t[3]) +
           '<td class="num">' + t[4] + "</td>" + cell(total(t)) + costCell(t, floor);
  }

  // The last row of a table: what its rows add up to. Its cost is like any
  // sum's, what Claude Code recorded wherever it recorded anything; a row
  // marked calc may then be left out of it, which the line under the table
  // says, with the calculated total beside it.
  function totalRow(label, t, parts) {
    var mixed = cost(t) !== null && parts.some(function (p) { return cost(p) === null && calc(p) !== null; });
    return { mixed: mixed, html: '<tr class="total"><td>' + esc(label) + "</td>" + numbers(t, sessionsInPart()) + "</tr>" };
  }
  function totalNote(id, row, t) {
    var el = document.getElementById(id);
    el.hidden = !row.mixed;
    el.textContent = row.mixed
      ? "The total's cost, " + (sessionsInPart() ? "≥ " : "≈ ") + money(cost(t)) + ", adds what Claude Code " +
        "recorded; the rows marked calc have no recorded cost and are not in it. A session's cost is recorded " +
        "as a running total when it exits, on that hour, so a row marked calc is work inside a later row's " +
        "figure, or not recorded yet by a session still open. Calculated for every row, the total is " +
        approx(t[MISS] ? "≥ " : "≈ ", calc(t)) + "."
      : "";
  }
  // What the filter narrows the page to, said in a heading.
  function filterNames() {
    return ["project", "model"].filter(function (k) { return filter[k]; })
      .map(function (k) { return DIMS[k].name(filter[k]); });
  }

  // A period's rows, one per part of the breakdown under the period's own
  // line. When the filter has narrowed the breakdown to one part (a project
  // chosen, the page broken down by project), that part is the same on every
  // line: the heading names it once and each period is a single row.
  function bucketTable(buckets, keys, span, current, unit) {
    var d = dim(), single = !!filter[dimName], all = zero(), parts = [];
    document.getElementById("dimh").textContent = single ? unit.charAt(0).toUpperCase() + unit.slice(1) : d.heading;
    var html = keys.slice().reverse().map(function (k) {
      var b = buckets[k];
      add(all, b.t);
      if (single) {
        parts.push(b.t);
        return '<tr class="one' + (k === current ? " now" : "") + '" id="b-' + esc(k) + '"><td class="nm pl">' +
          esc(k) + (k === current ? ' <span class="gc">current</span>' : "") + "</td>" + numbers(b.t) + "</tr>";
      }
      var ms = d.parts.filter(function (m) { return b.parts[m]; });
      ms.forEach(function (m) { parts.push(b.parts[m]); });
      html = '<tr class="bucket' + (k === current ? " now" : "") + '" id="b-' + esc(k) + '">' +
        '<th colspan="8">' + esc(span.label(k)) +
        (k === current ? ' <span class="gc">current</span>' : "") + "</th></tr>";
      html += ms.map(function (m) {
        return '<tr><td class="nm">' + nameButton(dimName, m, d.name(m), d.colour[m]) + "</td>" +
          numbers(b.parts[m]) + "</tr>";
      }).join("");
      if (ms.length > 1) html += '<tr class="sum"><td>' + d.all + "</td>" + numbers(b.t) + "</tr>";
      return html;
    }).join("");
    var row = totalRow("total · " + CH.plural(keys.length, unit), all, parts);
    document.getElementById("buckets").innerHTML = html + row.html;
    totalNote("bnote", row, all);
  }

  function projectTable(inPeriod, heading) {
    var other = dimName === "project" ? "model" : "project";
    var o = DIMS[other];
    var by = {};
    rows.forEach(function (r) {
      if (!keep(r) || (inPeriod && !inPeriod(r))) return;
      var k = o.of(r);
      var b = by[k] = by[k] || { t: zero() };
      add(b.t, r.t);
    });
    var keys = Object.keys(by).sort(function (a, b) { return total(by[b].t) - total(by[a].t); });
    document.getElementById("ph").textContent =
      ["By " + other].concat(filterNames(), [heading]).join(" · ");
    document.getElementById("oth").textContent = o.heading;
    var all = zero();
    keys.forEach(function (k) { add(all, by[k].t); });
    // One row is its own total.
    var row = keys.length > 1 ? totalRow("total", all, keys.map(function (k) { return by[k].t; }))
                              : { mixed: false, html: "" };
    document.getElementById("projects").innerHTML = (keys.map(function (k) {
      return '<tr><td class="nm">' + nameButton(other, k, o.name(k), o.colour[k]) + "</td>" +
        numbers(by[k].t) + "</tr>";
    }).join("") + row.html) || '<tr><td colspan="8" class="d">nothing in this period</td></tr>';
    totalNote("pnote", row, all);
  }

  function delta(now, before) {
    if (!before) return "";
    var pct = Math.round(100 * (now - before) / before);
    if (!isFinite(pct) || pct === 0) return '<div class="d">same as before</div>';
    return '<div class="d ' + (pct > 0 ? "up" : "dn") + '">' +
      (pct > 0 ? "▲ " : "▼ ") + Math.abs(pct) + "% vs previous</div>";
  }

  // An empty bucket before this one is said once, on the first card: four
  // "infinitely more" deltas would be noise.
  function cards(latest, previous, label) {
    var t = latest || zero(), p = previous;
    var idle = p && !total(p) && !p[4];
    if (idle) p = null;
    var per = t[4] ? t[1] / t[4] : 0;      // output per reply: the rest is mostly cache
    // The cost compares only with a period whose cost is known too. The
    // calculated one sits under it, apart.
    var c = cost(t), pc = p ? cost(p) : null, k = calc(t);
    document.getElementById("cards").innerHTML =
      '<div class="card"><div class="n">' + fmt(total(t)) + '</div><div class="l">' +
        esc(label) + "</div>" + (p ? delta(total(t), total(p)) : "") +
        (idle ? '<div class="d">nothing the ' + period + " before</div>" : "") + "</div>" +
      '<div class="card cost" title="as Claude Code recorded it, at API list prices">' +
        '<div class="n">' + (c === null ? "—" : money(c)) + '</div>' +
        '<div class="l">recorded by Claude Code</div>' + (c !== null && pc ? delta(c, pc) : "") +
        (PR ? '<div class="c2" title="' + esc(calcTitle(t).replace(/ — .*/, "")) + '"><b>' +
          (k === null ? "—" : (t[MISS] ? "≥ " : "") + money(k)) + "</b> calculated</div>" : "") +
        "</div>" +
      '<div class="card"><div class="n">' + fmt(t[1]) + '</div><div class="l">output</div>' +
        (p ? delta(t[1], p[1]) : "") + "</div>" +
      '<div class="card"><div class="n">' + fmt(t[2] + t[3]) + '</div><div class="l">cache</div>' +
        (p ? delta(t[2] + t[3], p[2] + p[3]) : "") + "</div>" +
      '<div class="card"><div class="n">' + t[4] + '</div><div class="l">replies</div>' +
        (p ? delta(t[4], p[4]) : "") + "</div>" +
      '<div class="card"><div class="n">' + fmt(per) + '</div><div class="l">output / reply</div></div>';
  }

  // How much of what is shown has a cost at all, said plainly, for the
  // project filtered to or for everything. Counted in sessions, by the build:
  // a model filter cannot narrow it, since one session spans models.
  var coverage = data.coverage || {};
  // Sessions in what is shown whose recorded cost is only part of theirs.
  function sessionsInPart() {
    return Object.keys(coverage).some(function (k) {
      return (!filter.project || k === filter.project) && Number(coverage[k][2]) > 0;
    });
  }
  function cover() {
    var c = [0, 0, 0];
    Object.keys(coverage).forEach(function (k) {
      if (filter.project && k !== filter.project) return;
      for (var i = 0; i < 3; i++) c[i] += Number(coverage[k][i]) || 0;
    });
    var el = document.getElementById("cover");
    if (!c[0]) { el.hidden = true; return; }
    el.hidden = false;
    el.textContent = "Cost is known for " + c[1] + " of " + c[0] + " session" + (c[0] === 1 ? "" : "s") +
      (filter.project ? " in " + filter.project : "") +
      (c[2] ? " (" + c[2] + " only in part, so a floor)" : "") +
      " — Claude Code only records it in recent versions, as a running total each time a" +
      " session exits, so it lands on that hour rather than spread over the work. Figures" +
      " are its own sums at API list prices: on a subscription they are an equivalent, not a bill." +
      (PR ? " Where nothing was recorded the tables show the calculated cost, marked calc."
          : " Where nothing was recorded the page says —.");
  }

  function draw() {
    ["week", "month", "all"].forEach(function (p) {
      document.getElementById("p" + p).classList.toggle("on", p === period);
    });
    ["then", "now"].forEach(function (w) {
      document.getElementById("c" + w).classList.toggle("on", w === priceAt);
    });

    // "all" means the whole history: day by day, unless that is too many bars
    // to read, in which case weeks carry it.
    var spanName = period === "all" ? (spanDays > 130 ? "week" : "day") : period;
    var span = SPANS[spanName];
    ["model", "project"].forEach(function (d) {
      document.getElementById("b" + d).classList.toggle("on", d === dimName);
    });
    chips();
    cover();
    var buckets = group(function (r) { return span.key(r.at); });
    var keys = Object.keys(buckets).sort();
    chart(buckets, allKeys(span, keys), span);

    var current = span.key(new Date());
    bucketTable(buckets, keys, span, current, spanName);
    // Every period there is, whichever the buttons chose: they choose the
    // cards and the table under this one.
    document.getElementById("bh").textContent =
      ["By " + spanName].concat(filterNames(), ["all time"]).join(" · ");

    if (period === "all") {
      var everything = zero();
      keys.forEach(function (k) { add(everything, buckets[k].t); });
      cards(everything, null, "all time");
      projectTable(null, "all time");
    } else {
      // The latest bucket that has data, and the one just before it in time
      // to compare — empty if nothing happened then.
      var last = keys[keys.length - 1];
      var prev = buckets[prevKey(span, last)];
      cards(buckets[last].t, prev ? prev.t : zero(),
            last === current ? "this " + period : span.label(last));
      projectTable(function (r) { return span.key(r.at) === last; }, span.label(last));
    }
    history();
  }

  // ── price history ──────────────────────────────────────────────────
  // Per model in use, its price lines newest first: the five prices, what
  // changed from the line before, and how much of the use shown fell in
  // each, priced by the line of its hour whatever the toggle says.
  var priceUse = data.priceUse || {};
  var FIG = [["input", "input"], ["output", "output"], ["cache_read", "cache read"],
             ["cache_write_5m", "write 5 min"], ["cache_write_1h", "write 1 h"]];
  function price(m) { return (m / 1000).toFixed(m % 10 ? 3 : 2); }
  function change(line, before) {
    if (!before) return "";
    for (var i = 0; i < FIG.length; i++) {
      var a = before[FIG[i][0]], b = line[FIG[i][0]];
      if (a === b) continue;
      var pct = a ? Math.round(100 * (b - a) / a) : 0;
      var rest = FIG.filter(function (f, j) { return j > i && before[f[0]] !== line[f[0]]; })
        .map(function (f) { return f[1] + " " + price(before[f[0]]) + " → " + price(line[f[0]]); });
      var said = FIG[i][1] + " " + price(a) + " → " + price(b) + " " + (pct > 0 ? "+" : "−") + Math.abs(pct) + " %";
      return '<span class="' + (b < a ? "dn" : "up") + '" title="' +
        esc(said + (rest.length ? "; also " + rest.join(", ") : "")) + '">' +
        (i ? said : said.slice(FIG[i][1].length + 1)) + (rest.length ? " …" : "") + "</span>";
    }
    return "no change";
  }
  function history() {
    var sec = document.getElementById("prices");
    if (!PR) { sec.hidden = true; return; }
    sec.hidden = false;
    var use = {}, ids = {}, miss = {}, unsplit = 0, shownSources = {};
    rows.forEach(function (r) {
      if (!keep(r)) return;
      unsplit += r.t[6] || 0;
      var line = PR.lineAt(r.model, r.hour);
      var id = PR.idOf(r.model);
      if (id === null) {
        if (total(r.t)) miss[r.model] = (miss[r.model] || 0) + total(r.t);
        return;
      }
      if (!(id in ids)) ids[id] = r.model;
      if (line) use[line.id] = (use[line.id] || 0) + total(r.t);
      else if (total(r.t)) miss[r.model + " (before its first price line)"] =
        (miss[r.model + " (before its first price line)"] || 0) + total(r.t);
    });
    var sessions = {};
    Object.keys(priceUse).forEach(function (p) {
      if (filter.project && p !== filter.project) return;
      Object.keys(priceUse[p]).forEach(function (k) { sessions[k] = (sessions[k] || 0) + priceUse[p][k]; });
    });
    var order = Object.keys(ids).sort(function (a, b) {
      return (modelTotals[ids[b]] || 0) - (modelTotals[ids[a]] || 0);
    });
    document.getElementById("pcheck").textContent = PR.checked ? " · price file checked " + PR.checked : "";
    document.getElementById("ptable").innerHTML = order.map(function (id) {
      var ls = PR.history(id).reverse();
      var html = '<tr class="bucket"><th colspan="9"><span class="pm"><i style="background:' +
        (colour[ids[id]] || "var(--dim)") + '"></i>' + esc(shortModel(id)) + "</span></th></tr>";
      return html + ls.map(function (l, i) {
        var before = ls[i + 1];
        l.source.split(/\s+/).forEach(function (u) { if (/^https:\/\//.test(u)) shownSources[u] = 1; });
        return '<tr' + (l.to ? ' class="old"' : "") + "><td>" +
          (l.to ? esc(l.from + " to " + l.to) : "since " + esc(l.from) + ' <span class="gc">current</span>') +
          "</td>" + FIG.map(function (f) { return '<td class="num">' + price(l[f[0]]) + "</td>"; }).join("") +
          "<td>" + (before ? change(l, before) : ls.length > 1 ? "—" : "no change") + "</td>" +
          '<td class="num">' + (use[l.id] ? fmt(use[l.id]) : "—") + "</td>" +
          '<td class="num">' + (sessions[l.id] || "—") + "</td></tr>";
      }).join("");
    }).join("") || '<tr><td colspan="9" class="d">no priced model in what is shown</td></tr>';
    var notes = [];
    var missed = Object.keys(miss);
    if (missed.length) {
      notes.push("Not priced, so left out of the calculated cost (no line in the price file covers them): " +
        missed.map(function (m) { return esc(shortModel(m)) + " " + fmt(miss[m]) + " tokens"; }).join(", ") +
        ". Nothing is guessed: add a line to prices.tsv to price them.");
    }
    if (unsplit) {
      notes.push(fmt(unsplit) + " tokens of cache writes are of unknown duration (split unknown): from " +
        "archives written before claude-html kept 5-minute and 1-hour writes apart, or from records " +
        "that do not say. They are priced as 5-minute writes.");
    }
    if (PR.errors.length) {
      notes.push("Lines of the price file that could not be read, and were skipped: " + esc(PR.errors.join("; ")) + ".");
    }
    var src = Object.keys(shownSources).sort();
    if (src.length) {
      notes.push("Sources: " + src.map(function (u) {
        return '<a href="' + esc(u) + '">' + esc(u.replace(/^https:\/\/(www\.)?/, "")) + "</a>";
      }).join(" · "));
    }
    document.getElementById("pnotes").innerHTML = notes.map(function (n) {
      return '<p class="hint">' + n + "</p>";
    }).join("");
  }

  // A bar points at its own row in the table below.
  document.getElementById("chart").addEventListener("click", function (e) {
    var col = e.target.closest(".col");
    if (!col) return;
    var row = document.getElementById("b-" + col.dataset.k);
    if (!row) return;
    row.scrollIntoView({ block: "center" });
    row.classList.add("flash");
    setTimeout(function () { row.classList.remove("flash"); }, 1400);
  });

  // Names live in the tables, the legend and the filter chips, all redrawn
  // on every change, so one listener on the page serves them all.
  document.addEventListener("click", function (e) {
    var b = e.target.closest && e.target.closest("[data-fk]");
    if (b) toggle(b.getAttribute("data-fk"), b.getAttribute("data-fv"));
  });

  // A narrower window fits fewer labels under the bars.
  var resized;
  window.addEventListener("resize", function () {
    clearTimeout(resized);
    resized = setTimeout(draw, 150);
  });

  ["week", "month", "all"].forEach(function (p) {
    document.getElementById("p" + p).addEventListener("click", function () {
      if (period === p) return;
      period = p;
      try { localStorage.setItem("ch-usage-period", period); } catch (e) {}
      draw();
    });
  });
  ["then", "now"].forEach(function (w) {
    document.getElementById("c" + w).addEventListener("click", function () {
      if (priceAt === w) return;
      priceAt = w;
      try { localStorage.setItem("ch-usage-prices", w); } catch (e) {}
      reprice();
      draw();
    });
  });
  // Without a price file there is nothing to toggle.
  if (!PR) document.getElementById("cgroup").hidden = true;
  ["model", "project"].forEach(function (d) {
    document.getElementById("b" + d).addEventListener("click", function () {
      if (dimName === d) return;
      dimName = d;
      try { localStorage.setItem("ch-usage-dim", d); } catch (e) {}
      draw();
    });
  });

  var DAYNAME = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  var at = DAYNAME[reset.dow] + " " + pad(reset.hour) + ":" + pad(reset.minute);
  // A UTC reset also says what that is on this clock today, once.
  var note = "";
  if (reset.utc) {
    var here = CH.weekStart(new Date(), reset);
    at += " UTC";
    note = " (" + DAYNAME[here.getDay()] + " " + pad(here.getHours()) + ":" +
           pad(here.getMinutes()) + " your time)";
  }
  document.getElementById("sub").textContent =
    "input, output and cache tokens from your own transcripts, and their cost where Claude Code" +
    " recorded it" + (PR ? " and as calculated from the price file" : "") + ", by model and project — " +
    firstDay + " to " + lastDay + ", local time. A week runs " + at + " to " + at + note +
    (data.weekResetSet ? ", matching your plan's reset." : ".");
  draw();
})();
