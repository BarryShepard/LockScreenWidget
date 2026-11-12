# Native notes verification

Task 1 adds note layers; countdown layers are a separate task. Notes use optional `SceneNoteModel` payloads and schema version 1. Missing payload resolves to the default background and 16 pt padding. `SceneElementKind.hasEditableText`, `hasTypography`, and `isImage` separate capabilities for future layer types. `SceneTextLayout.contentRect` and `overflows` provide shared padded geometry.

Automated coverage in `SceneTests` checks note defaults, JSON round trips, invalid padding and color, fixed frame during fitting, and overflow. `SceneEditingTests.nativeNote` checks padded native coordinates with rotation and viewport scaling, prepared background, background rendering while editing, fixed frame during input, width gesture and native/scene history, and note style invariants during proportional and Shift resize. Existing tests cover IME handling and generic scene transfer and history.

Manual visual verification and real lock-screen testing have not been performed as part of this implementation. In particular, the automated coordinate test checks transformed native glyph bounds and padding; it does not claim a pixel comparison of AppKit glyph rasterization against the renderer.

On 2026-11-12, the focused scene editor suite and `bash scripts/test.sh` passed with host access for private pasteboards. `bash scripts/build.sh --universal` succeeded; `codesign --verify --deep --strict` passed, and `lipo -archs` reported `x86_64 arm64`. `--diagnose` completed with 58 events, 19 countdowns and 39 period cards. The full suite logged an AppKit constraint-limit warning during the existing lock-screen controller tests.

Review fixes add native input clipping to the note content box, independent fixed insets on each axis, and correct provisional creation handling across width gestures. Focused note tests cover glyph bitmap clipping, creation checkpoints and Undo/Redo, copy and duplicate payloads, and marked-only provisional input. Full suite, universal build, strict signature, architecture and diagnose checks passed again; actual rotated-window pixel comparison and isolated UI smoke remain separate checks.
