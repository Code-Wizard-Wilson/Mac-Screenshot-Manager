#!/usr/bin/env bash
# Install a verified build and retain a recoverable copy of the previous bundle.
set -euo pipefail
SOURCE="${1:?Pass the path of the built Screenshot Manager.app}"
DESTINATION="/Applications/Screenshot Manager.app"
BUNDLE_ID="com.herpojmi365.screenshotmanager"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
[[ "$SOURCE" != "$DESTINATION" ]] || { echo "Source must be a separate build" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$SOURCE/Contents/Info.plist")" == "$BUNDLE_ID" ]]
codesign --verify --deep --strict "$SOURCE"
if pgrep -x ScreenshotManager >/dev/null; then
  echo "Quit Screenshot Manager before installing." >&2
  exit 2
fi
STAGING="$(mktemp -d '/Applications/.screenshot-manager-install.XXXXXX')"
ditto --norsrc --noextattr "$SOURCE" "$STAGING/Screenshot Manager.app"
codesign --verify --deep --strict "$STAGING/Screenshot Manager.app"
if [[ -e "$DESTINATION" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")" == "$BUNDLE_ID" ]]
  mkdir -p "$HOME/Library/Application Support/Screenshot Manager"
  BACKUP_DIR="$(mktemp -d "$HOME/Library/Application Support/Screenshot Manager/Previous-build.XXXXXX")"
  ditto -c -k --keepParent "$DESTINATION" "$BACKUP_DIR/Screenshot Manager.zip"
  "$LSREGISTER" -u "$DESTINATION" || true
  mv "$DESTINATION" "$STAGING/previous.bundle"
fi
if ! mv "$STAGING/Screenshot Manager.app" "$DESTINATION"; then
  if [[ -d "$STAGING/previous.bundle" ]]; then mv "$STAGING/previous.bundle" "$DESTINATION"; fi
  exit 1
fi
"$LSREGISTER" -f "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
printf 'Installed: %s\n' "$DESTINATION"
printf 'Previous build: %s\n' "${BACKUP_DIR:-No previous installation}"
