#!/bin/sh
# Usage: [FOCUS_APP=<bundle id>] focus-tab.sh ITERM_SESSION_UUID|/dev/ttysNNN — front the iTerm2 or Terminal.app tab, else FOCUS_APP.
[ -n "$1" ] || { echo "usage: focus-tab.sh SESSION_ID|TTY" >&2; exit 2; }
target=$1

if [ "$(osascript -e 'application "iTerm2" is running' 2>/dev/null)" = true ]; then
  out=$(osascript - "$target" <<'EOS'
on run argv
  set sid to item 1 of argv
  tell application "iTerm2"
    repeat with w in (get windows)
      repeat with t in (get tabs of w)
        try
          set s to (first session of t whose id is sid or tty is sid)
          select w
          tell t to select
          tell s to select
          activate
          return "ok"
        end try
      end repeat
    end repeat
  end tell
  return ""
end run
EOS
)
  [ "$out" = ok ] && exit 0
fi

case $target in
  /dev/*)
    if [ "$(osascript -e 'application "Terminal" is running' 2>/dev/null)" = true ]; then
      out=$(osascript - "$target" <<'EOS'
on run argv
  set want to item 1 of argv
  tell application "Terminal"
    repeat with w in windows
      repeat with t in tabs of w
        if tty of t is want then
          set selected of t to true
          set index of w to 1
          activate
          return "ok"
        end if
      end repeat
    end repeat
  end tell
  return ""
end run
EOS
)
      [ "$out" = ok ] && exit 0
    fi
    ;;
esac

[ -n "${FOCUS_APP:-}" ] && open -b "$FOCUS_APP" && exit 0
echo "focus-tab: no iTerm2 or Terminal.app tab matches $1${FOCUS_APP:+, and $FOCUS_APP could not be opened}" >&2
exit 1
