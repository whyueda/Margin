#!/bin/bash
# Publishes a new version: builds dist/Margin-<version>.dmg and puts it on GitHub as a release.
# Raise CFBundleShortVersionString (and CFBundleVersion) in build.sh first. Margin's daily update
# check reads the newest release and offers its .dmg to everyone on an older version.
# Usage: ./release.sh ["Release notes"]
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(sed -n 's/.*CFBundleShortVersionString<\/key><string>\([^<]*\).*/\1/p' build.sh)
NOTES="${1:-Margin $VERSION}"
if gh release view "v$VERSION" >/dev/null 2>&1; then
  echo "Release v$VERSION already exists. Raise the version in build.sh first."; exit 1
fi
./make_installer.sh
gh release create "v$VERSION" "dist/Margin-$VERSION.dmg" --title "Margin $VERSION" --notes "$NOTES"
