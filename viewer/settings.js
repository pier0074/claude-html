// The Settings page: every setting lib/settings.tsv describes, what it is
// set to as of the build, where that comes from (the environment, the conf
// or the default), and a field to change it. The page writes nothing: the
// changes are gathered in a bar at the foot, "copy command" gives them as
// claude-html --config lines, and "apply" opens one claude-html://settings
// link, which asks in a window of its own before anything is written. The
// Limits & budget section is plan.js's panel, the Token usage page's own.
(function () {
  "use strict";
  var data = JSON.parse(document.getElementById("settings-data").textContent);
  var esc = CH.esc;
  CH.themeInit(document.getElementById("theme"));
  if (typeof CHPlan !== "undefined") CHPlan.copyButtons();
  var S = claudeHtmlSettings(data.desc, CH.parseReset);
  var V = data.values || {}, SH = data.shell || {};
  var FP = SH.fp || "none";
  var HOME = data.home || "";
  function tilde(p) { return HOME && p && p.indexOf(HOME + "/") === 0 ? "~" + p.slice(HOME.length) : p || ""; }
  function shq(s) { return /^[A-Za-z0-9._~\/:@%+=,-]+$/.test(s) ? s : "'" + String(s).replace(/'/g, "'\\''") + "'"; }
  var HERE = SH.here || data.here || "";
  var VERSION = SH.version || (data.update && data.update.installed) || "";
  var DOCS = "https://github.com/pier0074/claude-html/blob/" +
    (/^\d+\.\d+\.\d+$/.test(VERSION) ? "v" + VERSION : "main") + "/docs/SETUP.md#";

  // ── what is pending ────────────────────────────────────────────────
  // By key: {op: "set"|"unset", value}; and the safe values to forget:
  // all of them, or by id.
  var pending = {}, forget = false, forgetIds = {}, typed = {};
  function cur(key) { return V[key] || { v: "", src: "default" }; }
  function forced(key) { return cur(key).src === "environment"; }
  function changes() {
    var out = [];
    S.list.forEach(function (s) { if (pending[s.key]) out.push({ key: s.key, op: pending[s.key].op, value: pending[s.key].value }); });
    if (forget) out.push({ op: "forget" });
    else Object.keys(forgetIds).forEach(function (id) { out.push({ op: "forget1", value: id }); });
    return out;
  }
  // A value given for a key: a change, or none when it is what is there.
  function propose(key, raw) {
    var s = S.byKey[key], c = cur(key), t = String(raw).replace(/^\s+|\s+$/g, "");
    typed[key] = raw;
    if (!t) {
      if (c.src === "conf") pending[key] = { op: "unset" }; else delete pending[key];
      return { ok: true };
    }
    var r = S.check(key, t);
    if (!r.ok) { pending[key] = { op: "bad", why: r.why }; return r; }
    if (r.unset) {
      if (c.src === "conf") pending[key] = { op: "unset" }; else delete pending[key];
    } else if (c.src !== "default" && c.v === r.value) delete pending[key];
    else pending[key] = { op: "set", value: r.value };
    return r;
  }
  function useDefault(key) {
    delete typed[key];
    if (cur(key).src === "conf") pending[key] = { op: "unset" }; else delete pending[key];
  }

  // ── a row ──────────────────────────────────────────────────────────
  function badge(src) { return '<span class="badge ' + src + '">' + esc(src) + "</span>"; }
  function meta(s, src) {
    return '<div class="sm">' + badge(src) +
      '<a href="' + esc(DOCS + s.anchor) + '" target="_blank" rel="noopener" title="its section in docs/SETUP.md">SETUP.md ↗</a></div>';
  }
  function key(s) {
    return '<div class="sk"><span class="sl">' + esc(s.label) + '</span><code class="sn">' + esc(s.key) + "</code></div>";
  }
  // A colour of the status line's from an earlier 3.7.0: on is level, off auto.
  var OLD = { CLAUDE_HTML_STATUSLINE_COLOR: { on: "level", off: "auto" } };
  function shown(s) {
    var c = cur(s.key);
    if (s.kind === "enum") { var v = c.v ? c.v.toLowerCase() : s.def; return OLD[s.key] && OLD[s.key][v] || v; }
    return c.v;
  }
  function wasLine(s) {
    var p = pending[s.key];
    if (!p || p.op === "bad") return "";
    var c = cur(s.key), now = c.v ? c.v : s.def + " (default)";
    var to = p.op === "unset" ? s.def + " (default)" : p.value;
    var low = s.flags.low && (p.op === "set" ? p.value : s.def) === s.flags.low ? " · ⚠ lowers protection" : "";
    return ' <span class="was">· now ' + esc(now) + " → " + esc(to) + esc(low) + "</span>";
  }
  function envNote(s) {
    return forced(s.key) ? '<p class="senv">' + esc(s.key) + " is set in the environment this page was built in, which wins over the conf: " +
      "a change here would do nothing while it is set.</p>" : "";
  }
  function control(s) {
    var dis = forced(s.key) ? " disabled" : "", p = pending[s.key];
    if (s.kind === "items" && SLJ && !dis) return itemsList();
    if (s.kind === "enum") {
      var on = p && p.op === "set" ? p.value : p && p.op === "unset" ? s.def : shown(s);
      // The status line's colours: a dot of each fixed one before its name.
      var sw = s.key === "CLAUDE_HTML_STATUSLINE_COLOR";
      return '<span class="seg' + (sw ? " colors" : "") + '" role="group" aria-label="' + esc(s.label) + '">' + s.values.map(function (v) {
        return '<button data-k="' + esc(s.key) + '" data-v="' + esc(v) + '"' + (v === on ? ' class="on" aria-pressed="true"' : ' aria-pressed="false"') +
          dis + ">" + (sw && v !== "auto" && v !== "level" ? '<i class="sw sl-' + v + '" aria-hidden="true"></i>' : "") + esc(v) + "</button>";
      }).join("") + "</span>";
    }
    var val = typed.hasOwnProperty(s.key) ? typed[s.key] : cur(s.key).v;
    var cls = (s.kind === "duration" || s.kind === "week" || s.kind === "number" ? "short" : "") + (p && p.op === "bad" ? " bad" : "");
    return '<input type="text" data-k="' + esc(s.key) + '" value="' + esc(val) + '" placeholder="' + esc(s.def) + '"' +
      (cls ? ' class="' + cls.trim() + '"' : "") + ' spellcheck="false" autocomplete="off" aria-label="' + esc(s.label) + '"' + dis + ">";
  }
  function row(s, extra) {
    var c = cur(s.key), p = pending[s.key], h = "";
    var src = p && p.op !== "bad" ? "changed" : c.src;
    h += '<div class="srow' + (p && p.op !== "bad" ? " changed" : "") + (s.key === "CLAUDE_HTML_STATUSLINE_COLOR" ? " wide" : "") + '" data-row="' + esc(s.key) + '">' + key(s) + '<div class="sv"><div class="sc">';
    if (s.flags.ro) {
      h += '<code class="val">' + esc(c.v || s.def) + "</code>";
    } else {
      h += control(s);
      if ((c.src === "conf" && !(p && p.op === "unset")) || (p && p.op === "set")) {
        h += ' <button class="lnk" data-def="' + esc(s.key) + '" title="take its line out of the conf">use the default</button>';
      }
    }
    h += "</div>";
    if (p && p.op === "bad") h += '<p class="sw">' + esc(p.why) + "</p>";
    h += '<p class="sh">' + esc(s.help) + "</p>";
    h += '<p class="sd">default: ' + esc(s.def) + wasLine(s) + "</p>";
    h += envNote(s);
    if (extra) h += extra;
    h += "</div>" + meta(s, src) + "</div>";
    return h;
  }
  // A row for something that is not a setting: what the build saw.
  function info(label, sub, body, right) {
    return '<div class="srow"><div class="sk"><span class="sl">' + esc(label) + "</span>" +
      (sub ? '<code class="sn">' + esc(sub) + "</code>" : "") + '</div><div class="sv">' + body + "</div>" +
      '<div class="sm">' + (right || "") + "</div></div>";
  }
  function copy(cmd, label) { return '<button class="cp" data-c="' + esc(cmd) + '">' + esc(label || "copy") + "</button>"; }
  function code(t) { return "<code>" + esc(t) + "</code>"; }
  function when(secs) {
    if (!secs) return "";
    var d = new Date(secs * 1000), p = function (n) { return (n < 10 ? "0" : "") + n; };
    return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) + " " + p(d.getHours()) + ":" + p(d.getMinutes());
  }
  function inGroup(g) { return S.list.filter(function (s) { return s.group === g && !s.flags.hidden; }); }

  // ── the status line: its items, and a preview ─────────────────────
  // build/statusline.js draws the line as statusline.sh does, from the
  // latest figures this page was built with, or sample ones.
  var SLJ = typeof claudeHtmlStatusline === "function" ? claudeHtmlStatusline() : null;
  var ITEM_WORDS = { five: "5-hour window", week: "week", session: "this session's cost", today: "today's cost, all sessions",
    ctx: "context used", model: "Agent", project: "project · git branch", stop: "active stop rule", budget: "budget, when one is set" };
  // A setting as it would be with what is pending: its conf value, "" for the default.
  function eff(k) {
    var p = pending[k];
    if (p && p.op === "set") return p.value;
    if (p && p.op === "unset") return "";
    return cur(k).v;
  }
  function slSettings() {
    return SLJ.settings({ items: eff("CLAUDE_HTML_STATUSLINE_ITEMS"), form: eff("CLAUDE_HTML_STATUSLINE_FORM"),
      width: eff("CLAUDE_HTML_STATUSLINE_WIDTH"), bar: eff("CLAUDE_HTML_STATUSLINE_BAR"),
      from: eff("CLAUDE_HTML_STATUSLINE_BAR_FROM"), color: eff("CLAUDE_HTML_STATUSLINE_COLOR") });
  }
  function slList() { var st = slSettings(); return (st.items || SLJ.DEFAULT).slice(); }
  function itemClick(item, what) {
    var l = slList(), i = l.indexOf(item);
    if (what === "toggle") { if (i > -1) l.splice(i, 1); else l.push(item); }
    else if (what === "up" && i > 0) { l.splice(i, 1); l.splice(i - 1, 0, item); }
    else if (what === "down" && i > -1 && i < l.length - 1) { l.splice(i, 1); l.splice(i + 1, 0, item); }
    var v = l.length ? l.join(" ") : "none";
    if (v === S.byKey.CLAUDE_HTML_STATUSLINE_ITEMS.def) useDefault("CLAUDE_HTML_STATUSLINE_ITEMS");
    else propose("CLAUDE_HTML_STATUSLINE_ITEMS", v);
    draw();
  }
  function hm(d) { return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes(); }
  var WD = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  // The figures: the plan's latest as the build saw them, else samples.
  function slData() {
    var L = data.limits || {}, P = L.plan || {}, now = L.now || Math.round(Date.now() / 1000), d = {};
    function lbl(secs, day) { var t = new Date(secs * 1000), n = new Date(now * 1000);
      return !day && t.toDateString() === n.toDateString() ? hm(t) : WD[t.getDay()] + " " + hm(t); }
    d.mode = "plan";
    d.five = P.five && P.five.reset > now ? { tenths: Math.floor(P.five.pct * 10), label: lbl(P.five.reset) } : { tenths: 624, label: "16:30" };
    d.week = P.week ? { tenths: Math.floor(P.week.pct * 10), label: lbl(P.week.reset, true) } : { tenths: 230, label: "Tue 08:00" };
    var c = L.rules && L.rules.length && CHPlan.current ? CHPlan.current(L) : null;
    d.stop = c ? { pct: c.rule.pct, from: c.rule.day.charAt(0).toUpperCase() + c.rule.day.slice(1) + " " + c.rule.time,
                   hit: c.force && d.week.tenths >= c.rule.pct * 10 } : { pct: 80, from: "Fri 20:00", hit: false };
    d.session = "$1.12"; d.today = "$8.40"; d.ctx = 410;
    d.model = { id: "claude-opus-5-5", name: "Opus 5.5" };
    d.project = { name: "Trading", branch: "v2" };
    return d;
  }
  function slBudget() {
    var B = (data.limits || {}).budget;
    if (!B) return null;
    var word = B.period === "day" ? "today" : B.period === "month" ? "month" : "week", micro = data.spend ? data.spend.micro : 0;
    var t = Math.floor(micro * 1000 / (B.cents * 10000));
    return { mode: "budget", session: "$1.12", today: "$8.40", ctx: 410, model: { id: "claude-opus-5-5" }, project: { name: "Trading", branch: "v2" },
             budget: { known: !!data.spend, period: word, spent: CH.fmtMoney ? CH.fmtMoney(micro) : "$" + (micro / 1e6).toFixed(2),
                       spentMicro: micro, amount: String(B.amount), tenths: t, unit: B.period, label: B.end ? WD[new Date(B.end * 1000).getDay()] + " " + hm(new Date(B.end * 1000)) : "" } };
  }
  // The items: each on or off, those on in their order, moved up or down.
  function itemsList() {
    var l = slList(), all = l.concat(SLJ.ITEMS.filter(function (i) { return l.indexOf(i) < 0; }));
    return '<ol class="sli" aria-label="items">' + all.map(function (i) {
      var on = l.indexOf(i) > -1, at = l.indexOf(i);
      return '<li class="' + (on ? "on" : "off") + '"><button class="sltog" data-sli="' + i + '" data-do="toggle" aria-pressed="' + on + '">' +
        (on ? "on" : "off") + '</button><span class="sln">' + esc(ITEM_WORDS[i]) + '</span><code class="slk">' + i + "</code>" +
        (on ? '<span class="slm"><button class="lnk" data-sli="' + i + '" data-do="up"' + (at === 0 ? " disabled" : "") + ' title="earlier: condensed later">↑</button>' +
              '<button class="lnk" data-sli="' + i + '" data-do="down"' + (at === l.length - 1 ? " disabled" : "") + ' title="later: condensed sooner">↓</button></span>' : "") + "</li>";
    }).join("") + "</ol>";
  }
  function statusGroup() {
    var h = "", sI = S.byKey.CLAUDE_HTML_STATUSLINE_ITEMS;
    if (!SLJ) return inGroup("statusline").map(function (s) { return row(s); }).join("");
    h += row(sI, '<p class="sh">with the default, this session\'s cost also shows for API use, as before; listed, it shows always. ' +
      "In a terminal: " + code("claude-html --config set STATUSLINE_ITEMS=\"five week ctx model\"") + "</p>");
    ["CLAUDE_HTML_STATUSLINE_FORM", "CLAUDE_HTML_STATUSLINE_WIDTH", "CLAUDE_HTML_STATUSLINE_BAR",
     "CLAUDE_HTML_STATUSLINE_BAR_FROM", "CLAUDE_HTML_STATUSLINE_COLOR"].forEach(function (k) { h += row(S.byKey[k]); });
    var st = slSettings(), r = SLJ.render(st, slData()), b = slBudget(), rb = b ? SLJ.render(st, b) : null;
    function term(html, label) { return '<div class="slp"><span class="slpl">' + esc(label) + '</span><code class="term' + (st.color ? "" : " plain") + '">' + html + "</code></div>"; }
    // A terminal line is one line: the box wraps it only to stay readable,
    // and says how wide it really is, and whether it would be too wide.
    function cols(t) { return Array.from(t).length + " columns"; }
    function over(t) { return Array.from(t).length > st.width ? ", wider than " + st.width + ": auto condenses it" : ""; }
    var fits = st.form === "auto" ? "as it fits " + st.width + " columns" : st.form;
    h += '<div class="srow slrow" id="slpreview"><div class="sk"><span class="sl">Preview</span><code class="sn">with these choices</code></div><div class="sv">' +
      term(r.html, fits + " · " + cols(r.text)) + term(r.normalHtml, "normal · " + cols(r.normal) + over(r.normal)) +
      term(r.condensedHtml, "condensed · " + cols(r.condensed) + over(r.condensed)) +
      (rb ? term(rb.html, "API use, " + fits) : "") +
      '<p class="sh">' + (data.limits && data.limits.plan ? "the latest figures Claude Code gave, as of the build" : "sample figures") +
      "; the agent, project and costs are samples. The line runs after every reply; Claude Code says the terminal's width, and a line wider than it less 4 is condensed (auto) or cut.</p></div></div>";
    return h;
  }

  // ── each group, with what it adds ──────────────────────────────────
  var EXTRA = {
    where: function () {
      var cd = "cd " + shq(tilde(HERE)) + " && ";
      return S.list.filter(function (s) { return s.group === "where"; }).map(function (s) {
        var flag = s.key === "CLAUDE_HTML_OUT" ? "--out" : "--root";
        return row(s, '<p class="sx">to change it: ' + code("./install.sh " + flag + " DIR") + " in the clone " +
          copy(cd + "./install.sh " + flag + " DIR", "copy command") + "</p>");
      }).join("");
    },
    engine: function () {
      var e = SH.engine || {}, s = S.byKey.CLAUDE_HTML_ENGINE;
      var now = e.name ? (e.name === "node" && e.node ? "node " + e.nodeVersion + " (" + e.node + ")" : e.name) + " — " + e.why
        : "not known: this page was built straight from convert.js";
      return row(s, '<p class="sx">in use: ' + esc(now) + "</p>" + (e.note ? '<p class="sw">' + esc(e.note) + "</p>" : ""));
    },
    prices: function () {
      var P = data.prices || {};
      return row(S.byKey.CLAUDE_HTML_PRICES, '<p class="sx">in use: ' + code(tilde(P.path)) + " · " + (P.lines || 0) +
        " price line(s)" + (P.checked ? ' · <span style="white-space:nowrap">newest checked ' + esc(P.checked) + "</span>" : "") + "</p>");
    },
    secrets: function () {
      var R = data.redact || {};
      var list = !R.exists ? "no list there yet" : (R.own || 0) + " entr" + (R.own === 1 ? "y" : "ies") + " in the list" +
        (R.ignored ? " · " + R.ignored + " line(s) it cannot use: claude-html --doctor says which" : "");
      // Edit: the list in the text editor, by the settings link (asked in a
      // window first: what it holds would then be on the screen) or by the
      // command. Never its contents here.
      var edit = (data.actions ? ' <a class="go" href="' + esc("claude-html://settings/v1/" + (/^[0-9a-f]{16}$/.test(FP) ? FP : "none") + "/edit-list") +
        '" title="opens it in your text editor, after asking in a window">edit</a>' : "") + " " + copy("claude-html --config edit-list", "copy command");
      return row(S.byKey.CLAUDE_HTML_REDACT) + row(S.byKey.CLAUDE_HTML_REDACT_FILE,
        '<p class="sx">' + esc(list) + " (what it says is never shown)</p>" + '<p class="sx">' + edit.replace(/^ /, "") + "</p>" +
        (R.exists ? "" : '<p class="sh">edit makes it first, with a few lines that say what goes in it</p>'));
    },
    guard: function () {
      var R = data.redact || {}, H = data.hooks || {}, n = R.safe || 0, h = "";
      inGroup("guard").forEach(function (s) { h += row(s); });
      var g = shown(S.byKey.CLAUDE_HTML_GUARD);
      var miss = g !== "off" && data.hooks && !(H.guardPrompt && (g === "prompt" || H.guardBash));
      // Each safe value: its kind and its date, and an id the command
      // derives again; never the value, nor its salt or fingerprint.
      var SL = R.safeList || [], nf = Object.keys(forgetIds).length;
      var lines = SL.map(function (e) {
        var gone = forget || forgetIds[e.id];
        return '<li' + (gone ? ' class="gone"' : "") + '><span class="sk2">' + esc(e.kind || "kind unknown") + "</span>" +
          '<span class="sdt">' + esc(e.date || "") + '</span><code class="sid" title="its id: claude-html --config forget-safe ' + esc(e.id) + '">' + esc(e.id) + "</code>" +
          (forget ? "" : ' <button class="lnk" data-forget="' + esc(e.id) + '">' + (forgetIds[e.id] ? "keep" : "forget") + "</button>") + "</li>";
      }).join("");
      var said = n + " safe value" + (n === 1 ? "" : "s") + (forget ? " · all to forget" : nf ? " · " + nf + " to forget" : "");
      h += info("Safe values", "in the own list",
        '<div class="sc">' + (SL.length ? '<details class="safe"' + (nf || forget || safeOpen ? " open" : "") + '><summary>' + esc(said) + "</summary><ul>" + lines + "</ul></details>"
          : "<span>" + esc(said) + "</span>") +
        (n ? ' <button class="cp danger' + (forget ? " on" : "") + '" id="forget">' + (forget ? "forget them all · undo" : "forget them all") + "</button>" : "") +
        '</div><p class="sh">values you answered Safe for: never asked about again. Each is kept as a fingerprint only, so only what it was and when shows here. ' +
        "Forgetting takes out safe: lines only; your own entries stay.</p>" +
        (miss ? '<p class="sw">the guard\'s hooks are not in settings.json, so nothing is checked: ' + code("./install.sh") + " in the clone adds them</p>" : ""),
        forget || nf ? badge("changed") : "");
      return h;
    },
    // The panel is the one place its four settings are changed; each of its
    // rows says where its value comes from, as every other row does.
    limits: function () {
      var h = row(S.byKey.CLAUDE_HTML_LIMITS);
      h += '<div id="limits"></div>';
      var env = S.list.filter(function (s) { return s.flags.panel && forced(s.key); });
      if (env.length) h += '<p class="senv">' + esc(env.map(function (s) { return s.key; }).join(", ")) +
        " set in the environment this page was built in, which wins over the conf: a change in the panel would do nothing while it is set.</p>";
      return h;
    },
    statusline: function () { return statusGroup(); },
    updates: function () {
      var U = data.update || {}, h = row(S.byKey.CLAUDE_HTML_UPDATE_CHECK);
      var A = U.updated ? "installed " + U.updated.to + " by itself, " + when(U.updated.at) :
        U.deferred ? U.deferred + " put off: a save was running; the next one tries again" :
        U.failed ? U.failed + " failed and was rolled back; tried again a day later" :
        U.held ? U.held + " is a major release: claude-html --update installs it" : "";
      h += row(S.byKey.CLAUDE_HTML_AUTO_UPDATE, A ? '<p class="sx">last: ' + esc(A) + "</p>" : "");
      var line = "installed " + esc(U.installed || "?") + " · " + (U.newest ? "newest " + esc(U.newest) + (U.checked ? ", seen " + esc(when(U.checked)) : "")
        : "no check has run yet");
      var act = U.notice ? " " + copy("claude-html --update") + (data.actions ? ' <a class="go" href="claude-html://update" title="run the update in a terminal">run</a>' : "") : "";
      h += info("Release", "", '<div class="sc"><span>' + line + "</span>" + act + "</div>" +
        '<p class="sh">' + (U.notice ? esc(U.notice) + " is out: update with " + code("claude-html --update") :
        "the daily check asks the release repository for its tags; nothing about you is sent") + "</p>");
      return h;
    },
    claude: function () {
      var H = data.hooks, cd = "cd " + shq(tilde(HERE)) + " && ";
      if (!H) return info("settings.json", "~/.claude/settings.json", '<p class="sh">could not be read</p>');
      if (H.unreadable) return info("settings.json", "~/.claude/settings.json", '<p class="sw">it is not JSON claude-html can read, so nothing is known about it</p>');
      var days = H.cleanupPeriodDays, h = "";
      h += info("cleanupPeriodDays", "~/.claude/settings.json",
        '<div class="sc"><code class="val">' + (days === null ? "not set: Claude Code keeps transcripts 30 days" : esc(days) + " days") + "</code></div>" +
        '<p class="sh">Claude Code deletes transcripts after this many days. It is Claude Code\'s setting: change it in ' + code("~/.claude/settings.json") +
        "; " + code("./install.sh") + " sets 3650 only when it is not set. This page never writes that file.</p>" +
        (typeof days === "number" && days < 365 ? '<p class="sw">under a year: older transcripts go, and only their archives stay</p>' : ""),
        '<a href="' + esc(DOCS + "transcript-cleanup") + '" target="_blank" rel="noopener">SETUP.md ↗</a>');
      function mark(ok, name) { return '<span class="hook"><span class="' + (ok ? "yes" : "no") + '">' + (ok ? "✓" : "✗") + "</span> " + esc(name) + "</span>"; }
      var saves = H.Stop && H.SessionEnd && H.PreCompact, guard = H.guardPrompt && H.guardBash;
      var sl = H.statusLine === "ours" || H.statusLine === "wrapped";
      var fix = [];
      if (!saves || !sl || (!guard && shown(S.byKey.CLAUDE_HTML_GUARD) !== "off")) fix.push(copy(cd + "./install.sh", "copy ./install.sh"));
      if (guard && shown(S.byKey.CLAUDE_HTML_GUARD) === "off") fix.push(copy(cd + "./install.sh --no-guard", "copy ./install.sh --no-guard"));
      h += info("Hooks", "~/.claude/settings.json",
        '<p class="sx">' + mark(H.Stop, "save after a reply (Stop)") + mark(H.SessionEnd, "save at the end (SessionEnd)") +
        mark(H.PreCompact, "save before compacting (PreCompact)") + "</p>" +
        '<p class="sx">' + mark(H.guardPrompt, "guard: prompts") + mark(H.guardBash, "guard: commands") +
        mark(sl, "status line" + (H.statusLine === "wrapped" ? ", around yours" : H.statusLine === "yours" ? ": yours, not claude-html's" : "")) + "</p>" +
        '<p class="sh">' + code("./install.sh") + " adds what is missing beside your own hooks; " + code("./install.sh --no-guard") +
        " leaves the guard's two out and turns it off. Run either in the clone.</p>" +
        (fix.length ? '<p class="sx">' + fix.join(" ") + "</p>" : ""),
        '<a href="' + esc(DOCS + "hooks") + '" target="_blank" rel="noopener">SETUP.md ↗</a>');
      return h;
    },
    view: function () {
      var h = "", NAME = { CLAUDE_HTML_VIEW_THEME: "theme", CLAUDE_HTML_VIEW_GROUP: "group", CLAUDE_HTML_VIEW_SESSION: "session",
                          CLAUDE_HTML_VIEW_PERIOD: "period", CLAUDE_HTML_VIEW_BREAKDOWN: "breakdown", CLAUDE_HTML_VIEW_PRICES: "prices" };
      var any = false;
      inGroup("view").forEach(function (s) {
        var n = NAME[s.key], st = n ? CH.stored(n) : null, word = null;
        if (st !== null) {
          var map = CH.PREFS[n][1];
          for (var w in map) if (map[w] === st) word = w;
        }
        var conf = shown(s);
        if (word !== null && word !== conf) any = true;
        h += row(s, word !== null && word !== conf ? '<p class="sx">this browser: ' + esc(word) + ", from a click it remembers</p>" : "");
      });
      h += info("This browser", "", '<div class="sc"><button class="cp" id="reset">reset this browser</button><span class="sh" id="resetsaid"></span></div>' +
        '<p class="sh">a click on a page changes its view at once, and this browser remembers it over the conf\'s default. ' +
        "Reset forgets what this browser remembered (claude-html's own keys only), so the defaults apply again." +
        (any ? "" : " It remembers nothing that differs now.") + "</p>");
      return h;
    },
    about: function () {
      var e = SH.engine || {};
      var rows = [
        ["Version", VERSION || "?"],
        ["Conf", tilde(SH.conf || "") + (FP === "none" ? " (not there yet)" : "")],
        ["Engine", e.name ? e.name + (e.node ? " · node " + e.nodeVersion + " at " + e.node : "") : "?"],
        ["System", SH.system || "?"],
        [SH.os === "darwin" ? "Helper app" : "Link handler", (SH.links || "?") + (data.actions ? "" : " · the pages offer no apply, delete or resume links")],
        ["Pages", tilde(decodeURIComponent(location.pathname).replace(/\/[^\/]*$/, ""))],
        ["Projects", tilde(data.root)],
        ["Clone", tilde(HERE)]
      ];
      return rows.map(function (r) { return info(r[0], "", '<div class="sc"><span>' + esc(r[1]) + "</span></div>"); }).join("") +
        info("Everything", "", '<div class="sc">' + code("claude-html --doctor") + " " + copy("claude-html --doctor") + "</div>" +
          '<p class="sh">what this machine is, and which of its tools does each job</p>');
    }
  };
  var GROUPS = S.groups.filter(function (g) { return g.id !== "conf"; }).map(function (g) { return { id: g.id, title: g.title }; });
  // Claude Code's side sits before the page defaults; About this machine last.
  GROUPS.splice(GROUPS.map(function (g) { return g.id; }).indexOf("view"), 0, { id: "claude", title: "Claude Code side" });
  GROUPS.push({ id: "about", title: "About this machine" });

  var root = document.getElementById("groups"), limEl = null, safeOpen = false;
  function draw() {
    var so = root.querySelector("details.safe");
    if (so) safeOpen = so.open;
    var focus = document.activeElement && root.contains(document.activeElement) && document.activeElement.tagName === "INPUT" ?
      [document.activeElement.getAttribute("data-k"), document.activeElement.selectionStart] : null;
    var h = "";
    GROUPS.forEach(function (g) {
      h += '<h2 id="g-' + g.id + '">' + esc(g.title) + "</h2>";
      h += EXTRA[g.id] ? EXTRA[g.id]() : inGroup(g.id).map(function (s) { return row(s); }).join("");
    });
    root.innerHTML = h;
    // The panel is drawn once and kept: what is typed in it outlives a
    // change elsewhere on the page.
    var lim = document.getElementById("limits");
    if (lim && typeof CHPlan !== "undefined") {
      if (!limEl) {
        limEl = lim;
        CHPlan.panel(limEl, limitsData(), { actions: !!data.actions, open: true, meta: function (k) {
          var s = S.byKey[k]; return s ? meta(s, cur(k).src) : "";
        } });
        limEl.hidden = false;
      }
      else lim.parentNode.replaceChild(limEl, lim);
    }
    if (focus) {
      var f = root.querySelector('input[data-k="' + focus[0] + '"]');
      if (f) { f.focus(); try { f.setSelectionRange(focus[1], focus[1]); } catch (e) {} }
    }
    bar();
  }
  // The panel's data: the build's, or, with nothing set and nothing seen
  // (when limits.sh gives the pages none), the settings as they stand.
  function limitsData() {
    if (data.limits) return data.limits;
    var w = String(cur("CLAUDE_HTML_BUDGET_WARN").v || "80 95").split(/[\s,%]+/).filter(Boolean).map(Number);
    return { on: !/^(off|0|no|false)$/i.test(cur("CLAUDE_HTML_LIMITS").v || ""), rules: [], budget: null,
             warn: w.length === 2 && w[0] < w[1] ? w : [80, 95], notify: /^(on|1|yes|true)$/i.test(cur("CLAUDE_HTML_LIMIT_NOTIFY").v || ""),
             week: null, plan: null, now: Math.round(Date.now() / 1000) };
  }

  // ── the bar ────────────────────────────────────────────────────────
  var B = document.getElementById("bar");
  function bar() {
    var ch = changes(), bad = S.list.filter(function (s) { return pending[s.key] && pending[s.key].op === "bad"; });
    var good = ch.filter(function (c) { return c.op !== "bad"; });
    B.hidden = !ch.length;
    document.body.style.paddingBottom = ch.length ? "90px" : "";
    if (!ch.length) return;
    var n = good.length;
    document.getElementById("bn").textContent = n + " change" + (n === 1 ? "" : "s") + (bad.length ? " · " + bad.length + " not valid" : "");
    var link = bad.length || !n ? null : S.linkFor(FP, good);
    var cmd = n ? S.commandFor(good) : "";
    var cp = document.getElementById("bcopy"), ap = document.getElementById("bapply");
    cp.disabled = !!bad.length || !n; cp.setAttribute("data-c", cmd);
    var can = !!link && !!data.actions;
    ap.classList.toggle("off", !can); ap.href = can ? link : "#";
    ap.hidden = !data.actions;
    var hint = bad.length ? "fix what is marked first" :
      !data.actions ? "no helper app or link handler here: copy the command and run it in a terminal" :
      !link ? "too many changes for one link: copy the command instead" :
      "apply asks in a window first, then writes the conf and rebuilds the pages · copy command gives the same change as claude-html --config lines";
    document.getElementById("bh").textContent = hint;
  }
  document.getElementById("bdiscard").addEventListener("click", function () {
    pending = {}; forget = false; forgetIds = {}; typed = {}; draw();
  });
  document.getElementById("bapply").addEventListener("click", function (e) {
    if (this.classList.contains("off")) e.preventDefault();
  });

  // ── what a click or a key does ─────────────────────────────────────
  root.addEventListener("click", function (e) {
    var t = e.target;
    if (t.matches(".seg button[data-k]") && !t.disabled) {
      propose(t.getAttribute("data-k"), t.getAttribute("data-v"));
      draw();
    } else if (t.hasAttribute("data-def")) {
      useDefault(t.getAttribute("data-def")); draw();
    } else if (t.id === "forget") {
      forget = !forget; forgetIds = {}; draw();
    } else if (t.hasAttribute("data-forget")) {
      var id = t.getAttribute("data-forget");
      if (forgetIds[id]) delete forgetIds[id]; else forgetIds[id] = 1;
      draw();
    } else if (t.hasAttribute("data-sli")) {
      itemClick(t.getAttribute("data-sli"), t.getAttribute("data-do"));
    } else if (t.id === "reset") {
      var n = CH.forgetPrefs();
      draw();
      var said = document.getElementById("resetsaid");
      if (said) said.textContent = n ? "forgot " + n + " remembered view(s); reload a page to see its default" : "nothing was remembered";
    }
  });
  root.addEventListener("input", function (e) {
    var t = e.target;
    if (t.tagName !== "INPUT" || !t.hasAttribute("data-k")) return;
    propose(t.getAttribute("data-k"), t.value);
    draw();
  });

  // ── the words at the top ───────────────────────────────────────────
  document.getElementById("sub").innerHTML =
    "Every claude-html setting, as of the last build. Each comes from the environment, then the conf, " +
    code(tilde(SH.conf || "~/.claude/claude-html.conf")) + ", then its default. " +
    "The page writes nothing: <b>apply</b> asks in a window first, and " + code("claude-html --config") +
    " does the same from a terminal; any change rebuilds the pages." +
    (data.partial ? " <b>Built straight from convert.js</b>, so nothing is known of the conf here: " +
      code("claude-html") + " builds it whole." : "");
  document.getElementById("toc").innerHTML = GROUPS.map(function (g) {
    return '<a href="#g-' + g.id + '">' + esc(g.title) + "</a>";
  }).join("");
  draw();
})();
