// What a session page does once the conversation is on screen: render it,
// then wire up the reading controls.
(function () {
  "use strict";

  var data = JSON.parse(document.getElementById("session-data").textContent);
  var main = document.getElementById("main");
  CH.themeInit(document.getElementById("theme"));

  // A long session is fifteen thousand messages and a hundred thousand DOM
  // nodes. Putting all of them on the page costs seven seconds of work after
  // it opens, and that churn is the lag you feel while scrolling. So only the
  // rows near the window are ever real: every other row is an empty block of
  // about the height it will have, and rows are built from their message as
  // they come near and taken back down once they are far away. Find, the
  // prompt arrows and links to a message all work from the data, and build
  // the one row they need on the spot.
  var msgs = data.messages;
  var plan = CH.planRows(msgs), R = plan.msg.length;
  // Below this a conversation is put up whole, in one go, as it always was:
  // there is nothing to gain and the guessed heights would only get in the way.
  // Rows go up and come down twenty at a time; NEAR is how far ahead of the
  // window they are built, FAR how far away they must be before they go.
  var BIG = 400, PER = 20, NEAR = 1500, FAR = 6000;
  var windowed = R > BIG;
  // Only a page that builds and takes down rows keeps its own place; a
  // short one leaves that to the browser, as it always did.
  if (windowed) document.documentElement.classList.add("win");
  var header = document.querySelector("header");

  // Which row shows message i. A tool result folded into its call, or one
  // with nothing to show, has no row of its own: it lives in the row before.
  var rowOf = new Array(msgs.length);
  (function () {
    var r = 0;
    for (var i = 0; i < msgs.length; i++) {
      if (r < R && plan.msg[r] === i) rowOf[i] = r++;
      else rowOf[i] = Math.max(0, r - 1);
    }
  })();

  // A sub-agent belongs to the call that spawned it: meta.json named that call,
  // so its link goes inside that very tool call. One that cannot be matched —
  // an older transcript, a call that is no longer in the page — is listed at
  // the end instead, so it is never simply lost. Both are part of the row's
  // HTML, so find sees them whether or not the row is on the page.
  var agents = data.agents || [], agentsAt = {}, orphans = [];
  (function () {
    var tidRow = {};
    for (var r = 0; r < R; r++) {
      (msgs[plan.msg[r]].tools || []).forEach(function (t) {
        if (t && typeof t === "object" && t.id) tidRow[t.id] = r;
      });
    }
    agents.forEach(function (a) {
      var r = a.toolUseId ? tidRow[a.toolUseId] : undefined;
      if (r === undefined) orphans.push(a);
      else (agentsAt[r] = agentsAt[r] || []).push(a);
    });
  })();
  // The orphans are one more row, after the last message.
  var NR = R + (orphans.length ? 1 : 0), NB = Math.ceil(NR / PER);

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

  function idOf(r) { return r === R ? "agents" : "m" + plan.msg[r]; }
  function rowEl(r) { return document.getElementById(idOf(r)); }

  function rowHtml(r) {
    if (r === R) {
      return '<div id="agents" class="m agents"><div class="who">Sub-agents</div>' +
        orphans.map(function (a) { return link(a, true); }).join("") + "</div>";
    }
    var h = CH.renderRow(msgs, plan, r);
    (agentsAt[r] || []).forEach(function (a) {
      // A tool call is one <details> with none inside it, so the first
      // closing tag after the call's own id is the end of that call.
      var at = h.indexOf('data-tid="' + CH.esc(a.toolUseId) + '"');
      var end = at < 0 ? -1 : h.indexOf("</details>", at);
      if (end > -1) h = h.slice(0, end) + link(a, false) + h.slice(end);
    });
    return h;
  }

  // Rows go up and come down a block of PER at a time, and a block that is
  // not built is one empty element of the height its rows will add up to:
  // seven hundred of those cost far less to lay out than fifteen thousand.
  // The guess needs to know how many characters fit on a line, which depends
  // on the window, so that is measured once, on the page's own font. Once a
  // block has been on the page, its measured height replaces the guess.
  var bAll = [], bTalk = [];
  (function () {
    var probe = document.createElement("span");
    probe.style.cssText = "position:absolute;visibility:hidden;white-space:pre";
    probe.textContent = "0000000000";
    main.appendChild(probe);
    var cw = probe.getBoundingClientRect().width / 10 || 9;
    var cpl = Math.max(20, Math.floor((main.clientWidth - 40) / cw));
    main.removeChild(probe);
    for (var r = 0; r < NR; r++) {
      var e = r < R ? CH.estimateRow(msgs, plan, r, cpl) : [60 + 34 * orphans.length, 60 + 34 * orphans.length];
      var b = Math.floor(r / PER);
      bAll[b] = (bAll[b] || 0) + e[0];
      bTalk[b] = (bTalk[b] || 0) + e[1];
    }
  })();

  function blockHtml(b) {
    var html = [];
    for (var r = b * PER; r < Math.min(NR, (b + 1) * PER); r++) html.push(rowHtml(r));
    return html.join("");
  }
  function sizeAsGuessed(sec, b) {
    sec.classList.add("ph");
    sec.style.setProperty("--h", Math.round(bAll[b]) + "px");
    sec.style.setProperty("--t", Math.round(bTalk[b]) + "px");
  }

  var real = [];
  (function () {
    var out = [];
    for (var b = 0; b < NB; b++) {
      out.push(windowed
        ? '<section class="blk ph" data-b="' + b + '" style="--h:' + Math.round(bAll[b]) +
          "px;--t:" + Math.round(bTalk[b]) + 'px"></section>'
        : '<section class="blk" data-b="' + b + '">' + blockHtml(b) + "</section>");
      real.push(!windowed);
    }
    main.innerHTML = out.join("");
  })();
  var secs = main.children;

  function talking() { return body.classList.contains("talk"); }

  function fillBlock(b) {
    if (real[b]) return;
    var sec = secs[b];
    sec.innerHTML = blockHtml(b);
    sec.classList.remove("ph");
    sec.removeAttribute("style");
    real[b] = true;
    var t = /^#(m\d+)$/.exec(location.hash), el = t && document.getElementById(t[1]);
    if (el && sec.contains(el)) el.classList.add("tgt");
    marksIn(b);
  }

  // Taking a block down keeps the room it took, measured in the mode that is
  // showing, so nothing on the page moves.
  function emptyBlock(b) {
    if (!real[b]) return;
    var sec = secs[b], h = sec.getBoundingClientRect().height;
    if (talking()) bTalk[b] = h; else bAll[b] = h;
    sec.innerHTML = "";
    sizeAsGuessed(sec, b);
    real[b] = false;
    // Watched afresh, so the observer reports it the next time it is near
    // even if it never saw the block leave.
    near.unobserve(sec); near.observe(sec);
  }

  function headerBottom() { return header ? header.getBoundingClientRect().bottom : 0; }

  // The first block whose bottom is below y, in window coordinates.
  function blockAt(y) {
    var lo = 0, hi = NB - 1;
    while (lo < hi) {
      var mid = (lo + hi) >> 1;
      if (secs[mid].getBoundingClientRect().bottom > y) hi = mid; else lo = mid + 1;
    }
    return lo;
  }

  // What is at the top of the window, just under the header: the first row
  // that starts at or below y, or the block itself when it is not built.
  // Conversation mode hides whole rows, and a hidden row has no box, so
  // those are passed over.
  function topThing(y) {
    for (var b = blockAt(y); b < NB; b++) {
      if (!real[b]) return { b: b, r: b * PER, el: secs[b] };
      var kids = secs[b].children;
      for (var k = 0; k < kids.length; k++) {
        if (!kids[k].getClientRects().length) continue;
        if (kids[k].getBoundingClientRect().top >= y) return { b: b, r: b * PER + k, el: kids[k] };
      }
    }
    return null;
  }

  // Where row r starts, or where its block does if the block is not built.
  function rowTop(r) {
    var b = Math.floor(r / PER), el = real[b] ? rowEl(r) : secs[b];
    return el.getBoundingClientRect().top;
  }

  // Rows going up or down above the window must not move what you are
  // reading. Browsers that anchor scrolling do this for themselves, but not
  // all of them do, and not always to the row you are on, so it is done
  // here, the same everywhere: note where something on screen is, make the
  // change, and scroll by however far it moved.
  function anchored(fn, el) {
    if (!el) { var t = topThing(headerBottom()); el = t && t.el; }
    var before = el ? el.getBoundingClientRect().top : 0;
    fn();
    if (!el || !el.isConnected || !el.getClientRects().length) return;
    var d = el.getBoundingClientRect().top - before;
    if (Math.abs(d) >= 1) window.scrollBy(0, d);
  }

  // Every block within `margin` of the window, built now rather than a frame
  // later, so a jump lands on a page and not on empty space.
  function fillNear(margin) {
    if (!windowed) return;
    var h = window.innerHeight, from = blockAt(-margin);
    anchored(function () {
      for (var b = from; b < NB && secs[b].getBoundingClientRect().top < h + margin; b++) fillBlock(b);
    });
  }

  // Make row r real, and hand back its element.
  function reveal(r) {
    var b = Math.floor(r / PER);
    if (!real[b]) anchored(function () { fillBlock(b); });
    return rowEl(r);
  }
  // A jump settles the header first, as it will be where it lands, so the
  // row comes to rest under the header that is really there.
  function scrollToEl(el, gap) {
    gap = gap === undefined ? 12 : gap;
    var to = function () {
      return window.pageYOffset + el.getBoundingClientRect().top - headerBottom() - gap;
    };
    var y = to();
    if (compactAt(y) !== mini) { setMini(compactAt(y)); y = to(); }
    window.scrollTo(0, y);
  }

  // ── the header, compact once you are reading ───────────────────────
  // On a narrow window the full header wraps to a third of the screen. Past
  // MINI_AT it folds to one line, and opens again under FULL_AT: two
  // thresholds, so no position can flip it back and forth. It keeps taking
  // the room it took open, as a margin under it, so folding moves nothing
  // in the page — not what you are reading, not a placeholder's place.
  var MINI_AT = 200, FULL_AT = 40;
  var mini = false, opened = false, hx = document.getElementById("hx");
  function compactAt(y) {
    if (opened) return false;
    if (y > MINI_AT) return true;
    if (y < FULL_AT) return false;
    return mini;
  }
  function setMini(on) {
    // Measured as it is at the top of the page, then given whatever margin
    // makes up the difference: the page below never sees a change of height.
    // In between it does, for a measurement, and on a short page the browser
    // would keep your place through that by scrolling — to the top, once the
    // fold has taken more than you had scrolled. So it is told not to.
    var root = document.documentElement, anchor = root.style.overflowAnchor;
    root.style.overflowAnchor = "none";
    header.classList.remove("mini", "open");
    header.style.marginBottom = "";
    var full = header.getBoundingClientRect().height;
    mini = on;
    header.classList.toggle("mini", on);
    header.classList.toggle("open", opened && !on);
    var d = full - header.getBoundingClientRect().height;
    if (d) header.style.marginBottom = d + "px";
    header.getBoundingClientRect();
    root.style.overflowAnchor = anchor;
    hx.textContent = on ? "▾" : "▴";
    hx.title = on ? "show the whole header" : "fold the header to one line";
    headerRoom();
  }
  // The open header's height follows the window and the find bar, so the
  // room kept for it is measured again whenever either changes.
  function fitHeader() { setMini(mini); }
  hx.addEventListener("click", function () {
    opened = mini;
    setMini(!mini);
  });
  window.addEventListener("scroll", function () {
    var y = window.pageYOffset;
    if (y < FULL_AT && opened) { opened = false; setMini(false); }
    var on = compactAt(y);
    if (on !== mini) setMini(on);
  }, { passive: true });

  var near = null;
  if (windowed) {
    near = new IntersectionObserver(function (entries) {
      var todo = [];
      entries.forEach(function (e) {
        var b = +e.target.getAttribute("data-b");
        if (e.isIntersecting && !real[b]) todo.push(b);
      });
      if (todo.length) anchored(function () { todo.forEach(fillBlock); });
    }, { rootMargin: NEAR + "px 0px" });
    for (var b0 = 0; b0 < NB; b0++) near.observe(secs[b0]);
  }

  // Blocks far from the window go back to placeholders, so however much of
  // the conversation has been read, the page holds only what is near you.
  // This is a sweep over the few built blocks after scrolling settles, not an
  // observer: a jump builds a block and leaves it in one go, and an observer
  // only hears about blocks whose state it saw change.
  var sweepTimer;
  function sweep() {
    var h = window.innerHeight, far = [];
    for (var b = 0; b < NB; b++) {
      if (!real[b]) continue;
      var box = secs[b].getBoundingClientRect();
      if (box.bottom < -FAR || box.top > h + FAR) far.push(b);
    }
    if (far.length) anchored(function () { far.forEach(emptyBlock); });
  }
  function sweepSoon() {
    clearTimeout(sweepTimer);
    sweepTimer = setTimeout(sweep, 300);
  }
  if (windowed) window.addEventListener("scroll", sweepSoon, { passive: true });
  // Printing takes the page as it is, and a placeholder prints as blank
  // paper: the whole conversation is built first, slow as that is, and the
  // sweep takes it back down once you scroll again.
  if (windowed) window.addEventListener("beforeprint", function () {
    anchored(function () { for (var b = 0; b < NB; b++) fillBlock(b); });
  });

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

  // What this conversation cost, in one line: the total, then where it went.
  // Cache reads are nearly all of the volume and the cheapest part of it, so
  // output is named separately — it is the one that tracks the work done.
  (function tokens() {
    var t = meta.tok;
    if (!t) return;
    var el = document.getElementById("tok");
    if (!el) return;
    var f = CH.fmtTokens;
    var parts = [f(t[0] + t[1] + t[2] + t[3]) + " tokens",
                 f(t[1]) + " out", f(t[0]) + " in", f(t[2] + t[3]) + " cached",
                 t[4] + " replies"];
    if (t[4]) parts.push(f(t[1] / t[4]) + " out/reply");
    // The cost, where Claude Code recorded one: its own sum at API list
    // prices, second only to the tokens. "≥" when some of the session's
    // replies fall outside what it recorded, so the figure is a floor.
    if (t.length > 5) {
      parts.splice(1, 0, '<span class="cost" title="' + CH.esc(meta.costPart
        ? "what Claude Code recorded at API list prices; some replies fall outside its record, so it cost at least this"
        : "what Claude Code recorded at API list prices; on a subscription an equivalent, not a bill") + '">' +
        (meta.costPart ? "≥ " : "≈ ") + CH.fmtMoney(t[5]) + "</span>");
    }
    if (meta.models && meta.models.length) {
      // The three that did most of the work; naming six wraps the line.
      var names = meta.models.slice(0, 3).map(function (m) {
        return m.replace(/^claude-/, "").replace(/-20\d{6}$/, "");
      });
      var more = meta.models.length - names.length;
      parts.push(names.join(", ") + (more > 0 ? " +" + more : ""));
    }
    el.innerHTML = parts.join(' <span class="sep">·</span> ') +
      ' <span class="sep">·</span> ' +
      '<a href="../usage.html" title="every session, by week, month and project">all usage ↗</a>';
    el.hidden = false;
  })();
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
    // meta.open is set only where something receives claude-html:// links,
    // which is what running the command from here needs too.
    if (meta.open) {
      document.getElementById("copy").insertAdjacentHTML("afterend",
        '<a class="go" href="claude-html://resume/' + CH.esc(meta.id) +
        '" title="reopen this conversation in a terminal">resume</a>');
    }
  }

  // ── reading controls ───────────────────────────────────────────────
  var body = document.body,
      talk = document.getElementById("mtalk"),
      all = document.getElementById("mall");

  // A row both modes show: what to hold still while the other mode's rows
  // come and go around it.
  function shownInBoth(r) {
    if (r === R) return true;
    var m = msgs[plan.msg[r]];
    return m.role === "user" || m.role === "system" || (m.role === "assistant" && !!m.text);
  }

  function mode(m, opening) {
    // Hold still the text you are reading: the first row both modes show
    // that reaches below the header. Rows the new mode hides vanish from
    // above it, and if they stood between it and the header it moves up to
    // take their place, as the text it now follows would.
    var y = headerBottom(), t = topThing(y), el = null;
    if (t) {
      for (var r = Math.max(0, t.r - 1), stop = Math.min(NR, t.r + 400); r < stop; r++) {
        if (!real[Math.floor(r / PER)]) { el = el || secs[Math.floor(r / PER)]; break; }
        var row = rowEl(r);
        if (shownInBoth(r) && row.getBoundingClientRect().bottom > y) { el = row; break; }
      }
    }
    anchored(function () {
      body.classList.toggle("talk", m === "talk");
      talk.classList.toggle("on", m === "talk");
      all.classList.toggle("on", m !== "talk");
    }, el);
    if (!opening && el && el.classList.contains("m")) {
      var gap = el.getBoundingClientRect().top - y - 12;
      if (gap > 0) window.scrollBy(0, gap);
    }
    try { localStorage.setItem("ch-mode", m); } catch (e) {}
    place();
    // What can be seen has changed, so what find can land on has too.
    if (typeof find === "function" && fq && fq.value) find();
  }
  talk.onclick = function () { mode("talk"); };
  all.onclick = function () { mode("all"); };

  // The prompts come from the data, not from the page, so the count and the
  // last one are right from the start, whether or not they have been built.
  var ps = [], at = 0, pc = document.getElementById("pc");
  for (var pr = 0; pr < R; pr++) if (plan.prompt[pr]) ps.push(pr);

  function showPrompt() { pc.textContent = ps.length ? (at + 1) + " / " + ps.length : "no prompts"; }
  function jump(i) {
    if (!ps.length) return;
    at = Math.max(0, Math.min(ps.length - 1, i));
    scrollToEl(reveal(ps[at]));
    fillNear(400);
    // Built rows above can still have moved it: one more look settles it.
    scrollToEl(rowEl(ps[at]));
    showPrompt();
  }
  function go(d) { jump(at + d); }
  document.getElementById("prev").onclick = function () { go(-1); };
  document.getElementById("next").onclick = function () { go(1); };
  document.getElementById("first").onclick = function () { jump(0); };
  document.getElementById("last").onclick = function () { jump(Infinity); };
  document.addEventListener("keydown", function (e) {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.target.matches("input,textarea")) return;
    if (e.key === "j") { go(1); e.preventDefault(); }
    else if (e.key === "k") { go(-1); e.preventDefault(); }
  });

  // The counter says which prompt you are under, not only the last one you
  // jumped to. At the very end of the page the last prompts cannot scroll up
  // to the header, so there what can be seen is passed as well.
  function place() {
    var h = window.innerHeight, end = window.pageYOffset + h >= document.documentElement.scrollHeight - 2;
    at = CH.promptUnder(ps.length, function (k) { return rowTop(ps[k]); },
                        headerBottom() + 20, at, end ? [headerBottom(), h] : null);
    showPrompt();
  }
  var timer;
  window.addEventListener("scroll", function () {
    clearTimeout(timer);
    timer = setTimeout(function () { place(); hold(); }, 110);
  }, { passive: true });

  // With the browser's own scroll anchoring off, a window made narrower
  // would leave you somewhere else in a long conversation, as every row
  // above grows taller. What was just under the header when scrolling last
  // settled is put back there.
  var held = null;
  function hold() {
    if (!windowed) return;
    var t = topThing(headerBottom());
    held = t && { el: t.el, gap: t.el.getBoundingClientRect().top - headerBottom() };
  }
  if (windowed) window.addEventListener("resize", function () {
    fitHeader();
    if (!held || !held.el.isConnected || !held.el.getClientRects().length) return;
    var d = held.el.getBoundingClientRect().top - headerBottom() - held.gap;
    if (Math.abs(d) >= 1) window.scrollBy(0, d);
  });

  // A link to one message — what the index's search results are — opens on
  // that message, built first if it was not, and marked the way :target is.
  function toHash() {
    var t = /^#m(\d+)$/.exec(location.hash);
    if (!t || +t[1] >= msgs.length) return;
    [].forEach.call(main.querySelectorAll(".tgt"), function (el) { el.classList.remove("tgt"); });
    var el = reveal(rowOf[+t[1]]);
    if (!el) return;
    // Conversation mode hides tool output, and a hidden row has no place to
    // scroll to: the page would open at the top with the match nowhere.
    if (!el.getClientRects().length && talking()) mode("all", true);
    if (el.id === "m" + t[1]) el.classList.add("tgt");
    scrollToEl(el);
    fillNear(400);
    scrollToEl(rowEl(rowOf[+t[1]]));
  }
  window.addEventListener("hashchange", toHash);
  // The browser scrolls to a link's target on its own as well, at a moment
  // of its choosing; told how tall the header is, it lands where toHash does
  // rather than under the header.
  function headerRoom() {
    document.documentElement.style.setProperty("--hh", Math.round(header.offsetHeight) + "px");
  }
  headerRoom();
  window.addEventListener("resize", function () { fitHeader(); });

  // ── find in this conversation ──────────────────────────────────────
  // The browser's own find works too, but on a long page only on the rows
  // near the window, the only ones built — so there ⌘F comes here. This one
  // searches every row's text, built or not, counts, matches case
  // when asked, and in Conversation mode skips the tool output that mode
  // hides — landing on a match you cannot see is worse than not finding it.
  // A match is only highlighted once its row is on the page.
  var fq = document.getElementById("fq"), fcs = document.getElementById("fcs"),
      fc = document.getElementById("fc"), ftimer;
  var hits = [], marks = [], hitRows = {}, cur = -1, needle = "", hitCase = false, hitTalk = false;
  var HIDDEN_IN_TALK = ".tool,.res,.think,.m.notext";
  var CAP = 2000;
  try { fcs.checked = localStorage.getItem("ch-case") === "1"; } catch (e) {}

  // A row's searchable text is worked out once, the first time it is wanted.
  var texts = [];
  function textOf(r) { return texts[r] || (texts[r] = CH.rowText(rowHtml(r))); }
  // Lower-cased once per mode, not once per search.
  function hayOf(r) {
    var t = textOf(r), base = hitTalk ? "talk" : "all";
    if (hitCase) return t[base];
    if (t[base + "L"] === undefined) t[base + "L"] = t[base].toLowerCase();
    return t[base + "L"];
  }
  // Reading every row's text the first time costs a moment on a long
  // conversation; start on it, a few milliseconds at a time, as soon as the
  // field is focused, so the first search is not the one that waits.
  var warmAt = 0;
  function warm() {
    var t = Date.now();
    while (warmAt < NR && Date.now() - t < 8) textOf(warmAt++);
    if (warmAt < NR) window.setTimeout(warm, 0);
  }

  function unmark(mk) {
    var p = mk.parentNode;
    if (!p) return;
    p.replaceChild(document.createTextNode(mk.textContent), mk);
    p.normalize();
  }
  function clearHits() {
    marks.forEach(function (mk) { if (mk && mk.isConnected) unmark(mk); });
    hits = []; marks = []; hitRows = {}; cur = -1;
  }

  // Highlight row r's matches on the page, the same ones, in the same order,
  // that the search over its text counted.
  function markRow(r) {
    var span = hitRows[r], el = rowEl(r);
    if (!span || !el || !el.classList.contains("m")) return;
    if (marks[span[0]] && marks[span[0]].isConnected) return;
    var n = 0, talk = hitTalk;
    var walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, {
      acceptNode: function (t) {
        if (t.nodeValue.length < needle.length) return NodeFilter.FILTER_REJECT;
        if (talk && t.parentNode.closest(HIDDEN_IN_TALK)) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var nodes = [], node;
    while ((node = walker.nextNode())) nodes.push(node);
    for (var i = 0; i < nodes.length && n < span[1]; i++) {
      var t = nodes[i], text = t.nodeValue, hay = hitCase ? text : text.toLowerCase();
      var pos = hay.indexOf(needle);
      if (pos < 0) continue;
      var frag = document.createDocumentFragment(), from = 0;
      while (pos > -1 && n < span[1]) {
        frag.appendChild(document.createTextNode(text.slice(from, pos)));
        var mk = document.createElement("mark");
        mk.className = "hit" + (span[0] + n === cur ? " cur" : "");
        mk.textContent = text.slice(pos, pos + needle.length);
        frag.appendChild(mk);
        marks[span[0] + n] = mk;
        n++;
        from = pos + needle.length;
        pos = hay.indexOf(needle, from);
      }
      frag.appendChild(document.createTextNode(text.slice(from)));
      t.parentNode.replaceChild(frag, t);
    }
  }
  // A block that has just been built gets its highlights back.
  function marksIn(b) {
    if (!hits.length) return;
    for (var r = b * PER; r < Math.min(NR, (b + 1) * PER); r++) if (hitRows[r]) markRow(r);
  }

  function showFind() {
    fc.textContent = !hits.length ? (fq.value.length >= 2 ? "no matches" : "") :
      (cur + 1) + " / " + hits.length + (hits.length >= CAP ? "+" : "");
  }

  function goto(i) {
    if (!hits.length) return;
    if (cur > -1 && marks[cur]) marks[cur].classList.remove("cur");
    cur = (i + hits.length) % hits.length;
    var r = hits[cur];
    reveal(r);
    markRow(r);
    var mk = marks[cur];
    if (mk && mk.isConnected) {
      mk.classList.add("cur");
      mk.scrollIntoView({ block: "center" });
      fillNear(400);
      mk.scrollIntoView({ block: "center" });
      // Centred can still be under the header, on a short window with the
      // header open: then it goes just below it.
      var under = headerBottom() + 12 - mk.getBoundingClientRect().top;
      if (under > 0) window.scrollBy(0, -under);
    } else {
      scrollToEl(rowEl(r));
    }
    showFind();
  }
  function step(d) { goto(cur + d); }

  function find() {
    clearHits();
    var raw = fq.value;
    if (raw.length < 2) { showFind(); return; }
    hitCase = fcs.checked;
    hitTalk = talking();
    needle = hitCase ? raw : raw.toLowerCase();
    for (var r = 0; r < NR && hits.length < CAP; r++) {
      var n = CH.countIn(hayOf(r), needle, CAP - hits.length);
      if (!n) continue;
      hitRows[r] = [hits.length, n];
      for (var k = 0; k < n; k++) hits.push(r);
    }
    for (var b = 0; b < NB; b++) if (real[b]) marksIn(b);
    // Start from where you are reading, not from the top of a long page:
    // the first match at or below the top of the window.
    var y = headerBottom() + 8, start = -1, t = topThing(y);
    var from = t ? Math.max(0, t.r - 1) : NR;
    for (var h = 0; h < hits.length; h++) {
      if (hits[h] < from) continue;
      var mk = marks[h];
      if (!mk || !mk.isConnected || mk.getBoundingClientRect().top >= y) { start = h; break; }
    }
    if (hits.length) goto(start < 0 ? 0 : start); else showFind();
  }

  var fbar = document.querySelector(".find");
  function showOption() {
    var was = fbar.classList.contains("on");
    fbar.classList.toggle("on", !!fq.value || fcs.checked);
    if (fbar.classList.contains("on") !== was) fitHeader();
  }
  showOption();
  fq.addEventListener("focus", function () { if (!warmAt) warm(); });
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
  var mac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);
  if (windowed) {
    var keyName = mac ? "⌘F" : "Ctrl+F";
    fq.placeholder = "find in all of it   / or " + keyName;
    fq.title = "searches the whole conversation, even the parts not on the page yet. " +
      keyName + " comes here; " + keyName + " again opens the browser's own find, " +
      "which only sees what is on the page";
  }
  document.addEventListener("keydown", function (e) {
    if (!CH.ownsFindKey(e, mac, windowed, document.activeElement === fq)) return;
    e.preventDefault();
    fq.focus();
    fq.select();
  });

  var saved = "all";
  try { saved = localStorage.getItem("ch-mode") || "all"; } catch (e) {}
  mode(saved, true);
  if (/^#m\d+$/.test(location.hash)) toHash();
  else fillNear(NEAR);
  // Which prompt you are under, from the moment the page opens — not only
  // once you have scrolled.
  place();
  hold();
  // A reload can open the page halfway down, with no scroll to say so.
  if (compactAt(window.pageYOffset) !== mini) setMini(compactAt(window.pageYOffset));
})();
