#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/build/ModuleCache"
/usr/bin/swiftc -module-cache-path "$PROJECT_DIR/build/ModuleCache" \
  "$PROJECT_DIR/Sources/Core.swift" "$PROJECT_DIR/Tests/CoreTests.swift" -o "$PROJECT_DIR/build/CoreTests"
"$PROJECT_DIR/build/CoreTests" "$PROJECT_DIR/Resources/events.json"
/usr/bin/swiftc -swift-version 5 -module-cache-path "$PROJECT_DIR/build/ModuleCache" \
  -framework AppKit -framework CoreText "$PROJECT_DIR/Sources/Core.swift" \
  "$PROJECT_DIR/Sources/CountdownView.swift" "$PROJECT_DIR/Tests/LayoutTests.swift" \
  -o "$PROJECT_DIR/build/LayoutTests"
"$PROJECT_DIR/build/LayoutTests" "$PROJECT_DIR"
