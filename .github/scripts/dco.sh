#!/bin/sh
# Usage: dco.sh BASE HEAD — fail if a commit in BASE..HEAD lacks a Signed-off-by trailer; Dependabot's commits are exempt.
[ $# -eq 2 ] || { echo "usage: dco.sh BASE HEAD" >&2; exit 2; }
log=$(git log --format='%H %ae %(trailers:key=Signed-off-by,valueonly,separator=%x2C)' "$1..$2") || exit 2
missing=$(printf '%s\n' "$log" | awk '$2 != "49699333+dependabot[bot]@users.noreply.github.com" && NF == 2 { print $1 }')
[ -z "$missing" ] && { echo "DCO: every commit is signed off"; exit 0; }
echo "DCO: these commits have no Signed-off-by trailer (commit with -s, see CONTRIBUTING.md):"
echo "$missing"
exit 1
