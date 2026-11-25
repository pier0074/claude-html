// The diff acceptance criterion from the spec: applying the diff to the old
// text must reproduce the new text exactly, on every edit ever made here.
const CH = require("../viewer/viewer.js");
const edits = require("./fixtures/corpus/edits.json");

let pass = 0, fail = [];
for (const [i, e] of edits.entries()) {
  const ops = CH.diffOps(e.old.split("\n"), e.new.split("\n"));
  if (CH.applyOps(ops) === e.new) pass++;
  else fail.push(i);
}
console.log(`  reconstruction: ${pass}/${edits.length} edits reproduce new_string exactly`);
if (fail.length) {
  console.log(`  FAILING indices: ${fail.slice(0, 5).join(", ")}`);
  process.exit(1);
}

// Deletions must also reconstruct the old text, or the diff is lying in the
// other direction.
let back = 0;
for (const e of edits) {
  const ops = CH.diffOps(e.old.split("\n"), e.new.split("\n"));
  const old = ops.filter(o => o.op !== "+").map(o => o.text).join("\n");
  if (old === e.old) back++;
}
console.log(`  reverse:        ${back}/${edits.length} reproduce old_string exactly`);
if (back !== edits.length) process.exit(1);

// One Edit that rewrites a whole file: the table was every old line by
// every new one, which froze the page for seconds and took most of a
// gigabyte. The lines both share at the ends are not in it, and it never
// grows past its bound; the diff is still true both ways. Run in a child
// with a time limit, so a table that does grow cannot stall the suite.
const cp = require("child_process");
const big = cp.spawnSync(process.execPath, ["-e", `
  const CH = require(${JSON.stringify(require("path").join(__dirname, "../viewer/viewer.js"))});
  const n = 20000, a = [], b = [];
  for (let i = 0; i < n; i++) { a.push("old line " + i); b.push(i % 7 ? "new line " + i : "old line " + i); }
  const t0 = Date.now(), whole = a.concat(["the same end"]);
  const ops = CH.diffOps(["the same start"].concat(whole), ["the same start"].concat(b, ["the same end"]));
  const ok = CH.applyOps(ops) === ["the same start"].concat(b, ["the same end"]).join("\\n") &&
    ops.filter(o => o.op !== "+").map(o => o.text).join("\\n") === ["the same start"].concat(whole).join("\\n");
  const small = CH.diffOps(["x"].concat(a.slice(0, 50), ["y"]), ["x"].concat(b.slice(0, 50), ["y"]));
  console.log(JSON.stringify({ ok, cells: ops.cells, smallCells: small.cells, ends: ops[0].op + ops[ops.length - 1].op,
                               html: CH.renderDiff(a.join("\\n"), b.join("\\n"), "f").length > 0 }));`],
  { encoding: "utf8", timeout: 20000 });
let r = null;
try { r = JSON.parse(big.stdout); } catch (e) { r = null; }
const bounded = !!r && r.ok && r.html && typeof r.cells === "number" && r.cells <= 2000000 &&
  r.ends === "  " && r.smallCells > 0 && r.smallCells <= 51 * 51;
console.log(`  a whole-file edit: ${bounded ? "true both ways, its table bounded" : "FAIL " + (r ? JSON.stringify(r) : "did not finish: " + (big.signal || big.status))}`);
if (!bounded) process.exit(1);
