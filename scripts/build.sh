#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/build/TEotW.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/Fonts" "$PROJECT_DIR/build/ModuleCache"
test -f "$PROJECT_DIR/Resources/Fonts/Manrope.ttf"
ARCHITECTURES=(arm64)
if [[ "${1:-}" == "--universal" ]]; then
  ARCHITECTURES=(arm64 x86_64)
elif [[ -n "${1:-}" ]]; then
  printf 'Usage: %s [--universal]\n' "$0" >&2
  exit 2
fi
BINARIES=()
for architecture in "${ARCHITECTURES[@]}"; do
  binary="$PROJECT_DIR/build/TEotW-$architecture"
  /usr/bin/swiftc -swift-version 5 -O -module-cache-path "$PROJECT_DIR/build/ModuleCache" \
    -target "$architecture-apple-macosx15.0" -framework AppKit -framework CoreText -framework CoreGraphics \
    "$PROJECT_DIR"/Sources/Models/*.swift "$PROJECT_DIR"/Sources/Views/*.swift \
    "$PROJECT_DIR"/Sources/Controllers/*.swift "$PROJECT_DIR"/Sources/Infrastructure/*.swift \
    "$PROJECT_DIR"/Sources/Scene*.swift \
    "$PROJECT_DIR/Sources/AppDelegate.swift" "$PROJECT_DIR/Sources/main.swift" \
    -o "$binary"
  BINARIES+=("$binary")
done
/usr/bin/lipo -create "${BINARIES[@]}" -output "$APP_DIR/Contents/MacOS/TEotW"
/usr/bin/swiftc -swift-version 5 -module-cache-path "$PROJECT_DIR/build/ModuleCache" -framework AppKit \
  "$PROJECT_DIR/Sources/Views/StatusIcon.swift" "$PROJECT_DIR/scripts/GenerateIcon.swift" -o "$PROJECT_DIR/build/GenerateIcon"
"$PROJECT_DIR/build/GenerateIcon" "$PROJECT_DIR/build/AppIcon.iconset"
cp "$PROJECT_DIR/build/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Resources/events.json" "$APP_DIR/Contents/Resources/"
cp "$PROJECT_DIR/Resources/Fonts/Manrope.ttf" "$PROJECT_DIR/Resources/Fonts/OFL.txt" "$APP_DIR/Contents/Resources/Fonts/"
mkdir -p "$APP_DIR/Contents/Resources/Licenses"
cp "$PROJECT_DIR/Resources/Licenses/SkyLightWindow-MIT.txt" "$APP_DIR/Contents/Resources/Licenses/"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TEotW</string>
<key>CFBundleIdentifier</key><string>local.teotw.countdown</string>
<key>CFBundleName</key><string>Следующий конец света</string>
<key>CFBundleDisplayName</key><string>Следующий конец света</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$APP_DIR"
printf '%s\n' "$APP_DIR"
