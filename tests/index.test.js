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

let ran = 0, failed = [];
function test(name, fn) {
  ran++;
  try { fn(); } catch (e) { failed.push([name, e.message]); }
}

function el(id) {
  const cls = new Set();
  return {
    id, innerHTML: "", textContent: "", title: "", hidden: false, value: "",
    checked: false, dataset: {}, handlers: {},
    classList: {
      add: (c) => cls.add(c), remove: (c) => cls.delete(c),
      contains: (c) => cls.has(c),
      toggle: (c, on) => { if (on === undefined) on = !cls.has(c); on ? cls.add(c) : cls.delete(c); }
    },
    addEventListener(t, f) { this.handlers[t] = f; },
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

// Builds an index page from data, runs it, and hands back its elements.
// searchable lists the session ids whose search file exists.
function load(data, searchable) {
  const els = {};
  const get = (id) => els[id] || (els[id] = el(id));
  get("index-data").textContent = JSON.stringify(data);
  let timers = [];
  const store = () => { const m = {}; return {
    getItem: (k) => (k in m ? m[k] : null), setItem: (k, v) => { m[k] = String(v); },
    removeItem: (k) => { delete m[k]; } }; };
  const ctx = {
    console, JSON, Date, Math,
    localStorage: store(), sessionStorage: store(),
    setTimeout: (f) => { timers.push(f); return timers.length; },
    clearTimeout: () => {},
    location: { reload() {}, href: "" },
    navigator: {},
    getSelection: () => "",
    addEventListener() {}, removeEventListener() {},
    document: {
      getElementById: get,
      addEventListener() {},
      querySelector: () => null,
      documentElement: { setAttribute() {}, removeAttribute() {} },
      createElement: () => ({}),
      head: { appendChild(tag) {
        const id = decodeURIComponent(tag.src.replace(/^search\/|\.js$/g, ""));
        timers.push(() => {
          if ((searchable || []).indexOf(id) < 0) return tag.onerror();
          ctx.CH_SEARCH(id, [[0, "u", "hello there " + id, 1]]);
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
  return { get, search };
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

// ── when it was built ────────────────────────────────────────────────
test("the build time is shown when the data carries it", () => {
  const t = Math.floor(Date.now() / 1000) - 7200;
  const txt = load({ sessions: S, built: t }).get("built").textContent;
  assert.ok(/^ · built \d{4}-\d\d-\d\d \d\d:\d\d \(2 h ago\)$/.test(txt), txt);
});

test("and nothing is shown when it does not", () => {
  assert.strictEqual(load({ sessions: S }).get("built").textContent, "");
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
  assert.ok(/^0 of 3 sessions · 1 messages$/.test(p.get("n").textContent), p.get("n").textContent);
});

if (failed.length) {
  failed.forEach(([n, m]) => console.log("FAIL " + n + "\n     " + m));
  console.log(failed.length + " of " + ran + " failed");
  process.exit(1);
}
console.log(ran + " passed");
