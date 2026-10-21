// The diff acceptance criterion from the spec: applying the diff to the old
// text must reproduce the new text exactly, on every edit ever made here.
const CH = require("../viewer/viewer.js");
const edits = require("./corpus/edits.json");

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
