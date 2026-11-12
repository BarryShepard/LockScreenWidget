# Native editor transforms implementation plan

> **For agentic workers:** Use subagent-driven-development to execute this bounded stage, with one implementation task and independent code review.

**Goal:** Add direct resize, rotation and image crop gestures to the native canvas, following editor-spec.md sections 5, 7 and 8.

**Architecture:** Keep Foundation document models backward compatible, transformation mathematics in focused controller helpers, and AppKit views limited to presentation and input forwarding. Every gesture previews from its initial snapshot, commits once, and cancels with Escape.

**Tech Stack:** Swift 5, AppKit, existing swiftc scripts; macOS 15+.

## Global constraints

- Work in the existing checkout and branch codex/personal-lockscreen-editor, following the project's declared preference. Baseline 54695b7; previous turn verified all suites and universal build.
- Preserve the feature-based MVC structure integrated in PR #2, scene schema compatibility, asset originals, legacy countdown behavior and native editing commands.
- Never use personal scene storage or general clipboard for tests. Never lock the computer, push, publish or merge remotely.
- Notes, timers and superellipse design are separate later stages. Existing rounded corner style remains.
- Multi-selection Shift resizing of differently rotated elements is explicitly deferred by spec P02; show why when unavailable, rather than approximating shear.

## Task 1: Direct canvas transforms

**Files:** New focused Sources/Features/SceneEditor/Controllers/SceneTransformController.swift (or similarly named helpers); modify SceneCanvasController.swift, SceneCanvasView.swift, optional backward-compatible text transform fields in Sources/Shared/Scene/Models/SceneModel.swift; update Shared/Scene/Controllers/SceneTextLayout.swift and ScenePresentationController.swift and Shared/Scene/Rendering/SceneRenderer.swift as needed; Tests/SceneEditingTests.swift, Tests/SceneTests.swift and docs.

**Interfaces:** Consume SceneSnapshot, SceneEditingStateModel.preview/finish, SceneGeometry, viewport conversion, existing model frame/rotation/imageRect and renderer presentation. Produce deterministic transformation math and gesture routing; views consume handle positions and cursor regions from controller presentation. No model reads in views.

- [x] Add regression tests for rotated single-element opposite anchor resizing, proportional edge/corner resize, Shift stretch, minimum positive size; group uniform resize and center rotation; crop all edge/corners including rotated images while preserving original image canvas coordinates and asset bytes; no-op and Escape history; one Undo per gesture; old JSON decoding of optional text transforms.
- [x] Implement geometry from original snapshot and pointer delta (no initial jump), proportional resize by default and Shift stretch; preserve image crop on resize and scale radius by smaller factor. Prevent flipping/negative sizes. Group scale must preserve relative centers and rotation, group rotation orbits centers and adds angle.
- [x] Support saved anisotropic text display scale separately from original style so resizing does not silently reflow ordinary text. Ensure rendering and entering/editing text use consistent coordinates and persistence. Editing side edges change layout width without changing font size. Preserve marked text behavior and existing history.
- [x] Add edge and corner resize targets, outside-corner rotation targets, visible handles and appropriate native cursor feedback. Capture Cmd crop mode at mouse down for a single image. Crop clamps to source coverage without resampling, translates frame and internal image coordinates together, preserves source position at any rotation. Existing double-click replacement and drag/marquee/Shift selection retain their behavior.
- [x] Use state.preview during gestures, state.finish(from:) once at completion, original snapshot restoration on Escape. Handle no-motion clicks, selection and keyboard focus consistently. Keep gesture state separate from text/move states; unsupported multi-selection stretch should explain restriction inline.
- [x] Run bash scripts/test.sh (SceneEditingTests may need system private pasteboard access outside sandbox), bash scripts/build.sh --universal, signature/architecture and --diagnose checks, git diff --check. Do not claim live UI or secure-lock acceptance from tests.
- [x] Update README and handoff/checklist with implemented behavior, validation and remaining native manual checks. Record concise report for independent reviewer. No remote operations.

## Review and completion

- [x] Independent reviewer checks code and tests against this plan and editor-spec sections 5, 7, 8. Fix meaningful findings and rerun affected checks.
- [x] Summarize delivered stage and remaining manual checks; retain all changes locally for user review.

## Completion — 12 November 2026

Code through `8a58d57`. All six suites, universal build, signature and diagnostics pass. Independent stage review and scoped corrections accepted. Actual native UI checks confirm scaled/rotated editing, width reflow and chronological native Undo/Redo. Remaining manual environment checks are listed in `docs/native-editor-transforms-verification.md`. Work retained locally; no remote push/merge.
