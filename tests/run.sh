#!/bin/sh
# Offline tests for check-context.sh: stub notifier, osascript and uname record calls; nothing is shown on screen.
here=$(cd "$(dirname "$0")/.." && pwd)
unset ANTHROPIC_MODEL CLAUDE_PLUGIN_OPTION_WINDOW_TOKENS CLAUDE_PLUGIN_OPTION_PERCENT CLAUDE_PLUGIN_OPTION_THRESHOLD_TOKENS \
  CONTEXT_THRESHOLD_NOTIFY_TOKENS CONTEXT_THRESHOLD_NOTIFY_PERCENT CONTEXT_THRESHOLD_NOTIFY_WINDOW
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"; mkdir "$bin"
printf '#!/bin/sh\necho Darwin\n' > "$bin/uname"
printf '#!/bin/sh\necho "osascript $*" >> "%s/calls"\n' "$tmp" > "$bin/osascript"
stub="$tmp/notifier"; printf '#!/bin/sh\nfor a; do printf "%%s\\n" "$a"; done > "%s/argv.$$"\necho "$@" >> "%s/calls"\n' "$tmp" "$tmp" > "$stub"
chmod +x "$bin/uname" "$bin/osascript" "$stub"
nojq="$tmp/nojq"; mkdir "$nojq"
for c in sh sed grep tail head tr ps basename dirname mkdir cat wc; do ln -s "$(command -v $c)" "$nojq/$c"; done
ln -s "$bin/uname" "$nojq/uname"; ln -s "$bin/osascript" "$nojq/osascript"
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1 (want $3, got $2)"; fi; }
calls() { [ -f "$tmp/calls" ] && wc -l < "$tmp/calls" | tr -d ' ' || echo 0; }
settle() { # wait for $1 calls (the notifier runs in the background), then a short grace for any extra one
  i=0; while [ "$(calls)" -lt "$1" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done; sleep 0.3
}
transcript() { # $1 file, $2 tokens in main line, $3 tokens in a later sidechain line
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"\\"input_tokens\\":999999"}],"usage":{"input_tokens":2,"cache_read_input_tokens":%s,"cache_creation_input_tokens":10}}}\n' "$2" > "$1"
  [ -n "$3" ] && printf '{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":%s}}}\n' "$3" >> "$1"; :
}
hook() { # $1 JSON on stdin of the hook; env: P (PATH), N (notifier), I (ITERM_SESSION_ID)
  printf '%s' "$1" | env CLAUDE_CONFIG_DIR="${C:-$tmp/cfg}" PATH="${P:-$bin:$PATH}" CONTEXT_THRESHOLD_NOTIFY_STATE="$tmp/state" \
    CONTEXT_THRESHOLD_NOTIFY_NOTIFIER="${N:-$stub}" ITERM_SESSION_ID="${I:-w0t1p0:UUID-1}" \
    __CFBundleIdentifier="com.example.Term" sh "$here/scripts/check-context.sh"
}
run() { hook "{\"session_id\":\"$1\",\"transcript_path\":\"$2\",\"cwd\":\"/x/my-proj\"}"; }

mkdir "$tmp/cfg"; printf '{"model": "opus[1m]"}\n' > "$tmp/cfg/settings.json"  # [1m] -> 1M window -> default 500k
transcript "$tmp/low.jsonl" 400000 900000
transcript "$tmp/high.jsonl" 520000

run low "$tmp/low.jsonl"; settle 0; check "below threshold, sidechain above -> no notification" "$(calls)" 0
run high "$tmp/high.jsonl"; settle 1; check "above threshold -> one notification" "$(calls)" 1
grep -q "Context ~520k passed the 500k threshold" "$tmp/calls"; check "message names tokens, ignores text decoy" $? 0
grep -q "FOCUS_APP=com.example.Term '.*focus-tab.sh' 'UUID-1'" "$tmp/calls"; check "click focuses tab, falls back to app" $? 0
grep -q "Claude Code: my-proj context" "$tmp/calls"; check "title names the project" $? 0
exe=$(cat "$tmp"/argv.* | sed -n '/^-execute$/{n;p;}' | head -n 1)
sh -n -c "$exe"; check "click command is valid shell" $? 0
run high "$tmp/high.jsonl"; settle 1; check "same session again -> no repeat" "$(calls)" 1

( P="$nojq"; run nojq "$tmp/high.jsonl" ); settle 2; check "works without jq" "$(calls)" 2  # subshell: macOS sh keeps a VAR=x func prefix set afterwards
check "no-jq path ignores text decoy" "$(grep -c 'Context ~520k' "$tmp/calls")" 2

nested='{"session_id":"nested","transcript_path":"'"$tmp/high.jsonl"'","cwd":"/x/real-proj","tool_input":{"session_id":"other","transcript_path":"/nonexistent","cwd":"/y/elsewhere"}}'
hook "$nested"; settle 3; check "nested tool_input keys ignored (jq)" "$(tail -n 1 "$tmp/calls" | grep -c 'real-proj')" 1
check "marker uses the hook's session id (jq)" "$( [ -e "$tmp/state/nested" ] && [ ! -e "$tmp/state/other" ] && echo ok)" ok
( P="$nojq"; hook "$(printf '%s' "$nested" | sed 's/"nested"/"nested2"/')" ); settle 4
check "nested tool_input keys ignored (no jq)" "$(tail -n 1 "$tmp/calls" | grep -c 'real-proj')" 1

: > "$tmp/calls"; rm -f "$tmp"/argv.*
( I="w0:x'; touch $tmp/PWNED; '"; run inject "$tmp/high.jsonl" ); settle 1
check "quote in ITERM_SESSION_ID -> rejected, tty or none instead" "$(grep -cE "focus-tab.sh' '(none|/dev/ttys[0-9]+)'" "$tmp/calls")" 1
check "quote in ITERM_SESSION_ID -> nothing injected" "$(grep -c PWNED "$tmp/calls")" 0

: > "$tmp/calls"
for _ in 1 2 3 4 5 6 7 8; do run race "$tmp/high.jsonl" & done; wait; settle 1
check "8 concurrent hook runs -> one notification (smoke test: cannot catch a missing set -C)" "$(calls)" 1

: > "$tmp/calls"
( N=/nonexistent; run fallback "$tmp/high.jsonl" ); settle 1
check "no notifier -> osascript fallback" "$(grep -c '^osascript -e display notification' "$tmp/calls")" 1

printf '#!/bin/sh\necho Linux\n' > "$tmp/linux-uname"; mkdir "$tmp/linux"; mv "$tmp/linux-uname" "$tmp/linux/uname"; chmod +x "$tmp/linux/uname"
( P="$tmp/linux:$bin:$PATH"; run linux "$tmp/high.jsonl" ); settle 0
check "non-macOS -> no marker, no call" "$( [ -e "$tmp/state/linux" ] && echo marker; calls)" 1

hook '{"session_id":"../evil","transcript_path":"'"$tmp/high.jsonl"'"}'; check "unsafe session id -> no marker" "$( [ -e "$tmp/evil" ] && echo 1 || echo 0)" 0
hook 'not json'; check "garbage input -> exit 0" $? 0
: > "$tmp/calls"; ( export CONTEXT_THRESHOLD_NOTIFY_TOKENS=600000; run high600 "$tmp/high.jsonl" ); settle 0; check "custom threshold respected" "$(calls)" 0

sh "$here/scripts/focus-tab.sh" >/dev/null 2>&1; check "focus-tab.sh without args -> usage, rc 2" $? 2

: > "$tmp/calls"
transcript "$tmp/re.jsonl" 520000; run rearm "$tmp/re.jsonl"; settle 1
transcript "$tmp/re.jsonl" 450000; run rearm "$tmp/re.jsonl"; settle 1
check "drop to 90% of threshold -> stays fired" "$( [ -e "$tmp/state/rearm" ] && echo kept)" kept
transcript "$tmp/re.jsonl" 520000; run rearm "$tmp/re.jsonl"; settle 1; check "climb again without re-arm -> no repeat" "$(calls)" 1
transcript "$tmp/re.jsonl" 100000; run rearm "$tmp/re.jsonl"; settle 1
check "drop below 80% (e.g. /compact) -> re-armed" "$( [ -e "$tmp/state/rearm" ] && echo kept || echo cleared)" cleared
transcript "$tmp/re.jsonl" 520000; run rearm "$tmp/re.jsonl"; settle 2; check "climb past threshold again -> second notification" "$(calls)" 2

pad=$(head -c 300000 /dev/zero | tr '\0' a)
bigline() { printf '{"parentUuid":"p","isSidechain":%s,"message":{"content":[{"type":"text","text":"%s"}],"usage":{"input_tokens":%s}},"type":"assistant"}\n' "$1" "$pad" "$2"; }
: > "$tmp/calls"
bigline false 520000 > "$tmp/big-main.jsonl"; run bigmain "$tmp/big-main.jsonl"; settle 1
check "300 KB last main line (past the 256 KiB window) -> still notifies" "$(calls)" 1
{ printf '{"isSidechain":false,"message":{"usage":{"input_tokens":1000}},"type":"assistant"}\n'; bigline true 900000; } > "$tmp/big-side.jsonl"
: > "$tmp/calls"; ( P="$nojq"; run bigside "$tmp/big-side.jsonl" ); settle 0
check "300 KB sidechain line, no jq -> its cut fragment is not read as main thread" "$(calls)" 0

mkdir "$tmp/cfg200"; printf '{"model": "sonnet"}\n' > "$tmp/cfg200/settings.json"
transcript "$tmp/t120.jsonl" 120000; transcript "$tmp/t90.jsonl" 90000; transcript "$tmp/t160.jsonl" 160000
: > "$tmp/calls"; ( C="$tmp/cfg200"; run w200a "$tmp/t90.jsonl" ); settle 0; check "no [1m] in model -> 200k window, 90k under 50%" "$(calls)" 0
( C="$tmp/cfg200"; run w200b "$tmp/t120.jsonl" ); settle 1; check "no [1m] in model -> 200k window, 120k past 50%" "$(calls)" 1
grep -q "passed the 100k threshold" "$tmp/calls"; check "threshold shown as 100k" $? 0
: > "$tmp/calls"; ( C="$tmp/cfg200"; export CLAUDE_PLUGIN_OPTION_PERCENT=75; run p75a "$tmp/t120.jsonl" ); settle 0
check "percent option 75 -> 120k under 150k" "$(calls)" 0
( C="$tmp/cfg200"; export CLAUDE_PLUGIN_OPTION_PERCENT=75; run p75b "$tmp/t160.jsonl" ); settle 1; check "percent option 75 -> 160k past 150k" "$(calls)" 1
: > "$tmp/calls"; ( export CLAUDE_PLUGIN_OPTION_WINDOW_TOKENS=200000; run win "$tmp/t120.jsonl" ); settle 1
check "window option beats the [1m] model guess" "$(calls)" 1
: > "$tmp/calls"; ( export CLAUDE_PLUGIN_OPTION_THRESHOLD_TOKENS=100000; run abs "$tmp/t120.jsonl" ); settle 1
check "absolute option 100k beats the 500k percent threshold" "$(calls)" 1
: > "$tmp/calls"; ( C="$tmp/cfg200"; export CLAUDE_PLUGIN_OPTION_PERCENT=abc; run badpct "$tmp/t120.jsonl" ); settle 1; check "invalid percent -> 50" "$(calls)" 1
mkdir -p "$tmp/proj/.claude"; printf '{"model": "opus[1m]"}\n' > "$tmp/proj/.claude/settings.local.json"
: > "$tmp/calls"; ( C="$tmp/cfg200"; hook '{"session_id":"projlocal","transcript_path":"'"$tmp/t120.jsonl"'","cwd":"'"$tmp/proj"'"}' ); settle 0
check "project settings.local.json [1m] beats user model" "$(calls)" 0

: > "$tmp/calls"; ( C="$tmp/cfg200"; export CLAUDE_PLUGIN_OPTION_PERCENT=08; run pct08 "$tmp/t90.jsonl" ); rc=$?; settle 0
check "percent 08 -> exit 0" "$rc" 0
check "percent 08 -> treated as 50 (90k under 100k)" "$(calls)" 0
( C="$tmp/cfg200"; export CLAUDE_PLUGIN_OPTION_PERCENT=050; run pct050 "$tmp/t90.jsonl" ); settle 0
check "percent 050 -> 50, not octal 40 (90k under 100k)" "$(calls)" 0
( C="$tmp/cfg200"; export CLAUDE_PLUGIN_OPTION_WINDOW_TOKENS=0100000; run win0 "$tmp/t90.jsonl" ); settle 0
check "window 0100000 -> ignored, guessed 200k (90k under 100k)" "$(calls)" 0
printf '{"isSidechain":false,"requestedModel":"claude-x-1[1m]","message":{"usage":{"input_tokens":120000}},"type":"assistant"}\n' > "$tmp/req1m.jsonl"
( C="$tmp/cfg200"; run req1m "$tmp/req1m.jsonl" ); settle 0
check "requestedModel [1m] beats a settings model without it" "$(calls)" 0
printf '{"isSidechain":false,"requestedModel":"claude-x-1[1m]","message":{"usage":{"input_tokens":120000}},"type":"assistant"}\n' > "$tmp/req1m2.jsonl"
( C="$tmp/cfg200"; P="$nojq"; run req1mnojq "$tmp/req1m2.jsonl" ); settle 0
check "requestedModel [1m] read without jq" "$(calls)" 0
printf '{"isSidechain":false,"requestedModel":"claude-x-1","message":{"usage":{"input_tokens":120000}},"type":"assistant"}\n' > "$tmp/req200.jsonl"
: > "$tmp/calls"; run reqplain "$tmp/req200.jsonl"; settle 0
check "requestedModel without [1m] falls back to settings opus[1m] (120k under 500k)" "$(calls)" 0
transcript "$tmp/t250.jsonl" 250000
( C="$tmp/cfg200"; run over200 "$tmp/t250.jsonl" ); settle 0
check "context above 200k -> window is not 200k (250k under 500k)" "$(calls)" 0

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
