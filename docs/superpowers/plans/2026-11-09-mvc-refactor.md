# MVC Refactoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the supplied MVC specification without changing existing behavior or preferences.

**Architecture:** Shared data-only `ApplicationModel` contains the catalog, editor settings, and enabled state. Pure model-layer functions perform calculations and validation; separate functions load/save. Controllers own actions, gestures, lifecycle, and the common timer; views consume value snapshots.

**Tech Stack:** Swift 5, Foundation, AppKit, macOS 15+, existing shell build/test scripts.

**Spec:** `docs/superpowers/specs/2026-11-09-mvc-refactor.md`

## Global Constraints

- Data type suffix `Model`; view subclasses `View`; panels `Panel`; controllers `Controller`.
- No dependencies added to the app. Keep the existing JSON/preferences schema and SkyLight adapter behavior.
- Explicit `now: Date` for event selection/countdown calculations. One timer for both displays.
- Work in `codex/mvc-refactor`; leave changes reviewable, without publishing.

## Review Focus

- Legacy/v1 settings, malformed array lengths, nonfinite numeric input: model tests.
- Exact deadline rollover, period cards, empty/exhausted catalog: core/controller tests.
- Group typography edits, edge-clamped drag, Shift axis locking: layout/controller tests.
- Inspector live input must not reset caret/partial text each second: controller tests/manual check.
- Lock during panel test, repeated tests, unlock/disable/shutdown: controller review and macOS smoke checklist.

## Tasks

### 1. Extract data-only models and operations

Files: `Sources/Models/*`, `Tests/CoreTests.swift`, `Tests/SettingsTests.swift`.
Interfaces: `loadEventCatalog(_:) -> EventCatalogModel`, `selectNextEvent(in:now:)`, `calculateCountdown(until:now:)`, `makeCountdownDisplay(event:now:)`, `validateEditorSettings(_:)`, `loadEditorSettings(from:)`, `saveEditorSettings(_:to:)`.

- [x] Adapt core tests to free functions; add literal old-format settings fixture, validation and migration checks before implementation.
- [x] Move stored event/settings fields into suffixed types; extract calculations, persistence, and validation without altering JSON keys.
- [ ] Run Foundation-only tests with Swift; report toolchain limitations explicitly if unavailable.

### 2. Move editor behavior to its controller

Files: `Sources/Controllers/EditorWindowController.swift`, `Sources/Views/{CountdownView,TypographyInspectorView,EditorView,EditorWindow,TypographyRendering}.swift`, `Tests/LayoutTests.swift`.
Interfaces: snapshot `CountdownDisplayModel`, `CountdownView.render(...)`, raw input callbacks, controller selection/drag/typography methods.

- [x] Adapt behavior tests to drive controller and inspect rendered output/settings. Include unchanged group font sizes, preview-only card selection, and input refresh behavior.
- [x] Move settings mutations, persistence, selection and gestures into controller; leave layout/font construction in views.
- [x] Wire all controls directly to controller target-action and text-field delegate.
- [ ] Run layout/controller tests on macOS.

### 3. Split runtime coordination and update build

Files: `Sources/Controllers/{LockScreenController,CountdownController}.swift`, `Sources/Views/OverlayPanel.swift`, `Sources/Infrastructure/*`, `Sources/AppDelegate.swift`, `Sources/main.swift`, `scripts/{build,test}.sh`.

- [x] Move lock/session notifications, polling, panel tests and teardown into LockScreenController; preserve adapter implementation.
- [x] Introduce one shared timer; wire controller callbacks and menu targets in AppDelegate.
- [x] Update all source paths, diagnostics and test commands.
- [ ] Build both macOS architectures (requires macOS toolchain).

### 4. Verify and document

- [x] Update README architecture/testing and add macOS acceptance checklist.
- [x] Review full diff against the specification with an independent reviewer; resolve actionable findings.
- [x] Run available syntax/static checks and `git diff --check`; record actual tests/build results and limitations in `docs/mvc-verification.md`.

## Execution notes

- Baseline clean at `258dbbf`; branch `codex/mvc-refactor` created.
- Windows host has no Swift compiler, Bash, WSL distribution, or AppKit SDK. Native test execution is unavailable here; do not claim Swift tests or the macOS acceptance scenario passed. Prepare runnable macOS coverage and use available parsing checks locally.
- Implementation follows the already approved user specification without another approval gate. No worktree is necessary for this clean dedicated checkout.

- Final review: independent reviewer inspected all source/test files. One editor-restoration regression was identified and addressed by explicit restore/defer/discard outcomes; controller regression tests are prepared. Native execution remains unavailable.
- Final available verification: 32 Swift files and 3 Bash scripts parsed successfully; model/view dependency audit and `git diff --check` passed. No Swift type checking or runtime success is claimed.
- Implementation choices: keep the existing SkyLight implementation and v1 persistence format; use one shared ApplicationModel and one CountdownController; leave panel creation and delay scheduling injectable for lifecycle checks without private WindowServer calls.
- No deferred code-review findings. Native test/build/manual acceptance gates remain open in `docs/mvc-verification.md`.
