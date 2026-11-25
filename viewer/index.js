// The index: every session, filterable, and full-text search across all of
// them. Renders from the manifest embedded in the page.
(function () {
  "use strict";

  var data = JSON.parse(document.getElementById("index-data").textContent);
  var sessions = data.sessions || [];
  var home = data.home || "";
  var errors = data.errors || [];
  // The bin, the project links and the resume links are claude-html://
  // links, which need something to receive them: the helper app on macOS, the
  // desktop handler on Linux. Without one they would be controls that do
  // nothing while promising to delete things, so they are not drawn. An index
  // built before "actions" existed said "mac", and one before that came from
  // a mac.
  var mac = "actions" in data ? !!data.actions : data.mac !== false;

  function esc(s) { return CH.esc(s); }

  CH.themeInit(document.getElementById("theme"));
  // The plan's figures and the stop rule, between the build line and the
  // search box, where the build put some (plan.js).
  if (typeof CHPlan !== "undefined") CHPlan.mount(data);

  function stamp(secs) {
    if (!secs) return "";
    var d = new Date(secs * 1000);
    return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" +
      ("0" + d.getDate()).slice(-2) + " " + ("0" + d.getHours()).slice(-2) + ":" +
      ("0" + d.getMinutes()).slice(-2);
  }
  // The same on a row, with the time in a span of its own: a narrow window
  // drops it and keeps the day, which gives the title its width back.
  function stampCell(secs) {
    var t = stamp(secs);
    return t ? t.slice(0, 10) + '<span class="hm">' + t.slice(10) + "</span>" : "";
  }

  // How old the page is, in the one unit that reads at a glance.
  function ago(secs) {
    var m = Math.floor((Date.now() / 1000 - secs) / 60);
    if (m < 1) return "just now";
    if (m < 60) return m + " min ago";
    if (m < 60 * 48) return Math.floor(m / 60) + " h ago";
    return Math.floor(m / 1440) + " days ago";
  }

  // When the page was built. A hook that has stopped firing leaves the index
  // looking perfectly healthy, only old, and this is the one place that says so.
  if (data.built) {
    var bt = document.getElementById("built");
    bt.textContent = " · built " + stamp(data.built) + " (" + ago(data.built) + ")";
    bt.title = "when claude-html last wrote this page";
  }
  // A newer release, as the daily check last saw it. The build put it here;
  // the page asks nothing of the network.
  var up = document.getElementById("update");
  if (up && /^\d+\.\d+\.\d+$/.test(data.update || "")) {
    // copy is the rows' own button, on the rows' own click handler; run is
    // a link for the helper or the Linux handler, drawn only where one is.
    up.innerHTML = esc(data.update) + " is out · update with <code>claude-html --update</code>" +
      ' <button class="cp" data-c="claude-html --update">copy</button>' +
      (mac ? '<a class="go" href="claude-html://update" title="run the update in a terminal">run</a>' : "");
    up.hidden = false;
  }
  // Updated by itself (CLAUDE_HTML_AUTO_UPDATE): said for a day after.
  var ud = document.getElementById("updated"), U = data.updated;
  if (ud && U && /^\d+\.\d+\.\d+$/.test(U.to || "") && Date.now() / 1000 - U.at < 86400) {
    ud.innerHTML = "updated to " + esc(U.to) + " by itself, " + esc(stamp(U.at)) +
      " · what changed: <code>CHANGELOG.md</code> in the clone · <code>claude-html --update status</code>";
    ud.hidden = false;
  }
  // How to reopen a conversation, said plainly. Every build that carries
  // "actions" also wrote a launcher per conversation into resume/.
  var launch = document.getElementById("launch");
  if (mac) {
    launch.innerHTML = " · to reopen a conversation, click its <b>resume</b>," +
      " or double-click its file in <code>resume/</code>";
  } else if ("actions" in data) {
    launch.innerHTML = " · to reopen a conversation, paste its <b>copy</b> into a terminal," +
      " or double-click its file in <code>resume/</code>";
  } else {
    launch.hidden = true;
  }
  if (!mac) document.getElementById("ix").classList.add("nomac");

  // ── failures are never silent ──────────────────────────────────────
  if (errors.length) {
    document.getElementById("errors").innerHTML =
      "<strong>" + errors.length + " session(s) could not be built.</strong><ul>" +
      errors.map(function (e) {
        return "<li>" + esc(e.id || "?") + " — " + esc(e.error || "unknown") +
               (e.source ? ' <span class="d">' + esc(e.source) + "</span>" : "") + "</li>";
      }).join("") + "</ul>";
    document.getElementById("errors").hidden = false;
  }

  // ── the table ──────────────────────────────────────────────────────
  // The bin is a claude-html:// link. A page opened from disk may not delete
  // files, so the helper app receives it, shows what would go, and waits for
  // you to confirm in a dialog of its own.
  function bin(s) {
    if (!mac) return "";
    var web = s.kind === "web";
    // The icon alone says nothing to a screen reader: the label says it.
    var what = web ? "hide this chat from the index" : "delete this conversation and its history";
    return '<a class="del" href="claude-html://delete/' + esc(s.id) + '" title="' + what +
      '" aria-label="' + what + '">' + (web ? "⊘" : "✕") + "</a>";
  }

  // The project name opens the project. A claude.ai chat has no folder, and
  // the pseudo-projects (~ and the projects root itself) are not projects.
  function project(s) {
    var name = esc(s.project || "");
    if (!mac || !s.cwd || s.kind === "web") return name;
    return '<a class="proj" href="claude-html://open/' + esc(s.id) + '" title="open this ' +
      'project: its server if one is running, otherwise its page or its folder">' + name + "</a>";
  }

  // What Claude Code recorded the session cost, at API list prices. Most
  // sessions predate the record and say "—", never "$0.00"; "≥" marks one
  // whose record covers only part of it. Whole dollars from ten up, so the
  // column stays narrow enough for the title to keep its room.
  // Where nothing was recorded, the cost calculated from the price file,
  // marked "calc": never mistaken for what Claude Code recorded.
  function cost(s) {
    if ((!s.tok || s.tok.length < 6) && s.calc !== undefined && s.calc !== null) {
      return '<td class="num cost calc" title="calculated from the price file at the price of the time' +
        (s.calcPart ? "; some models have no price line, so at least this" : "") +
        ': Claude Code recorded no cost">' + (s.calcPart ? "≥ " : "") + CH.fmtMoney(s.calc, true) +
        ' <span class="cm">calc</span></td>';
    }
    if (!s.tok || s.tok.length < 6) return '<td class="num cost d">—</td>';
    return '<td class="num cost" title="' + (s.costPart
      ? "at least: some replies fall outside what Claude Code recorded"
      : "as Claude Code recorded it, at API list prices") + '">' +
      (s.costPart ? "≥ " : "≈ ") + CH.fmtMoney(s.tok[5], true) + "</td>";
  }

  function row(s, inGroup) {
    // Copy puts the command on the clipboard; resume runs it, through the
    // launcher in resume/, by way of the helper.
    var action = CH.resumable(s)
      ? '<button class="cp" data-c="' + esc(CH.resumeCmd(s, home)) + '">copy</button>' +
        (mac ? '<a class="go" href="claude-html://resume/' + esc(s.id) +
               '" title="reopen this conversation in a terminal">resume</a>' : "")
      : (s.url ? '<a href="' + esc(s.url) + '">open ↗</a>' : '<span class="d">—</span>');
    // A page built before its source changed is saying something out of date.
    var stale = s.stale ? ' <span class="stale" title="the source has changed since this was built">stale</span>' : "";
    // Under a project heading the project cell would say the heading again,
    // so it is left empty — but the name is still on the row, in data-proj,
    // because searching for a project has to keep working either way.
    var href = "sessions/" + esc(s.id) + ".html";
    return '<tr data-href="' + href + '" data-proj="' +
      esc(s.project || "") + '"><td class="dt">' + stampCell(s.mtime) + "</td><td>" +
      (inGroup ? "" : project(s)) + "</td>" +
      // The title truncates; the sub-agent count sits beside it and does not,
      // so a long title can never hide how many agents a session spawned.
      // The flex row lives in a div inside the cell. A <td> made display:flex
      // stops being a table cell at all, and the whole row comes apart.
      // The title is the link to the conversation: the one way to it that is
      // there at every width, and the one a keyboard can reach.
      '<td class="what"><div class="wl"><a class="ti" href="' + href + '" title="' +
      esc(s.title || s.id) + '">' + esc(s.title || s.id.slice(0, 8) + "…") + "</a>" +
      (s.agents ? '<span class="nag">' + s.agents + " agent" + (s.agents === 1 ? "" : "s") +
        "</span>" : "") + "</div></td>" +
      '<td class="num">' + (s.prompts || 0) + "</td>" +
      // The whole transcript's, a copy from a resume or a fork included.
      '<td class="num tok"' + (s.shares && s.shares[0] ? ' title="incl. ' + CH.fmtTokens(s.shares[1]) +
        ' tokens also in another session (a resume or a fork): all usage counts them once"' : "") +
      ">" + (s.tok ? CH.fmtTokens(s.tok[0] + s.tok[1] + s.tok[2] + s.tok[3]) : "") +
      "</td>" + cost(s) +
      '<td class="d">' + esc(s.kind) + stale + "</td>" +
      '<td><a href="sessions/' + esc(s.id) + '.html">' + esc(s.id.slice(0, 8)) + "…</a></td>" +
      "<td>" + action + "</td><td>" + bin(s) + "</td></tr>";
  }

  var tbody = document.getElementById("rows");
  var table = document.getElementById("ix");
  var rows = [], order = [];

  // What the filter above the table searches: the row's date, project, title
  // and id — not the words on its buttons, or "copy" would match every row.
  function filterText(s) {
    return [stamp(s.mtime), s.project || "", s.title || "", s.id].join(" ");
  }

  // Sessions of the same project, gathered. Most projects have one, which is
  // why the toggle only appears when at least one of them has more.
  var byProject = {}, names = [];
  sessions.forEach(function (s) {
    var k = s.project || "";
    if (!byProject[k]) { byProject[k] = []; names.push(k); }
    byProject[k].push(s);
  });
  var worthGrouping = names.some(function (k) { return byProject[k].length > 1; });
  // Projects in the order you last worked on them, not alphabetically: the
  // one you were in an hour ago belongs at the top.
  names.sort(function (a, b) { return newest(byProject[b]) - newest(byProject[a]); });
  function newest(list) {
    return list.reduce(function (m, s) { return Math.max(m, s.mtime || 0); }, 0);
  }

  var grouped = false;
  grouped = CH.pref("group", "0") === "1";
  if (!worthGrouping) grouped = false;

  function heading(name) {
    var list = byProject[name];
    var prompts = list.reduce(function (t, s) { return t + (s.prompts || 0); }, 0);
    // The heading opens the project, like the name on a row does. It uses the
    // most recent session, since the link carries a session id.
    var openable = list.filter(function (s) { return s.cwd && s.kind !== "web"; })[0];
    // A reply copied by a resume or a fork counts once, as on the dashboard.
    var tok = list.reduce(function (t, s) {
      return t + (s.tok ? s.tok[0] + s.tok[1] + s.tok[2] + s.tok[3] - (s.dup || 0) : 0);
    }, 0);
    return '<tr class="grp"><th colspan="' + visibleCols() + '">' +
      (openable ? project(openable) : esc(name || "—")) +
      ' <span class="gc">' + CH.plural(list.length, "session") +
      " · " + CH.plural(prompts, "prompt") +
      (tok ? " · " + CH.fmtTokens(tok) + " tokens" : "") + "</span></th></tr>";
  }

  // A heading spans the columns that are showing, not all ten: a narrow
  // window hides some, and a span over hidden ones adds columns of its own
  // to the table, which took their width from the title.
  function visibleCols() {
    var n = [].filter.call(document.querySelectorAll("#ix thead th"), function (th) {
      return window.getComputedStyle(th).display !== "none";
    }).length;
    return n || 10;
  }
  function fitHeadings() {
    var n = visibleCols();
    [].forEach.call(tbody.querySelectorAll("tr.grp th"), function (th) {
      if (th.colSpan !== n) th.colSpan = n;
    });
  }
  window.addEventListener("resize", fitHeadings);
  // Paper hides resume and the bin, so the span is counted again for it.
  window.matchMedia("print").addListener(fitHeadings);

  function draw() {
    // Grouped, the project is the heading, so its column goes.
    table.classList.toggle("grouped", grouped);
    order = [];
    tbody.innerHTML = grouped
      ? names.map(function (name) {
          var list = byProject[name].slice()
            .sort(function (a, b) { return (b.mtime || 0) - (a.mtime || 0); });
          order = order.concat(list);
          return heading(name) + list.map(function (s) { return row(s, true); }).join("");
        }).join("")
      : (order = sessions.slice()).map(function (s) { return row(s, false); }).join("");
    rows = [].slice.call(tbody.querySelectorAll("tr:not(.grp)"));
    rows.forEach(function (r, i) { r.dataset.s = filterText(order[i]); });
  }
  draw();
  document.getElementById("count").textContent = CH.plural(sessions.length, "session");

  // A heading with nothing under it is noise, so it goes while a search is
  // narrowing the table down.
  function syncGroups() {
    [].slice.call(tbody.querySelectorAll("tr.grp")).forEach(function (g) {
      var any = false, r = g.nextElementSibling;
      while (r && !r.classList.contains("grp")) {
        if (!r.hidden) any = true;
        r = r.nextElementSibling;
      }
      g.hidden = !any;
    });
  }

  (function groupToggle() {
    var view = document.getElementById("view");
    var bd = document.getElementById("gdate"), bp = document.getElementById("gproj");
    if (!worthGrouping) return;              // nothing to group
    view.hidden = false;
    function paint() {
      bd.classList.toggle("on", !grouped);
      bp.classList.toggle("on", grouped);
      bd.setAttribute("aria-pressed", String(!grouped));
      bp.setAttribute("aria-pressed", String(grouped));
    }
    function set(v) {
      if (v === grouped) return;
      grouped = v;
      try { localStorage.setItem("ch-group", v ? "1" : "0"); } catch (e) {}
      paint();
      draw();
      run();                                 // the table was rebuilt under it
    }
    bd.addEventListener("click", function () { set(false); });
    bp.addEventListener("click", function () { set(true); });
    paint();
  })();

  if (!sessions.length) {
    // A table of headings over nothing says less than the sentence does.
    document.getElementById("tw").hidden = true;
    document.getElementById("empty").innerHTML =
      "No sessions yet. They appear here as you use Claude Code — run " +
      "<code>claude-html</code> again once one has ended.<br>Looking for projects under " +
      "<code>" + esc(data.root || "") + "</code>; change that in " +
      "<code>~/.claude/claude-html.conf</code>.";
    document.getElementById("empty").hidden = false;
  }

  document.addEventListener("click", function (e) {
    if (!e.target.matches("button.cp")) return;
    navigator.clipboard.writeText(e.target.dataset.c).then(function () {
      e.target.textContent = "copied";
      setTimeout(function () { e.target.textContent = "copy"; }, 1200);
    });
  });

  // Deleting happens in another app, so there is nothing here to wait on. The
  // page remembers what it asked to have deleted, and each time the window
  // comes back it reloads until that conversation is gone: the browser's own
  // "open this app?" prompt can hand focus back before the helper has even
  // started, so one reload is not always enough. It gives up after a few goes
  // or a minute, which is what a cancelled delete looks like from here.
  var PENDING = "ch-deleting", LIMIT = 3, WINDOW_MS = 60000;

  function pending(v) {
    try {
      if (v === undefined) return JSON.parse(sessionStorage.getItem(PENDING) || "null");
      if (v) sessionStorage.setItem(PENDING, JSON.stringify(v));
      else sessionStorage.removeItem(PENDING);
    } catch (e) {}
    return null;
  }

  function armReload(p) {
    var a = document.querySelector('a.del[href$="/' + p.id + '"]');
    if (a && a.closest("tr")) a.closest("tr").classList.add("pending");
    // Only a return from somewhere else counts. Loading a page fires focus by
    // itself, so watching focus alone would have the page reload itself over
    // and over after a delete that was cancelled.
    var away = false;
    function blurred() { away = true; }
    function back() {
      if (!away) return;
      window.removeEventListener("blur", blurred);
      window.removeEventListener("focus", back);
      p.tries++;
      pending(p);
      setTimeout(function () { location.reload(); }, 300);
    }
    window.addEventListener("blur", blurred);
    window.addEventListener("focus", back);
  }

  document.addEventListener("click", function (e) {
    var a = e.target.closest && e.target.closest("a.del");
    if (!a) return;
    var p = { id: a.getAttribute("href").split("/").pop(), at: Date.now(), tries: 0 };
    pending(p);
    armReload(p);
  });

  (function resumeDelete() {
    var p = pending();
    if (!p) return;
    if (!mac) { pending(null); return; }
    var still = sessions.some(function (s) { return s.id === p.id; });
    if (!still || p.tries >= LIMIT || Date.now() - p.at > WINDOW_MS) { pending(null); return; }
    armReload(p);
  })();

  // The whole row opens the conversation. Not when something else on the row
  // was clicked — a link, the copy button, the bin — and not when you were
  // only selecting text, which is a click as far as the browser is concerned.
  tbody.addEventListener("click", function (e) {
    if (e.target.closest("a,button,input,label")) return;
    var tr = e.target.closest("tr");
    if (!tr || !tr.dataset.href) return;
    if (String(window.getSelection())) return;
    if (e.metaKey || e.ctrlKey || e.shiftKey) window.open(tr.dataset.href, "_blank");
    else location.href = tr.dataset.href;
  });

  // ── search ─────────────────────────────────────────────────────────
  var q = document.getElementById("q"),
      n = document.getElementById("n"),
      mh = document.getElementById("mh"),
      mr = document.getElementById("mr"),
      LC = null, loading = false, noIndex = false, missing = 0, timer;

  // Match case, or not. Everything that compares text goes through fold(), so
  // the table filter, the message search and the highlighting always agree.
  var csBox = document.getElementById("cs"), sb = document.getElementById("sb");
  var cs = false;
  try { cs = localStorage.getItem("ch-case") === "1"; } catch (e) {}
  csBox.checked = cs;
  function fold(s) { return cs ? s : s.toLowerCase(); }
  function showOption() { sb.classList.toggle("on", !!q.value || cs); }
  csBox.addEventListener("change", function () {
    cs = csBox.checked;
    try { localStorage.setItem("ch-case", cs ? "1" : "0"); } catch (e) {}
    showOption();
    run();
  });

  // Quoted runs stay together; everything else splits on whitespace.
  // The longest word or phrase searched for, as typed: the session page
  // looks for it again, which opens what hides it (thinking starts folded).
  function findWord(s) {
    var best = "", re = /"([^"]+)"|(\S+)/g, m;
    while ((m = re.exec(s)) !== null) {
      var w = m[1] || m[2];
      if (w.length > best.length) best = w;
    }
    return best.length >= 2 ? ":find=" + encodeURIComponent(best) : "";
  }
  function parse(s) {
    var out = [], re = /"([^"]+)"|(\S+)/g, m;
    while ((m = re.exec(s)) !== null) out.push(fold(m[1] || m[2]));
    return out;
  }

  function hi(s, ts) {
    var lo = fold(s), marks = [];
    ts.forEach(function (t) {
      var i = lo.indexOf(t);
      while (i > -1) { marks.push([i, i + t.length]); i = lo.indexOf(t, i + t.length); }
    });
    if (!marks.length) return esc(s);
    marks.sort(function (a, b) { return a[0] - b[0]; });
    var out = "", pos = 0;
    marks.forEach(function (m) {
      if (m[0] < pos) return;
      out += esc(s.slice(pos, m[0])) + "<mark>" + esc(s.slice(m[0], m[1])) + "</mark>";
      pos = m[1];
    });
    return out + esc(s.slice(pos));
  }

  function snippet(text, lo, ts) {
    var p = lo.indexOf(ts[0]);
    if (p < 0) p = 0;
    var a = Math.max(0, p - 90), b = Math.min(text.length, a + 320);
    return (a > 0 ? "…" : "") + hi(text.slice(a, b), ts) + (b < text.length ? "…" : "");
  }

  // One small script per session, so a save rewrites only the one that changed.
  // They load on the first keystroke, as script tags because file:// blocks
  // fetch, and are put back in the index's order once they have all arrived.
  var parts = {};
  window.CH_SEARCH = function (id, rows) { parts[id] = rows; };

  // Nothing could be loaded at all: say so in both places, every time, rather
  // than leave "searching…" standing forever.
  function noSearch(shown) {
    mr.innerHTML = '<p class="d">no search index — run <code>claude-html</code> to build one</p>';
    n.textContent = shown + " of " + CH.plural(rows.length, "session") + " · messages not searchable";
  }

  function need(cb, shown) {
    if (window.SEARCH) { cb(); return; }
    if (noIndex) { noSearch(shown); return; }
    if (loading) return;
    loading = true;
    mh.hidden = false;
    mr.innerHTML = '<p class="d">loading conversations…</p>';
    var left = sessions.length, loaded = 0;
    function settle() { if (--left === 0) done(); }
    function done() {
      loading = false;
      // A part that is missing, or that loaded without handing over its rows,
      // is a conversation the results below cannot contain.
      missing = sessions.filter(function (s) { return !parts[s.id]; }).length;
      if (sessions.length && !loaded) {
        noIndex = true;
        run();
        return;
      }
      window.SEARCH = sessions
        .filter(function (s) { return parts[s.id] && parts[s.id].length; })
        .map(function (s) { return [s.id, s.project || "", s.title || "", parts[s.id]]; });
      LC = window.SEARCH.map(function (x) {
        return x[3].map(function (r) { return r[2].toLowerCase(); });
      });
      // Search again rather than finish the first query: whatever was typed
      // while this loaded is what should be shown.
      run();
    }
    if (!left) { done(); return; }
    sessions.forEach(function (s) {
      var tag = document.createElement("script");
      tag.src = "search/" + encodeURIComponent(s.id) + ".js";
      tag.onload = function () { loaded++; settle(); };
      tag.onerror = settle;
      document.head.appendChild(tag);
    });
  }

  var WHO = { u: "You", t: "Claude", k: "thinking" };

  // Newest first: what you said last week is likelier to be what you meant
  // than the same words in a session from March. Each session's messages
  // are read from its last back, so the PER it shows are its newest, and
  // every match is counted, so the page can say how many it is not showing.
  var CAP = 200, PER = 5;
  function messages(ts) {
    var found = [];
    for (var i = 0; i < window.SEARCH.length; i++) {
      var sess = window.SEARCH[i], rws = sess[3], lc = LC[i], f = null;
      for (var j = rws.length - 1; j >= 0; j--) {
        var lo = cs ? rws[j][2] : lc[j], ok = true;
        for (var k = 0; k < ts.length; k++) {
          if (lo.indexOf(ts[k]) < 0) { ok = false; break; }
        }
        if (!ok) continue;
        if (!f) found.push(f = { sess: sess, hits: [], n: 0, next: null });
        f.n++;
        if (f.hits.length < PER) f.hits.push([sess, rws[j], lo, f]);
        else if (!f.next) f.next = rws[j];
      }
    }
    return found;
  }

  function render(found, ts, shown) {
    var hits = [], total = 0, ids = {};
    found.forEach(function (f) {
      hits = hits.concat(f.hits);
      total += f.n;
      ids[f.sess[0]] = 1;
      f.left = f.n;
    });
    hits.sort(function (a, b) { return (b[1][3] || 0) - (a[1][3] || 0); });
    var cut = hits.slice(CAP);
    hits = hits.slice(0, CAP);
    // A hit the cap left out is where that session's "more" link goes.
    cut.forEach(function (h) { if (!h[3].cutAt) h[3].cutAt = h[1]; });
    hits.forEach(function (h) { h[3].shown = (h[3].shown || 0) + 1; });
    var fw = esc(findWord(q.value));
    var out = hits.map(function (h) {
      var sess = h[0], r = h[1], f = h[3], when = stamp(r[3]);
      var html = '<a class="r" href="sessions/' + esc(sess[0]) + ".html#m" + r[0] + fw + '">' +
        '<span class="rh">' + (when ? '<span class="rt">' + when + "</span> · " : "") +
        esc(sess[1]) + (sess[2] ? " · " + esc(sess[2]) : "") +
        " · " + WHO[r[1]] + "</span>" +
        '<span class="rs">' + snippet(r[2], h[2], ts) + "</span></a>";
      // Under the last of a session's results, how many more it holds, and
      // a way to the next of them.
      if (--f.left === f.n - f.shown && f.n > f.shown) {
        var next = f.cutAt || f.next;
        html += '<a class="more" href="sessions/' + esc(sess[0]) + ".html#m" + next[0] + fw + '">+ ' +
          (f.n - f.shown) + " more in this session</a>";
      }
      return html;
    });
    // Sessions the cap left out altogether are said in one line.
    var unseen = found.filter(function (f) { return !f.shown; });
    if (unseen.length) {
      out.push('<p class="d more">+ ' + CH.plural(unseen.reduce(function (t, f) { return t + f.n; }, 0), "message") +
        " in " + CH.plural(unseen.length, "more session") + " — add a word to narrow it down</p>");
    }
    mr.innerHTML = out.join("") || '<p class="d">no messages match</p>';
    // A session counts once, whether its row matched, its messages, or both.
    rows.forEach(function (r, i) { if (!r.hidden) ids[order[i].id] = 1; });
    var matched = Object.keys(ids).length;
    n.textContent = matched + " of " + CH.plural(rows.length, "session") + " · " +
      CH.plural(total, "message") +
      (missing ? " · " + CH.plural(missing, "conversation") +
        " not searched, search file missing — run claude-html" : "");
  }

  function run() {
    var ts = parse(q.value);
    if (!ts.length) {
      rows.forEach(function (r) { r.hidden = false; });
      document.getElementById("tw").hidden = !sessions.length;
      syncGroups();
      mh.hidden = true;
      mr.innerHTML = "";
      n.textContent = "";
      return;
    }
    var shown = 0;
    rows.forEach(function (r) {
      var hit = ts.every(function (t) { return fold(r.dataset.s).indexOf(t) > -1; });
      r.hidden = !hit;
      if (hit) shown++;
    });
    syncGroups();
    // No row left: the column headings over nothing go too.
    document.getElementById("tw").hidden = !shown;
    n.textContent = shown + " of " + CH.plural(rows.length, "session") + " · searching…";
    mh.hidden = false;
    need(function () { render(messages(ts), ts, shown); }, shown);
  }

  q.addEventListener("input", function () {
    showOption();
    clearTimeout(timer);
    timer = setTimeout(run, 130);
  });
  showOption();
  run();
})();
