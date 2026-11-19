#!/bin/sh
# PostToolUse/Stop hook: one notification per climb past the context threshold (see README § Configure); never blocks.
[ "$(uname)" = Darwin ] || exit 0
input=$(cat)
if command -v jq >/dev/null 2>&1; then
  has_jq=1
  fields=$(printf '%s' "$input" | jq -r '.session_id // "", .transcript_path // "", .cwd // ""' 2>/dev/null) || exit 0
  sid=$(printf '%s\n' "$fields" | sed -n 1p)
  tp=$(printf '%s\n' "$fields" | sed -n 2p)
  cwd=$(printf '%s\n' "$fields" | sed -n 3p)
else
  has_jq=""
  # Top-level keys precede tool_input/tool_response, so the first match is the hook's own field.
  field() { printf '%s' "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 | sed 's/.*:[[:space:]]*"\(.*\)"$/\1/'; }
  sid=$(field session_id)
  tp=$(field transcript_path)
  cwd=$(field cwd)
fi
case $sid in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
[ -f "$tp" ] || exit 0

state=${CONTEXT_THRESHOLD_NOTIFY_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/context-threshold-notify}
size=$(wc -c < "$tp" | tr -d ' '); size=${size:-0}
tail_window() { if [ "$1" -lt "$size" ]; then tail -c "$1" "$tp" | sed 1d; else cat "$tp"; fi; }  # a cut window's first line may be partial
num() { v=$(printf '%s' "$line" | sed -n "s/.*\"$1\":\([0-9][0-9]*\).*/\1/p"); echo "${v:-0}"; }
tokens=""
for bytes in 262144 4194304; do
  line=$(tail_window "$bytes" | grep '"type":"assistant"' | grep -v '"isSidechain":true' | tail -n 1)
  [ -n "$line" ] || continue
  if [ -n "$has_jq" ]; then
    tokens=$(printf '%s' "$line" | jq -r '.message.usage // {} | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)' 2>/dev/null)
  else
    tokens=$(( $(num input_tokens) + $(num cache_read_input_tokens) + $(num cache_creation_input_tokens) ))
  fi
  case $tokens in ''|0|*[!0-9]*) tokens="" ;; *) break ;; esac
  [ "$bytes" -lt "$size" ] || break
done
[ -n "$tokens" ] || exit 0
uint() { case $1 in ''|0*|*[!0-9]*|?????????????*) return 1 ;; esac; }  # no leading zero: $(( )) reads 08 as an error, 050 as octal
threshold=${CONTEXT_THRESHOLD_NOTIFY_TOKENS:-${CLAUDE_PLUGIN_OPTION_THRESHOLD_TOKENS:-}}
if ! uint "$threshold"; then
  percent=${CONTEXT_THRESHOLD_NOTIFY_PERCENT:-${CLAUDE_PLUGIN_OPTION_PERCENT:-50}}
  { uint "$percent" && [ "$percent" -le 100 ]; } || percent=50
  window=${CONTEXT_THRESHOLD_NOTIFY_WINDOW:-${CLAUDE_PLUGIN_OPTION_WINDOW_TOKENS:-}}
  if ! uint "$window"; then
    if [ -n "$has_jq" ]; then
      model=$(printf '%s' "$line" | jq -r '.requestedModel // ""' 2>/dev/null)
    else
      model=$(printf '%s' "$line" | grep -o '"requestedModel":"[^"]*"' | head -n 1)
    fi
    case $model in *'[1m]'*) ;; *) model=${ANTHROPIC_MODEL:-} ;; esac
    for f in "$cwd/.claude/settings.local.json" "$cwd/.claude/settings.json" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; do
      [ -z "$model" ] && [ -f "$f" ] && model=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
    done
    case $model in *'[1m]'*) window=1000000 ;; *) window=200000 ;; esac
    [ "$tokens" -gt 200000 ] && window=1000000
  fi
  threshold=$(( window * percent / 100 ))
fi

# Re-arm only well below the threshold, so small context edits near it cannot re-notify.
if [ "$tokens" -lt "$threshold" ]; then
  [ -e "$state/$sid" ] && [ "$tokens" -lt $(( threshold * 4 / 5 )) ] && rm -f "$state/$sid"
  exit 0
fi
[ -e "$state/$sid" ] && exit 0

mkdir -p "$state" 2>/dev/null || exit 0
( set -C; : > "$state/$sid" ) 2>/dev/null || exit 0
project=$(basename "$cwd" | tr -cd 'A-Za-z0-9._ -')
title="Claude Code: ${project:-session} context"
message="Context ~$(( tokens / 1000 ))k passed the $(( threshold / 1000 ))k threshold."

focus=${ITERM_SESSION_ID#*:} pid=$PPID
case $focus in *[!A-Za-z0-9-]*) focus="" ;; esac
while [ -z "$focus" ] && [ "${pid:-1}" -gt 1 ]; do
  t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
  case $t in ttys[0-9]*) focus="/dev/$t" ;; esac
  pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
done
case $focus in ''|*[!A-Za-z0-9/-]*) focus=none ;; esac
app=""
case ${__CFBundleIdentifier:-} in ''|*[!A-Za-z0-9.-]*) ;; *) app="FOCUS_APP=$__CFBundleIdentifier " ;; esac

tn=${CONTEXT_THRESHOLD_NOTIFY_NOTIFIER:-$(command -v terminal-notifier)}
[ -n "$tn" ] || for p in /opt/homebrew/bin/terminal-notifier /usr/local/bin/terminal-notifier; do [ -x "$p" ] && tn=$p && break; done
here=$(cd "$(dirname "$0")" && pwd)
if [ -n "$tn" ] && [ -x "$tn" ]; then
  case $here in
    *"'"*) ("$tn" -title "$title" -message "$message" -group "context-threshold-notify:$sid" >/dev/null 2>&1 &) ;;
    *) ("$tn" -title "$title" -message "$message" -group "context-threshold-notify:$sid" \
         -execute "${app}'$here/focus-tab.sh' '$focus'" >/dev/null 2>&1 &) ;;
  esac
else
  (osascript -e "display notification \"$message\" with title \"$title\"" >/dev/null 2>&1 &)
fi
exit 0
