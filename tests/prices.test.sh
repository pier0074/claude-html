#!/bin/bash
# The price file and the cost calculated from it. What must never be wrong:
# a reply is priced by the line in force on its UTC day, a dated model id
# finds its line and an unknown one is not priced (never guessed); the cache
# write's 5-minute and 1-hour parts are kept apart, the same under both
# engines and from an archive as from the transcript, and an old archive
# that never had them says so; the calculated cost sits beside what Claude
# Code recorded and is never added to it; and the page's toggle prices every
# hour at the price of the time or at today's.
#
#   bash tests/prices.test.sh
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/lib.sh"
T="$(cd "$(tmpdir chprices)" && pwd)"
trap 'rm -rf "$T"' EXIT

# A JavaScript expression over d, the JSON on stdin, or over the JSON a page
# embeds in the element with that id.
js() {
  node -e '
    var fs = require("fs"), a = process.argv;
    var d = a[2] ? JSON.parse(new RegExp("id=\"" + a[3] + "\">([\\s\\S]*?)</script>").exec(fs.readFileSync(a[2], "utf8"))[1])
                 : JSON.parse(fs.readFileSync(0, "utf8"));
    var v = eval(a[1]);
    console.log(typeof v === "string" ? v : JSON.stringify(v));' "$1" "${2:-}" "${3:-}"
}

# ── a price file of its own ─────────────────────────────────────────
# Made-up models and figures, so the real file can change without this
# suite noticing. alpha-1 halves on 2026-10-07; alpha-1/fast is its fast
# mode; beta-2 has prices with three decimals.
PF="$T/prices.tsv"
{
  printf '# a comment, then the heading\n'
  printf 'model\tfrom\tto\tinput\toutput\tcache_read\tcache_write_5m\tcache_write_1h\tsource\tchecked\n'
  printf 'claude-alpha-1\t2026-01-01\t2026-10-06\t2\t10\t0.20\t2.50\t4\thttps://example.invalid/old\t2026-11-01\n'
  printf 'claude-alpha-1\t2026-10-07\t\t1\t5\t0.10\t1.25\t2\thttps://example.invalid/new\t2026-11-02\n'
  printf 'claude-alpha-1/fast\t2026-01-01\t\t4\t20\t0.40\t5\t8\thttps://example.invalid/fast\t2026-11-02\n'
  printf 'claude-beta-2\t2026-01-01\t\t0.125\t0.5\t0.01\t0.125\t0.2\thttps://example.invalid/beta\t2026-11-02\n'
} > "$PF"
BAD="$T/bad.tsv"
{
  cat "$PF"
  printf 'claude-alpha-1\t2026-10-01\t\t1\t5\t0.10\t1.25\t2\tx\t2026-11-02\n'      # overlaps
  printf 'claude-gamma\t2026-10-01\t2026-09-01\t1\t5\t0.10\t1.25\t2\tx\t2026-11-02\n'  # ends before it starts
  printf 'claude-delta\t2026-10-01\t\tfree\t5\t0.10\t1.25\t2\tx\t2026-11-02\n'        # not a price
  printf 'claude-eps\t2026-10-01\t\t1\t5\n'                                          # too short
} > "$BAD"

# ── prices.js on its own ────────────────────────────────────────────
cat "$HERE/build/prices.js" > "$T/unit.js"
cat >> "$T/unit.js" <<'JS'
function run(argv) {
  var text = typeof $ !== "undefined"
    ? ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null))
    : require("fs").readFileSync(argv[0], "utf8");
  var bad = typeof $ !== "undefined"
    ? ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(argv[1], $.NSUTF8StringEncoding, null))
    : require("fs").readFileSync(argv[1], "utf8");
  var P = claudeHtmlPrices(text), B = claudeHtmlPrices(bad), o = {};
  function from(l) { return l ? l.model + "@" + l.from : null; }
  o.lines = P.lines.length; o.errors = P.errors; o.checked = P.checked;
  o.badErrors = B.errors.length; o.badLines = B.lines.length;
  o.badWhy = B.errors.map(function (e) { return e.replace(/^line \d+: /, "").split(" ")[0]; }).join(",");
  o.milli = [P.current("claude-beta-2").input, P.current("claude-beta-2").cache_read];
  o.exact = P.idOf("claude-alpha-1");
  o.dated = P.idOf("claude-alpha-1-20261001");
  o.datedFast = P.idOf("claude-alpha-1-20261001/fast");
  o.unknown = [P.idOf("claude-alpha"), P.idOf("claude-alphabet-1"), P.idOf("claude-gone"), P.idOf("alpha-1")];
  o.lastOld = from(P.lineAt("claude-alpha-1", "2026-10-06T23"));
  o.firstNew = from(P.lineAt("claude-alpha-1", "2026-10-07T00"));
  o.firstDay = from(P.lineAt("claude-alpha-1", "2026-01-01T00"));
  o.before = from(P.lineAt("claude-alpha-1", "2025-12-31T23"));
  o.beforeToday = from(P.lineAt("claude-alpha-1", "2025-12-31T23", true));
  o.oldToday = from(P.lineAt("claude-alpha-1", "2026-03-01T10", true));
  // 1 M of each, 3 M written: 2 M for 5 minutes (half a million of it of
  // unknown duration, priced the same), 1 M for an hour.
  var cell = [1e6, 1e6, 1e6, 3e6, 1, 1e6, 5e5];
  o.costNew = P.cellCost("claude-alpha-1", "2026-10-07T00", cell);
  o.costOld = P.cellCost("claude-alpha-1", "2026-10-06T23", cell);
  o.costOldToday = P.cellCost("claude-alpha-1", "2026-10-06T23", cell, true);
  o.costUnknown = P.cellCost("claude-gone", "2026-10-07T00", cell);
  o.costThree = P.cellCost("claude-beta-2", "2026-10-07T00", [3, 0, 0, 0, 1, 0, 0]);
  var usage = { "2026-10-06T23": { "claude-alpha-1": cell.concat([7000000]), "claude-gone": [10, 0, 0, 0, 1, 0, 0] },
                "2026-10-07T00": { "claude-alpha-1": cell } };
  o.total = P.total(usage);
  o.week = P.total(usage, { since: Date.UTC(2026, 9, 7), until: Date.UTC(2026, 9, 14) });
  o.hourKey = P.hourKey(Date.UTC(2026, 9, 7, 5, 30));
  return JSON.stringify(o);
}
if (typeof $ === "undefined") console.log(run(process.argv.slice(2)));
JS
U="$(node "$T/unit.js" "$PF" "$BAD")"
u() { printf '%s' "$U" | js "$1"; }
check "the price file is read: four lines, no errors" "$(u '[d.lines, d.errors.length]')" "[4,0]"
check "  the file's checked date is its newest" "$(u d.checked)" "2026-11-02"
check "  a bad line is skipped and said, each for its reason" \
  "$(u '[d.badLines, d.badErrors, d.badWhy]')" '[4,4,"claude-alpha-1,to,input,fewer"]'
check "  prices are read from the digits: 0.125 and 0.01 exactly" "$(u d.milli)" "[125,10]"
check "a model matches its own line" "$(u d.exact)" "claude-alpha-1"
check "  a dated id matches the line without the date" "$(u d.dated)" "claude-alpha-1"
check "  and keeps a suffix of its own" "$(u d.datedFast)" "claude-alpha-1/fast"
check "  an unknown or merely similar one is not priced" "$(u d.unknown)" "[null,null,null,null]"
check "the old price holds to the last hour of its last day (UTC)" "$(u d.lastOld)" "claude-alpha-1@2026-01-01"
check "  the new one from the first hour of its first" "$(u d.firstNew)" "claude-alpha-1@2026-10-07"
check "  a first day counts whole" "$(u d.firstDay)" "claude-alpha-1@2026-01-01"
check "  before the first line, nothing is priced" "$(u d.before)" "null"
check "  but at today's prices everything is" "$(u '[d.beforeToday, d.oldToday]')" \
  '["claude-alpha-1@2026-10-07","claude-alpha-1@2026-10-07"]'
check "a cell's cost: 5-minute and 1-hour writes at their own prices, unknown as 5-minute" \
  "$(u '[d.costNew, d.costOld, d.costOldToday]')" "[10600000,21200000,10600000]"
check "  no line, no cost — not zero" "$(u d.costUnknown)" "null"
check "  three decimals stay exact" "$(u d.costThree)" "0"
check "a total keeps recorded and calculated apart, and counts what it could not price" \
  "$(u '[d.total.calc, d.total.recorded, d.total.unpriced, d.total.unpricedBy, d.total.unsplit]')" \
  '[31800000,7000000,10,{"claude-gone":10},1000000]'
check "  over a week, only that week's hours" "$(u '[d.week.calc, d.week.recorded]')" "[10600000,null]"
check "  an hour key is the build's" "$(u d.hourKey)" "2026-10-07T05"
if [ "$HAVE_OSASCRIPT" = true ]; then
  check "  osascript works it out byte for byte as node does" \
    "$(osascript -l JavaScript "$T/unit.js" "$PF" "$BAD")" "$U"
fi

# ── the real price file ─────────────────────────────────────────────
R="$(node -e '
  var fs = require("fs"), here = process.argv[1];
  var P = new Function(fs.readFileSync(here + "/build/prices.js", "utf8") + "\nreturn claudeHtmlPrices;")()(
    fs.readFileSync(here + "/build/prices.tsv", "utf8"));
  var o = { errors: P.errors, n: P.lines.length };
  o.unsourced = P.lines.filter(function (l) {
    return !/^https:\/\/(www\.anthropic\.com|platform\.claude\.com|docs\.claude\.com|claude\.com)\//.test(l.source) || !l.checked;
  }).map(function (l) { return l.id; });
  o.open = P.models().filter(function (m) { return !P.history(m).some(function (l) { return !l.to; }); });
  // the models the other suites use, at the hours they use them
  o.fixtures = ["claude-opus-5", "claude-haiku-4-5", "claude-haiku-4-5-20251001", "claude-sonnet-4"]
    .map(function (m) { return !!P.lineAt(m, "2026-10-06T10"); });
  o.gone = P.idOf("claude-gone");
  console.log(JSON.stringify(o));' "$HERE")"
check "prices.tsv reads without an error" "$(printf '%s' "$R" | js 'd.errors.length + " " + (d.n > 20)')" "0 true"
check "  every line names an official source and a checked date" "$(printf '%s' "$R" | js d.unsourced)" "[]"
check "  every model has a current line" "$(printf '%s' "$R" | js d.open)" "[]"
check "  the models the suites use are priced; claude-gone is not" \
  "$(printf '%s' "$R" | js '[d.fixtures, d.gone]')" "[[true,true,true,true],null]"

# ── the build ───────────────────────────────────────────────────────
ROOT="$T/root"; APP="$ROOT/app"; H="$T/home"
D="$(printf '%s' "$APP" | tr '/' '-')"; PD="$H/.claude/projects/$D"
S1=11111111-0000-0000-0000-000000000001     # no cost recorded: split, unsplit, fast, unknown
S2=11111111-0000-0000-0000-000000000002     # cost recorded
mkdir -p "$PD" "$APP"
node -e '
  var fs = require("fs"), a = process.argv, app = a[1];
  function rec(o) { return JSON.stringify(Object.assign({ cwd: app }, o)) + "\n"; }
  function reply(sid, at, id, model, usage) {
    return rec({ type: "assistant", sessionId: sid, timestamp: at, message: { id: id, role: "assistant", model: model,
      content: [{ type: "text", text: "reply " + id }], usage: usage } });
  }
  function ask(sid, at) { return rec({ type: "user", sessionId: sid, timestamp: at, message: { role: "user", content: "go" } }); }
  var u = { input_tokens: 1000, output_tokens: 2000, cache_read_input_tokens: 10000, cache_creation_input_tokens: 3000 };
  var s = ask(a[2], "2026-10-06T10:00:00Z") +
    reply(a[2], "2026-10-06T10:00:01Z", "m1", "claude-alpha-1",
          Object.assign({ cache_creation: { ephemeral_5m_input_tokens: 1000, ephemeral_1h_input_tokens: 2000 } }, u)) +
    reply(a[2], "2026-10-07T10:00:01Z", "m2", "claude-alpha-1", u) +
    reply(a[2], "2026-10-07T11:00:01Z", "m3", "claude-alpha-1",
          { input_tokens: 100, output_tokens: 100, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, speed: "fast" }) +
    reply(a[2], "2026-10-07T12:00:01Z", "m4", "claude-gone",
          { input_tokens: 50, output_tokens: 50, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 });
  fs.writeFileSync(a[4] + "/" + a[2] + ".jsonl", s);
  var s2 = ask(a[3], "2026-10-08T09:00:00Z") +
    reply(a[3], "2026-10-08T09:00:01Z", "n1", "claude-alpha-1",
          { input_tokens: 4000, output_tokens: 4000, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }) +
    rec({ type: "cost-state", sessionId: a[3], startTime: Date.UTC(2026, 9, 8, 9), totalCostUSD: 0.5,
          modelUsage: { "claude-alpha-1": { costUSD: 0.5 } } });
  fs.writeFileSync(a[4] + "/" + a[3] + ".jsonl", s2);' "$APP" "$S1" "$S2" "$PD"

build() {   # out [engine]
  local o="$1"
  if [ "${2:-}" = node ]; then
    HOME="$H" CLAUDE_HTML_PRICES="$PF" node "$HERE/build/convert.js" \
      "{\"root\":\"$ROOT\",\"out\":\"$o\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}"
  else
    HOME="$H" CLAUDE_HTML_PRICES="$PF" run_js "$HERE/build/convert.js" \
      "{\"root\":\"$ROOT\",\"out\":\"$o\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}"
  fi
}
OUT="$T/out"
build "$OUT" >/dev/null
cell() { js "JSON.stringify(d.byProject.app[\"$1\"][\"$2\"])" "$OUT/usage.html" usage-data; }
check "a reply's split write is kept: 1,000 for 5 minutes, 2,000 for an hour" \
  "$(cell 2026-10-06T10 claude-alpha-1)" "[1000,2000,10000,3000,1,2000,0]"
check "  one that does not say is all of unknown duration" \
  "$(cell 2026-10-07T10 claude-alpha-1)" "[1000,2000,10000,3000,1,0,3000]"
check "  a reply in fast mode is filed under its own price" \
  "$(cell 2026-10-07T11 claude-alpha-1/fast)" "[100,100,0,0,1,0,0]"
check "  the recorded cost is the eighth figure, where there is one" \
  "$(cell 2026-10-08T09 claude-alpha-1)" "[4000,4000,0,0,1,0,0,500000]"
ix() { js "JSON.stringify(d.sessions.filter(function(s){return s.id===\"$1\"}).map(function(s){return $2})[0])" "$OUT/index.html" index-data; }
# 34,500 + 15,750 + 2,400 micro-dollars; claude-gone is not priced, so a floor.
check "a session with nothing recorded gets a calculated cost, a floor when a model has no line" \
  "$(ix $S1 '[s.tok.length, s.calc, !!s.calcPart]')" "[5,52650,true]"
check "  one with a recorded cost keeps it, and the calculated one beside it, apart" \
  "$(ix $S2 '[s.tok[5], s.calc, !!s.calcPart]')" "[500000,24000,false]"
check "  the session page carries it too" \
  "$(js 'JSON.stringify([d.meta.calc, !!d.meta.calcPart, d.meta.tok.length])' "$OUT/sessions/$S1.html" session-data)" "[52650,true,5]"
check "the dashboard carries the price file as it is" \
  "$(js 'd.prices === require("fs").readFileSync(process.argv[4] || "'"$PF"'", "utf8")' "$OUT/usage.html" usage-data)" "true"
check "  and which line priced how many sessions" \
  "$(js 'JSON.stringify(d.priceUse)' "$OUT/usage.html" usage-data)" \
  '{"app":{"claude-alpha-1@2026-01-01":1,"claude-alpha-1@2026-10-07":2,"claude-alpha-1/fast@2026-01-01":1}}'
if [ "$HAVE_OSASCRIPT" = true ]; then
  build "$T/node" node >/dev/null
  same=same
  for f in usage.html index.html .manifest.json "sessions/$S1.html" "sessions/$S2.html"; do
    # the index says when it was built, which no two builds share
    cmp -s <(sed 's/"built":[0-9]*//' "$OUT/$f") <(sed 's/"built":[0-9]*//' "$T/node/$f") || same="differ: $f"
  done
  check "osascript and node build the same bytes, split and prices included" "$same" same
fi

# A new price is a new page: the calculated cost on it would be stale.
sed 's/^claude-alpha-1\t2026-10-07\t\t1\t5/claude-alpha-1\t2026-10-07\t\t1\t6/' "$PF" > "$T/p2.tsv"
B="$(HOME="$H" CLAUDE_HTML_PRICES="$T/p2.tsv" run_js "$HERE/build/convert.js" \
  "{\"root\":\"$ROOT\",\"out\":\"$OUT\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}")"
check "a changed price file rebuilds the pages it prices" \
  "$(printf '%s' "$B" | js d.built) $(ix $S1 's.calc')" "2 54650"
build "$OUT" >/dev/null

# ── archives ────────────────────────────────────────────────────────
sed -n "/^cat > \"\$ARCHIVER\" <<'ARCHIVEREOF'\$/,/^ARCHIVEREOF\$/p" "$HERE/save-conversation.sh" |
  sed '1d;$d' > "$T/archive.js"
cat "$HERE/build/redact.js" "$HERE/build/parse.js" >> "$T/archive.js"
AF="$(. "$HERE/lib/version.sh"; printf '%s' "$CH_ARCHIVE_FORMAT")"
CONV="$APP/.claude/.claude-conversations"; mkdir -p "$CONV"
for s in $S1 $S2; do
  run_js "$T/archive.js" "$PD/$s.jsonl" "$s" "$APP" "$(size_of "$PD/$s.jsonl")" "" "" "" "" "$AF" > "$CONV/$s.json"
done
check "the archive keeps the split, in format $AF" \
  "$(js 'JSON.stringify([d.format, d.usage["2026-10-06T10"]["claude-alpha-1"], d.replies[0].slice(3)])' < "$CONV/$S1.json")" \
  "[$AF,[1000,2000,10000,3000,1,2000,0],[1000,2000,10000,3000,2000,0]]"
if [ "$HAVE_OSASCRIPT" = true ]; then
  check "  both engines write it byte for byte the same" \
    "$(cmp -s <(osascript -l JavaScript "$T/archive.js" "$PD/$S1.jsonl" "$S1" "$APP" 9 "" "" "" "" "$AF") \
               <(node "$T/archive.js" "$PD/$S1.jsonl" "$S1" "$APP" 9 "" "" "" "" "$AF") && echo same || echo differ)" same
fi
# Compared by content: a build from archives may list projects, hours and
# models in another order than one from transcripts, with the same cells.
CANON='(function c(v){return Array.isArray(v)?"["+v.map(c).join(",")+"]":v&&typeof v==="object"?"{"+Object.keys(v).sort().map(function(k){return JSON.stringify(k)+":"+c(v[k])}).join(",")+"}":JSON.stringify(v)})(d.byProject)'
BEFORE="$(js "$CANON" "$OUT/usage.html" usage-data)"
IXBEFORE="$(ix $S1 '[s.tok, s.calc, s.calcPart]') $(ix $S2 '[s.tok, s.calc, s.calcPart]')"
mkdir -p "$T/gone"; mv "$PD/$S1.jsonl" "$PD/$S2.jsonl" "$T/gone/"
build "$OUT" >/dev/null
check "with the transcripts gone, the archives give the same cells" \
  "$(js "$CANON" "$OUT/usage.html" usage-data)" "$BEFORE"
check "  and the same tokens, recorded and calculated costs" \
  "$(ix $S1 '[s.tok, s.calc, s.calcPart]') $(ix $S2 '[s.tok, s.calc, s.calcPart]')" "$IXBEFORE"

# An archive from before the split: format 5, cost the sixth figure, reply
# rows without the parts. Its whole write is of unknown duration.
node -e 'var fs=require("fs"),p=process.argv[1],a=JSON.parse(fs.readFileSync(p,"utf8")); a.format=5;
  Object.keys(a.usage).forEach(function (h) { Object.keys(a.usage[h]).forEach(function (m) {
    var c = a.usage[h][m]; a.usage[h][m] = c.slice(0, 5).concat(c.length > 7 ? [c[7]] : []); }); });
  a.replies = a.replies.map(function (r) { return r.slice(0, 7); });
  fs.writeFileSync(p, JSON.stringify(a))' "$CONV/$S1.json"
node -e 'var fs=require("fs"),p=process.argv[1],a=JSON.parse(fs.readFileSync(p,"utf8")); a.format=5;
  Object.keys(a.usage).forEach(function (h) { Object.keys(a.usage[h]).forEach(function (m) {
    var c = a.usage[h][m]; a.usage[h][m] = c.slice(0, 5).concat(c.length > 7 ? [c[7]] : []); }); });
  a.replies = a.replies.map(function (r) { return r.slice(0, 7); });
  fs.writeFileSync(p, JSON.stringify(a))' "$CONV/$S2.json"
build "$OUT" >/dev/null
check "an old archive's write is all of unknown duration (split unknown)" \
  "$(cell 2026-10-06T10 claude-alpha-1)" "[1000,2000,10000,3000,1,0,3000]"
check "  and its recorded cost is still the recorded cost" \
  "$(cell 2026-10-08T09 claude-alpha-1)" "[4000,4000,0,0,1,0,0,500000]"
# the 2,000 an hour is priced as 5-minute writes now: 34,500 - 2,000 × (4 - 2.50)
check "  priced as 5-minute writes" "$(ix $S1 's.calc')" "49650"
mv "$T/gone/"* "$PD/"
build "$OUT" >/dev/null

# ── the page ────────────────────────────────────────────────────────
# usage.js with prices.js, as the page loads them, against a stand-in for
# the few DOM calls it makes.
cat > "$T/page.js" <<'EOF'
var fs = require("fs"), vm = require("vm");
var here = process.argv[2], page = process.argv[3], stored = process.argv[4];
var html = fs.readFileSync(page, "utf8");
var data = /id="usage-data">([\s\S]*?)<\/script>/.exec(html)[1];
if (process.argv[5]) { var dd = JSON.parse(data); eval(process.argv[5]); data = JSON.stringify(dd); }
var els = {}, onClick = null, store = stored ? JSON.parse(stored) : {};
function el(id) {
  return els[id] = els[id] || { id: id, innerHTML: "", textContent: id === "usage-data" ? data : "",
    hidden: id === "prices", listeners: {}, cls: {}, clientWidth: 1000,
    classList: { toggle: function (c, on) { this.o.cls[c] = !!on; }, add: function () {}, remove: function () {} },
    addEventListener: function (t, f) { this.listeners[t] = f; }, setAttribute: function () {} };
}
var ctx = {
  document: { getElementById: function (id) { var e = el(id); e.classList.o = e; return e; },
              documentElement: { setAttribute: function () {}, removeAttribute: function () {} },
              addEventListener: function (t, f) { if (t === "click") onClick = f; } },
  localStorage: { getItem: function (k) { return k in store ? store[k] : null; },
                  setItem: function (k, v) { store[k] = String(v); }, removeItem: function (k) { delete store[k]; } },
  setTimeout: setTimeout, clearTimeout: clearTimeout, console: console,
  window: { addEventListener: function () {} }
};
vm.runInNewContext(fs.readFileSync(here + "/viewer/viewer.js", "utf8") + "\n" +
                   fs.readFileSync(here + "/build/prices.js", "utf8") + "\n" +
                   fs.readFileSync(here + "/viewer/usage.js", "utf8"), ctx);
function text(id) { return el(id).innerHTML.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim(); }
function button(id) { el(id).listeners.click(); }
var o = {};
button("pall"); button("bmodel");
o.card = text("cards"); o.rows = text("buckets"); o.tableHtml = el("buckets").innerHTML;
o.on = [el("cthen").cls.on, el("cnow").cls.on]; o.group = el("cgroup").hidden;
o.history = text("ptable"); o.notes = text("pnotes"); o.check = el("pcheck").textContent;
o.links = (el("pnotes").innerHTML.match(/<a href="[^"]*"/g) || []).length;
o.shown = !el("prices").hidden;
o.sub = el("sub").textContent;
button("cnow");
o.nowCard = text("cards"); o.nowOn = [el("cthen").cls.on, el("cnow").cls.on];
o.stored = store["ch-usage-prices"];
o.nowHistory = text("ptable");
button("cthen");
o.backCard = text("cards");
console.log(JSON.stringify(o));
EOF
pg() { TZ=UTC node "$T/page.js" "$HERE" "$OUT/usage.html" "${1:-}" "${2:-}"; }
PG="$(pg)"
p() { printf '%s' "$PG" | js "$1"; }
# all time: recorded $0.50; calculated 52,650 + 24,000 = $0.07665 → $0.08
check "the cost card: recorded by Claude Code, and calculated under it" \
  "$(p 'd.card.split(" ").slice(4, 12).join(" ")')" '$0.50 recorded by Claude Code ≥ $0.08 calculated'
check "  the toggle starts at the price of the time" "$(p 'JSON.stringify(d.on)') $(p d.group)" "[true,false] false"
check "the table: recorded plain, calculated where none was, marked calc" \
  "$(p 'd.rows.split(" 2026-10-07 ")[0] + " | " + d.rows.split(" 2026-10-07 ")[1].split(" alpha-1/fast")[0]')" \
  "2026-10-08 alpha-1 4.0 k 4.0 k 0 0 1 8.0 k ≈ \$0.50 | alpha-1 1.0 k 2.0 k 10.0 k 3.0 k 1 16.0 k ≈ \$0.02 calc"
check "  a recorded cost is never replaced by a calculated one" \
  "$(p '(d.tableHtml.match(/class="num cc"/g) || []).length + " " + /≈ \$0\.50<\/td>/.test(d.tableHtml)')" "4 true"
check "  calc cells say what they are" "$(p '/title="[^"]*no price line[^"]*">≥ \$0\.02 <span class="cm">calc<\/span>/.test(d.tableHtml)')" "true"
check "today's prices: every hour at the current line" \
  "$(p 'd.nowCard.split(" ").slice(4, 12).join(" ")')" '$0.50 recorded by Claude Code ≥ $0.06 calculated'
check "  the toggle shows it and remembers it" "$(p 'JSON.stringify(d.nowOn) + " " + d.stored')" "[false,true] now"
check "  and back again gives the first figures" "$(p 'd.backCard === d.card')" "true"
check "  a stored choice is where the page starts" \
  "$(pg '{"ch-usage-prices":"now"}' | js 'JSON.stringify(d.on)')" "[false,true]"
check "price history: each model's lines, newest first, with what changed" \
  "$(p d.history)" \
  "alpha-1 since 2026-10-07 current 1.00 5.00 0.10 1.25 2.00 2.00 → 1.00 −50 % … 24.0 k 2 2026-01-01 to 2026-10-06 2.00 10.00 0.20 2.50 4.00 — 16.0 k 1 alpha-1/fast since 2026-01-01 current 4.00 20.00 0.40 5.00 8.00 no change 200 1"
check "  tokens per line stay at the price of the time whatever the toggle" "$(p 'd.nowHistory === d.history')" "true"
check "  the heading says when the file was checked" "$(p d.check)" " · price file checked 2026-11-02"
check "  what is not priced is said, never guessed" "$(p 'd.notes.indexOf("gone 100 tokens") > -1')" "true"
check "  and the writes of unknown duration" "$(p '/3\.0 k tokens of cache writes are of unknown duration/.test(d.notes)')" "true"
check "  with its sources, as plain links" "$(p d.links)" "3"
check "  the subtitle says both costs are there" "$(p '/recorded it and as calculated from the price file/.test(d.sub)')" "true"
# No price file: the page is as it was, recorded alone.
NP="$(pg '' 'dd.prices = null')"
check "without a price file there is no toggle, no history, no calculated figure" \
  "$(printf '%s' "$NP" | js 'JSON.stringify([d.group, d.shown, /calculated/.test(d.card), /calc/.test(d.rows)])')" \
  "[true,false,false,false]"

# ── the session page ────────────────────────────────────────────────
# page.js's token line, alone, against the page's own meta.
cat > "$T/tok.js" <<'EOF'
var fs = require("fs"), vm = require("vm");
var src = fs.readFileSync(process.argv[2] + "/viewer/page.js", "utf8");
var at = src.indexOf("(function tokens() {"), end = src.indexOf("\n  })();\n", at) + 8;
var html = fs.readFileSync(process.argv[3], "utf8");
var meta = JSON.parse(/id="session-data">([\s\S]*?)<\/script>/.exec(html)[1]).meta;
var el = { innerHTML: "", hidden: true };
var ctx = { meta: meta, document: { getElementById: function () { return el; } } };
vm.runInNewContext(fs.readFileSync(process.argv[2] + "/viewer/viewer.js", "utf8") + "\n" + src.slice(at, end), ctx);
console.log(JSON.stringify(el.innerHTML.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").split(" · ").slice(0, 2)));
EOF
check "the session page: a calculated cost where — was, marked calc" \
  "$(node "$T/tok.js" "$HERE" "$OUT/sessions/$S1.html")" '["32.3 k tokens","≥ $0.05 calc"]'
check "  and the recorded one where there is one" \
  "$(node "$T/tok.js" "$HERE" "$OUT/sessions/$S2.html")" '["8.0 k tokens","≈ $0.50"]'

echo
verdict
