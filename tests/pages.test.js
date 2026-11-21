// The three page templates and the dashboard, checked without a browser:
// what every page needs in its head, what each says in words, and the
// dashboard's chart run in a sandbox against a stand-in document.
//   node tests/pages.test.js
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const V = path.join(__dirname, "..", "viewer");
const read = (f) => fs.readFileSync(path.join(V, f), "utf8");

let ran = 0, failed = [];
function test(name, fn) {
  ran++;
  try { fn(); } catch (e) { failed.push([name, e.message]); }
}

const PAGES = ["index.html", "page.html", "usage.html"];

// ── every page ───────────────────────────────────────────────────────
// Without a viewport a phone lays the page out at 980px and shrinks it;
// without lang a screen reader guesses the language.
PAGES.forEach((f) => {
  const html = read(f);
  test(`${f} says its language and fits a phone's width`, () => {
    assert.ok(/^<!doctype html><html lang="en">/.test(html), html.slice(0, 60));
    assert.ok(html.includes('<meta name="viewport" content="width=device-width,initial-scale=1">'));
  });
  // A page forced to dark showed light first, until its script ran at the end.
  test(`${f} sets the stored theme before anything is drawn`, () => {
    const at = html.indexOf('localStorage.getItem("ch-theme")');
    assert.ok(at > -1 && at < html.indexOf("<style>"), "in the head, before the styles");
  });
  // A glyph is not a name: « ‹ › » ◐ ▾ need one in words.
  test(`${f}: every button without a word in it has an aria-label`, () => {
    (html.match(/<button[^>]*>[^<]*<\/button>/g) || []).forEach((b) => {
      const text = b.replace(/<[^>]*>/g, "");
      if (!/[a-z]/i.test(text)) assert.ok(/aria-label="[^"]+"/.test(b), b);
    });
  });
});

// Printed, a dark screen gave light grey on white paper.
["index.css", "session.css"].forEach((f) => {
  test(`${f} prints in the light palette, without its controls`, () => {
    const css = read(f), at = css.indexOf("@media print{");
    assert.ok(at > -1, "a print block");
    const block = css.slice(at);
    assert.ok(/:root:root:root\{--bg:#fff;--fg:#111;/.test(block), "light tokens that outrank the dark ones");
    assert.ok(/\.th[,{]/.test(block) || /\.th,/.test(block) || /\.hx/.test(block), "the toggles go");
  });
});
test("a printed session has its header once, unfolded, and no sticky band", () => {
  const css = read("session.css"), block = css.slice(css.indexOf("@media print{"));
  assert.ok(block.includes("header{position:static;margin-bottom:0!important}"));
  assert.ok(block.includes("header.mini .meta:not([hidden]){display:block}"));
  assert.ok(block.includes("header .bar,header .resume,.hx{display:none!important}"));
});

// ── contrast ─────────────────────────────────────────────────────────
// Text that carries information was drawn at a fraction of the muted colour:
// times at 2.5:1, the stale tag at 4:1, the bin at 1.6:1.
function lum(h) {
  return [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255)
    .map((v) => (v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)))
    .reduce((t, v, i) => t + v * [0.2126, 0.7152, 0.0722][i], 0);
}
function ratio(a, b) { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); }
function tokens(css, sel) {
  const at = css.indexOf(sel + "{"), body = css.slice(at + sel.length + 1, css.indexOf("}", at));
  const out = {};
  body.split(";").forEach((d) => { const m = /^(--[\w-]+):(#[0-9a-f]{6})$/.exec(d.trim()); if (m) out[m[1]] = m[2]; });
  return out;
}
test("muted and warning text read at 4.5:1 or better in both themes", () => {
  const css = read("index.css");
  [":root", ":root[data-theme=dark]"].forEach((sel) => {
    const t = tokens(css, sel);
    assert.ok(ratio(t["--dim"], t["--bg"]) >= 4.5, sel + " --dim");
    assert.ok(ratio(t["--warn"], t["--bg"]) >= 4.5, sel + " --warn");
  });
  assert.ok(/\.stale\{color:var\(--warn\);font-size:10\.5px/.test(css));
  const bin = +/\n\.del\{[^}]*opacity:([\d.]+)/.exec(css)[1];
  assert.ok(bin >= 0.75, "the idle bin at " + bin);
});
test("times, labels and separators are not faded below the muted colour", () => {
  const css = read("session.css");
  ["\n.ts{", "\n.nav .lbl{", "\n.crumbs .sep{"].forEach((sel) => {
    const at = css.indexOf(sel);
    assert.ok(at > -1, sel);
    assert.ok(!/opacity/.test(css.slice(at, css.indexOf("}", at))), sel.trim() + " has no opacity");
  });
});

// ── a session page, in words ─────────────────────────────────────────
// page.js needs a real page to run; what it writes is checked here as source.
const pageSrc = read("page.js");
test("a session's counts use the plural only when there are several", () => {
  assert.ok(/CH\.plural\(prompts, "prompt"\)/.test(pageSrc));
  assert.ok(/CH\.plural\(data\.messages\.length, "message"\)/.test(pageSrc));
  assert.ok(/CH\.plural\(data\.agents\.length, "sub-agent"\)/.test(pageSrc));
  assert.ok(!/" prompts · "|" sub-agents"/.test(pageSrc), "no fixed plurals left");
});
test("a page with no prompts of yours has no prompt arrows", () => {
  assert.ok(/if \(!ps\.length\) document\.querySelector\("\.nav"\)\.hidden = true;/.test(pageSrc));
  assert.ok(read("session.css").includes(".nav[hidden]{display:none}"), "display:flex would outrank hidden");
});
// Escape emptied the field but left « ‹ › » around an empty counter.
test("Escape in find empties it the way deleting the text does", () => {
  assert.ok(/e\.key === "Escape"\) \{ fq\.value = ""; showOption\(\); find\(\); fq\.blur\(\); \}/.test(pageSrc));
});
test("find opens what is folded over the match it lands on", () => {
  const go = pageSrc.slice(pageSrc.indexOf("function goto"), pageSrc.indexOf("function step"));
  assert.ok(/unfold\(mk\)/.test(go) && go.indexOf("unfold(mk)") < go.indexOf("scrollIntoView"));
});

// ── the dashboard ────────────────────────────────────────────────────
function el(id) {
  const cls = new Set();
  return {
    id, innerHTML: "", textContent: "", hidden: false, handlers: {}, clientWidth: 1000,
    classList: { add: (c) => cls.add(c), remove: (c) => cls.delete(c), contains: (c) => cls.has(c),
      toggle: (c, on) => { if (on === undefined) on = !cls.has(c); on ? cls.add(c) : cls.delete(c); } },
    addEventListener(t, f) { this.handlers[t] = f; },
    setAttribute() {}
  };
}
function usage(byProject, store) {
  const els = {};
  const get = (id) => els[id] || (els[id] = el(id));
  get("usage-data").textContent = JSON.stringify({ byProject, coverage: {} });
  const m = Object.assign({}, store || {});
  const ctx = {
    console, JSON, Date, Math,
    localStorage: { getItem: (k) => (k in m ? m[k] : null), setItem: (k, v) => { m[k] = String(v); }, removeItem: (k) => { delete m[k]; } },
    setTimeout: () => 0, clearTimeout: () => {},
    addEventListener() {},
    document: { getElementById: get, addEventListener() {}, documentElement: { setAttribute() {}, removeAttribute() {} } }
  };
  ctx.window = ctx;
  vm.createContext(ctx);
  vm.runInContext(read("viewer.js"), ctx);
  vm.runInContext(read("usage.js"), ctx);
  return get;
}
const cell = [10, 20, 300, 40, 2];
// Midday on a Wednesday, so no timezone moves a record into another week.
const GAPPY = { app: {
  "2026-09-16T12": { "claude-opus-4-5": cell },
  "2026-10-14T12": { "claude-opus-4-5": cell },
  "2026-11-18T12": { "claude-opus-4-5": cell.concat([0, 0, 1234567]) } } };
const cols = (html) => (html.match(/class="col"/g) || []).length;
const bars = (html) => (html.match(/<button type="button" class="col"/g) || []).length;

// Only the periods that had data were drawn, so September and November
// stood side by side as if October had happened in between.
test("by month the chart has a column for every month, the empty ones too", () => {
  const get = usage(GAPPY, { "ch-usage-period": "month" });
  const html = get("chart").innerHTML;
  assert.strictEqual(cols(html), 3, html);
  assert.strictEqual(bars(html), 3, "October had data too");
  const quiet = usage({ app: { "2026-09-16T12": GAPPY.app["2026-09-16T12"], "2026-11-18T12": GAPPY.app["2026-11-18T12"] } },
    { "ch-usage-period": "month" })("chart").innerHTML;
  assert.strictEqual(cols(quiet), 3, "September, an empty October, November");
  assert.strictEqual(bars(quiet), 2, "the empty month is a column, not a bar to click");
});

test("by week, every week from the first to the last", () => {
  const html = usage(GAPPY, { "ch-usage-period": "week" })("chart").innerHTML;
  // Sep 14 … Nov 16: ten weeks, three with data
  assert.strictEqual(cols(html), 10, html);
  assert.strictEqual(bars(html), 3);
  const keys = (html.match(/data-k="([^"]+)"/g) || []).map((k) => k.slice(8, -1));
  assert.deepStrictEqual(keys, keys.slice().sort(), "in order");
});

test("all time goes by day over the calendar span, not the days that had data", () => {
  // three days with data, sixty-four days apart: by day, every one of them
  const html = usage(GAPPY, { "ch-usage-period": "all" })("chart").innerHTML;
  assert.strictEqual(cols(html), 64, cols(html));
  assert.strictEqual(bars(html), 3);
});

test("a bar is a button that names itself, its fields kept apart", () => {
  const html = usage(GAPPY, { "ch-usage-period": "month" })("chart").innerHTML;
  assert.ok(/<button type="button" class="col" data-k="2026-11" title="2026-11 · 370 tokens · 2 replies · ≈ \$1\.23" aria-label="2026-11 · 370 tokens · 2 replies · ≈ \$1\.23">/.test(html), html);
});

test("the tables say ≈ before a cost, as the cards and the index do", () => {
  const get = usage(GAPPY, { "ch-usage-period": "month" });
  assert.ok(get("buckets").innerHTML.includes(">≈ $1.23</td>"), get("buckets").innerHTML);
  assert.ok(/class="num d">—<\/td>/.test(get("buckets").innerHTML), "and — where none was recorded");
});

// The empty dashboard showed a blank chart and two tables of headings over
// the sentence that said there was nothing.
test("with nothing recorded, only the sentence shows", () => {
  const get = usage({});
  assert.strictEqual(get("empty").hidden, false);
  assert.strictEqual(get("dash").hidden, true);
  assert.ok(/<p class="none" id="empty" hidden>/.test(read("usage.html")));
  const html = read("usage.html");
  assert.ok(html.indexOf('<div id="dash">') < html.indexOf('id="chart"') &&
            html.indexOf('id="projects"') < html.indexOf("</div>\n\n<p class=\"none\" id=\"empty\""),
    "the chart and both tables are inside what is hidden");
});

// The label "broken down by ·" wrapped away from its buttons on a narrow window.
test("each toggle's label stays on the line of its buttons", () => {
  const html = read("usage.html");
  assert.ok(/<span class="vg">period ·\n<button id="pweek">/.test(html));
  assert.ok(/<span class="vg gap">broken down by ·\n<button id="bmodel">/.test(html));
  assert.ok(/\.view \.vg\{display:inline-block;white-space:nowrap/.test(html));
});

if (failed.length) {
  failed.forEach(([n, m]) => console.log("FAIL " + n + "\n     " + m));
  console.log(failed.length + " of " + ran + " failed");
  process.exit(1);
}
console.log(ran + " passed");
