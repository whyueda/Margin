#!/bin/bash
# Makes dist/Margin-<version>.dmg: a disk image with Margin and a shortcut to Applications to drag it onto.
# The app inside runs on Apple silicon and Intel Macs, macOS 13 and later.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(sed -n 's/.*CFBundleShortVersionString<\/key><string>\([^<]*\).*/\1/p' build.sh)
NAME="Margin"
OUT="dist/$NAME-$VERSION.dmg"
WORK=$(mktemp -d)
MNT=""
trap '[ -n "$MNT" ] && hdiutil detach "$MNT" -quiet -force 2>/dev/null; rm -rf "$WORK"' EXIT
# Finder only lays out a disk mounted in /Volumes, under the name the installer window shows.
if [ -e "/Volumes/$NAME" ]; then echo "Eject the disk named \"$NAME\" first (it is in the way)."; exit 1; fi

echo "Building $NAME $VERSION for Apple silicon and Intel…"
APP="$WORK/stage/$NAME.app" UNIVERSAL=1 ./build.sh >/dev/null
lipo -archs "$WORK/stage/$NAME.app/Contents/MacOS/$NAME"

echo "Drawing the window background…"
mkdir -p "$WORK/stage/.background"
swift tools/make_dmg_background.swift "$WORK/bg.png" 1 2>/dev/null
swift tools/make_dmg_background.swift "$WORK/bg@2x.png" 2 2>/dev/null
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$WORK/stage/.background/background.tiff" 2>/dev/null
ln -s /Applications "$WORK/stage/Applications"

echo "Making the disk image…"
hdiutil create -quiet -srcfolder "$WORK/stage" -volname "$NAME" -fs HFS+ -format UDRW -size 60m "$WORK/rw.dmg"
MNT=$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" 2>/dev/null | awk -F'\t' '/\/Volumes\//{print $NF}')
[ "$MNT" = "/Volumes/$NAME" ] || { echo "The disk image mounted at an unexpected place: $MNT"; exit 1; }
SetFile -a V "$MNT/.background"

# Window layout (icon places, size, background). Finder writes it into the image's .DS_Store.
if osascript <<OSA
tell application "Finder"
  set d to disk "$NAME"
  open d
  delay 2
  set w to container window of d
  set current view of w to icon view
  try
    set toolbar visible of w to false
  end try
  try
    set statusbar visible of w to false
  end try
  set bounds of w to {200, 120, 840, 568}
  set o to icon view options of w
  set arrangement of o to not arranged
  set icon size of o to 112
  set text size of o to 13
  set background picture of o to file ".background:background.tiff" of d
  set position of item "$NAME.app" of d to {170, 206}
  set position of item "Applications" of d to {470, 206}
  update d without registering applications
  delay 1
  try
    close w
  end try
end tell
OSA
then echo "Window layout set."
else echo "Note: Finder would not lay out the window (Automation permission?); the image still works, just without the background."
fi
# The disk's own icon goes in last: Finder removes it while laying out the window.
cp AppIcon.icns "$MNT/.VolumeIcon.icns"
SetFile -a V "$MNT/.VolumeIcon.icns"
SetFile -a C "$MNT"
sync
sleep 1
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Finder registers the app it just showed; forget that copy so only the installed one is known.
"$LSREG" -u "$MNT/$NAME.app" >/dev/null 2>&1 || true
hdiutil detach -quiet "$MNT"

mkdir -p dist
rm -f "$OUT"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"
# The staged copy was registered with the system while it was being built; forget it.
"$LSREG" -u "$WORK/stage/$NAME.app" >/dev/null 2>&1 || true
echo "Made $(pwd)/$OUT ($(du -h "$OUT" | cut -f1 | tr -d ' '))"
