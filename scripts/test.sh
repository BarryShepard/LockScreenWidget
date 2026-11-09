#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTC="${SWIFTC:-swiftc}"
mkdir -p "$PROJECT_DIR/build/ModuleCache"
COMMON=(-swift-version 5 -module-cache-path "$PROJECT_DIR/build/ModuleCache")
MODELS=("$PROJECT_DIR"/Sources/Models/*.swift)
"$SWIFTC" "${COMMON[@]}" "${MODELS[@]}" "$PROJECT_DIR/Tests/CoreTests.swift" -o "$PROJECT_DIR/build/CoreTests"
"$PROJECT_DIR/build/CoreTests" "$PROJECT_DIR/Resources/events.json"
"$SWIFTC" "${COMMON[@]}" "${MODELS[@]}" "$PROJECT_DIR/Tests/MemoryPreferences.swift" \
  "$PROJECT_DIR/Tests/SettingsTests.swift" -o "$PROJECT_DIR/build/SettingsTests"
"$PROJECT_DIR/build/SettingsTests"
if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'AppKit layout/controller tests require macOS; Foundation checks completed.\n'
  exit 0
fi
for suite in LayoutTests LockScreenControllerTests; do
  "$SWIFTC" "${COMMON[@]}" -framework AppKit -framework CoreText -framework CoreGraphics \
    "${MODELS[@]}" "$PROJECT_DIR"/Sources/Views/*.swift "$PROJECT_DIR"/Sources/Controllers/*.swift \
    "$PROJECT_DIR"/Sources/Infrastructure/*.swift "$PROJECT_DIR/Tests/MemoryPreferences.swift" \
    "$PROJECT_DIR/Tests/$suite.swift" -o "$PROJECT_DIR/build/$suite"
  "$PROJECT_DIR/build/$suite" "$PROJECT_DIR"
done
"$SWIFTC" "${COMMON[@]}" -framework AppKit \
  "$PROJECT_DIR/Sources/SceneModel.swift" "$PROJECT_DIR/Sources/SceneStore.swift" \
  "$PROJECT_DIR/Tests/SceneTests.swift" -o "$PROJECT_DIR/build/SceneTests"
"$PROJECT_DIR/build/SceneTests"
"$SWIFTC" "${COMMON[@]}" -framework AppKit "$PROJECT_DIR"/Sources/Scene*.swift \
  "$PROJECT_DIR/Tests/SceneEditingTests.swift" -o "$PROJECT_DIR/build/SceneEditingTests"
"$PROJECT_DIR/build/SceneEditingTests"
