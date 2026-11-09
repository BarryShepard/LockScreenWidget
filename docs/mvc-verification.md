# MVC refactoring verification — 2026-11-09

Original MVC baseline: `258dbbf`; colleague head: `3eecd16ce7b3d556c64e9dddf529d1517ba1c62b`. Adopted locally as `52770a1` on `codex/personal-lockscreen-editor`, above the scene/store foundation. No remote merge or push.

## Scope implemented

- Data-only model types; free calculation/validation functions; model-layer persistence.
- Shared model for the editor and lock-screen panels, with preview selection owned by the editor controller.
- View rendering separated from input handling and persistence. Button targets and text delegates point to controllers.
- Separate editor, lock-screen and single-timer controllers; AppDelegate limited to startup/shutdown, menus and wiring.
- Existing `LockScreenSpace` implementation relocated without changes. Resources and application identifier unchanged.
- Build, diagnostic mode and tests updated for the new source layout.

## Local verification

The author originally checked grammar and whitespace on Windows without executing Swift. The corrected combined checkout was subsequently tested natively on 2026-11-09, macOS 15.7.3 (24G419), Apple Silicon arm64, Apple Swift 6.1.2. The no-nib `EditorWindowController` now creates its initial programmatic window when `window == nil`; `isWindowLoaded` cannot establish window existence for this controller.

- `bash scripts/test.sh`: exit 0. CoreTests, SettingsTests, LayoutTests (348 layouts), LockScreenControllerTests, and SceneTests all passed. The lifecycle suite retains its first-open visible-window assertion and hide/defer/restore assertions; timers, lock-state reads and panel creation are injected.
- The lifecycle run emitted one AppKit informational system line: `IOPMScheduleUserActivityLevelNotification returned 0`. The output was not pristine; this line did not fail the suite.
- `bash scripts/build.sh --universal`: exit 0; `lipo -archs` reports `x86_64 arm64`; `codesign --verify --deep --strict` exits 0. The build replaced the local ad-hoc signature.
- `build/TEotW.app/Contents/MacOS/TEotW --diagnose`: exit 0; `events=58`, `countdowns=19`, `periodCards=39`, `font=.AppleSystemUIFontBold`, next event `foerster-2026-11-13`, `lockStateKeyPresent=false`. This unlocked-session diagnostic does not exercise protected-screen visibility.
- `git diff --check`: exit 0.
- SceneTests passed model/style/geometry validation, durable asset import, atomic-save preservation, corrupt-document reporting and asset-directory boundary checks. Scene/store interfaces and their tests remain unchanged.
- Test preferences are in-memory; scene/store tests use temporary directories. No existing user settings, scene files or clipboard contents were changed.

## Automated verification on macOS

From the repository root:

```sh
bash scripts/test.sh
bash scripts/build.sh --universal
build/TEotW.app/Contents/MacOS/TEotW --diagnose
```

Expected suites:

- `CoreTests`: Moscow date parsing, fractional seconds, total hours, exact expiry, next-event selection, exhausted catalog, period cards, duplicate IDs.
- `SettingsTests`: a literal JSON payload from the old schema, identical JSON round-trip, old coordinate migration, invalid payload fallback, nonfinite values and numeric input.
- `LayoutTests`: 348 layouts, dragging and marquee selection, Shift locking, group edge constraints, typography and line height, visibility, keyboard movement, centering, live inspector input, persistence through controller actions, shared tick and preview-only card selection.
- `LockScreenControllerTests`: first editor open, repeated-test deadlines, lock/unlock interruption and editor restoration, disabling and shutdown. Screen creation and delayed scheduling are injected; these checks do not create a private SkyLight space.
- `SceneTests`: the new scene model and filesystem store, including corrupt documents and symlink-boundary rejection. This separate suite requires AppKit and runs alongside all MVC suites on macOS.

The build command compiles arm64 and x86_64, generates the app icon and signs the local bundle ad-hoc. It does not publish a release.

## Manual acceptance on macOS

1. Quit any previously running copy. Build and launch the refactored `build/TEotW.app` in the same user account, keeping existing preferences. Confirm old positions, typography and information visibility load.
2. Close the editor and reopen it from the menu-bar menu. Select a different card; confirm the title/counter or period label changes and the source menu opens the selected card's source.
3. Edit each typography control, including comma decimal input and `Авто` line height. Confirm live preview; partial input must survive a timer tick. Edit one group property and verify each block retains its other properties.
4. Drag single blocks and a marquee-selected group; use Shift axis locking, arrow keys, Shift+arrows, Escape, centering and layout reset. Verify group spacing at screen edges.
5. Toggle additional information and lock-screen visibility. Menu and editor checkbox must agree. Restart the app and verify persisted settings.
6. Run the eight-second transparent-panel test. The editor hides, then returns if previously visible. Start the test again before it expires; the most recent test must get its full duration.
7. With display enabled, lock using Control–Command–Q. Confirm panels display the nearest future event, regardless of the editor's selected card, and the counter changes each second. Unlock and verify panels disappear.
8. Lock during the panel test; unlock before/after its original deadline. Confirm no stale delayed callback reopens the editor over the lock screen or closes a subsequent test. Disable display/quit during a test and confirm cleanup.
9. Repeat with multiple displays and sleep/wake if available. Private SkyLight behavior requires a real user session and cannot be established by syntax checks.

## Independent review

A separate reviewer inspected all sources/tests against `258dbbf` and the specification. The review found one regression: cancelling a panel test on lock discarded the editor's pending restoration. The implementation now distinguishes restoration, deferral until unlock, and discard on shutdown. Session deactivation defers restoration; reactivation rechecks lock state. A dedicated controller test covers restoration and stale timeout cancellation. These controller tests now pass on the native Mac checkout. A later native review found the no-nib first-open regression; correcting its window-existence guard made the existing visibility assertion pass. See the local verification above.

Status: all combined automated Swift suites pass. Universal build and diagnostic results are recorded above. Manual application launch, close/reopen through the menu, real field-editor/caret/IME behavior, protected-screen visibility, interruption ordering, multiple displays and sleep/wake remain pending; no secure-lock validation is claimed.
