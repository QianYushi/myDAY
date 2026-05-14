#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="myDAY"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"
DMG_PATH="$ROOT_DIR/$APP_NAME.dmg"
MOUNT_DIR=""
SIGNED_APP_BUNDLE=""

cleanup() {
  if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
    /usr/bin/hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
    /bin/rm -rf "$MOUNT_DIR"
  fi
  if [[ -n "$SIGNED_APP_BUNDLE" && -d "$SIGNED_APP_BUNDLE" ]]; then
    /bin/rm -rf "$SIGNED_APP_BUNDLE"
  fi
}
trap cleanup EXIT

"$ROOT_DIR/script/build_app.sh"

SIGNED_APP_BUNDLE="${TMPDIR:-/tmp}/myDAY-release.app"
/bin/rm -rf "$SIGNED_APP_BUNDLE"
/usr/bin/ditto --norsrc --noextattr "$APP_BUNDLE" "$SIGNED_APP_BUNDLE"

APP_BUNDLE="$SIGNED_APP_BUNDLE" "$ROOT_DIR/script/sign_app.sh"
APP_BUNDLE="$SIGNED_APP_BUNDLE" "$ROOT_DIR/script/notarize_app.sh"
APP_BUNDLE="$SIGNED_APP_BUNDLE" DMG_PATH="$DMG_PATH" "$ROOT_DIR/script/make_dmg.sh"
DMG_PATH="$DMG_PATH" "$ROOT_DIR/script/notarize_dmg.sh"

MOUNT_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/myDAY-release-check.XXXXXX")"
/usr/bin/hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
/usr/bin/codesign --verify --deep --strict --verbose=2 "$MOUNT_DIR/$APP_NAME.app"
/usr/bin/xcrun stapler validate "$MOUNT_DIR/$APP_NAME.app"
/usr/sbin/spctl -a -vvv --type exec "$MOUNT_DIR/$APP_NAME.app"
/usr/bin/hdiutil detach "$MOUNT_DIR" -quiet
/bin/rm -rf "$MOUNT_DIR"
MOUNT_DIR=""

/usr/bin/shasum -a 256 "$DMG_PATH"
