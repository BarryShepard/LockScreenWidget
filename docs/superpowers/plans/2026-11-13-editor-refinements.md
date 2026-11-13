# Editor refinements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Correct lock-screen guides and add centered resizing, editor app lifecycle, clock layers, persistent groups and relative alignment.

**Architecture:** Keep the flat render elements and shared one-second clock. Store optional clock payload and group ancestry on elements for backward-compatible loading; groups select and transform their descendant leaves. Views consume presentations; controllers own actions and AppDelegate owns activation policy.

**Tech Stack:** Swift 5, AppKit, Foundation; macOS 15+, no external dependencies.

## Global Constraints

- Work in the existing checkout on `codex/editor-refinements`; preserve user README, AGENTS and all user scenes.
- One agent. No automatic screen lock. UI redesign and display switching are deferred.
- Existing passing full suite is the baseline. Run focused checks during implementation and full suite/universal build once at delivery.
- System clock visibility has no verified public app API; offer a system-settings link without changing system preferences.

### Task 1: Guides and centered scaling

**Files:** `Sources/Features/SceneEditor/Views/SceneCanvasView.swift`, `Sources/Features/SceneEditor/Controllers/SceneTransformController.swift`, `SceneCanvasController.swift`, `Tests/SceneEditingTests.swift`.

- [x] Match approximate guide geometry to the supplied overlay: clock moves down, login avatar/field shrink; use logical canvas coordinates and add the missing name/date guide.
- [x] Extend `applying(..., centered: Bool = false)`. Centered resize doubles pointer delta, preserves the original center and enforces uniform scale (including notes). Crop takes precedence.
- [x] Pass `.option` from the gesture without changing Option-move duplication.
- [x] Check rotated element center, opposite edges, group distances, image crop and Undo with real geometry assertions.

### Task 2: Editor activation lifecycle

**Files:** `Sources/AppDelegate.swift`, `SceneEditorWindowController.swift`.

- [x] Add editor visibility callback. On explicit show use `NSApp.setActivationPolicy(.regular)` before activation; on close flush then return to `.accessory` when no editor remains visible. Temporary panel-test hiding does not count as close.
- [x] Restore editor from Dock reopen; keep status menu and app alive after last window closes.
- [x] Verify close/reopen and normal quit in an isolated QA document.

### Task 3: Current-time layer

**Files:** `Sources/Shared/Scene/Models/SceneClockModel.swift`, `SceneModel.swift`, `Controllers/ScenePresentationController.swift`, `SceneClockPresentationController.swift`; editor clock view/controller, canvas/window integration; `Tests/SceneCountdownTests.swift`.

- [x] Add `.clock`, optional `clock`, `SceneClockModel(timeZoneID: String?, showsSeconds: Bool, uses24Hour: Bool)`; nil timezone follows the system. Validate timezone if present. Include clock typography and scaling.
- [x] Format `HH:mm[:ss]` or `h:mm[:ss] a` with a cached POSIX formatter and current/specified timezone. Shared presenter caches rendered values; ticks never mutate the scene/history/store.
- [x] Add menu creation and inspector for seconds, 24/12-hour and timezone; use existing typography controls. Add a button opening Lock Screen settings with an explanation of the system clock switch.
- [x] Assert timezone, midnight/noon, DST, minute invalidation, JSON and history invariants; smoke in native editor.

### Task 4: Persistent groups and alignment

**Files:** `SceneModel.swift`, `SceneEditingStateModel.swift`, inspector and canvas controllers/views, `SceneCanvasView.swift`, `AppDelegate.swift`, `Tests/SceneEditingTests.swift`.

- [x] Store optional group ancestry per element; validate nonrepeating ancestry and keep old scenes valid. Grouping appends a shared UUID beneath the shared parent; ungroup removes the selected group and keeps nested descendants.
- [x] Expand normal selection to outer group, double click descends to a leaf, display ancestry in layer list, offer group/ungroup menu shortcuts through native responder chain. Remap group IDs when copying so copies do not select with originals.
- [x] Add six relative alignment commands. Bounds use rotated geometry; move whole selected groups as units, preserve internal layout, one command per Undo. Default anchor is the selection bounds, subject to user clarification.
- [x] Assert nested selection, deletion, copy, grouping/ungrouping history, persistence and rotated alignment.

### Task 5: Delivery

- [x] Self-review changed logic and run `bash scripts/test.sh`, `bash scripts/build.sh --universal`, `codesign --verify --deep --strict build/TEotW.app`, `git diff --check` once on the final source tree.
- [x] Native smoke with new isolated scene; preserve running user QA scene and assets. Do not claim protected-screen checks without user observation.
- [x] Update backlog, specification and continuation with implemented behavior and remaining work. UI redesign follows completion and integration of primary functions; no redesign in this batch.


## Delivery record

Completed inline by one implementer and one scoped reviewer. User approved nested groups, direct child double-click and selection-bounds alignment. Full tests, universal build, signature, diagnose and isolated native smoke passed. Reviewer finding about numeric group sizing was repaired and covered by regression. See `docs/native-editor-refinements-verification.md`. Actual protected-screen verification of new clocks/guides remains a user step; no automatic lock was performed.
