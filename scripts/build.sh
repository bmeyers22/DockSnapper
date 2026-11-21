#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="build/DockSnapper.app"
mkdir -p "$app/Contents/MacOS" build/module-cache
arch="$(uname -m)"
xcrun swiftc -swift-version 5 -O -target "${arch}-apple-macos14.0" -module-cache-path build/module-cache Sources/*.swift -o "$app/Contents/MacOS/DockSnapper"
cp Info.plist "$app/Contents/Info.plist"
identity="${SIGN_IDENTITY:--}"
if [[ "$identity" == "-" ]]; then
  codesign --force --sign - "$app"
else
  codesign --force --timestamp --options runtime --sign "$identity" "$app"
fi
codesign --verify --strict "$app"
echo "$PWD/$app"
