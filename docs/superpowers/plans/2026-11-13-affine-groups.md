# Exact affine group resizing Implementation Plan

> **For agentic workers:** Execute inline, task by task, with one agent under AGENTS.md. Steps use checkbox syntax for tracking.

**Goal:** Resize groups and multiple selections exactly without Shift, including sheared rotated leaves and their contents.

**Architecture:** Add an optional positive-determinant local linear transform around each leaf center. Keep existing frame, rotation, typography and image crop semantics; group stretch composes a canvas scale into that transform instead of approximating rotated rectangles. Shared rendering, selection and native editing consume the same map. Native text uses two nested AppKit views to express rotation–scale–rotation, including coordinate conversion for caret and mouse events.

**Tech Stack:** Swift 5, Foundation, AppKit, existing swiftc scripts; macOS 15+.

## Global Constraints

- Existing checkout; preserve user README, AGENTS.md and all user scenes. One implementer and one scoped reviewer required by requesting-code-review; no remote operations or automatic screen lock.
- User chose exact stretch including contents on 13 November. A rotated rectangle may become a parallelogram; notes stretch as part of the group, while individual note resizing retains reflow.
- Shift and Option resizing remain uniform; default resizing is free. No reflections or negative dimensions. Numeric group size retains existing uniform behavior.
- Backward-compatible optional JSON field; preview from starting snapshot, one Undo per gesture, Escape restores.

### Task 1: Document geometry and group transformation

**Files:** SceneModel.swift; new Shared/Scene/Models/SceneLinearTransformModel.swift; SceneEditingStateModel.swift; SceneTransformController.swift; SceneCornerController.swift; Tests/SceneEditingTests.swift; new Tests/SceneAffineChecks.swift; scripts/test.sh.

**Interfaces:** `SceneElementModel.localVector(_:)` maps a local vector through residual and rotation; `localPoint(_:)` maps local top-left coordinates to canvas; `inverseVector(_:)` maps canvas deltas back. Optional `linearTransform` stores four finite coefficients with finite inverse and positive determinant.

- [x] Add regression: for each original corner `p`, group stretch anchored at `a` must produce `a + diag(sx,sy)*(p-a)` within 1e-7, including a second stretch and undo/redo.
- [x] Add optional transform validation and identity fallback. Geometry corners and SAT normals use transformed parallelogram edges.
- [x] Compose group residual as `R(-rotation) * diag(sx,sy) * R(rotation) * oldResidual`; map centers through group scale; preserve local content and asset references.
- [x] Route individual resize, crop, handles and radius gestures through forward/inverse maps; retain local scaling and note reflow.
- [x] Run focused SceneEditingTests including persistence, invalid matrices, hit testing and gesture cancellation.

### Task 2: Shared rendering and native text

**Files:** SceneRenderer.swift; ScenePresentationController.swift; SceneCanvasView.swift; SceneCanvasController.swift; Tests/SceneAffineChecks.swift.

**Interfaces:** Presentations pass primitive `CGAffineTransform` values to views; no model dependency in views. Native view decomposition satisfies `M = R(theta) * diag(s1,s2) * R(phi)` with positive singular values.

- [x] Concatenate residual after rotation and before local-origin translation in the shared renderer.
- [x] Remove obsolete unsupported-group-stretch badge.
- [x] Match native input geometry with nested view transforms, preserve logical mask and native text history. Invert element map for native width gestures.
- [x] Assert converted native input corners/glyphs match shared geometry at multiple viewport sizes, after editing/reflow and reopening. Assert private pasteboard round trip retains transform.
- [x] Verify rendered content bounds and clipping using synthetic raster output; use no personal assets or general clipboard.

### Task 3: Delivery

**Files:** docs/editor-spec.md; docs/continuation.md; docs/backlog.md; new docs/native-affine-groups-verification.md; this plan.

- [x] Self-review changed paths. Run `bash scripts/test.sh`, `bash scripts/build.sh --universal`, `codesign --verify --deep --strict build/TEotW.app`, app `--diagnose`, `git diff --check` on final source.
- [x] Record exact checks and remaining physical lock-screen acceptance without claiming unobserved behavior.
- [x] Update handoff with implemented semantics and next remaining functional work. Keep changes local for review.

## Delivery record

Implemented locally over `46eaef5`, no commit or remote operation. One scoped read-only reviewer found no significant issues. Runtime checks repaired native hit routing and hidden zero-size canvas initialization. Final seven suites, universal build, signature and diagnose passed; native QA smoke confirms group selection, proportional drag/Undo and child text entry. Shift affine gestures are covered by real NSEvent tests; CUA does not provide modifier-only key holding for a separate manual Shift drag. Physical lock-screen acceptance remains a user observation. See `docs/native-affine-groups-verification.md`.

## Follow-up: resize behavior correction

User reversed modifiers: default is nonuniform, Shift constrains proportions for single and grouped elements. All edges and corners of text/countdown/clock resize the box while preserving font display scale and reflowing lines; text width becomes fixed. User further clarified that corners also resize only the box, preserving displayed font size. Notes preserve font and padding for every handle, with free vertical and horizontal box resizing by default. Existing geometry `stretch` parameter still means unconstrained scale; the canvas now passes `!shift`. New real-event regressions cover all eight handles and both modifier states for all five kinds, group Shift constraint, Undo and wrap preservation. This small correction is implemented inline; no repeated independent review of the already-reviewed affine subsystem.
