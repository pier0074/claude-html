// The token dashboard. The data is project -> UTC hour -> model -> [input,
// output, cache read, cache write, replies]; everything on the page is an
// aggregate of that, converted to local time here, and the period buttons
// decide how wide a bucket is.
//
// Hours, not days, because a usage week can start at 9am — and because a
// record at 23:00 UTC already belongs to the next day in most of Europe.
(function () {
  "use strict";

  CH.themeInit(document.getElementById("theme"));

  var data = JSON.parse(document.getElementById("usage-data").textContent) || {};
  var byProject = data.byProject || {};
  var projects = Object.keys(byProject);

  var esc = CH.esc;
  var COLS = 5;
  function zero() { return [0, 0, 0, 0, 0]; }
  function add(into, from) { for (var i = 0; i < COLS; i++) into[i] += from[i] || 0; }
  // Tokens only: the fifth column counts replies and must never be summed in.
  function total(t) { return t[0] + t[1] + t[2] + t[3]; }

  function shortModel(m) { return String(m).replace(/^claude-/, "").replace(/-20\d{6}$/, ""); }
  function fmt(n) {
    if (n >= 1e9) return (n / 1e9).toFixed(2) + " B";
    if (n >= 1e6) return (n / 1e6).toFixed(1) + " M";
    if (n >= 1e3) return (n / 1e3).toFixed(1) + " k";
    return String(Math.round(n));
  }

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

  function group(keyOf, filter) {
    var out = {};
    rows.forEach(function (r) {
      if (filter && !filter(r)) return;
      var k = keyOf(r);
      var b = out[k] = out[k] || { t: zero(), models: {} };
      add(b.t, r.t);
      add(b.models[r.model] = b.models[r.model] || zero(), r.t);
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
      var segs = models.filter(function (m) { return b.models[m]; }).map(function (m) {
        var v = total(b.models[m]);
        return '<i style="height:' + (100 * v / (sum || 1)) + "%;background:" + colour[m] + '"></i>';
      }).join("");
      return '<div class="col" data-k="' + esc(k) + '" title="' + esc(span.label(k)) +
        " " + fmt(sum) + " tokens " + b.t[4] + ' replies">' +
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
    document.getElementById("legend").innerHTML = models.map(function (m) {
      return '<span><i style="background:' + colour[m] + '"></i>' + esc(shortModel(m)) + "</span>";
    }).join("");
  }

  function cell(v) { return '<td class="num">' + fmt(v) + "</td>"; }
  function numbers(t) {
    return cell(t[0]) + cell(t[1]) + cell(t[2]) + cell(t[3]) +
           '<td class="num">' + t[4] + "</td>" + cell(total(t));
  }

  function bucketTable(buckets, keys, span, current) {
    document.getElementById("buckets").innerHTML = keys.slice().reverse().map(function (k) {
      var b = buckets[k];
      var ms = models.filter(function (m) { return b.models[m]; });
      var html = '<tr class="bucket' + (k === current ? " now" : "") + '" id="b-' + esc(k) + '">' +
        '<th colspan="7">' + esc(span.label(k)) +
        (k === current ? ' <span class="gc">current</span>' : "") + "</th></tr>";
      html += ms.map(function (m) {
        return '<tr><td class="model"><i style="background:' + colour[m] + '"></i>' +
          esc(shortModel(m)) + "</td>" + numbers(b.models[m]) + "</tr>";
      }).join("");
      if (ms.length > 1) html += '<tr class="sum"><td>all models</td>' + numbers(b.t) + "</tr>";
      return html;
    }).join("");
  }

  function projectTable(filter, heading) {
    var by = group(function (r) { return r.project; }, filter);
    var keys = Object.keys(by).sort(function (a, b) { return total(by[b].t) - total(by[a].t); });
    document.getElementById("ph").textContent = "By project · " + heading;
    document.getElementById("projects").innerHTML = keys.map(function (k) {
      return '<tr><td class="proj">' + esc(k) + "</td>" + numbers(by[k].t) + "</tr>";
    }).join("") || '<tr><td colspan="7" class="d">nothing in this period</td></tr>';
  }

  function delta(now, before) {
    if (!before) return "";
    var pct = Math.round(100 * (now - before) / before);
    if (!isFinite(pct) || pct === 0) return '<div class="d">same as before</div>';
    return '<div class="d ' + (pct > 0 ? "up" : "dn") + '">' +
      (pct > 0 ? "▲ " : "▼ ") + Math.abs(pct) + "% vs previous</div>";
  }

  function cards(latest, previous, label) {
    var t = latest || zero(), p = previous;
    var per = t[4] ? t[1] / t[4] : 0;      // output per reply: the rest is mostly cache
    document.getElementById("cards").innerHTML =
      '<div class="card"><div class="n">' + fmt(total(t)) + '</div><div class="l">' +
        esc(label) + "</div>" + (p ? delta(total(t), total(p)) : "") + "</div>" +
      '<div class="card"><div class="n">' + fmt(t[1]) + '</div><div class="l">output</div>' +
        (p ? delta(t[1], p[1]) : "") + "</div>" +
      '<div class="card"><div class="n">' + fmt(t[2] + t[3]) + '</div><div class="l">cache</div>' +
        (p ? delta(t[2] + t[3], p[2] + p[3]) : "") + "</div>" +
      '<div class="card"><div class="n">' + t[4] + '</div><div class="l">replies</div>' +
        (p ? delta(t[4], p[4]) : "") + "</div>" +
      '<div class="card"><div class="n">' + fmt(per) + '</div><div class="l">output / reply</div></div>';
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
      // The latest bucket that has data, and the one before it to compare.
      var last = keys[keys.length - 1];
      var prev = keys[keys.length - 2];
      cards(buckets[last].t, prev ? buckets[prev].t : null,
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

  ["week", "month", "all"].forEach(function (p) {
    document.getElementById("p" + p).addEventListener("click", function () {
      if (period === p) return;
      period = p;
      draw();
    });
  });

  var DAYNAME = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  var at = DAYNAME[reset.dow] + " " + pad(reset.hour) + ":" + pad(reset.minute);
  document.getElementById("sub").textContent =
    "input, output and cache tokens from your own transcripts, by model and project — " +
    firstDay + " to " + lastDay + ", local time. A week runs " + at + " to " + at +
    (data.weekReset ? ", matching your plan's reset." : ".");
  draw();
})();
