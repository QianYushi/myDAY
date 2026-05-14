#!/usr/bin/env bash
set -euo pipefail

APP_NAME="myDAY"
PROFILE_NAME="${NOTARY_PROFILE:-turnintoserver-notary}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$ROOT_DIR/$APP_NAME.app}"
SUBMISSION_ZIP_PATH="${SUBMISSION_ZIP_PATH:-$ROOT_DIR/$APP_NAME-notary.zip}"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "missing app bundle: $APP_BUNDLE" >&2
  exit 1
fi

cleanup() {
  /bin/rm -f "$SUBMISSION_ZIP_PATH"
}
trap cleanup EXIT

/usr/bin/xattr -cr "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

/bin/rm -f "$SUBMISSION_ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$SUBMISSION_ZIP_PATH"

/usr/bin/xcrun notarytool submit "$SUBMISSION_ZIP_PATH" \
  --keychain-profile "$PROFILE_NAME" \
  --wait

/usr/bin/xcrun stapler staple "$APP_BUNDLE"
/usr/bin/xcrun stapler validate "$APP_BUNDLE"
/usr/sbin/spctl -a -vvv --type exec "$APP_BUNDLE"

echo "$APP_BUNDLE"
