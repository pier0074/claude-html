#!/bin/bash
# What dev/release.sh does before and after it pushes a candidate to the CI
# repository, which is public, tested here with nothing pushed anywhere:
# dev/secret-check.js reads the lines the candidate adds to the public
# release for secrets, and dev/ci-clean.sh takes the candidate branch and
# every run away there (gh stood in for). dev/ is never published, so in a
# clone without it (CI's) there is nothing to test.
#
#   bash tests/release.test.sh
set -u

SRC="$(cd "$(dirname "$0")" && pwd)"
. "$SRC/lib.sh"
CL="$(cd "$SRC/.." && pwd)"
pass=0; fail=0
if [ ! -f "$CL/dev/secret-check.js" ] || [ ! -f "$CL/dev/ci-clean.sh" ]; then
  echo "  skip  dev/ is not in this clone: the release's checks are not either"; exit 0
fi
command -v node >/dev/null 2>&1 || { echo "  skip  the secret check needs node"; exit 0; }

T="$(cd "$(tmpdir chrelease)" && pwd -P)"
trap 'rm -rf "$T"' EXIT
H="$T/home"; mkdir -p "$H"

# ── the secret check ──
# A fake GitHub token, put together here so this file holds none.
TOK="gh""p_$(printf 'aB3dE5fG7h%.0s' 1 2 3 4)"
R="$T/repo"; mkdir -p "$R/build" "$R/actions" "$R/tests"
cp "$CL/build/redact.js" "$R/build/"; cp "$CL/actions/guard.js" "$R/actions/"
gitx init -q "$R"
printf 'claude-html\n' > "$R/README.md"
printf 'a fixture\nthe token %s here\n' "$TOK" > "$R/tests/fixture.txt"
gitx -C "$R" add -A; gitx -C "$R" commit -q -m base
BASE="$(gitx -C "$R" rev-parse 'HEAD^{tree}')"
tree() { gitx -C "$R" add -A && gitx -C "$R" write-tree; }
scan() {   # tree [own list]: the output, then the status on a line of its own
  HOME="$H" node "$CL/dev/secret-check.js" "$R" "$BASE" "$1" ${2+"$2"} 2>&1; echo "rc=$?"
}

printf 'claude-html\nmore words, and a token: string\n' > "$R/README.md"
gitx -C "$R" mv tests/fixture.txt tests/moved.txt
OUT="$(scan "$(tree)")"
check "a clean change passes" "$(printf '%s\n' "$OUT" | tail -1)" "rc=0"
has "it says how much it read" "$OUT" "secret check: 1 added line(s), 0 possible secret(s)"
check "a secret already public, moved but unchanged, is not a hit" "$(printf '%s\n' "$OUT" | grep -c moved.txt)" 0

mkdir -p "$R/notes"; printf 'one\ntwo\nuse %s for the push\n' "$TOK" > "$R/notes/new.txt"
OUT="$(scan "$(tree)")"
check "a secret in a new file stops it" "$(printf '%s\n' "$OUT" | tail -1)" "rc=1"
has "the hit is named by file, line and rule" "$OUT" "notes/new.txt:3  github"
check "the value is never printed" "$(printf '%s\n' "$OUT" | grep -cF "$TOK")" 0
rm -rf "$R/notes"

printf 'a fixture\nthe token %s here, and changed\n' "$TOK" > "$R/tests/moved.txt"
OUT="$(scan "$(tree)")"
check "a line changed around a secret is read again" "$(printf '%s\n' "$OUT" | grep -c 'tests/moved.txt:2  github')" 1
printf 'a fixture\nthe token %s here\n' "$TOK" > "$R/tests/moved.txt"

# A line that starts "++" is "+++" in the diff, like a file's header.
printf '++ %s\n' "$TOK" > "$R/tests/plus.txt"
OUT="$(scan "$(tree)")"
has "an added line starting ++ is read as a line" "$OUT" "tests/plus.txt:1  github"
rm -f "$R/tests/plus.txt"

printf 'acme-hidden-thing\n' > "$T/own.list"
printf 'claude-html\nmore words, and a token: string\nbuilt for acme-hidden-thing\n' > "$R/README.md"
OUT="$(scan "$(tree)" "$T/own.list")"
has "the owner's own list is read too" "$OUT" "README.md:3  own list"
check "nor is its value printed" "$(printf '%s\n' "$OUT" | grep -c acme-hidden)" 0
OUT="$(scan "$(tree)" "$T/no-such.list")"
check "without an own list, the rules alone" "$(printf '%s\n' "$OUT" | tail -1)" "rc=0"

mv "$R/actions/guard.js" "$T/guard.js"
OUT="$(scan "$(tree)")"
check "without the guard's rules it says it could not look" "$(printf '%s\n' "$OUT" | tail -1)" "rc=2"
mv "$T/guard.js" "$R/actions/guard.js"
OUT="$(HOME="$H" node "$CL/dev/secret-check.js" "$R" "$BASE" no-such-tree 2>&1; echo "rc=$?")"
check "a tree git does not know is not a pass" "$(printf '%s\n' "$OUT" | tail -1)" "rc=2"

# ── release.sh: the check and the sweep come before the push ──
RS="$CL/dev/release.sh"
line_of() { grep -nF -- "$1" "$RS" | head -1 | cut -d: -f1; }
PUSH="$(line_of '"${C}:refs/heads/candidate"')"
check "release.sh pushes a candidate once" "$(grep -cF '"${C}:refs/heads/candidate"' "$RS")" 1
check "the secret check runs before the push" "$([ "$(line_of 'dev/secret-check.js" "$W" "$BASE" "$T"')" -lt "$PUSH" ] && echo yes)" yes
check "a hit is NOT RELEASED, before the push" \
  "$([ "$(line_of 'NOT RELEASED: possible secret in the candidate')" -lt "$PUSH" ] && echo yes)" yes
check "the clean-up is set for every exit before the push" "$([ "$(line_of 'trap on_exit EXIT')" -lt "$PUSH" ] && echo yes)" yes
check "the sweep runs before the push" "$([ "$(line_of 'ci_clean "$R_CI" ||')" -lt "$PUSH" ] && echo yes)" yes
check "on_exit cleans the CI repository" "$(sed -n '/^on_exit() {/,/^}/p' "$RS" | grep -c 'ci_clean "$R_CI"')" 1
check "release.sh still reads as bash" "$(bash -n "$RS" 2>&1 && echo ok)" ok

# ── ci_clean, with gh stood in for ──
# The stand-in keeps the runs in a file, "id status" a line. A cancelled
# run ends on the next listing; "stuck" ignores a cancel; a run is deleted
# only once it has ended, as GitHub's are.
B="$T/bin"; mkdir -p "$B"
cat > "$B/gh" <<EOF
#!/bin/bash
S='$T/gh'
echo "\$*" >> "\$S/calls"
case "\$1 \$2" in
  "api repos/"*) [ -f "\$S/branch" ] ;;
  "api -X") rm -f "\$S/branch" ;;
  "run list")
    [ -f "\$S/down" ] && exit 1
    awk '\$2 == "cancelling" { \$2 = "completed" } { print }' "\$S/runs" > "\$S/runs.n"; mv "\$S/runs.n" "\$S/runs"
    cat "\$S/runs" ;;
  "run cancel") awk -v i="\$3" '\$1 == i && \$2 != "stuck" && \$2 != "completed" { \$2 = "cancelling" } { print }' "\$S/runs" > "\$S/runs.n"
    mv "\$S/runs.n" "\$S/runs" ;;
  "run delete") grep -q "^\$3 completed\$" "\$S/runs" || exit 1
    grep -v "^\$3 " "\$S/runs" > "\$S/runs.n"; mv "\$S/runs.n" "\$S/runs" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$B/gh"
mkdir -p "$T/gh"
clean() {   # wait poll: the warning, then the status
  PATH="$B:$PATH" CI_CLEAN_WAIT="$1" CI_CLEAN_POLL="$2" bash -c '. "$0"; ci_clean owner/ci' "$CL/dev/ci-clean.sh" 2>&1
  echo "rc=$?"
}

: > "$T/gh/calls"; touch "$T/gh/branch"
printf '101 completed\n102 in_progress\n103 queued\n' > "$T/gh/runs"
OUT="$(clean 30 0)"
check "every run is gone" "$(printf '%s\n' "$OUT" | tail -1) $(grep -c . "$T/gh/runs")" "rc=0 0"
check "so is the candidate branch" "$([ -f "$T/gh/branch" ] && echo there || echo gone)" gone
check "the runs not done are cancelled, the done one is not" \
  "$(grep '^run cancel' "$T/gh/calls" | awk '{ print $3 }' | sort -u | paste -s -d, -)" "102,103"
check "each run is deleted once it has ended" \
  "$(grep '^run delete' "$T/gh/calls" | awk '{ print $3 }' | sort -u | paste -s -d, -)" "101,102,103"

: > "$T/gh/calls"
printf '201 completed\n999 stuck\n' > "$T/gh/runs"
OUT="$(clean 1 0.2)"
check "a run that will not end: it gives up after the wait" "$(printf '%s\n' "$OUT" | tail -1)" "rc=1"
has "and names the run left, not just a count" "$OUT" "WARNING: owner/ci still has runs after 1s: 999 (stuck)"
check "the others are deleted all the same" "$(cat "$T/gh/runs")" "999 stuck"
check "no branch, nothing deleted" "$(grep -c 'api -X DELETE' "$T/gh/calls")" 0

touch "$T/gh/down"
OUT="$(clean 1 0)"
check "runs it cannot list are a warning, not a pass" "$(printf '%s\n' "$OUT" | tail -1)" "rc=1"
has "which says so" "$OUT" "WARNING: the runs of owner/ci could not be listed"
rm -f "$T/gh/down"

verdict
