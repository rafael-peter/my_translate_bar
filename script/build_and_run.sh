#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="TranslateBar"
BUNDLE_ID="com.mytranslatebar.app"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
# Supply an existing Apple Development / Developer ID identity for permissions
# that survive code changes. The default remains local ad-hoc signing.
TRANSLATEBAR_SIGNING_IDENTITY="${TRANSLATEBAR_SIGNING_IDENTITY:--}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify) ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac

# Only stop this project's staged executable, never the installed reference app.
pkill -f "^${APP_BINARY}$" >/dev/null 2>&1 || true
cd "$ROOT_DIR"
if [[ "$MODE" == "--debug" || "$MODE" == "debug" ]]; then BUILD_CONFIGURATION="debug"; fi
swift build --configuration "$BUILD_CONFIGURATION"
BUILD_DIR="$(swift build --configuration "$BUILD_CONFIGURATION" --show-bin-path)"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_CONTENTS/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_BINARY"
for bundle in "$BUILD_DIR"/*.bundle; do
  [ -d "$bundle" ] || continue
  cp -R "$bundle" "$APP_CONTENTS/Resources/"
done
cp "$ROOT_DIR/Resources/AppInfo.plist" "$APP_CONTENTS/Info.plist"

# Sign the completed bundle, including its identifier and resources. Do not
# replace the designated requirement with identifier-only rules: macOS must
# still verify who signed a future version before carrying permissions over.
/usr/bin/codesign --force --sign "$TRANSLATEBAR_SIGNING_IDENTITY" \
  --identifier "$BUNDLE_ID" "$APP_BUNDLE"
/usr/bin/codesign --verify --strict "$APP_BUNDLE"

open_app() { /usr/bin/open -n "$APP_BUNDLE"; }
case "$MODE" in
  run) open_app ;;
  --debug|debug) lldb -- "$APP_BINARY" ;;
  --logs|logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry|telemetry) open_app; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --verify|verify) open_app; sleep 2; pgrep -f "^${APP_BINARY}$" >/dev/null ;;
esac
