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

// ── report ───────────────────────────────────────────────────────────
if (failed.length) {
  failed.forEach(([n, m]) => console.log(`  FAIL  ${n}\n        ${m}`));
  console.log(`\n  ${ran - failed.length}/${ran} passed, ${failed.length} failed`);
  process.exit(1);
}
console.log(`  ${ran}/${ran} viewer tests passed`);
