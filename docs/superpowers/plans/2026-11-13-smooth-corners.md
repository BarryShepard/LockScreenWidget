# Smooth corners Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add native continuous corners and a canvas radius handle for every scene element.

**Architecture:** A shared rendering helper produces the native SwiftUI continuous rounded-rectangle CGPath. Controllers clamp logical-point radii and resolve a distinct inside-frame drag handle. Presentations carry only primitive geometry to views; the same shape clips static rendering and native text editing.

**Tech Stack:** Swift 5, AppKit/CoreGraphics, SwiftUI Shape path; macOS 15+, no packages.

## Global Constraints

- Preserve user scenes, README and AGENTS. Existing checkout, branch `codex/smooth-corners`.
- Radius is shared across four corners, clamped to half the smaller side. Zero has square corners. Group input applies the value separately clamped to each leaf.
- Notes retain logical-point radius when resized, bounded by the new size. Other elements scale radius with the smaller scale. Cmd crop preserves the radius while it fits.
- One drag = one Undo; Escape restores the entire starting snapshot. No automatic Mac lock.
- Final shape needs user visual acceptance; HTML polygons are not the reference. Use the system continuous shape directly.

### Task 1: Shared native clipping

**Files:** Create `Sources/Shared/Scene/Rendering/SceneCornerPath.swift`; modify `SceneRenderer.swift`, `SceneModel.swift`, `SceneCanvasView.swift`, `SceneCanvasController.swift`.

- [x] Add `SceneCornerPath.path(in:radius:) -> CGPath`, using `RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath` with bounds/zero handling.
- [x] Replace renderer's circular clip; apply the same shape as a layer mask to the transformed native text container so text, selection and caret stay clipped. Pass radius in the text-input presentation; convert the path by inverse text display scales.
- [x] Add `maximumCornerRadius` and `effectiveCornerRadius` computed properties without changing old scene JSON or silently resaving loaded files.

### Task 2: Inspector and geometry limits

**Files:** `SceneInspectorController.swift`, `SceneInspectorView.swift`, `SceneCountdownInspectorController.swift`, `SceneCountdownInspectorView.swift`, `SceneTransformController.swift`.

- [x] Move radius into common element fields. Remove duplicate countdown-specific radius editor. Display effective radii and mixed placeholders; apply finite nonnegative values to all selected leaves, clamped independently.
- [x] Clamp persisted radii after actual crop/resize and inspector size changes. Preserve zero/no-motion behavior and note typography.

### Task 3: Canvas handle

**Files:** Create `Sources/Features/SceneEditor/Controllers/SceneCornerController.swift`; modify `SceneCanvasController.swift`, `SceneCanvasView.swift`.

- [x] Resolve an inside-frame circular marker on the frontmost selected leaf. Use fixed screen-space inset and reject small frames/conflicts with resize/rotation hit areas.
- [x] Compute radius from the initial snapshot and pointer delta in the leaf's unrotated coordinates. For mixed selection use the marker leaf as the initial radius and apply the requested common value to every selected leaf.
- [x] Preview without saving/history; commit one gesture, support Escape and no-motion. Show live radius badge and hide handle during native text editing/text tool.

### Task 4: Validation and delivery

**Files:** `Tests/SceneEditingTests.swift`, project docs and a new native verification report.

- [x] Cover native-path bounds, zero, clamp, symmetry; all-kind/mixed radius editing, crop/resize limits, rotated handle and hit separation, preview/Undo/Redo/Escape, save/reload and native text-mask coordinates.
- [x] Run focused scene editing checks during implementation. One scoped reviewer before final checks; fix important findings.
- [x] Run full suite and universal build once on final sources, strict signature/architecture/diagnose/diff checks. Repeat only for failures or material changes.
- [x] Native smoke in a new isolated scene: numeric field, circular marker, Undo, native input and persistence. Preserve existing QA documents; visual acceptance on protected screen remains a user step.
- [x] Record result in backlog/continuation. UI redesign and display work remain deferred; exact group nonproportional transforms are a separate next task.


## Delivery record

One implementer and one scoped reviewer. Review finding in native-width radius limiting repaired; native smoke also identified and repaired post-commit field normalization. Final seven suites, universal build, signature, architectures, diagnose and native QA passed. Details: `docs/native-smooth-corners-verification.md`. User visual acceptance of the continuous shape and actual protected-screen checks remain unclaimed.
