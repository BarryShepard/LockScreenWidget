#!/bin/bash
set -euo pipefail
command -v dirname >/dev/null
command -v grep >/dev/null
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
failed=0
models=("$PROJECT_DIR"/Sources/Features/*/Models/*.swift
        "$PROJECT_DIR"/Sources/Shared/Models/*.swift
        "$PROJECT_DIR"/Sources/Shared/Scene/Models/*.swift)
# Include model helpers and types without a Model suffix.
model_symbols="$(sed -nE 's/^((private|fileprivate|internal|public|final) +)*(class|struct|enum|protocol|typealias|func) +([A-Za-z_][A-Za-z_0-9]*).*/\4/p' "${models[@]}")"
[[ -n "$model_symbols" ]]
view_dependencies="${model_symbols//$'\n'/|}|[[:alnum:]_]+(Model|Controller)|SceneStore|SceneTransfer|SceneTextLayout"

for source in "$PROJECT_DIR"/Sources/Features/*/Views/*.swift \
              "$PROJECT_DIR"/Sources/Shared/Views/*.swift \
              "$PROJECT_DIR"/Sources/Shared/Scene/Rendering/*.swift; do
  if grep -nE "(^|[^[:alnum:]_])($view_dependencies)([^[:alnum:]_]|$)" "$source"; then
    printf 'View depends on model or application logic: %s\n' "$source" >&2
    failed=1
  fi
done

for source in "${models[@]}"; do
  if grep -nE '^import (AppKit|Cocoa|SwiftUI)|(^|[^[:alnum:]_])([[:alnum:]_]+Controller|NSView|NSWindow|NSFont|NSColor|SceneStore|SceneTransfer)([^[:alnum:]_]|$)' "$source"; then
    printf 'Model depends on UI or application services: %s\n' "$source" >&2
    failed=1
  fi
done

if [[ "$failed" != 0 ]]; then exit 1; fi
printf 'MVC dependency checks passed.\n'
