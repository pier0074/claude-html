// The index: every session, filterable, and full-text search across all of
// them. Renders from the manifest embedded in the page.
(function () {
  "use strict";

  var data = JSON.parse(document.getElementById("index-data").textContent);
  var sessions = data.sessions || [];
  var home = data.home || "";
  var errors = data.errors || [];

  function esc(s) { return CH.esc(s); }

  CH.themeInit(document.getElementById("theme"));

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
    var web = s.kind === "web";
    return '<a class="del" href="claude-html://delete/' + esc(s.id) + '" title="' +
      (web ? "hide this chat from the index" : "delete this conversation and its history") +
      '">' + (web ? "⊘" : "✕") + "</a>";
  }

  // The project name opens the project. A claude.ai chat has no folder, and
  // the pseudo-projects (~ and the projects root itself) are not projects.
  function project(s) {
    var name = esc(s.project || "");
    if (!s.cwd || s.kind === "web") return name;
    return '<a class="proj" href="claude-html://open/' + esc(s.id) + '" title="open this ' +
      'project: its server if one is running, otherwise its page or its folder">' + name + "</a>";
  }

  function row(s, inGroup) {
    var date = new Date((s.mtime || 0) * 1000);
    var stamp = date.getFullYear() + "-" +
      ("0" + (date.getMonth() + 1)).slice(-2) + "-" + ("0" + date.getDate()).slice(-2) +
      " " + ("0" + date.getHours()).slice(-2) + ":" + ("0" + date.getMinutes()).slice(-2);
    var action = CH.resumable(s)
      ? '<button class="cp" data-c="' + esc(CH.resumeCmd(s, home)) + '">copy</button>'
      : (s.url ? '<a href="' + esc(s.url) + '">open ↗</a>' : '<span class="d">—</span>');
    // A page built before its source changed is saying something out of date.
    var stale = s.stale ? ' <span class="stale" title="the source has changed since this was built">stale</span>' : "";
    // Under a project heading the project cell would say the heading again,
    // so it is left empty — but the name is still on the row, in data-proj,
    // because searching for a project has to keep working either way.
    return '<tr data-href="sessions/' + esc(s.id) + '.html" data-proj="' +
      esc(s.project || "") + '"><td class="dt">' + stamp + "</td><td>" +
      (inGroup ? "" : project(s)) + "</td>" +
      '<td><span class="ti">' + esc(s.title || "") +
      (s.agents ? ' <span class="nag">· ' + s.agents + " sub-agents</span>" : "") +
      "</span></td>" +
      "<td>" + (s.prompts || 0) + '</td><td class="d">' + esc(s.kind) + stale + "</td>" +
      '<td><a href="sessions/' + esc(s.id) + '.html">' + esc(s.id.slice(0, 8)) + "…</a></td>" +
      "<td>" + action + "</td><td>" + bin(s) + "</td></tr>";
  }

  var tbody = document.getElementById("rows");
  var rows = [];

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
  try { grouped = localStorage.getItem("ch-group") === "1"; } catch (e) {}
  if (!worthGrouping) grouped = false;

  function heading(name) {
    var list = byProject[name];
    var prompts = list.reduce(function (t, s) { return t + (s.prompts || 0); }, 0);
    // The heading opens the project, like the name on a row does. It uses the
    // most recent session, since the link carries a session id.
    var openable = list.filter(function (s) { return s.cwd && s.kind !== "web"; })[0];
    return '<tr class="grp"><th colspan="8">' +
      (openable ? project(openable) : esc(name || "—")) +
      ' <span class="gc">' + list.length + " session" + (list.length === 1 ? "" : "s") +
      " · " + prompts + " prompts</span></th></tr>";
  }

  function draw() {
    tbody.innerHTML = grouped
      ? names.map(function (name) {
          return heading(name) + byProject[name].slice()
            .sort(function (a, b) { return (b.mtime || 0) - (a.mtime || 0); })
            .map(function (s) { return row(s, true); }).join("");
        }).join("")
      : sessions.map(function (s) { return row(s, false); }).join("");
    rows = [].slice.call(tbody.querySelectorAll("tr:not(.grp)"));
    rows.forEach(function (r) { r.dataset.s = r.textContent + " " + (r.dataset.proj || ""); });
  }
  draw();
  document.getElementById("count").textContent = sessions.length;

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
      LC = null, loading = false, timer;

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

  function need(cb) {
    if (window.SEARCH) { cb(); return; }
    if (loading) return;
    loading = true;
    mh.hidden = false;
    mr.innerHTML = '<p class="d">loading conversations…</p>';
    var pending = sessions.length, loaded = 0;
    function settle() { if (--pending === 0) done(); }
    function done() {
      if (sessions.length && !loaded) {
        mr.innerHTML = '<p class="d">no search index — run <code>claude-html</code> to build one</p>';
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
    if (!pending) { done(); return; }
    sessions.forEach(function (s) {
      var tag = document.createElement("script");
      tag.src = "search/" + encodeURIComponent(s.id) + ".js";
      tag.onload = function () { loaded++; settle(); };
      tag.onerror = settle;
      document.head.appendChild(tag);
    });
  }

  var WHO = { u: "You", t: "Claude", k: "thinking" };

  function stamp(secs) {
    if (!secs) return "";
    var d = new Date(secs * 1000);
    return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" +
      ("0" + d.getDate()).slice(-2) + " " + ("0" + d.getHours()).slice(-2) + ":" +
      ("0" + d.getMinutes()).slice(-2);
  }

  function messages(ts) {
    var out = [], CAP = 200, PER = 5;
    for (var i = 0; i < window.SEARCH.length && out.length < CAP; i++) {
      var sess = window.SEARCH[i], rws = sess[3], lc = LC[i], per = 0;
      for (var j = 0; j < rws.length && out.length < CAP && per < PER; j++) {
        var lo = cs ? rws[j][2] : lc[j], ok = true;
        for (var k = 0; k < ts.length; k++) {
          if (lo.indexOf(ts[k]) < 0) { ok = false; break; }
        }
        if (ok) { out.push([sess, rws[j], lo]); per++; }
      }
    }
    return out;
  }

  function render(hits, ts, shown) {
    // Newest first: what you said last week is likelier to be what you meant
    // than the same words in a session from March.
    hits.sort(function (a, b) { return (b[1][3] || 0) - (a[1][3] || 0); });
    mr.innerHTML = hits.map(function (h) {
      var sess = h[0], r = h[1], when = stamp(r[3]);
      return '<a class="r" href="sessions/' + esc(sess[0]) + ".html#m" + r[0] + '">' +
        '<span class="rh">' + (when ? '<span class="rt">' + when + "</span> · " : "") +
        esc(sess[1]) + (sess[2] ? " · " + esc(sess[2]) : "") +
        " · " + WHO[r[1]] + "</span>" +
        '<span class="rs">' + snippet(r[2], h[2], ts) + "</span></a>";
    }).join("") || '<p class="d">no messages match</p>';
    n.textContent = shown + " of " + rows.length + " sessions · " + hits.length +
      (hits.length >= 200 ? "+" : "") + " messages";
  }

  function run() {
    var ts = parse(q.value);
    if (!ts.length) {
      rows.forEach(function (r) { r.hidden = false; });
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
    n.textContent = shown + " of " + rows.length + " sessions · searching…";
    mh.hidden = false;
    need(function () { render(messages(ts), ts, shown); });
  }

  q.addEventListener("input", function () {
    showOption();
    clearTimeout(timer);
    timer = setTimeout(run, 130);
  });
  showOption();
  run();
})();
