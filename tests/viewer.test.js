// Viewer tests. Node runs these; the browser runs the same code.
//   node tests/viewer.test.js
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const CH = require("../viewer/viewer.js");

let ran = 0, failed = [];
function test(name, fn) {
  ran++;
  try { fn(); } catch (e) { failed.push([name, e.message]); }
}

// ── prose ────────────────────────────────────────────────────────────
test("inline code and bold survive escaping", () => {
  assert.ok(CH.prose("run `x` now").includes('<code class="ic">x</code>'));
  assert.ok(CH.prose("very **y** thing").includes("<strong>y</strong>"));
});

test("headings and lists", () => {
  const out = CH.prose("## Title\n- one\n- two");
  assert.ok(out.includes('<div class="h">Title</div>'));
  assert.strictEqual((out.match(/<li>/g) || []).length, 2);
});

test("fenced code survives intact", () => {
  const out = CH.markdownish("before\n```py\nif x < 1:\n```\nafter");
  assert.ok(out.includes("if x &lt; 1:"));
  assert.ok(out.includes('<pre class="code">'));
});

test("html in prose is escaped", () => {
  assert.ok(!CH.prose("a <b>tag</b>").includes("<b>"));
});

test("truncation says how much was cut", () => {
  assert.ok(CH.cap("x".repeat(50), 10).includes("40 more characters"));
});

// ── tools ────────────────────────────────────────────────────────────
test("an Edit becomes a diff", () => {
  const out = CH.renderTool({ name: "Edit", input: {
    file_path: "/a.py", old_string: "one\ntwo", new_string: "one\n2" } });
  assert.ok(out.includes('class="dl del"'));
  assert.ok(out.includes('class="dl add"'));
});

test("the summary line reads as a sentence, not JSON", () => {
  const out = CH.renderTool({ name: "Grep", input: { pattern: "todo", path: "src" } });
  const summary = out.split("</summary>")[0];
  assert.ok(summary.includes("todo  src"));
  assert.ok(!summary.includes("{"));
});

test("a bare tool name from an old archive does not crash", () => {
  assert.ok(CH.renderTool("Bash").includes("not recorded"));
});

test("recovered output is shown and height-capped", () => {
  const out = CH.renderTool("Bash", "line\n".repeat(40));
  assert.ok(out.includes('class="code out"'));
  assert.ok(out.includes(" open>"));
});

test("a one-line result needs no body", () => {
  const out = CH.renderTool("Bash", "3 files changed");
  assert.ok(!out.includes("<pre"));
  assert.ok(out.includes("3 files changed"));
});

test("tool input is escaped", () => {
  assert.ok(!CH.renderTool({ name: "Bash", input: { command: "<script>" } }).includes("<script>"));
});

test("nothing needs a click", () => {
  ["Bash", "Read", "Grep"].forEach(n => {
    assert.ok(CH.renderTool({ name: n, input: { command: "x", file_path: "/a", pattern: "p" } })
      .includes('<details class="tool" open>'), n);
  });
});

test("a command is not height-capped, output is", () => {
  const cmd = CH.renderTool({ name: "Bash", input: { command: "ls" } });
  assert.ok(cmd.includes('class="code"') && !cmd.includes('class="code out"'));
  assert.ok(CH.renderTool({ name: "Grep", input: { pattern: "x" } }).includes('class="code out"'));
});

// ── pairing ──────────────────────────────────────────────────────────
const TURN = [
  { role: "assistant", text: "", tools: ["Read", "Bash"] },
  { role: "tool_result", text: "1 def main():" },
  { role: "tool_result", text: "3 files changed" },
  { role: "assistant", text: "done", tools: [] },
];

test("results are matched to the calls in order", () => {
  const p = CH.pairBareTools(TURN);
  assert.deepStrictEqual(p.paired[0], ["1 def main():", "3 files changed"]);
  assert.deepStrictEqual(Object.keys(p.consumed), ["1", "2"]);
});

test("output appears inside the call, not twice", () => {
  const page = CH.renderMessages(TURN);
  assert.strictEqual((page.match(/3 files changed/g) || []).length, 1);
  assert.ok(!page.includes("not recorded"));
});

test("a call with no result still says so", () => {
  const page = CH.renderMessages([
    { role: "assistant", text: "", tools: ["Read", "Bash"] },
    { role: "tool_result", text: "only one result" }]);
  assert.ok(page.includes("only one result"));
  assert.strictEqual((page.match(/not recorded/g) || []).length, 1);
});

test("modern tool calls are untouched by pairing", () => {
  const p = CH.pairBareTools([
    { role: "assistant", text: "", tools: [{ name: "Bash", input: { command: "ls" } }] },
    { role: "tool_result", text: "a.txt" }]);
  assert.deepStrictEqual(p.paired, {});
  assert.deepStrictEqual(p.consumed, {});
});

// ── a session ────────────────────────────────────────────────────────
test("prompts are numbered and anchored", () => {
  const page = CH.renderMessages([
    { role: "user", text: "first" },
    { role: "assistant", text: "ok", tools: [] },
    { role: "user", text: "second" }]);
  assert.ok(page.includes('data-p="1"'));
  assert.ok(page.includes('data-p="2"'));
  assert.ok(page.includes('id="m2"'));
});

test("sub-agent turns are marked, not counted as yours", () => {
  const page = CH.renderMessages([
    { role: "user", text: "mine" },
    { role: "user", text: "theirs", side: true }]);
  assert.ok(page.includes("Sub-agent"));
  assert.strictEqual((page.match(/data-p=/g) || []).length, 1);
});

test("thinking is kept and open", () => {
  const page = CH.renderMessages([{ role: "assistant", text: "hi", thinking: "hmm", tools: [] }]);
  assert.ok(page.includes('<details class="think" open>'));
});

test("a turn that is only tool calls is marked notext", () => {
  const page = CH.renderMessages([
    { role: "assistant", text: "", tools: [{ name: "Bash", input: { command: "ls" } }] }]);
  assert.ok(page.includes("notext"));
});

test("harness text gets its own lane", () => {
  const page = CH.renderMessages([{ role: "system", text: "Launching skill: x" }]);
  assert.ok(page.includes('class="m sys"'));
  assert.ok(page.includes("System"));
});

test("prompts are counted without sub-agents", () => {
  assert.strictEqual(CH.countPrompts([
    { role: "user", text: "a" }, { role: "user", text: "b", side: true },
    { role: "assistant", text: "c" }]), 1);
});

// ── resume ───────────────────────────────────────────────────────────
test("a web chat is not resumable", () => {
  assert.strictEqual(CH.resumable({ kind: "web", cwd: "" }), false);
  assert.strictEqual(CH.resumable({ kind: "transcript", cwd: "" }), false);
  assert.strictEqual(CH.resumable({ kind: "transcript", cwd: "/x" }), true);
});

test("the resume command shortens home", () => {
  assert.strictEqual(
    CH.resumeCmd({ id: "abc", cwd: "/Users/x/Sites/app" }, "/Users/x"),
    "cd ~/Sites/app && claude --resume abc");
});

// A stylesheet that does not close a brace does not fail — it quietly applies
// the rest of itself inside whatever block is still open. index.css spent a
// while with its dark-mode media query swallowing every rule after it, so the
// index was unstyled in light mode while the session pages were fine.
["index.css", "session.css"].forEach((name) => {
  const css = fs.readFileSync(path.join(__dirname, "..", "viewer", name), "utf8");
  let depth = 0;
  for (const c of css) { if (c === "{") depth++; else if (c === "}") depth--; }
  test(`${name} closes every block it opens`, () => assert.strictEqual(depth, 0));
});

// ── one name, one function ───────────────────────────────
// Two function declarations of the same name in one scope are not two
// functions: the later one wins, silently, everywhere. It has happened twice
// here — show() wrote the find counter instead of the prompt counter, and a
// render loop called the find bar's step() instead of its own. Declarations
// at the same indentation in one file are the cheap approximation of "one
// scope", and it catches exactly that mistake.
["viewer.js", "page.js", "index.js", "usage.js"].forEach((name) => {
  const src = fs.readFileSync(path.join(__dirname, "..", "viewer", name), "utf8");
  const seen = new Map();
  const clashes = [];
  for (const line of src.split("\n")) {
    const m = /^(\s*)function\s+([A-Za-z_$][\w$]*)\s*\(/.exec(line);
    if (!m) continue;
    const key = m[1].length + ":" + m[2];
    if (seen.has(key)) clashes.push(m[2]);
    else seen.set(key, true);
  }
  test(`${name} declares each function name once per scope`, () =>
    assert.deepStrictEqual(clashes, []));
});

// ── staged rendering ──────────────────────────────────
// A long page puts its first screenful up and adds the rest in idle time, so
// the rows have to be separable and still add up to exactly the old output.
test("rows are one per rendered message, and join to the whole page", () => {
  const msgs = [
    { role: "user", text: "one" },
    { role: "assistant", text: "two" },
    { role: "user", text: "three" }];
  const rows = CH.renderRows(msgs);
  assert.strictEqual(rows.length, 3);
  assert.strictEqual(rows.join(""), CH.renderMessages(msgs));
});

test("a row consumed into its tool call is not a row of its own", () => {
  // TURN is the fixture the pairing tests use: two calls and their results.
  const rows = CH.renderRows(TURN);
  const consumed = Object.keys(CH.pairBareTools(TURN).consumed).length;
  assert.strictEqual(rows.length, TURN.length - consumed);
  assert.ok(rows.join("").includes("3 files changed"));
});

test("prompts stay numbered across the whole conversation", () => {
  const msgs = [];
  for (let i = 0; i < 5; i++) {
    msgs.push({ role: "user", text: "q" + i });
    msgs.push({ role: "assistant", text: "a" + i });
  }
  const rows = CH.renderRows(msgs);
  assert.ok(rows[8].includes(">#5<"), "the fifth prompt is numbered 5 wherever it lands");
});

// ── windowed rendering ────────────────────────────────
// A long page builds a row only when it comes near the window, from the plan
// and the message alone, so a row built on its own has to be exactly the row
// the whole-page render would have produced, numbering and pairing included.
const MIXED = [
  { role: "user", text: "first" },
  { role: "assistant", text: "", tools: ["Read", "Bash"] },
  { role: "tool_result", text: "1 def main():" },
  { role: "tool_result", text: "3 files changed" },
  { role: "tool_result", text: "   " },
  { role: "user", side: true, text: "from a sub-agent" },
  { role: "system", text: "Launching skill: x" },
  { role: "user", text: "second" },
  { role: "assistant", text: "done", thinking: "hmm",
    tools: [{ name: "Bash", id: "t1", input: { command: "ls" } }] },
];

test("a row built on its own is the row the whole page would have", () => {
  const plan = CH.planRows(MIXED), rows = CH.renderRows(MIXED);
  assert.strictEqual(plan.msg.length, rows.length);
  plan.msg.forEach((_, r) => assert.strictEqual(CH.renderRow(MIXED, plan, r), rows[r]));
});

test("the plan skips folded and empty results and numbers only your prompts", () => {
  const plan = CH.planRows(MIXED);
  assert.deepStrictEqual(plan.msg, [0, 1, 5, 6, 7, 8]);
  assert.deepStrictEqual(plan.prompt, [1, 0, 0, 0, 2, 0]);
  assert.ok(CH.renderRow(MIXED, plan, 4).includes(">#2<"));
});

test("long lines count as the lines they wrap to", () => {
  assert.strictEqual(CH.linesIn("", 80), 0);
  assert.strictEqual(CH.linesIn("one", 80), 1);
  assert.strictEqual(CH.linesIn("a\nb\nc", 80), 3);
  assert.strictEqual(CH.linesIn("x".repeat(200), 80), 3);
  assert.strictEqual(CH.linesIn("\n\n", 80), 3);
});

test("a guessed height grows with the text and is never negative", () => {
  const short = [{ role: "assistant", text: "hi" }];
  const long = [{ role: "assistant", text: "word ".repeat(2000) }];
  const h1 = CH.estimateRow(short, CH.planRows(short), 0, 100);
  const h2 = CH.estimateRow(long, CH.planRows(long), 0, 100);
  assert.ok(h1[0] > 0 && h2[0] > h1[0] * 10, `${h1} vs ${h2}`);
  const plan = CH.planRows(MIXED);
  plan.msg.forEach((_, r) => {
    const e = CH.estimateRow(MIXED, plan, r, 100);
    assert.ok(e[0] >= 0 && e[1] >= 0 && e[1] <= e[0], `row ${r}: ${e}`);
  });
});

test("Conversation mode guesses no room for what it hides", () => {
  const msgs = [
    { role: "assistant", text: "", tools: [{ name: "Bash", input: { command: "ls" } }] },
    { role: "tool_result", text: "a.txt\nb.txt" }];
  const plan = CH.planRows(msgs);
  assert.strictEqual(CH.estimateRow(msgs, plan, 0, 100)[1], 0);
  assert.strictEqual(CH.estimateRow(msgs, plan, 1, 100)[1], 0);
  assert.ok(CH.estimateRow(msgs, plan, 1, 100)[0] > 0);
});

// Find counts in rows that are not on the page from their HTML, so its text
// has to come out the way the browser would read it into text nodes.
test("row text is read the way the parser reads it", () => {
  const t = CH.rowText('<div class="t">a &lt;b&gt; &amp; &quot;c&quot; &#x27;d&#x27;</div>');
  assert.strictEqual(t.all, "a <b> & \"c\" 'd'");
  assert.strictEqual(CH.rowText('<pre class="code">\nkept\n</pre>').all, "kept\n");
  assert.strictEqual(CH.rowText("<div>a\r\nb\rc</div>").all, "a\nb\nc");
});

test("a match cannot run across a tag, as it cannot across text nodes", () => {
  const t = CH.rowText('<div class="t">foo<code class="ic">bar</code></div>');
  assert.strictEqual(CH.countIn(t.all, "foo", 99), 1);
  assert.strictEqual(CH.countIn(t.all, "oob", 99), 0);
});

test("text Conversation mode hides is kept out of its search", () => {
  const plan = CH.planRows(MIXED);
  const asst = CH.rowText(CH.renderRow(MIXED, plan, 5));
  assert.ok(asst.all.includes("ls") && asst.all.includes("hmm") && asst.all.includes("done"));
  assert.ok(!asst.talk.includes("hmm"), "thinking is hidden");
  assert.ok(!asst.talk.includes("ls"), "the tool call is hidden");
  assert.ok(asst.talk.includes("done"));
  const callOnly = CH.rowText(CH.renderRow(MIXED, plan, 1));
  assert.ok(callOnly.all.includes("3 files changed"));
  assert.strictEqual(callOnly.talk, "", "a turn of only tool calls is hidden whole");
  const prompt = CH.rowText(CH.renderRow(MIXED, plan, 0));
  assert.strictEqual(prompt.talk, prompt.all);
});

test("⌘F is the page's own find only on a long page, and only the first time", () => {
  const k = (o) => Object.assign({ key: "f", metaKey: false, ctrlKey: false, altKey: false, shiftKey: false }, o);
  assert.strictEqual(CH.ownsFindKey(k({ metaKey: true }), true, true, false), true);
  assert.strictEqual(CH.ownsFindKey(k({ ctrlKey: true }), false, true, false), true);
  assert.strictEqual(CH.ownsFindKey(k({ metaKey: true, key: "F" }), true, true, false), true);
  // a short page has every row built: the browser's find sees it all
  assert.strictEqual(CH.ownsFindKey(k({ metaKey: true }), true, false, false), false);
  // pressed again in the field, the browser's own find opens
  assert.strictEqual(CH.ownsFindKey(k({ metaKey: true }), true, true, true), false);
  // other platforms' modifier, other keys, and added modifiers are not it
  assert.strictEqual(CH.ownsFindKey(k({ ctrlKey: true }), true, true, false), false);
  assert.strictEqual(CH.ownsFindKey(k({ metaKey: true }), false, true, false), false);
  assert.strictEqual(CH.ownsFindKey(k({ metaKey: true, key: "g" }), true, true, false), false);
  assert.strictEqual(CH.ownsFindKey(k({ metaKey: true, shiftKey: true }), true, true, false), false);
  assert.strictEqual(CH.ownsFindKey(k({ metaKey: true, altKey: true }), true, true, false), false);
  assert.strictEqual(CH.ownsFindKey(k({ key: "f" }), true, true, false), false);
});

test("matches are counted left to right without overlapping, up to a cap", () => {
  assert.strictEqual(CH.countIn("aaaa", "aa", 99), 2);
  assert.strictEqual(CH.countIn("abcabcabc", "abc", 2), 2);
  assert.strictEqual(CH.countIn("abc", "", 99), 0);
});

// The session page's ◐ cycles auto, light and dark. A colour declared outside
// the three-state palette follows the system and not the button, which is how
// find's highlight went light-on-light in forced dark.
test("session.css declares the same colours in all three theme states", () => {
  const css = fs.readFileSync(path.join(__dirname, "..", "viewer", "session.css"), "utf8");
  const vars = (sel) => {
    const at = css.indexOf(sel + "{");
    assert.ok(at > -1, "missing " + sel);
    const body = css.slice(at + sel.length + 1, css.indexOf("}", at));
    return (body.match(/--[\w-]+(?=:)/g) || []).filter(v => v !== "--col").sort();
  };
  const light = vars(":root"), auto = vars(":root:not([data-theme=light])"),
        dark = vars(":root[data-theme=dark]");
  assert.ok(light.includes("--hit") && light.includes("--cur"));
  assert.deepStrictEqual(auto, light);
  assert.deepStrictEqual(dark, light);
  assert.ok(!/prefers-color-scheme:dark\)\{:root\{/.test(css), "an unguarded dark palette ignores the button");
});

// The » button once read the prompt count before the rest of the page was
// there, and went to prompt four of two thousand.
test("the last-prompt button asks for the last, not for a count it read early", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "viewer", "page.js"), "utf8");
  assert.ok(/getElementById\("last"\)\.onclick = function \(\) \{ jump\(Infinity\); \}/.test(src));
  assert.ok(!/addChunk|flush\(/.test(src), "the staged render is gone, not layered under");
});

// The counter is worked out from where the prompts are; at the end of a page
// the last ones never reach the header, and » once read "1 / 2" there.
test("the prompt counter names the prompt you are under", () => {
  const tops = [-900, -200, 300, 700];
  const top = (k) => tops[k];
  assert.strictEqual(CH.promptUnder(4, top, 120, 0, null), 1);
  assert.strictEqual(CH.promptUnder(4, top, 400, 0, null), 2);
  assert.strictEqual(CH.promptUnder(4, (k) => [500, 900][k], 120, 0, null), 0, "above the first");
  assert.strictEqual(CH.promptUnder(0, top, 120, 0, [100, 900]), 0, "no prompts at all");
});

test("at the end of the page the counter names a prompt in view", () => {
  const top = (k) => [-900, -200, 300, 700][k];
  assert.strictEqual(CH.promptUnder(4, top, 120, 0, [100, 900]), 3, "scrolled to the end: the last showing");
  assert.strictEqual(CH.promptUnder(4, top, 120, 2, [100, 900]), 2, "the one jumped to, while it is showing");
  assert.strictEqual(CH.promptUnder(4, (k) => [-900, -200, 300, 1700][k], 120, 0, [100, 900]), 2,
    "not one still below the window");
});

// A long page keeps its own place as rows are built; a short one has nothing
// built late and should keep the browser's anchoring, which also holds your
// place when the window is resized.
test("only a windowed page turns the browser's scroll anchoring off", () => {
  const css = fs.readFileSync(path.join(__dirname, "..", "viewer", "session.css"), "utf8");
  const src = fs.readFileSync(path.join(__dirname, "..", "viewer", "page.js"), "utf8");
  assert.ok(/html\.win\{overflow-anchor:none\}/.test(css));
  assert.ok(!/(^|\})\s*html\{overflow-anchor/m.test(css), "not on every page");
  assert.ok(/if \(windowed\) document\.documentElement\.classList\.add\("win"\)/.test(src));
  assert.ok(/if \(windowed\) window\.addEventListener\("resize"/.test(src), "and holds its place on resize itself");
});

// Rows are flex items, whose margins do not fold into the gap below; in
// Conversation mode a reply's last visible part is often followed only by
// hidden tool calls, and its margin made that gap 8px taller than before.
test("Conversation mode zeroes the margin of a reply's last visible part", () => {
  const css = fs.readFileSync(path.join(__dirname, "..", "viewer", "session.css"), "utf8");
  assert.ok(css.includes("body.talk .m>:not(.tool,.think,.res):not(:has(~ :not(.tool,.think,.res))){margin-bottom:0}"));
});

// The index links to tool output too; opened in Conversation mode, which
// hides it, such a link landed at the top of the page with nothing marked.
test("a link to a row Conversation mode hides shows everything first", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "viewer", "page.js"), "utf8");
  const body = src.slice(src.indexOf("function toHash"), src.indexOf("function toHash") + 900);
  assert.ok(/if \(!el\.getClientRects\(\)\.length && talking\(\)\) mode\("all", true\);/.test(body));
  assert.ok(body.indexOf('mode("all"') < body.indexOf("scrollToEl("), "before it scrolls");
});

// Placeholders print as blank paper, so a long page builds every row first.
test("a windowed page builds every row before it prints", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "viewer", "page.js"), "utf8");
  assert.ok(/if \(windowed\) window\.addEventListener\("beforeprint"[\s\S]{0,120}for \(var b = 0; b < NB; b\+\+\) fillBlock\(b\)/.test(src));
});

// ── the usage week ───────────────────────────────────
// Every date here is built and read in local time, so these hold in any
// timezone the tests happen to run in.
const TUE9 = CH.parseReset("tue 09:00");

test("a reset spec is read, and a bad one falls back to calendar weeks", () => {
  assert.strictEqual(TUE9.dow, 2);
  assert.strictEqual(TUE9.hour, 9);
  assert.strictEqual(CH.parseReset("Tuesday 9").spec, "tue 09:00");
  assert.strictEqual(CH.parseReset("").spec, "mon 00:00");
  assert.strictEqual(CH.parseReset("nonsense").dow, 1);
});

// 2026-10-20 is a Tuesday; 10-21 a Wednesday.
function wk(y, m, d, h, min) {
  const s = CH.weekStart(new Date(y, m - 1, d, h, min || 0), TUE9);
  return `${s.getFullYear()}-${String(s.getMonth() + 1).padStart(2, "0")}-` +
         `${String(s.getDate()).padStart(2, "0")} ${String(s.getHours()).padStart(2, "0")}:` +
         `${String(s.getMinutes()).padStart(2, "0")}`;
}

test("midweek belongs to the Tuesday just gone", () =>
  assert.strictEqual(wk(2026, 10, 21, 14), "2026-10-20 09:00"));

test("Tuesday before the reset hour still belongs to the week before", () =>
  assert.strictEqual(wk(2026, 10, 20, 8, 59), "2026-10-13 09:00"));

test("the reset hour itself starts the new week", () =>
  assert.strictEqual(wk(2026, 10, 20, 9, 0), "2026-10-20 09:00"));

test("Monday night is the end of the old week, not the start of a new one", () =>
  assert.strictEqual(wk(2026, 10, 19, 23, 30), "2026-10-13 09:00"));

test("the reset hour survives a daylight-saving change", () => {
  // Europe moved its clocks on 2026-10-25, between these two Tuesdays.
  assert.strictEqual(wk(2026, 10, 27, 10), "2026-10-27 09:00");
  assert.strictEqual(wk(2026, 10, 26, 10), "2026-10-20 09:00");
});

test("a calendar-week spec still gives Mondays at midnight", () => {
  const s = CH.weekStart(new Date(2026, 9, 21, 14), CH.parseReset("mon 00:00"));
  assert.strictEqual(s.getDate(), 19);
  assert.strictEqual(s.getHours(), 0);
});

// ── money ────────────────────────────────────────────────────────────
// Micro-dollars in, one way of writing them out on all three pages.
test("an unknown cost is a dash, never $0.00", () => {
  [undefined, null, "", "x"].forEach((v) => assert.strictEqual(CH.fmtMoney(v), "—"));
});

test("cents up to a thousand dollars", () => {
  assert.strictEqual(CH.fmtMoney(0), "$0.00");
  assert.strictEqual(CH.fmtMoney(50000), "$0.05");
  assert.strictEqual(CH.fmtMoney(1234567), "$1.23");
  assert.strictEqual(CH.fmtMoney(498942735), "$498.94");
});

test("less than a cent says so rather than rounding to nothing", () => {
  assert.strictEqual(CH.fmtMoney(990), "<$0.01");
  assert.strictEqual(CH.fmtMoney(5000), "$0.01");
});

test("whole dollars, grouped, from a thousand", () => {
  assert.strictEqual(CH.fmtMoney(999994999), "$999.99");
  assert.strictEqual(CH.fmtMoney(999995000), "$1,000");
  assert.strictEqual(CH.fmtMoney(1327735018), "$1,328");
  assert.strictEqual(CH.fmtMoney(1234567890123), "$1,234,568");
});

test("short drops the cents from ten dollars, for a narrow column", () => {
  assert.strictEqual(CH.fmtMoney(9994999, true), "$9.99");
  assert.strictEqual(CH.fmtMoney(9995000, true), "$10");
  assert.strictEqual(CH.fmtMoney(498942735, true), "$499");
});

// ── report ───────────────────────────────────────────────────────────
if (failed.length) {
  failed.forEach(([n, m]) => console.log(`  FAIL  ${n}\n        ${m}`));
  console.log(`\n  ${ran - failed.length}/${ran} passed, ${failed.length} failed`);
  process.exit(1);
}
console.log(`  ${ran}/${ran} viewer tests passed`);
