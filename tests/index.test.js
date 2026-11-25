// Index tests. The index is browser code with no exports, so it runs here in
// a sandbox against a stand-in document just large enough for it: what it
// writes into the page is what is checked.
//   node tests/index.test.js
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const V = path.join(__dirname, "..", "viewer");
const viewerSrc = fs.readFileSync(path.join(V, "viewer.js"), "utf8");
const indexSrc = fs.readFileSync(path.join(V, "index.js"), "utf8");

const { test } = require("./lib.js");

function el(id) {
  const cls = new Set(), attrs = {};
  return {
    id, innerHTML: "", textContent: "", title: "", hidden: false, value: "",
    checked: false, dataset: {}, handlers: {}, attrs,
    setAttribute(k, v) { attrs[k] = String(v); },
    classList: {
      add: (c) => cls.add(c), remove: (c) => cls.delete(c),
      contains: (c) => cls.has(c),
      toggle: (c, on) => { if (on === undefined) on = !cls.has(c); on ? cls.add(c) : cls.delete(c); }
    },
    addEventListener(t, f) { this.handlers[t] = f; },
    classes: () => cls,
    // Rows only, which is all the index asks for after drawing the table.
    querySelectorAll(sel) {
      if (sel !== "tr:not(.grp)") return [];
      return (this.innerHTML.match(/<tr data-href[\s\S]*?<\/tr>/g) || []).map((h) => ({
        hidden: false, dataset: { proj: (/data-proj="([^"]*)"/.exec(h) || [])[1] || "" },
        textContent: h.replace(/<[^>]+>/g, "")
      }));
    }
  };
}

// Which of the table's ten columns index.css hides, at a window width, for
// the classes the table carries: read from the stylesheet itself, so the
// page's own column count is checked against the rules that really apply.
const CSS = fs.readFileSync(path.join(V, "index.css"), "utf8");
function hiddenCols(width, classes) {
  const hidden = new Set(), media = [];
  const re = /([^{}]*)\{|\}/g;
  let m, rule = null;
  while ((m = re.exec(CSS)) !== null) {
    if (m[0] === "}") {
      if (rule !== null) {
        const body = CSS.slice(rule.at, m.index);
        const applies = media.every((q) => q === null || width <= q);
        if (applies && /display:none/.test(body)) {
          rule.sel.split(",").forEach((sel) => {
            const x = /^#ix((?:\.[\w-]+)*) (?:thead )?th:nth-child\((\d+)\)$/.exec(sel.trim());
            if (x && x[1].split(".").filter(Boolean).every((c) => classes.has(c))) hidden.add(+x[2]);
          });
        }
        rule = null;
      } else media.pop();
      continue;
    }
    const pre = m[1].replace(/\/\*[\s\S]*?\*\//g, "").trim();
    if (/^@media/.test(pre)) {
      const w = /max-width:\s*(\d+)px/.exec(pre);
      media.push(/print/.test(pre) ? -1 : w ? +w[1] : null);
    } else rule = { sel: pre, at: re.lastIndex };
  }
  return hidden;
}

// Builds an index page from data, runs it, and hands back its elements.
// searchable lists the session ids whose search file exists; rowsFor, when
// given, says what each one's search file holds.
// The clock a loaded page sees: the real one, or a fixed "now" a test sets,
// so no result depends on when or how fast the test runs.
let NOW = null;
function clockAt(ms) {
  return class extends Date {
    constructor(...a) { if (a.length) super(...a); else super(ms); }
    static now() { return ms; }
  };
}
function load(data, searchable, width, rowsFor) {
  const els = {}, docHandlers = {}, clipboard = [];
  const get = (id) => els[id] || (els[id] = el(id));
  get("index-data").textContent = JSON.stringify(data);
  let timers = [];
  const store = () => { const m = {}; return {
    getItem: (k) => (k in m ? m[k] : null), setItem: (k, v) => { m[k] = String(v); },
    removeItem: (k) => { delete m[k]; } }; };
  const ths = Array.from({ length: 10 }, (_, i) => ({ col: i + 1 }));
  const ctx = {
    console, JSON, Date: NOW === null ? Date : clockAt(NOW), Math,
    getComputedStyle: (th) => ({
      display: hiddenCols(width || 1600, get("ix").classes()).has(th.col) ? "none" : "table-cell" }),
    matchMedia: () => ({ matches: false, addListener() {} }),
    localStorage: store(), sessionStorage: store(),
    setTimeout: (f) => { timers.push(f); return timers.length; },
    clearTimeout: () => {},
    location: { reload() {}, href: "" },
    navigator: { clipboard: { writeText: (t) => { clipboard.push(t); return { then: (f) => f() }; } } },
    getSelection: () => "",
    addEventListener() {}, removeEventListener() {},
    document: {
      getElementById: get,
      querySelectorAll: (sel) => (sel === "#ix thead th" ? ths : []),
      addEventListener(t, f) { (docHandlers[t] = docHandlers[t] || []).push(f); },
      querySelector: () => null,
      documentElement: { setAttribute() {}, removeAttribute() {} },
      createElement: () => ({}),
      head: { appendChild(tag) {
        const id = decodeURIComponent(tag.src.replace(/^search\/|\.js$/g, ""));
        timers.push(() => {
          if ((searchable || []).indexOf(id) < 0) return tag.onerror();
          ctx.CH_SEARCH(id, (rowsFor && rowsFor[id]) || [[0, "u", "hello there " + id, 1]]);
          tag.onload();
        });
      } }
    }
  };
  ctx.window = ctx;
  vm.createContext(ctx);
  vm.runInContext(viewerSrc, ctx);
  vm.runInContext(indexSrc, ctx);
  const flush = () => { for (let i = 0; i < 50 && timers.length; i++) { const t = timers; timers = []; t.forEach((f) => f()); } };
  const search = (text) => { get("q").value = text; get("q").handlers.input(); flush(); };
  // A click anywhere on the page, as the page's own document handlers see it.
  const click = (target) => (docHandlers.click || []).forEach((f) => f({ target }));
  return { get, search, click, clipboard, timers: () => timers };
}

const S = [
  { id: "aaaaaaaa-1", kind: "transcript", project: "app", cwd: "/x/app", title: "one", mtime: 1700000000, prompts: 3, tok: [1, 2, 3, 4], agents: 2 },
  { id: "bbbbbbbb-2", kind: "transcript", project: "app", cwd: "/x/app", title: "two", mtime: 1700000500, prompts: 1 },
  { id: "cccccccc-3", kind: "web", project: "claude.ai", title: "chat", url: "https://claude.ai/chat/c", mtime: 1700001000, prompts: 9 }
];

// ── platform ─────────────────────────────────────────────────────────
// The bin and the project links work only through the macOS helper app.
test("on a mac every row has a bin and a project link", () => {
  const p = load({ sessions: S, home: "/x", mac: true });
  const html = p.get("rows").innerHTML;
  assert.strictEqual((html.match(/class="del"/g) || []).length, 3);
  assert.ok(html.includes("claude-html://open/aaaaaaaa-1"));
  assert.strictEqual(p.get("launch").hidden, false);
});

test("an index without the flag is treated as a mac one", () => {
  const html = load({ sessions: S, home: "/x" }).get("rows").innerHTML;
  assert.ok(html.includes("claude-html://delete/"));
});

test("elsewhere nothing offers what cannot happen", () => {
  const p = load({ sessions: S, home: "/x", mac: false });
  const html = p.get("rows").innerHTML;
  assert.ok(!html.includes("claude-html://"), "no helper links");
  assert.ok(!/delete|hide this chat/.test(html), "no tooltip promising deletion");
  assert.ok(html.includes("<td>app</td>"), "project name is plain text");
  assert.ok(p.get("ix").classList.contains("nomac"), "bin column hidden");
  assert.strictEqual(p.get("launch").hidden, true, "no launcher claim");
});

test("with link actions, each resumable row offers resume beside copy", () => {
  const p = load({ sessions: S, home: "/x", actions: true, mac: false });
  const html = p.get("rows").innerHTML;
  assert.strictEqual((html.match(/claude-html:\/\/resume\//g) || []).length, 2, "not on the web chat");
  assert.ok(/>copy<\/button><a class="go" href="claude-html:\/\/resume\/aaaaaaaa-1"/.test(html));
  assert.ok(/click its <b>resume<\/b>/.test(p.get("launch").innerHTML));
});

test("actions false wins over mac, and still says how to reopen one", () => {
  const p = load({ sessions: S, home: "/x", actions: false, mac: true });
  const html = p.get("rows").innerHTML;
  assert.ok(!html.includes("claude-html://"), "no links");
  assert.ok(html.includes(">copy</button>"), "copy stays");
  assert.ok(p.get("ix").classList.contains("nomac"));
  assert.strictEqual(p.get("launch").hidden, false);
  assert.ok(/paste its <b>copy<\/b> into a terminal/.test(p.get("launch").innerHTML));
});

test("grouped by project, the headings are plain text too", () => {
  const p = load({ sessions: S, home: "/x", mac: false });
  p.get("gproj").handlers.click();
  const html = p.get("rows").innerHTML;
  assert.ok(html.includes('class="grp"'));
  assert.ok(html.includes("10 tokens"), "token totals stay on the heading");
  assert.ok(!html.includes("claude-html://"));
});

// A resumed or forked session holds a copy of the replies it came from:
// its row counts its whole transcript and says so, while the project's
// heading counts each reply once, as the dashboard does.
test("a heading counts a copied reply once; the row says it holds one", () => {
  const C = [
    { id: "aaaaaaaa-1", kind: "transcript", project: "app", cwd: "/x/app", title: "original", mtime: 1700000000, prompts: 1,
      tok: [100, 200, 300, 400, 2], shares: [1, 500] },
    { id: "bbbbbbbb-2", kind: "transcript", project: "app", cwd: "/x/app", title: "resumed", mtime: 1700000500, prompts: 1,
      tok: [100, 200, 3000, 4000, 2], shares: [1, 500], dup: 500 }
  ];
  const p = load({ sessions: C, home: "/x", mac: false });
  p.get("gproj").handlers.click();
  const html = p.get("rows").innerHTML;
  assert.ok(html.includes("7.8 k tokens"), /<span class="gc">[^<]*/.exec(html)[0]);
  assert.strictEqual((html.match(/title="incl\. 500 tokens also in another session/g) || []).length, 2);
});

// ── when it was built ────────────────────────────────────────────────
test("the build time is shown when the data carries it", () => {
  NOW = Date.UTC(2026, 10, 20, 12, 0, 0);
  const t = NOW / 1000 - 7200;
  const txt = load({ sessions: S, built: t }).get("built").textContent;
  NOW = null;
  assert.ok(/^ · built \d{4}-\d\d-\d\d \d\d:\d\d \(2 h ago\)$/.test(txt), txt);
});

test("and nothing is shown when it does not", () => {
  assert.strictEqual(load({ sessions: S }).get("built").textContent, "");
});

// ── a newer release ──────────────────────────────────────────────────
test("a newer release is one line in the header, the command in code", () => {
  const up = load({ sessions: S, update: "3.1.0" }).get("update");
  assert.strictEqual(up.hidden, false);
  assert.ok(up.innerHTML.startsWith("3.1.0 is out · update with <code>claude-html --update</code> <button"), up.innerHTML);
});

test("the notice has the rows' copy button, with the exact command", () => {
  const html = load({ sessions: S, update: "3.2.0", actions: false }).get("update").innerHTML;
  assert.ok(html.includes('<button class="cp" data-c="claude-html --update">copy</button>'), html);
  assert.ok(!html.includes("claude-html://"), "no run link without the link handler: " + html);
});

test("and the rows' run-style link to claude-html://update where links work", () => {
  const html = load({ sessions: S, update: "3.2.0", actions: true }).get("update").innerHTML;
  assert.ok(/<a class="go" href="claude-html:\/\/update" [^>]*>run<\/a>$/.test(html), html);
  assert.ok(load({ sessions: S, update: "3.2.0", mac: true }).get("update").innerHTML.includes('href="claude-html://update"'));
});

test("its copy goes through the one copy handler the rows use", () => {
  const p = load({ sessions: S, update: "3.2.0" });
  const c = /data-c="([^"]*)"/.exec(p.get("update").innerHTML)[1];
  const btn = { matches: (sel) => sel === "button.cp", dataset: { c }, textContent: "copy" };
  p.click(btn);
  assert.deepStrictEqual(p.clipboard, ["claude-html --update"]);
  assert.strictEqual(btn.textContent, "copied");
  assert.strictEqual((indexSrc.match(/clipboard\.writeText/g) || []).length, 1, "one copy handler, not two");
});

test("the notice is in the title's colour, the token the page itself uses", () => {
  const css = fs.readFileSync(path.join(V, "index.css"), "utf8");
  assert.ok(/body\{[^}]*color:var\(--fg\)/.test(css), "the title inherits --fg from body");
  assert.ok(/p\.sub\.upd\{[^}]*color:var\(--fg\)/.test(css), "the notice uses --fg");
  assert.ok(/<p class="sub upd" id="update" hidden>/.test(fs.readFileSync(path.join(V, "index.html"), "utf8")));
});

test("and nothing, or nothing odd, when the data has none or a strange one", () => {
  assert.strictEqual(load({ sessions: S }).get("update").innerHTML, "");
  assert.strictEqual(load({ sessions: S, update: "<b>x</b>" }).get("update").innerHTML, "");
});

// ── rows ─────────────────────────────────────────────────────────────
test("rows keep the agents pill and right-aligned figures", () => {
  const html = load({ sessions: S, home: "/x" }).get("rows").innerHTML;
  // a no-break space, so the count and its word never part
  assert.ok(html.includes("<span class=\"nag\">2\u00a0agents</span>"));
  assert.strictEqual((html.match(/<td class="num">/g) || []).length, 3);
  assert.ok(html.includes('<td class="dt">2023-11-'));
});

// ── cost ─────────────────────────────────────────────────────────────
// A cost Claude Code recorded is a sixth figure on tok; a session without
// one says "—", never "$0.00", and one whose record covers only part of it
// says it cost at least that much.
test("the cost column: known, a floor, and unknown", () => {
  const C = [
    { id: "dddddddd-4", kind: "transcript", project: "app", title: "known", mtime: 1700002000, prompts: 1, tok: [1, 2, 3, 4, 1, 498942735] },
    { id: "eeeeeeee-5", kind: "transcript", project: "app", title: "part", mtime: 1700003000, prompts: 1, tok: [1, 2, 3, 4, 1, 1327735018], costPart: true },
    { id: "ffffffff-6", kind: "transcript", project: "app", title: "none", mtime: 1700004000, prompts: 1, tok: [1, 2, 3, 4, 1] }
  ];
  const html = load({ sessions: C, home: "/x" }).get("rows").innerHTML;
  const cells = html.match(/<td class="num cost[^"]*"[^>]*>[^<]*<\/td>/g).map((c) => c.replace(/<[^>]*>/g, ""));
  assert.deepStrictEqual(cells, ["≈ $499", "≥ $1,328", "—"]);
  assert.ok(!html.includes("$0.00"));
  // one cell per row, so every column after it stays where the widths put it
  assert.strictEqual((html.match(/<td/g) || []).length, 3 * 10);
});

// Where Claude Code recorded nothing, the cost calculated from the price
// file takes the place of "—", marked calc; a recorded one is never
// replaced by it, and a floor says so.
test("the cost column: calculated where nothing was recorded, marked as such", () => {
  const C = [
    { id: "dddddddd-7", kind: "transcript", project: "app", title: "recorded", mtime: 1700002000, prompts: 1, tok: [1, 2, 3, 4, 1, 498942735], calc: 1000000 },
    { id: "eeeeeeee-8", kind: "transcript", project: "app", title: "calc", mtime: 1700003000, prompts: 1, tok: [1, 2, 3, 4, 1], calc: 12400000 },
    { id: "ffffffff-9", kind: "transcript", project: "app", title: "calc part", mtime: 1700004000, prompts: 1, tok: [1, 2, 3, 4, 1], calc: 2500000, calcPart: true },
    { id: "aaaaaaaa-0", kind: "transcript", project: "app", title: "unpriced", mtime: 1700005000, prompts: 1, tok: [1, 2, 3, 4, 1] }
  ];
  const html = load({ sessions: C, home: "/x" }).get("rows").innerHTML;
  const cells = html.match(/<td class="num cost[^"]*"[^>]*>.*?<\/td>/g).map((c) => c.replace(/<[^>]*>/g, ""));
  assert.deepStrictEqual(cells, ["≈ $499", "$12 calc", "≥ $2.50 calc", "—"]);
  assert.strictEqual((html.match(/class="num cost calc"/g) || []).length, 2);
  assert.strictEqual((html.match(/<td/g) || []).length, 4 * 10);
});

test("the header has a column for every cell", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "viewer", "index.html"), "utf8");
  const head = /<thead><tr>([\s\S]*?)<\/tr><\/thead>/.exec(src)[1];
  assert.strictEqual((head.match(/<th/g) || []).length, 10);
  const css = fs.readFileSync(path.join(__dirname, "..", "viewer", "index.css"), "utf8");
  assert.ok(/td:nth-child\(10\),thead th:nth-child\(10\)\{width:34px\}/.test(css), "the bin keeps its width");
});

// ── search ───────────────────────────────────────────────────────────
test("a missing search file is said in the results line", () => {
  const p = load({ sessions: S, home: "/x" }, ["aaaaaaaa-1", "bbbbbbbb-2"]);
  p.search("hello");
  const n = p.get("n").textContent;
  assert.ok(n.includes("2 messages"), n);
  assert.ok(n.includes("1 conversation not searched"), n);
});

test("with every file present the line says nothing extra", () => {
  const p = load({ sessions: S, home: "/x" }, S.map((s) => s.id));
  p.search("hello");
  assert.ok(!p.get("n").textContent.includes("not searched"));
});

test("with none present it does not stay on searching… forever", () => {
  const p = load({ sessions: S, home: "/x" }, []);
  p.search("hello");
  assert.ok(p.get("mr").innerHTML.includes("no search index"));
  assert.ok(p.get("n").textContent.includes("not searchable"), p.get("n").textContent);
  p.search("hello again");
  assert.ok(p.get("n").textContent.includes("not searchable"), "and still says so");
});

// The loader counted down a local that was once called pending, the name of
// the delete helper too; renamed in one place only, an index with no sessions
// waited on scripts it never asked for and showed "loading…" for good.
test("an empty index finishes searching instead of loading forever", () => {
  const p = load({ sessions: [], home: "/x" }, []);
  p.search("hello");
  assert.ok(!p.get("mr").innerHTML.includes("loading"), p.get("mr").innerHTML);
  assert.ok(p.get("n").textContent.includes("0 messages"), p.get("n").textContent);
});

test("a search typed while the files load is the one answered", () => {
  const p = load({ sessions: S, home: "/x" }, S.map((s) => s.id));
  p.get("q").value = "hello"; p.get("q").handlers.input();
  p.get("q").value = "hello aaaaaaaa"; p.get("q").handlers.input();
  p.search("hello aaaaaaaa");
  // the one session whose message matched counts, though its row did not
  assert.ok(/^1 of 3 sessions · 1 message$/.test(p.get("n").textContent), p.get("n").textContent);
});

// ── search: newest first, and what it is not showing ─────────────────
// Each session shows its five newest matches, and says how many more it has.
// It once took the first five it met, the oldest, and said nothing of the rest.
const MANY = [
  { id: "aaaaaaaa-1", kind: "transcript", project: "app", cwd: "/x/app", title: "one", mtime: 1700000000, prompts: 3 },
  { id: "bbbbbbbb-2", kind: "transcript", project: "web", cwd: "/x/web", title: "two", mtime: 1700000500, prompts: 1 }
];
function manyRows() {
  const r = [];
  for (let i = 0; i < 8; i++) r.push([i * 2, "u", "needle number " + i, 1700000000 + i * 60]);
  return { "aaaaaaaa-1": r, "bbbbbbbb-2": [[0, "t", "a needle elsewhere", 1700000100]] };
}

test("search shows each session's newest matches first", () => {
  const p = load({ sessions: MANY, home: "/x" }, MANY.map((s) => s.id), 1600, manyRows());
  p.search("needle");
  const html = p.get("mr").innerHTML;
  const shown = (html.match(/needle<\/mark> number (\d)/g) || []).map((x) => +x.slice(-1));
  assert.deepStrictEqual(shown, [7, 6, 5, 4, 3], html);
  assert.ok(html.indexOf("number 3") < html.indexOf("a <mark>needle</mark> elsewhere"), "the older session's hit comes after");
});

test("and says how many more a session holds, linking to the next of them", () => {
  const p = load({ sessions: MANY, home: "/x" }, MANY.map((s) => s.id), 1600, manyRows());
  p.search("needle");
  const html = p.get("mr").innerHTML;
  assert.ok(/<a class="more" href="sessions\/aaaaaaaa-1\.html#m4:find=needle">\+ 3 more in this session<\/a>/.test(html), html);
  assert.strictEqual((html.match(/class="more"/g) || []).length, 1, "not under a session with nothing more");
  assert.strictEqual(p.get("n").textContent, "2 of 2 sessions · 9 messages");
});

// A hit in thinking lands on a folded block: the words searched for go with
// the link, and the session page looks for them again, which opens it.
test("every result link carries the longest word searched for", () => {
  const p = load({ sessions: MANY, home: "/x" }, MANY.map((s) => s.id), 1600, manyRows());
  p.search('nee "needle number"');
  const links = p.get("mr").innerHTML.match(/href="sessions\/[^"]+"/g) || [];
  assert.ok(links.length > 0, "no result links");
  links.forEach((l) => assert.ok(/#m\d+:find=needle%20number"$/.test(l), l));
});

// ── the filter over the rows ─────────────────────────────────────────
// It matched the rows' own text, button labels included: "copy" or
// "resume" kept every row that could be resumed.
test("the filter reads date, project, title and id, not button labels", () => {
  const p = load({ sessions: S, home: "/x", actions: true }, S.map((s) => s.id));
  ["copy", "resume", "transcript", "agents"].forEach((w) => {
    p.search(w);
    assert.ok(p.get("n").textContent.startsWith("0 of 3 sessions"), w + ": " + p.get("n").textContent);
  });
  p.search("bbbbbbbb");
  assert.ok(p.get("n").textContent.startsWith("1 of 3"), "the id still finds its row");
  p.search("app two");
  assert.ok(p.get("n").textContent.startsWith("1 of 3"), "project and title together");
});

// ── the title opens the conversation ─────────────────────────────────
// Below 1500px the session-id column is hidden, and it held the only link:
// a keyboard could not open a conversation at all.
test("the title is a link to the conversation, with the full title on it", () => {
  const html = load({ sessions: S, home: "/x" }).get("rows").innerHTML;
  assert.ok(html.includes('<a class="ti" href="sessions/aaaaaaaa-1.html" title="one">one</a>'), html);
  assert.strictEqual((html.match(/<a class="ti" href="sessions\//g) || []).length, 3);
});

// ── grouped, the heading spans what is showing ───────────────────────
// A span of ten over a table showing eight added two empty columns, which
// took the title's width: titles cut to four letters at 1100px.
[1600, 1500, 1400, 1100, 1000, 700, 400].forEach((w) => {
  [true, false].forEach((links) => {
    test(`at ${w}px${links ? "" : " without the helper"} a heading spans the visible columns`, () => {
      const p = load({ sessions: S, home: "/x", actions: links }, [], w);
      p.get("gproj").handlers.click();
      const spans = (p.get("rows").innerHTML.match(/colspan="(\d+)"/g) || []).map((x) => +x.match(/\d+/)[0]);
      const classes = p.get("ix").classes();
      assert.ok(classes.has("grouped"), "the table knows it is grouped");
      const visible = 10 - hiddenCols(w, classes).size;
      assert.ok(spans.length > 0);
      spans.forEach((n) => assert.strictEqual(n, visible));
      assert.ok(visible < 10, "the project column at least is hidden when grouped");
    });
  });
});

// ── counts in words ──────────────────────────────────────────────────
test("one session, one prompt: never 1 sessions or 1 prompts", () => {
  const one = S.concat([{ id: "dddddddd-4", kind: "transcript", project: "solo", cwd: "/x/solo", title: "s", mtime: 1700002000, prompts: 1 }]);
  const p = load({ sessions: one, home: "/x" });
  p.get("gproj").handlers.click();
  const html = p.get("rows").innerHTML;
  assert.ok(html.includes("1 session · 1 prompt<"), html);
  assert.ok(html.includes("2 sessions · 4 prompts"), html);
  assert.strictEqual(p.get("count").textContent, "4 sessions");
  assert.strictEqual(load({ sessions: [S[0]], home: "/x" }).get("count").textContent, "1 session");
});

test("an empty index hides the table's headings and says why", () => {
  const p = load({ sessions: [], home: "/x" });
  assert.strictEqual(p.get("tw").hidden, true);
  assert.strictEqual(p.get("empty").hidden, false);
});

test("the group toggle says which view is on", () => {
  const p = load({ sessions: S, home: "/x" });
  p.get("gproj").handlers.click();
  assert.strictEqual(p.get("gproj").attrs["aria-pressed"], "true");
  assert.strictEqual(p.get("gdate").attrs["aria-pressed"], "false");
});

require("./lib.js").report();
