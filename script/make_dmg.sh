#!/usr/bin/env bash
set -euo pipefail

APP_NAME="myDAY"
VOL_NAME="myDAY"
TEAM_ID="${APPLE_TEAM_ID:-G79WZ47SUC}"
DEVELOPER_ID_IDENTITY="${DEVELOPER_ID_IDENTITY:-Developer ID Application: Yushi Qian ($TEAM_ID)}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$ROOT_DIR/$APP_NAME.app}"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/$APP_NAME.dmg}"
STAGING_DIR=""
RW_DMG=""
DEVICE=""
MOUNT_POINT="/Volumes/$VOL_NAME"

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    /usr/bin/hdiutil detach "$DEVICE" -quiet >/dev/null 2>&1 || true
  fi
  if [[ -n "$STAGING_DIR" ]]; then
    /bin/rm -rf "$STAGING_DIR"
  fi
  if [[ -n "$RW_DMG" ]]; then
    /bin/rm -f "$RW_DMG"
  fi
}
trap cleanup EXIT

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
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
/usr/bin/xcrun stapler validate "$APP_BUNDLE"

STAGING_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/myDAY-dmg.XXXXXX")"
RW_DMG="$STAGING_DIR/$APP_NAME-rw.dmg"
BACKGROUND_DIR="$STAGING_DIR/background"
BACKGROUND_IMAGE="$BACKGROUND_DIR/background.png"

/bin/mkdir -p "$BACKGROUND_DIR"

/usr/bin/swift - "$BACKGROUND_IMAGE" <<'SWIFT'
import AppKit

let outputPath = CommandLine.arguments[1]
let canvas = NSSize(width: 760, height: 840)
let image = NSImage(size: canvas)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawRounded(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func drawChevronArrow(centerX: CGFloat, topY: CGFloat, bottomY: CGFloat) {
    let stem = NSBezierPath()
    stem.move(to: NSPoint(x: centerX, y: topY))
    stem.line(to: NSPoint(x: centerX, y: bottomY + 45))
    stem.lineWidth = 28
    stem.lineCapStyle = .butt
    color(255, 255, 255, 1).setStroke()
    stem.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: centerX - 72, y: bottomY + 58))
    head.line(to: NSPoint(x: centerX, y: bottomY))
    head.line(to: NSPoint(x: centerX + 72, y: bottomY + 58))
    head.close()
    color(255, 255, 255, 1).setFill()
    head.fill()
}

image.lockFocus()

color(255, 255, 255).setFill()
NSRect(origin: .zero, size: canvas).fill()

let folderRect = NSRect(x: 150, y: 82, width: 460, height: 294)
let tabRect = NSRect(x: 150, y: 340, width: 168, height: 66)
let tabCut = NSRect(x: 276, y: 340, width: 62, height: 32)
let folderColor = color(221, 227, 249, 0.76)

drawRounded(tabRect, radius: 7, fill: folderColor)
color(255, 255, 255).setFill()
NSBezierPath(rect: tabCut).fill()
drawRounded(folderRect, radius: 8, fill: folderColor)
drawChevronArrow(centerX: 380, topY: 470, bottomY: 350)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath))
SWIFT

/usr/bin/hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
/bin/rm -f "$DMG_PATH"
/usr/bin/hdiutil create "$RW_DMG" -volname "$VOL_NAME" -size 96m -fs HFS+ -ov -quiet
DEVICE="$(/usr/bin/hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen | /usr/bin/awk '/Apple_HFS/ {print $1; exit}')"

if [[ -z "$DEVICE" || ! -d "$MOUNT_POINT" ]]; then
  echo "failed to mount temporary dmg" >&2
  exit 1
fi

/usr/bin/ditto --norsrc --noextattr "$APP_BUNDLE" "$MOUNT_POINT/$APP_NAME.app"
/bin/ln -s /Applications "$MOUNT_POINT/Applications"
/bin/mkdir -p "$MOUNT_POINT/.background"
/bin/cp "$BACKGROUND_IMAGE" "$MOUNT_POINT/.background/background.png"
/bin/cp "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
/usr/bin/SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
/usr/bin/SetFile -a V "$MOUNT_POINT/.background" "$MOUNT_POINT/.VolumeIcon.icns" 2>/dev/null || true

/usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 80, 880, 920}
    set theOptions to icon view options of container window
    set arrangement of theOptions to not arranged
    set icon size of theOptions to 128
    set background picture of theOptions to file ".background:background.png"
    set position of item "$APP_NAME.app" to {380, 210}
    set position of item "Applications" to {380, 610}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

/bin/sync
/usr/bin/hdiutil detach "$DEVICE" -quiet
DEVICE=""

/usr/bin/hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" \
  -ov \
  -quiet

/usr/bin/xattr -cr "$DMG_PATH"
/usr/bin/codesign --force --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$DMG_PATH"
/usr/bin/hdiutil verify "$DMG_PATH" -quiet
/usr/bin/codesign --verify --verbose=2 "$DMG_PATH"

echo "$DMG_PATH"
