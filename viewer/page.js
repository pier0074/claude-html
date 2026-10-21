// What a session page does once the conversation is on screen: render it,
// then wire up the reading controls.
(function () {
  "use strict";

  var data = JSON.parse(document.getElementById("session-data").textContent);
  var main = document.getElementById("main");
  CH.themeInit(document.getElementById("theme"));
  main.innerHTML = CH.renderMessages(data.messages);

  // A sub-agent belongs to the call that spawned it: meta.json named that call,
  // so its link goes inside that very tool call. One that cannot be matched —
  // an older transcript, a call that is no longer in the page — is listed at
  // the end instead, so it is never simply lost.
  (function subagents() {
    var agents = data.agents || [];
    if (!agents.length) return;
    var orphans = [];
    // Inside its own call the summary already names the agent and its type, so
    // the link says only what the summary does not: how big the thing is.
    function link(a, withContext) {
      return '<a class="agent" href="' + CH.esc(a.href) + '">sub-agent' +
        (withContext && a.agentType ? " · " + CH.esc(a.agentType) : "") +
        (a.model ? " · " + CH.esc(a.model) : "") +
        " · " + a.messages + " messages" +
        (withContext && a.description
          ? ' <span class="ad">' + CH.esc(a.description) + "</span>" : "") +
        "</a>";
    }
    agents.forEach(function (a) {
      var call = a.toolUseId && main.querySelector('[data-tid="' + a.toolUseId + '"]');
      if (call) call.insertAdjacentHTML("beforeend", link(a, false));
      else orphans.push(link(a, true));
    });
    if (orphans.length) {
      main.insertAdjacentHTML("beforeend",
        '<div class="m agents"><div class="who">Sub-agents</div>' + orphans.join("") + "</div>");
    }
  })();

  // Header facts come from the same JSON, so the page has one source of truth.
  var meta = data.meta || {};
  var prompts = CH.countPrompts(data.messages);
  // The header reads as the path to this page, the way a URL does:
  //   claude-html / weather-app / 7c21a9b4-…   and one more crumb on a
  // sub-agent's page, whose parent is the crumb before it. The first crumb is
  // the way home, and takes meta.up, since a sub-agent page sits one folder
  // deeper. The project crumb opens the project, exactly as it does on the
  // index — a sub-agent inherits its parent's, having no folder of its own.
  (function crumbs() {
    var parts = [
      '<a class="brand" href="' + CH.esc(meta.up || "../index.html") + '">claude-html</a>'
    ];
    if (meta.project) {
      parts.push(meta.open
        ? '<a class="proj" href="claude-html://open/' + CH.esc(meta.open) +
          '" title="open this project: its server if one is running, otherwise its page or its folder">' +
          CH.esc(meta.project) + "</a>"
        : '<span class="proj">' + CH.esc(meta.project) + "</span>");
    }
    if (meta.parent) {
      parts.push('<a class="sid" href="' + CH.esc(meta.parent.href) +
                 '" title="the conversation this sub-agent belongs to">' +
                 CH.esc(meta.parent.id) + "</a>");
      parts.push('<span class="sid here">agent-' + CH.esc(meta.id) + "</span>");
    } else {
      parts.push('<span class="sid here">' + CH.esc(meta.id) + "</span>");
    }
    document.getElementById("crumbs").innerHTML =
      parts.join('<span class="sep">/</span>');
  })();
  document.getElementById("subtitle").textContent = meta.title || "";
  var counts = prompts + " prompts · " + data.messages.length + " messages · from " + (meta.kind || "");
  if ((data.agents || []).length) counts += " · " + data.agents.length + " sub-agents";
  document.getElementById("counts").textContent = counts;
  // A sub-agent's page says whose it is — the crumbs give the link, this
  // gives the parent's title, which is what you would recognise it by.
  if (meta.parent) {
    document.getElementById("subtitle").insertAdjacentHTML("afterend",
      '<div class="meta">part of <a href="' + CH.esc(meta.parent.href) + '">' +
      CH.esc(meta.parent.title || meta.parent.id) + "</a>" +
      (meta.agentType ? " · " + CH.esc(meta.agentType) : "") +
      (meta.model ? " · " + CH.esc(meta.model) : "") + "</div>");
  }
  document.title = (meta.project || "session") + " · " + (meta.title || meta.id.slice(0, 8));

  if (CH.resumable(meta)) {
    var cmd = CH.resumeCmd(meta, meta.home);
    document.getElementById("rc").textContent = cmd;
    document.getElementById("resume").hidden = false;
    document.getElementById("copy").addEventListener("click", function (e) {
      navigator.clipboard.writeText(cmd).then(function () {
        e.target.textContent = "copied";
        setTimeout(function () { e.target.textContent = "copy"; }, 1200);
      });
    });
  }

  // ── reading controls ───────────────────────────────────────────────
  var body = document.body,
      talk = document.getElementById("mtalk"),
      all = document.getElementById("mall");

  function mode(m) {
    body.classList.toggle("talk", m === "talk");
    talk.classList.toggle("on", m === "talk");
    all.classList.toggle("on", m !== "talk");
    try { localStorage.setItem("ch-mode", m); } catch (e) {}
    place();
    // What can be seen has changed, so what find can land on has too.
    if (typeof find === "function" && fq && fq.value) find();
  }
  talk.onclick = function () { mode("talk"); };
  all.onclick = function () { mode("all"); };

  var ps = [].slice.call(document.querySelectorAll(".m.prompt")),
      at = 0, pc = document.getElementById("pc");

  function showPrompt() { pc.textContent = ps.length ? (at + 1) + " / " + ps.length : "no prompts"; }
  function go(d) {
    if (!ps.length) return;
    at = Math.max(0, Math.min(ps.length - 1, at + d));
    ps[at].scrollIntoView();
    showPrompt();
  }
  function jump(i) {
    if (!ps.length) return;
    at = Math.max(0, Math.min(ps.length - 1, i));
    ps[at].scrollIntoView();
    showPrompt();
  }
  document.getElementById("prev").onclick = function () { go(-1); };
  document.getElementById("next").onclick = function () { go(1); };
  document.getElementById("first").onclick = function () { jump(0); };
  document.getElementById("last").onclick = function () { jump(ps.length - 1); };
  document.addEventListener("keydown", function (e) {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.target.matches("input,textarea")) return;
    if (e.key === "j") { go(1); e.preventDefault(); }
    else if (e.key === "k") { go(-1); e.preventDefault(); }
  });

  // The counter says which prompt you are under, not only the last one you
  // jumped to, and it ignores prompts the current mode has hidden.
  function place() {
    var y = window.pageYOffset + 140, n = 0;
    for (var i = 0; i < ps.length; i++) {
      if (ps[i].offsetParent === null) continue;
      if (ps[i].offsetTop <= y) n = i;
    }
    at = n;
    showPrompt();
  }
  var timer;
  window.addEventListener("scroll", function () {
    clearTimeout(timer);
    timer = setTimeout(place, 110);
  }, { passive: true });

  // ── find in this conversation ──────────────────────────────────────
  // The browser's own find (⌘F) works too. This one counts, matches case when
  // asked, and in Conversation mode skips the tool output that mode hides —
  // landing on a match you cannot see is worse than not finding it.
  var fq = document.getElementById("fq"), fcs = document.getElementById("fcs"),
      fc = document.getElementById("fc"), hits = [], cur = -1, ftimer;
  var HIDDEN_IN_TALK = ".tool,.res,.think,.m.notext";
  var CAP = 2000;
  try { fcs.checked = localStorage.getItem("ch-case") === "1"; } catch (e) {}

  function clearHits() {
    var parents = [];
    hits.forEach(function (m) {
      var p = m.parentNode;
      if (!p) return;
      p.replaceChild(document.createTextNode(m.textContent), m);
      if (parents.indexOf(p) < 0) parents.push(p);
    });
    parents.forEach(function (p) { p.normalize(); });
    hits = []; cur = -1;
  }

  function showFind() {
    fc.textContent = !hits.length ? (fq.value.length >= 2 ? "no matches" : "") :
      (cur + 1) + " / " + hits.length + (hits.length >= CAP ? "+" : "");
  }

  function goto(i) {
    if (!hits.length) return;
    if (cur > -1) hits[cur].classList.remove("cur");
    cur = (i + hits.length) % hits.length;
    hits[cur].classList.add("cur");
    hits[cur].scrollIntoView({ block: "center" });
    showFind();
  }
  function step(d) { goto(cur + d); }

  function find() {
    clearHits();
    var raw = fq.value, matchCase = fcs.checked;
    if (raw.length < 2) { showFind(); return; }
    var needle = matchCase ? raw : raw.toLowerCase();
    var talk = body.classList.contains("talk");
    var walker = document.createTreeWalker(main, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        if (n.nodeValue.length < needle.length) return NodeFilter.FILTER_REJECT;
        if (talk && n.parentNode.closest(HIDDEN_IN_TALK)) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var nodes = [], node;
    while ((node = walker.nextNode())) nodes.push(node);
    for (var i = 0; i < nodes.length && hits.length < CAP; i++) {
      var t = nodes[i], text = t.nodeValue, hay = matchCase ? text : text.toLowerCase();
      var at = hay.indexOf(needle);
      if (at < 0) continue;
      var frag = document.createDocumentFragment(), pos = 0;
      while (at > -1 && hits.length < CAP) {
        frag.appendChild(document.createTextNode(text.slice(pos, at)));
        var mk = document.createElement("mark");
        mk.className = "hit";
        mk.textContent = text.slice(at, at + needle.length);
        frag.appendChild(mk);
        hits.push(mk);
        pos = at + needle.length;
        at = hay.indexOf(needle, pos);
      }
      frag.appendChild(document.createTextNode(text.slice(pos)));
      t.parentNode.replaceChild(frag, t);
    }
    // Start from where you are reading, not from the top of a long page.
    var start = 0;
    for (var k = 0; k < hits.length; k++) {
      if (hits[k].getBoundingClientRect().top >= 120) { start = k; break; }
    }
    if (hits.length) { cur = start - 1; step(1); } else showFind();
  }

  var fbar = document.querySelector(".find");
  function showOption() { fbar.classList.toggle("on", !!fq.value || fcs.checked); }
  showOption();
  fq.addEventListener("input", function () {
    showOption();
    clearTimeout(ftimer);
    ftimer = setTimeout(find, 220);
  });
  fq.addEventListener("keydown", function (e) {
    if (e.key === "Enter") { e.preventDefault(); step(e.shiftKey ? -1 : 1); }
    else if (e.key === "Escape") { fq.value = ""; find(); fq.blur(); }
  });
  fcs.addEventListener("change", function () {
    try { localStorage.setItem("ch-case", fcs.checked ? "1" : "0"); } catch (e) {}
    showOption();
    find();
  });
  document.getElementById("fnext").onclick = function () { step(1); };
  document.getElementById("fprev").onclick = function () { step(-1); };
  // 579 matches is a lot to step through; the ends are worth one click.
  document.getElementById("ffirst").onclick = function () { goto(0); };
  document.getElementById("flast").onclick = function () { goto(hits.length - 1); };
  document.addEventListener("keydown", function (e) {
    if (e.key === "/" && !e.target.matches("input,textarea")) { e.preventDefault(); fq.focus(); }
  });

  var saved = "all";
  try { saved = localStorage.getItem("ch-mode") || "all"; } catch (e) {}
  mode(saved);
  // Which prompt you are under, from the moment the page opens — not only
  // once you have scrolled.
  place();
})();
