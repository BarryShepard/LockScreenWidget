#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/build/Mice.app"
if [[ "${1:-}" != "--skip-build" ]]; then
  bash "$PROJECT_DIR/scripts/test.sh"
  bash "$PROJECT_DIR/scripts/build.sh" --universal
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
OUTPUT="$PROJECT_DIR/build/Distribution"
mkdir -p "$OUTPUT"
STAGE="$(mktemp -d "$PROJECT_DIR/build/package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
FOLDER="$STAGE/Mice-$VERSION"
mkdir -p "$FOLDER"
/usr/bin/ditto "$APP_DIR" "$FOLDER/Mice.app"
cp "$PROJECT_DIR/docs/distribution/Read-me-ru.txt" "$FOLDER/Прочитать перед запуском.txt"
ln -s /Applications "$FOLDER/Applications"
/usr/bin/codesign --verify --deep --strict "$FOLDER/Mice.app"
/usr/bin/lipo "$FOLDER/Mice.app/Contents/MacOS/Mice" -verify_arch arm64 x86_64
ZIP="$OUTPUT/Mice-$VERSION-universal.zip"
DMG="$OUTPUT/Mice-$VERSION-universal.dmg"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$FOLDER" "$ZIP"
/usr/bin/hdiutil create -volname "Mice $VERSION" -srcfolder "$FOLDER" -ov -format UDZO "$DMG"
/usr/bin/hdiutil verify "$DMG"
(cd "$OUTPUT" && /usr/bin/shasum -a 256 "Mice-$VERSION-universal.zip" "Mice-$VERSION-universal.dmg" > SHA256SUMS.txt)
printf 'ZIP: %s\nDMG: %s\nSignature: ad-hoc, not notarized\n' "$ZIP" "$DMG"
