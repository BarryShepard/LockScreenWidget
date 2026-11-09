# MVC refactoring verification — 2026-11-09

Baseline: `258dbbf`. Working branch: `codex/mvc-refactor`.

## Scope implemented

- Data-only model types; free calculation/validation functions; model-layer persistence.
- Shared model for the editor and lock-screen panels, with preview selection owned by the editor controller.
- View rendering separated from input handling and persistence. Button targets and text delegates point to controllers.
- Separate editor, lock-screen and single-timer controllers; AppDelegate limited to startup/shutdown, menus and wiring.
- Existing `LockScreenSpace` implementation relocated without changes. Resources and application identifier unchanged.
- Build, diagnostic mode and tests updated for the new source layout.

## Local verification

This checkout was edited on Windows. `swiftc` is not installed, Bash is unavailable, and WSL has no installed distribution. There is no macOS/AppKit SDK. Consequently, neither the original baseline nor the refactored Swift test suites or app build could be executed here. No passing Swift tests or successful native build is claimed.

Available checks:

- Tree-sitter parsed the Swift sources, tests, icon generator and Bash scripts without syntax errors. This checks grammar, not Swift type checking, AppKit selectors or linking.
- `git diff --check` found no whitespace errors.
- Reviewed the model storage field names and old-format fixture, unchanged resources/SkyLight implementation, source paths and architecture boundaries.

Test sources were updated before their corresponding extraction, but a runtime RED/GREEN cycle could not be observed without Swift. Native validation below remains required before accepting the refactor as working on macOS.

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
- `LockScreenControllerTests`: repeated-test deadlines, lock/unlock interruption and editor restoration, disabling and shutdown. Screen creation and delayed scheduling are injected; these checks do not create a private SkyLight space.

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

A separate reviewer inspected all sources/tests against `258dbbf` and the specification. The review found one regression: cancelling a panel test on lock discarded the editor's pending restoration. The implementation now distinguishes restoration, deferral until unlock, and discard on shutdown. Session deactivation defers restoration; reactivation rechecks lock state. A dedicated controller test covers restoration and stale timeout cancellation. These new tests are prepared but were not executable on this Windows host.

Status: native build, automated Swift tests, and manual macOS acceptance are pending.
