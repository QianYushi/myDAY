#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="myDAY"
SCHEME_NAME="QuadrantDesktop"
APP_PATH="$ROOT_DIR/$APP_NAME.app"
OLD_APP_PATH="$ROOT_DIR/四象限.app"
DERIVED_DATA="${TMPDIR:-/tmp}/QuadrantDesktopDerivedData"
STAGED_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/QuadrantDesktopSource.XXXXXX")"
VALIDATION_APP="${TMPDIR:-/tmp}/$APP_NAME-build-validation.app"

cleanup() {
  rm -rf "$STAGED_ROOT"
  rm -rf "$VALIDATION_APP"
}
trap cleanup EXIT

clean_metadata() {
  local target="$1"
  /usr/bin/xattr -cr "$target" 2>/dev/null || true
  /usr/bin/xattr -dr com.apple.FinderInfo "$target" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.FinderInfo "$target" 2>/dev/null || true
  /usr/bin/xattr -d "com.apple.fileprovider.fpfs#P" "$target" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.macl "$target" 2>/dev/null || true
}

cd "$ROOT_DIR"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

rm -rf "$DERIVED_DATA"
rm -rf "$STAGED_ROOT/QuadrantDesktop.xcodeproj" "$STAGED_ROOT/QuadrantDesktop" "$STAGED_ROOT/Resources"
/usr/bin/ditto "$ROOT_DIR/QuadrantDesktop.xcodeproj" "$STAGED_ROOT/QuadrantDesktop.xcodeproj"
/usr/bin/ditto "$ROOT_DIR/QuadrantDesktop" "$STAGED_ROOT/QuadrantDesktop"
/usr/bin/ditto "$ROOT_DIR/Resources" "$STAGED_ROOT/Resources"
/usr/bin/xattr -cr "$STAGED_ROOT" || true

xcodebuild \
  -project "$STAGED_ROOT/QuadrantDesktop.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"

rm -rf "$APP_PATH"
if [[ "$OLD_APP_PATH" != "$APP_PATH" ]]; then
  rm -rf "$OLD_APP_PATH"
fi
/usr/bin/ditto --norsrc --noextattr "$BUILT_APP" "$APP_PATH"
clean_metadata "$APP_PATH"
/usr/bin/codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || true
clean_metadata "$APP_PATH"

/bin/rm -rf "$VALIDATION_APP"
/usr/bin/ditto --norsrc --noextattr "$APP_PATH" "$VALIDATION_APP"
for attempt in 1 2 3; do
  clean_metadata "$VALIDATION_APP"
  /usr/bin/codesign --force --deep --sign - "$VALIDATION_APP"
  clean_metadata "$VALIDATION_APP"
  if /usr/bin/codesign --verify --deep --strict --verbose=2 "$VALIDATION_APP"; then
    break
  fi
  if [[ "$attempt" == "3" ]]; then
    exit 1
  fi
  sleep 0.5
done

/usr/bin/plutil -lint "$APP_PATH/Contents/Info.plist"

echo "$APP_PATH"
