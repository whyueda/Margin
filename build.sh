#!/bin/bash
# Builds Margin.app into .build/ next to this script. The folder is hidden so Spotlight, Launchpad and
# "Open With" only show the installed copy in /Applications.
set -euo pipefail
cd "$(dirname "$0")"
APP="${APP:-.build/Margin.app}"
rm -rf "$APP" Margin.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ "${UNIVERSAL:-}" = 1 ]; then
  # One app for both Apple silicon and Intel Macs, running on macOS 13 and later (used for the installer).
  T=$(mktemp -d)
  for a in arm64 x86_64; do swiftc -O -swift-version 5 -target $a-apple-macos13.0 -o "$T/Margin-$a" Sources/main.swift; done
  lipo -create "$T/Margin-arm64" "$T/Margin-x86_64" -output "$APP/Contents/MacOS/Margin"
  rm -rf "$T"
else
  swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/Margin" Sources/main.swift
fi
cp -R ui "$APP/Contents/Resources/ui"
if [ ! -f AppIcon.icns ]; then
  T=$(mktemp -d); mkdir "$T/AppIcon.iconset"
  swift tools/make_icon.swift "$T/icon.png"
  for sz in 16 32 128 256 512; do
    sips -z $sz $sz "$T/icon.png" --out "$T/AppIcon.iconset/icon_${sz}x${sz}.png" >/dev/null
    sips -z $((sz*2)) $((sz*2)) "$T/icon.png" --out "$T/AppIcon.iconset/icon_${sz}x${sz}@2x.png" >/dev/null
  done
  iconutil -c icns "$T/AppIcon.iconset" -o AppIcon.icns
  cp "$T/icon.png" icon-preview.png
  rm -rf "$T"
fi
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Margin</string>
  <key>CFBundleDisplayName</key><string>Margin</string>
  <key>CFBundleIdentifier</key><string>local.margin.notes</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>Margin</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$APP" >/dev/null 2>&1
# Forget this copy (and the old one next to the script) as an app the system offers to open things with.
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -u "$(pwd)/$APP" >/dev/null 2>&1 || true
"$LSREG" -u "$(pwd)/Margin.app" >/dev/null 2>&1 || true
echo "Built $(pwd)/$APP"
