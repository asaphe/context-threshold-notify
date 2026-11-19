#!/bin/sh
# Tests for .github/scripts/dco.sh in a throwaway git repo.
dco="$(cd "$(dirname "$0")/.." && pwd)/.github/scripts/dco.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
git init -q -b main && git config user.email a@b.c && git config user.name t && git config commit.gpgsign false
git commit -q --allow-empty -m base; base=$(git rev-parse HEAD)
pass=0 fail=0
check() { sh "$dco" "$base" HEAD $3 >/dev/null 2>&1; rc=$?; if [ "$rc" = "$2" ]; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1 (want $2, got $rc)"; fi; }

check "empty range" 0
git commit -q --allow-empty -s -m signed; check "signed off by author" 0
git checkout -q -b side "$base" && git commit -q --allow-empty -s -m side && git checkout -q main && git merge -q --no-ff --no-edit side
check "plus an unsigned merge commit (Update branch)" 0
base=$(git rev-parse HEAD)  # each scenario below gets its own range
git -c user.email='49699333+dependabot[bot]@users.noreply.github.com' commit -q --allow-empty -m spoof
check "unsigned commit with Dependabot's email" 1
check "same range in a real Dependabot PR" 0 'dependabot[bot]'
git reset -q --hard "$base"; git commit -q --allow-empty -m other --trailer "Signed-off-by: Other <o@x.y>"
check "signed off by someone else" 1
git reset -q --hard "$base"; git commit -q --allow-empty -m unsigned; check "unsigned" 1
git reset -q --hard "$base"; git commit -q --allow-empty -s --author="Author <author@example.com>" -m applied
check "committer's sign-off on someone else's patch" 0
git reset -q --hard "$base"; git commit -q --allow-empty -m caps --trailer "Signed-off-by: t <A@B.C>"
check "sign-off email differs only in case" 0
sh "$dco" nope HEAD >/dev/null 2>&1; rc=$?; [ $rc = 2 ] && { pass=$((pass+1)); echo "PASS  bad base -> 2"; } || { fail=$((fail+1)); echo "FAIL  bad base (got $rc)"; }
sh "$dco" >/dev/null 2>&1; rc=$?; [ $rc = 2 ] && { pass=$((pass+1)); echo "PASS  no args -> 2"; } || { fail=$((fail+1)); echo "FAIL  no args (got $rc)"; }

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
