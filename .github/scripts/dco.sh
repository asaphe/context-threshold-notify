#!/bin/sh
# Usage: dco.sh BASE HEAD [PR_AUTHOR] — fail if a non-merge commit in BASE..HEAD lacks a Signed-off-by naming its author or committer.
[ $# -ge 2 ] || { echo "usage: dco.sh BASE HEAD [PR_AUTHOR]" >&2; exit 2; }
[ "${3:-}" = "dependabot[bot]" ] && { echo "DCO: Dependabot pull request, exempt"; exit 0; }  # PR author is set by GitHub, not the committer
log=$(git log --no-merges --format='%H%x09%ae%x09%ce%x09%(trailers:key=Signed-off-by,valueonly,separator=%x2C)' "$1..$2") || exit 2
missing=$(printf '%s\n' "$log" | awk -F '\t' 'NF { t = tolower($4) } NF && !index(t, "<" tolower($2) ">") && !index(t, "<" tolower($3) ">") { print $1 " (author " $2 ")" }')
[ -z "$missing" ] && { echo "DCO: every commit is signed off by its author or committer"; exit 0; }
echo "DCO: these commits have no Signed-off-by naming their author or committer (commit with -s, see CONTRIBUTING.md):"
echo "$missing"
exit 1
