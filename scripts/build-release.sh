#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/DeskBox.xcodeproj"
SCHEME="DeskBox"
DERIVED="$ROOT_DIR/.build-release"
DIST="$ROOT_DIR/dist"

cd "$ROOT_DIR"

VERSION="$(
  xcodebuild     -project "$PROJECT"     -scheme "$SCHEME"     -configuration Release     -showBuildSettings 2>/dev/null   | awk '/MARKETING_VERSION =/ { print $3; exit }'
)"

BUILD_NUMBER="$(
  xcodebuild     -project "$PROJECT"     -scheme "$SCHEME"     -configuration Release     -showBuildSettings 2>/dev/null   | awk '/CURRENT_PROJECT_VERSION =/ { print $3; exit }'
)"

if [[ -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
  echo "Unable to read DeskBox version from Xcode project."
  exit 1
fi

echo "==> Building DeskBox $VERSION ($BUILD_NUMBER)"
echo "==> Target: macOS Universal (arm64 + x86_64)"

rm -rf "$DERIVED"
mkdir -p "$DIST"

xcodebuild   -project "$PROJECT"   -scheme "$SCHEME"   -configuration Release   -derivedDataPath "$DERIVED"   ARCHS="arm64 x86_64"   ONLY_ACTIVE_ARCH=NO   CODE_SIGNING_ALLOWED=NO   build

APP="$DERIVED/Build/Products/Release/DeskBox.app"
BINARY="$APP/Contents/MacOS/DeskBox"

if [[ ! -d "$APP" ]]; then
  echo "Release app was not produced."
  exit 1
fi

echo "==> Verifying Universal binary"
FOUND_ARCHS="$(lipo -archs "$BINARY")"

if [[ "$FOUND_ARCHS" != *"arm64"* || "$FOUND_ARCHS" != *"x86_64"* ]]; then
  echo "Universal architecture check failed: $FOUND_ARCHS"
  exit 1
fi

lipo -info "$BINARY"

echo "==> Verifying bundle metadata"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")
BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")

if [[ "$BUNDLE_ID" != "com.wfb.deskbox" ]]; then
  echo "Unexpected bundle ID: $BUNDLE_ID"
  exit 1
fi

if [[ "$BUILT_VERSION" != "$VERSION" || "$BUILT_BUILD" != "$BUILD_NUMBER" ]]; then
  echo "Version metadata mismatch."
  exit 1
fi

plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> Applying free ad-hoc signature"
xattr -cr "$APP" || true
codesign   --force   --deep   --sign -   --timestamp=none   "$APP"

codesign   --verify   --deep   --strict   --verbose=2   "$APP"

ZIP_NAME="DeskBox-v${VERSION}-macOS-universal.zip"
DMG_NAME="DeskBox-v${VERSION}-macOS-universal.dmg"
ZIP_PATH="$DIST/$ZIP_NAME"
DMG_PATH="$DIST/$DMG_NAME"

rm -f "$ZIP_PATH" "$DMG_PATH"

echo "==> Creating ZIP"
ditto   -c   -k   --sequesterRsrc   --keepParent   "$APP"   "$ZIP_PATH"

echo "==> Creating DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/DeskBox.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create   -volname "DeskBox $VERSION"   -srcfolder "$STAGE"   -ov   -format UDZO   "$DMG_PATH"   >/dev/null

echo "==> Verifying packaged files"
unzip -t "$ZIP_PATH" >/dev/null
hdiutil verify "$DMG_PATH" >/dev/null

echo ""
echo "DeskBox release package is ready:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo ""
echo "Bundle ID: $BUNDLE_ID"
echo "Version:   $BUILT_VERSION ($BUILT_BUILD)"
echo "Architectures:"
lipo -archs "$BINARY"
echo ""
echo "Note: this build is ad-hoc signed and not Apple-notarized."
echo "Users may need Finder > right-click DeskBox > Open on first launch."
