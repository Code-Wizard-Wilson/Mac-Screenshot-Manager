#!/usr/bin/env bash
# Build an optimized, signed .app using Command Line Tools; full Xcode is optional.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d /private/tmp/screenshot-manager-build.XXXXXX)"
APP="$BUILD_DIR/Screenshot Manager.app"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-Screenshot Manager Local Development}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_DIR/AppIcon.iconset"

swiftc -swift-version 6 -O -target "$(uname -m)-apple-macosx14.0" \
  "$ROOT"/ScreenshotManager/*.swift -o "$APP/Contents/MacOS/ScreenshotManager"
cp "$ROOT/scripts/LocalApp-Info.plist" "$APP/Contents/Info.plist"
for size in 16 32 128 256 512; do
  cp "$ROOT/ScreenshotManager/Assets.xcassets/AppIcon.appiconset/app-icon-$size.png" \
    "$BUILD_DIR/AppIcon.iconset/icon_${size}x${size}.png"
  cp "$ROOT/ScreenshotManager/Assets.xcassets/AppIcon.appiconset/app-icon-$size@2x.png" \
    "$BUILD_DIR/AppIcon.iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
ditto --norsrc --noextattr "$ROOT/ScreenshotManager/Resources/DeviceBezels" "$APP/Contents/Resources/DeviceBezels"
xattr -cr "$APP"
if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGN_IDENTITY\""; then
  SIGN_IDENTITY="-"
fi
codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
printf 'Built app: %s\n' "$APP"

if [[ "${1:-}" == "--install" ]]; then
  DESTINATION="/Applications/Screenshot Manager.app"
  if [[ -e "$DESTINATION" ]]; then
    EXISTING_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")
    [[ "$EXISTING_ID" == "com.herpojmi365.screenshotmanager" ]] || { echo "Unexpected app at destination" >&2; exit 1; }
  fi
  # Refuse replacement while any version is running; the caller can close it first.
  if pgrep -x ScreenshotManager >/dev/null; then
    echo "Quit Screenshot Manager, then install with: bash scripts/install-local-app.sh '$APP'" >&2
    exit 2
  fi
  bash "$ROOT/scripts/install-local-app.sh" "$APP"
fi
