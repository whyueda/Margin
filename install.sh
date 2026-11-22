#!/bin/bash
# Builds Margin and installs it as the one copy in /Applications, replacing the old one, then opens it.
# Notes and settings live outside the app, so they are kept. Every other copy the system remembers
# (the build folder, mounted or long-gone installer disks) is forgotten, so Spotlight, Launchpad and
# "Open With" only ever show the installed Margin.
set -euo pipefail
cd "$(dirname "$0")"
DEST=/Applications/Margin.app
ID=local.margin.notes
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

LOG=$(mktemp)
./build.sh >/dev/null 2>"$LOG" || { cat "$LOG"; rm -f "$LOG"; exit 1; }
rm -f "$LOG"
echo "Built $(defaults read "$(pwd)/.build/Margin.app/Contents/Info" CFBundleShortVersionString)."

# Quit whichever Margin is running (only one may run at a time).
if pgrep -qf "Margin.app/Contents/MacOS/Margin"; then
  osascript -e "tell application id \"$ID\" to quit" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -qf "Margin.app/Contents/MacOS/Margin" || break; sleep 0.5; done
  pkill -f "Margin.app/Contents/MacOS/Margin" 2>/dev/null || true
fi

rm -rf "$DEST"
ditto .build/Margin.app "$DEST"

# Forget every other copy, then make sure the installed one is the one the system knows.
"$LSREG" -dump 2>/dev/null | sed -n 's/^path: *\(.*Margin[^ ]*\.app\) (0x[0-9a-f]*)$/\1/p' | sort -u | while read -r p; do
  [ "$p" = "$DEST" ] || "$LSREG" -u "$p" >/dev/null 2>&1 || true
done
"$LSREG" -f "$DEST" >/dev/null 2>&1 || true

open "$DEST"
echo "Installed and opened $DEST"
