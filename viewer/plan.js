// The plan line, the budget line and the Limits & budget section, on the
// index and the Token usage page. The build put what limits.sh worked out
// into the page's data as "limits" (settings, the week, the rules with
// their starts, the latest figures from Claude Code's status line, all as
// of the build) and what limits.js counted as "spend". The page writes
// nothing: "apply" is a claude-html://limits link, which asks in a window
// of its own before anything changes, and "copy command" gives the same
// change as claude-html --limits lines.
var CHPlan = (function () {
  "use strict";

  var DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
  var WD = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  function esc(s) { return CH.esc(s); }
  function pad(n) { return (n < 10 ? "0" : "") + n; }
  function cap(d) { return d.charAt(0).toUpperCase() + d.slice(1); }
  function hm(d) { return pad(d.getHours()) + ":" + pad(d.getMinutes()); }
  function sameDay(a, b) { return a.toDateString() === b.toDateString(); }
  // "16:30" on the day of the build, else "Tue 08:00".
  function when(secs, now) {
    var d = new Date(secs * 1000);
    return sameDay(d, new Date(now * 1000)) ? hm(d) : WD[d.getDay()] + " " + hm(d);
  }
  function day(secs) { var d = new Date(secs * 1000); return WD[d.getDay()] + " " + hm(d); }
  function utc(secs) { var d = new Date(secs * 1000); return pad(d.getUTCHours()) + ":" + pad(d.getUTCMinutes()); }
  function level(p) { return p >= 95 ? "bad" : p >= 80 ? "warn" : "ok"; }
  function pct(p) { return Math.round(p) + " %"; }
  function money(micro) { return CH.fmtMoney ? CH.fmtMoney(micro) : "$" + (micro / 1e6).toFixed(2); }
  function dollars(a) { return "$" + a; }
  function ruleName(r) { return cap(r.day) + " " + r.time; }

  // The rule that matters now: of those in force, the lowest; else the
  // next to start. As the status line and the stop decide it.
  function current(L) {
    var now = L.now, reset = L.week && L.week.reset, best = null, next = null;
    (L.rules || []).forEach(function (r) {
      if (typeof r.start !== "number") return;
      if (r.start <= now && now < reset) { if (!best || r.pct < best.pct) best = r; }
      else if (!next || r.start < next.start) next = r;
    });
    return best ? { rule: best, force: true } : next ? { rule: next, force: false } : null;
  }

  function bar(p, mark, label) {
    var w = Math.max(0, Math.min(100, p));
    return '<span class="pbar"><i class="' + level(p) + '" style="width:' + w + '%"></i>' +
      (mark ? '<u style="left:' + mark + '%"></u><em style="left:' + mark + '%">' + esc(label) + "</em>" : "") +
      "</span>";
  }
  var SEP = ' <span class="psep">·</span> ';

  // The one line: the plan's two windows, or, with an API key, the budget.
  function line(L, spend) {
    if (!L) return "";
    var P = L.plan, now = L.now;
    if (P && (P.week || P.five)) {
      var out = '<span class="pk">plan</span>', cur = L.on ? current(L) : null, stale = !P.fresh;
      if (P.five && P.five.reset > now) {
        out += SEP + '5 h: ' + bar(P.five.pct) + ' <b class="' + level(P.five.pct) + '">' + pct(P.five.pct) +
          "</b>" + SEP + '<span class="pd">resets ' + esc(when(P.five.reset, now)) + "</span>";
      }
      if (P.week) {
        var mark = cur ? cur.rule.pct : 0;
        out += SEP + 'week: ' + bar(P.week.pct, mark, cur ? "from " + ruleName(cur.rule) : "") +
          ' <b class="' + level(P.week.pct) + '">' + pct(P.week.pct) + "</b>" +
          SEP + '<span class="pd">resets ' + esc(day(P.week.reset)) + "</span>";
        if (cur) {
          var hit = cur.force && P.week.pct >= cur.rule.pct;
          out += SEP + '<span class="pstop' + (hit ? " warn" : "") + '" title="' +
            (cur.force ? "in force: a new prompt past this asks first" : "the next rule to start") + '">stop at ' +
            cur.rule.pct + " % from " + esc(ruleName(cur.rule)) + "</span>";
        }
      }
      out += SEP + '<span class="pasof" title="the last figures Claude Code gave its status line; they update while Claude Code runs">as of ' +
        esc(day(P.asof)) + (stale ? " · no recent values" : "") + "</span>";
      return '<div class="plan' + (stale ? " stale" : "") + '">' + out + "</div>";
    }
    var B = L.budget;
    if (B && spend && !L.onPlan) {
      var p = spend.micro / (B.cents * 100);
      var word = B.period === "day" ? "today" : B.period === "month" ? "this month" : "this week";
      return '<div class="plan"><span class="pk">budget</span>' + SEP + word + " " + bar(p) +
        ' <b>' + esc(money(spend.micro)) + '</b> <span class="pd">of ' + esc(dollars(B.amount)) + "</span>" +
        SEP + '<b class="' + level(p) + '">' + pct(p) + "</b>" + SEP +
        '<span class="pd">resets ' + esc(day(B.end)) + "</span>" + SEP +
        '<span class="pasof" title="the cost Claude Code recorded, or the price table\'s where it recorded none, counted when the page was built' +
        (spend.unpriced ? "; some usage has neither and is not in it" : "") + '">as of ' +
        esc(when(now, now)) + "</span></div>";
    }
    return "";
  }

  // ── the section ────────────────────────────────────────────────────
  // What the section's fields say, as the claude-html://limits link that
  // "apply" opens (the grammar limits-cli.sh, the helper and handler.sh
  // check) and as the claude-html --limits lines "copy command" gives:
  // those that change something, or all of them when nothing does.
  function amountOf(a) { var n = Number(a); return n % 1 ? n.toFixed(2) : String(n); }
  function linkFor(st) {
    var r = st.rules.map(function (x) { return x.day + "-" + x.time.replace(":", "") + "-" + (+x.pct); }).join(".") || "none";
    var b = st.amount === "" ? "none" : amountOf(st.amount) + "-" + st.period;
    return "claude-html://limits/v1/" + r + "/" + b + "/" + (+st.w1) + "-" + (+st.w2) + "/" + (st.notify ? "on" : "off");
  }
  function commandsFor(st, was) {
    var all = JSON.stringify(st) === JSON.stringify(was), out = [];
    var rules = st.rules.map(function (x) { return x.day + " " + x.time + " " + (+x.pct) + "%"; }).join(" · ");
    if (all || JSON.stringify(was.rules) !== JSON.stringify(st.rules)) out.push('claude-html --limits rules "' + (rules || "none") + '"');
    if (all || was.amount !== st.amount || was.period !== st.period) {
      out.push("claude-html --limits budget " + (st.amount === "" ? "off" : st.period + " " + amountOf(st.amount)));
    }
    if (all || was.w1 !== st.w1 || was.w2 !== st.w2) out.push("claude-html --limits budget warn " + (+st.w1) + " " + (+st.w2));
    if (all || was.notify !== st.notify) out.push("claude-html --limits notify " + (st.notify ? "on" : "off"));
    return out.join("\n");
  }

  function summary(L) {
    var bits = [];
    var n = (L.rules || []).length;
    bits.push(n ? n + " stop rule" + (n === 1 ? "" : "s") : "no stop rule");
    bits.push(L.budget ? "budget " + dollars(L.budget.amount) + " / " + L.budget.period + ", for API use" : "no budget");
    if (!L.on) bits.push("off");
    return bits.join(" · ");
  }
  function resetLabel(L) {
    if (!L.week) return "";
    return "weekly reset " + day(L.week.reset) + " (" + utc(L.week.reset) + " UTC)";
  }

  // The panel: the rules, the budget, its warnings and the banner, each a
  // field; what they say as a claude-html://limits link and as commands.
  function panel(el, L, opts) {
    if (!el || !L) return;
    opts = opts || {};
    var state = {
      rules: (L.rules || []).map(function (r) { return { day: r.day, time: r.time, pct: String(r.pct) }; }),
      amount: L.budget ? String(L.budget.amount) : "", period: L.budget ? L.budget.period : "week",
      w1: String((L.warn || [80, 95])[0]), w2: String((L.warn || [80, 95])[1]), notify: !!L.notify
    };
    var first = JSON.stringify(state);
    var open = false;
    try { open = localStorage.getItem("ch-limits-open") === "1"; } catch (e) {}
    // The Settings page shows it open, whatever the dashboard last did.
    if (opts.open) open = true;
    el.innerHTML = '<details class="lim"' + (open ? " open" : "") + '><summary><span class="lt">Limits &amp; budget</span>' +
      ' <span class="ls"></span><span class="lr">' + esc(resetLabel(L)) + "</span></summary>" +
      '<div class="lb"></div></details>';
    var det = el.querySelector("details"), body = el.querySelector(".lb");
    if (!opts.open) det.addEventListener("toggle", function () {
      try { localStorage.setItem("ch-limits-open", det.open ? "1" : "0"); } catch (e) {}
    });
    el.querySelector(".ls").textContent = "· " + summary(L);

    function valid() {
      var bad = {}, seen = {};
      state.rules.forEach(function (r, i) {
        if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(r.time)) bad["t" + i] = 1;
        if (!/^(100|[1-9]\d?)$/.test(r.pct)) bad["p" + i] = 1;
        var k = r.day + r.time;
        if (seen[k]) bad["t" + i] = 1;
        seen[k] = 1;
      });
      if (state.amount !== "" && !/^[1-9]\d{0,5}(\.\d{1,2})?$/.test(state.amount)) bad.amount = 1;
      if (!/^[1-9]\d?$/.test(state.w1)) bad.w1 = 1;
      if (!/^[1-9]\d?$/.test(state.w2) || +state.w2 <= +state.w1) bad.w2 = 1;
      return bad;
    }
    function link() { return linkFor(state); }
    function commands() { return commandsFor(state, JSON.parse(first)); }
    function opt(v, cur, label) { return '<option value="' + v + '"' + (v === cur ? " selected" : "") + ">" + label + "</option>"; }
    function draw() {
      var bad = valid(), h = "";
      if (!L.on) h += '<p class="lnote">Limits are off: no stop, no announcement, no budget warning. <code>claude-html --limits on</code> turns them on.</p>';
      h += '<div class="lrow"><span class="lk">Stop rules</span><div class="lv">';
      state.rules.forEach(function (r, i) {
        h += '<div class="lrule">from <select data-i="' + i + '" data-f="day" aria-label="day">' +
          DAYS.map(function (d) { return opt(d, r.day, cap(d)); }).join("") + "</select> " +
          '<input data-i="' + i + '" data-f="time" value="' + esc(r.time) + '" size="5" aria-label="time"' + (bad["t" + i] ? ' class="bad"' : "") + "> stop at " +
          '<input data-i="' + i + '" data-f="pct" value="' + esc(r.pct) + '" size="3" aria-label="percent"' + (bad["p" + i] ? ' class="bad"' : "") + "> % " +
          '<button class="lx" data-del="' + i + '" title="remove this rule" aria-label="remove this rule">×</button></div>';
      });
      h += '<div class="lrule">' + (state.rules.length < 8 ? '<button class="ladd">+ add a rule</button> ' : "") +
        '<span class="lh">each rule: from that moment until the weekly reset, a new prompt past that % asks first</span></div>';
      h += "</div></div>";
      h += '<div class="lrow"><span class="lk">Budget</span><div class="lv">' +
        '<input data-f="amount" value="' + esc(state.amount) + '" size="7" aria-label="budget in dollars"' + (bad.amount ? ' class="bad"' : "") + '> $ per ' +
        '<select data-f="period" aria-label="period">' + opt("day", state.period, "day") + opt("week", state.period, "week") +
        opt("month", state.period, "month") + '</select> <span class="lh">for API use; empty = none</span>' +
        '<div class="lrule">budget warnings at <input data-f="w1" value="' + esc(state.w1) + '" size="3" aria-label="first warning"' + (bad.w1 ? ' class="bad"' : "") +
        '> % <input data-f="w2" value="' + esc(state.w2) + '" size="3" aria-label="second warning"' + (bad.w2 ? ' class="bad"' : "") +
        '> % <span class="lh">for API use; Claude Code warns about plan limits itself</span></div></div></div>';
      h += '<div class="lrow"><span class="lk">Notification</span><div class="lv"><label><input type="checkbox" data-f="notify"' +
        (state.notify ? " checked" : "") + '> desktop banner when a rule is about to apply or a budget level is reached</label>' +
        ' <span class="lh">off by default</span></div></div>';
      var ok = !Object.keys(bad).length;
      h += '<div class="lrow"><span class="lk"></span><div class="lv">' +
        '<button class="cp lcp" data-c="' + esc(commands()) + '"' + (ok ? "" : " disabled") + '>copy command</button> ' +
        (opts.actions ? '<a class="go lgo' + (ok ? "" : " off") + '" href="' + (ok ? esc(link()) : "#") + '" title="asks in a window before anything changes">apply</a> ' : "") +
        '<span class="lh">' + (opts.actions ? "apply asks in a window first, then writes the conf and rebuilds the pages · " : "") +
        "copy command gives the same change as <code>claude-html --limits</code> lines</span></div></div>";
      var focus = document.activeElement && body.contains(document.activeElement) ?
        [document.activeElement.getAttribute("data-i"), document.activeElement.getAttribute("data-f"),
         document.activeElement.selectionStart] : null;
      body.innerHTML = h;
      if (focus) {
        var sel = '[data-f="' + focus[1] + '"]' + (focus[0] !== null ? '[data-i="' + focus[0] + '"]' : "");
        var f = body.querySelector(sel);
        if (f) { f.focus(); try { if (focus[2] !== null) f.setSelectionRange(focus[2], focus[2]); } catch (e) {} }
      }
    }
    function edit(e) {
      var t = e.target, f = t.getAttribute("data-f"), i = t.getAttribute("data-i");
      if (!f) return;
      var v = t.type === "checkbox" ? t.checked : String(t.value).trim();
      if ((i !== null ? state.rules[+i][f] : state[f]) === v) return;
      if (i !== null) state.rules[+i][f] = v; else state[f] = v;
      draw();
    }
    body.addEventListener("input", edit);
    body.addEventListener("change", edit);
    body.addEventListener("click", function (e) {
      var t = e.target;
      if (t.matches(".ladd")) {
        state.rules.push({ day: "fri", time: "20:00", pct: "80" });
        draw();
      } else if (t.hasAttribute("data-del")) {
        state.rules.splice(+t.getAttribute("data-del"), 1);
        draw();
      } else if (t.matches("a.lgo.off")) {
        e.preventDefault();
      }
    });
    draw();
  }

  // The copy buttons of the Token usage page, as the index has its own: the
  // command a button carries, to the clipboard, and "copied" for a moment.
  function copyButtons() {
    document.addEventListener("click", function (e) {
      if (!e.target.matches("button.cp[data-c]")) return;
      navigator.clipboard.writeText(e.target.dataset.c).then(function () {
        var was = e.target.textContent;
        e.target.textContent = "copied";
        setTimeout(function () { e.target.textContent = was === "copied" ? "copy" : was; }, 1200);
      });
    });
  }

  // Where the page has a place for it: the line, and on the Token usage
  // page the section under it.
  function mount(data) {
    var L = data && data.limits;
    var at = document.getElementById("plan");
    if (!at || !L) return;
    at.innerHTML = line(L, data.spend);
    at.hidden = !at.innerHTML;
    var lim = document.getElementById("limits");
    if (lim) { panel(lim, L, { actions: !!data.actions }); lim.hidden = false; }
  }

  return { line: line, panel: panel, mount: mount, current: current, copyButtons: copyButtons,
           linkFor: linkFor, commandsFor: commandsFor };
})();

if (typeof module !== "undefined" && module.exports) module.exports = CHPlan;
