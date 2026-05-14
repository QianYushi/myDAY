#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="myDAY"
SCHEME_NAME="QuadrantDesktop"
APP_PATH="$ROOT_DIR/$APP_NAME.app"
OLD_APP_PATH="$ROOT_DIR/四象限.app"
DERIVED_DATA="${TMPDIR:-/tmp}/QuadrantDesktopDerivedData"

cd "$ROOT_DIR"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

rm -rf "$DERIVED_DATA"

xcodebuild \
  -project "$ROOT_DIR/QuadrantDesktop.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"

rm -rf "$APP_PATH"
if [[ "$OLD_APP_PATH" != "$APP_PATH" ]]; then
  rm -rf "$OLD_APP_PATH"
fi
/usr/bin/ditto "$BUILT_APP" "$APP_PATH"
/usr/bin/xattr -cr "$APP_PATH" || true

for attempt in 1 2 3; do
  /usr/bin/xattr -dr com.apple.FinderInfo "$APP_PATH" 2>/dev/null || true
  /usr/bin/xattr -cr "$APP_PATH" || true
  /usr/bin/codesign --force --deep --sign - "$APP_PATH"
  /usr/bin/xattr -dr com.apple.FinderInfo "$APP_PATH" 2>/dev/null || true
  /usr/bin/xattr -cr "$APP_PATH" || true
  if /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"; then
    break
  fi
  if [[ "$attempt" == "3" ]]; then
    exit 1
  fi
  sleep 0.5
done

/usr/bin/plutil -lint "$APP_PATH/Contents/Info.plist"

echo "$APP_PATH"
