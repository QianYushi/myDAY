#!/usr/bin/env bash
set -euo pipefail

APP_NAME="myDAY"
TEAM_ID="${APPLE_TEAM_ID:-G79WZ47SUC}"
DEVELOPER_ID_IDENTITY="${DEVELOPER_ID_IDENTITY:-Developer ID Application: Yushi Qian ($TEAM_ID)}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$ROOT_DIR/$APP_NAME.app}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-$ROOT_DIR/$APP_NAME.entitlements}"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "missing app bundle: $APP_BUNDLE" >&2
  exit 1
fi

clean_app_metadata() {
  /usr/bin/SetFile -a b "$APP_BUNDLE" 2>/dev/null || true
  /usr/bin/xattr -cr "$APP_BUNDLE"
  /usr/bin/xattr -d com.apple.FinderInfo "$APP_BUNDLE" 2>/dev/null || true
  /usr/bin/xattr -d "com.apple.fileprovider.fpfs#P" "$APP_BUNDLE" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.macl "$APP_BUNDLE" 2>/dev/null || true
}

clean_app_metadata

CODESIGN_ARGS=(
  --force
  --options runtime
  --timestamp
  --sign "$DEVELOPER_ID_IDENTITY"
)

if [[ -f "$ENTITLEMENTS_PATH" ]]; then
  CODESIGN_ARGS+=(--entitlements "$ENTITLEMENTS_PATH")
fi

/usr/bin/codesign "${CODESIGN_ARGS[@]}" "$APP_BUNDLE"
clean_app_metadata
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
/usr/bin/codesign -dvvv "$APP_BUNDLE" 2>&1 | /usr/bin/sed -n '1,22p'

echo "$APP_BUNDLE"
