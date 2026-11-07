// The token dashboard. The data is project -> UTC hour -> model -> [input,
// output, cache read, cache write, replies, cost]; everything on the page is
// an aggregate of that, converted to local time here, and the period buttons
// decide how wide a bucket is. The cost, in micro-dollars, is there only
// where Claude Code recorded one: a cell of five figures has none.
//
// Hours, not days, because a usage week can start at 9am — and because a
// record at 23:00 UTC already belongs to the next day in most of Europe.
(function () {
  "use strict";

  CH.themeInit(document.getElementById("theme"));

  var data = JSON.parse(document.getElementById("usage-data").textContent) || {};
  var byProject = data.byProject || {};
  var projects = Object.keys(byProject);

  var esc = CH.esc, fmt = CH.fmtTokens, money = CH.fmtMoney;
  var COLS = 5;
  // The sixth figure starts as null, not 0: a sum that no known cost went
  // into is unknown, and must read "—" rather than "$0.00".
  function zero() { return [0, 0, 0, 0, 0, null]; }
  function add(into, from) {
    for (var i = 0; i < COLS; i++) into[i] += from[i] || 0;
    if (from.length > COLS && from[COLS] !== null && from[COLS] !== undefined) {
      into[COLS] = (into[COLS] || 0) + from[COLS];
    }
  }
  function cost(t) { return t[COLS] === null || t[COLS] === undefined ? null : t[COLS]; }
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
        rows.push({ at: at, model: m, project: p, t: byProject[p][hour][m] });
      });
    });
  });
  if (!rows.length) {
    document.getElementById("empty").hidden = false;
    document.getElementById("view").hidden = true;
    return;
  }
  var allDays = rows.map(function (r) { return ymd(r.at); }).sort();
  var firstDay = allDays[0], lastDay = allDays[allDays.length - 1];
  var spanDays = Object.keys(allDays.reduce(function (o, d) { o[d] = 1; return o; }, {})).length;

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
  try { dimName = localStorage.getItem("ch-usage-dim") || "model"; } catch (e) {}
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
    week: {
      key: function (at) { return ymdhm(CH.weekStart(at, reset)); },
      label: function (k) { return "week of " + k; },
      xl: function (k) { return k.slice(5, 10); }
    },
    month: {
      key: function (at) { return ymd(at).slice(0, 7); },
      label: function (k) { return k; },
      xl: function (k) { return k.slice(2); }
    },
    day: {
      key: function (at) { return ymd(at); },
      label: function (k) { return k; },
      xl: function (k) { return k.slice(5); }
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
  try { period = localStorage.getItem("ch-usage-period") || "week"; } catch (e) {}
  if (!/^(week|month|all)$/.test(period)) period = "week";

  function chart(buckets, keys, span) {
    var peak = 0;
    keys.forEach(function (k) { peak = Math.max(peak, total(buckets[k].t)); });
    document.getElementById("ymax").textContent = peak ? "peak " + fmt(peak) + " tokens" : "";
    document.getElementById("chart").innerHTML = keys.map(function (k) {
      var b = buckets[k], sum = total(b.t);
      var d = dim();
      var segs = d.parts.filter(function (m) { return b.parts[m]; }).map(function (m) {
        var v = total(b.parts[m]);
        return '<i style="height:' + (100 * v / (sum || 1)) + "%;background:" + d.colour[m] + '"></i>';
      }).join("");
      return '<div class="col" data-k="' + esc(k) + '" title="' + esc(span.label(k)) +
        " " + fmt(sum) + " tokens " + b.t[4] + " replies" +
        (cost(b.t) === null ? "" : " ≈ " + money(cost(b.t))) + '">' +
        '<div class="stack" style="height:' + Math.max(0.6, 100 * sum / (peak || 1)) + '%">' +
        segs + "</div></div>";
    }).join("");
    // Seventy daily labels in the width of a page is a grey smear; print
    // every nth, counting back from the newest so the latest always shows.
    var every = Math.ceil(keys.length / 26);
    document.getElementById("xaxis").innerHTML = keys.map(function (k, i) {
      var show = (keys.length - 1 - i) % every === 0;
      return '<div class="xl">' + (show ? esc(span.xl(k)) : "") + "</div>";
    }).join("");
    // Only what the filter leaves, so every entry is a click that shows something.
    var d2 = dim(), seen = {};
    keys.forEach(function (k) { Object.keys(buckets[k].parts).forEach(function (m) { seen[m] = 1; }); });
    document.getElementById("legend").innerHTML = d2.parts.filter(function (m) {
      return seen[m];
    }).map(function (m) {
      return nameButton(dimName, m, d2.name(m), d2.colour[m]);
    }).join("");
  }

  function cell(v) { return '<td class="num">' + fmt(v) + "</td>"; }
  function numbers(t) {
    return cell(t[0]) + cell(t[1]) + cell(t[2]) + cell(t[3]) +
           '<td class="num">' + t[4] + "</td>" + cell(total(t)) +
           '<td class="num' + (cost(t) === null ? " d" : "") + '">' + money(cost(t)) + "</td>";
  }

  function bucketTable(buckets, keys, span, current) {
    document.getElementById("buckets").innerHTML = keys.slice().reverse().map(function (k) {
      var b = buckets[k];
      var d = dim();
      var ms = d.parts.filter(function (m) { return b.parts[m]; });
      var html = '<tr class="bucket' + (k === current ? " now" : "") + '" id="b-' + esc(k) + '">' +
        '<th colspan="8">' + esc(span.label(k)) +
        (k === current ? ' <span class="gc">current</span>' : "") + "</th></tr>";
      html += ms.map(function (m) {
        return '<tr><td class="nm">' + nameButton(dimName, m, d.name(m), d.colour[m]) + "</td>" +
          numbers(b.parts[m]) + "</tr>";
      }).join("");
      if (ms.length > 1) html += '<tr class="sum"><td>' + d.all + "</td>" + numbers(b.t) + "</tr>";
      return html;
    }).join("");
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
      "By " + other + " · " + heading;
    document.getElementById("oth").textContent = o.heading;
    document.getElementById("projects").innerHTML = keys.map(function (k) {
      return '<tr><td class="nm">' + nameButton(other, k, o.name(k), o.colour[k]) + "</td>" +
        numbers(by[k].t) + "</tr>";
    }).join("") || '<tr><td colspan="8" class="d">nothing in this period</td></tr>';
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
    // The cost compares only with a period whose cost is known too.
    var c = cost(t), pc = p ? cost(p) : null;
    document.getElementById("cards").innerHTML =
      '<div class="card"><div class="n">' + fmt(total(t)) + '</div><div class="l">' +
        esc(label) + "</div>" + (p ? delta(total(t), total(p)) : "") +
        (idle ? '<div class="d">nothing the ' + period + " before</div>" : "") + "</div>" +
      '<div class="card" title="as Claude Code recorded it, at API list prices">' +
        '<div class="n">' + (c === null ? "—" : "≈ " + money(c)) + '</div>' +
        '<div class="l">cost</div>' + (c !== null && pc ? delta(c, pc) : "") + "</div>" +
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
      " Where nothing was recorded the page says —.";
  }

  function draw() {
    ["week", "month", "all"].forEach(function (p) {
      document.getElementById("p" + p).classList.toggle("on", p === period);
    });
    try { localStorage.setItem("ch-usage-period", period); } catch (e) {}

    // "all" means the whole history: day by day, unless that is too many bars
    // to read, in which case weeks carry it.
    var spanName = period === "all" ? (spanDays > 130 ? "week" : "day") : period;
    var span = SPANS[spanName];
    document.getElementById("dimh").textContent = dim().heading;
    ["model", "project"].forEach(function (d) {
      document.getElementById("b" + d).classList.toggle("on", d === dimName);
    });
    chips();
    cover();
    var buckets = group(function (r) { return span.key(r.at); });
    var keys = Object.keys(buckets).sort();
    chart(buckets, keys, span);

    var current = span.key(new Date());
    bucketTable(buckets, keys, span, current);

    if (period === "all") {
      var everything = zero();
      keys.forEach(function (k) { add(everything, buckets[k].t); });
      cards(everything, null, "all time");
      document.getElementById("bh").textContent =
        "By " + (spanName === "day" ? "day" : "week") + " · all time";
      projectTable(null, "all time");
    } else {
      // The latest bucket that has data, and the one just before it in time
      // to compare — empty if nothing happened then.
      var last = keys[keys.length - 1];
      var prev = buckets[prevKey(span, last)];
      cards(buckets[last].t, prev ? prev.t : zero(),
            last === current ? "this " + period : span.label(last));
      document.getElementById("bh").textContent = "By " + period;
      projectTable(function (r) { return span.key(r.at) === last; }, span.label(last));
    }
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

  ["week", "month", "all"].forEach(function (p) {
    document.getElementById("p" + p).addEventListener("click", function () {
      if (period === p) return;
      period = p;
      draw();
    });
  });
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
  document.getElementById("sub").textContent =
    "input, output and cache tokens from your own transcripts, and their cost where Claude Code" +
    " recorded it, by model and project — " +
    firstDay + " to " + lastDay + ", local time. A week runs " + at + " to " + at +
    (data.weekResetSet ? ", matching your plan's reset." : ".");
  draw();
})();
