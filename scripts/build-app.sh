#!/bin/bash
# Builds build/Portfolio.app from the Swift package.
#   ./scripts/build-app.sh            build the app
#   ./scripts/build-app.sh --install  also move it into /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Portfolio 2>&1 | grep -v "xcrun: error: unable to lookup item 'PlatformPath'" || true
BIN="$(swift build -c release --show-bin-path 2>/dev/null)/Portfolio"
[ -x "$BIN" ] || { echo "✗ Build failed"; exit 1; }

APP=build/Portfolio.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Portfolio"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Ad-hoc signature: enough to run on this Mac (no Apple developer account
# needed). On its own, macOS identifies it by this exact build's fingerprint,
# so every rebuild looks like a different app; the fixed rule ("any build
# called local.portfolio.ibkr") makes every build the same app to macOS.
codesign --force --sign - --requirements '=designated => identifier "local.portfolio.ibkr"' "$APP"
echo "✓ Built $APP"

if [ "${1:-}" = "--install" ]; then
  # Moved, not copied: a second copy in build/ shows up as a second app in
  # Spotlight and Launchpad.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/$APP" 2>/dev/null || true
  rm -rf /Applications/Portfolio.app
  mv "$APP" /Applications/
  echo "✓ Installed to /Applications/Portfolio.app"
fi
