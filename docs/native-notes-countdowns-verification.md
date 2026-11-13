# Native notes and countdowns verification

Task 1 adds note layers; Task 2 adds date countdown layers. Notes use optional `SceneNoteModel` payloads and schema version 1. Missing payload resolves to the default background and 16 pt padding. `SceneElementKind.hasEditableText`, `hasTypography`, and `isImage` separate capabilities for future layer types. `SceneTextLayout.contentRect` and `overflows` provide shared padded geometry.

Automated coverage in `SceneTests` checks note defaults, JSON round trips, invalid padding and color, fixed frame during fitting, and overflow. `SceneEditingTests.nativeNote` checks padded native coordinates with rotation and viewport scaling, prepared background, background rendering while editing, fixed frame during input, width gesture and native/scene history, and note style invariants during proportional and Shift resize. Existing tests cover IME handling and generic scene transfer and history.

Root completed the isolated native note smoke on baseline `5b874e6`: four persisted Cyrillic lines, padded clipping and overflow at height 60, full text at height 200, proportional resize with fixed font/padding/radius, Undo, background and padding edits. Real lock-screen and long-duration checks remain separate. The automated coordinate test does not claim a rotated-window pixel comparison of AppKit glyph rasterization against the renderer.

On 2026-11-12, the focused scene editor suite and `bash scripts/test.sh` passed with host access for private pasteboards. `bash scripts/build.sh --universal` succeeded; `codesign --verify --deep --strict` passed, and `lipo -archs` reported `x86_64 arm64`. `--diagnose` completed with 58 events, 19 countdowns and 39 period cards. The full suite logged an AppKit constraint-limit warning during the existing lock-screen controller tests.

Review fixes add native input clipping to the note content box, independent fixed insets on each axis, and correct provisional creation handling across width gestures. Focused note tests cover glyph bitmap clipping, creation checkpoints and Undo/Redo, copy and duplicate payloads, and marked-only provisional input. Full suite, universal build, strict signature, architecture and diagnose checks passed again; actual rotated-window pixel comparison remains a separate check; the isolated note smoke was subsequently completed as described above.


## Task 2: countdown layers

`SceneCountdownModel` is an optional schema-1 element payload with `source`, `targetDate`, `timeZoneID`, `format`, and `showsSeconds`. Custom deadline and timezone remain stored when using the catalog source. Old text/image/note files and legacy settings/catalog formats are unchanged. Countdown layers have typography but never enter the native text editor or image picker. Adding a timer uses a 320×80 pt frame (bounded by canvas), 32 pt text and a deadline 24 hours from the editor clock.

`SceneCountdownPresentationController` resolves and formats values without mutating the scene. Visible seconds round upward so a positive subsecond remainder stays at one; hidden seconds display whole minutes, and days-only displays floor full days. Finite extreme targets are clamped before integer conversion; extreme dates cannot enter Foundation calendar conversion. The editor accepts complete Gregorian years 1583–9999; older absolute targets remain stored and render normally but require a new supported date for wall-time editing. Russian day plurals and total hours above 24 are covered.

The preset preserves `selectNextEvent` / `eventHasCountdown` semantics for valid single-day dates, including legacy missing review status and approved secondary-source records. It does not introduce a new review-status gate. The real catalog regression retains `foerster-2026-11-13` as the next event at the fixed test instant. Event deadlines remain Moscow midnight. At a deadline it advances to the next future event; after exhaustion it renders zero and explains the condition in the sidebar. It never writes catalog data.

The separate countdown inspector prepares source, date/time, timezone, format, seconds, radius and inline messages. Date parsing requires ASCII `YYYY-MM-DD` and `HH:mm[:ss]`; impossible dates and DST gaps stay uncommitted. Repeated local times require an explicit first/second choice. Actual Foundation tests cover New York hour folds/gaps and Lord Howe half-hour folds/gaps. Candidate dates use nearby actual UTC offsets and exact Calendar component round-trips because Foundation `nextDate` repeated-time policies returned identical candidates for the Lord Howe test. Ambiguous drafts are tied to selected layer, deadline, source and timezone, and discarded when those change.

The existing `CountdownController` remains the only repeating timer. AppDelegate sends its same `Date` to the scene editor, legacy editor and lock controller. Shared presenters cache scene plus actual rendered values. Ticks update only canvas/overlay content and the preset information label; they do not rebuild popups, touch date/time editors, change selection, save or create Undo entries. Static, seconds-hidden and expired content remain clean until a rendered value changes. Panel restoration/retry behavior is unchanged.

Automated `SceneCountdownTests` covers payload validation/round-trip and old schema, formatting/expiry/extreme dates, strict date/year bounds, Foundation DST, stale ambiguous choice, timezone preservation, source restoration, catalog continuity/transition/exhaustion, duplicate payload, shared presentation values, minute/day invalidation, simulated sleep/relaunch, no save/Undo on ticks, partial native fields/menu item identity and timer typography retaining frame. `LockScreenControllerTests` additionally exercises a common clock with a canvas and injected unlocked panel, changing values, minute invalidation, sleep/expiry, no history and stable panel identity. Existing static-scene invalidation and panel recovery tests remain in place.

Root subsequently completed native timer smoke and independent final integration review. Physical multi-display behavior, protected lock-screen interaction with the new kinds, actual sleep/wake and long-duration observation remain manual checks. No production app installation, automatic lock, personal document, real clipboard or real elevated Space was used for Task 2 implementation.


Final Task 2 automated validation on 2026-11-12: `bash scripts/test.sh` passed all seven suites, `bash scripts/build.sh --universal` succeeded, `codesign --verify --deep --strict build/TEotW.app` passed, `lipo -archs` reported `x86_64 arm64`, `--diagnose` reported 58 events / 19 countdowns / 39 period cards with next `foerster-2026-11-13`, and `git diff --check` passed. Existing lock-suite NSLayoutConstraint warning remains. An earlier new test used unreliable `needsDisplay` on an unattached canvas; the corrected assertion compares its prepared content with the actual overlay, alongside existing invalidation counters. Focused lock tests and the final complete suite passed after that correction.


## Native review repair

Root's isolated native smoke on `51983bc` passed creation, ticking while partial input stayed focused, preset/Moscow information, total-hours format without seconds, custom deadline restoration, explicit New York repeated-time choice, and expired zero. It also found an active-field ordering defect: choosing a timezone before leaving a time field could reinterpret the old wall text under the new timezone. The repair captures the intended menu action and original layer first, finishes the native field session under its original layer/zone, then applies the captured option. Immediate field refresh shows the new timezone, including date changes across midnight. End-edit sessions have opaque tokens, immutable original layer/zone/target context and captured paired wall fields; duplicate or stale end notifications cannot edit a new layer.

Invalid and ambiguous wall drafts remain inline and block source/timezone changes until corrected or explicitly resolved. Format/seconds changes are independent and retain the draft. Selection transfer completes valid input on its original layer; unresolved drafts do not overwrite another layer. Time ticks still touch neither native fields nor menus.

Public Foundation Gregorian and ISO8601 calendars both use the historical 1582 cutover. To avoid private calendar APIs or fragile bridges, supported wall-time input/display is explicitly bounded to full Gregorian years 1583–9999. Tests reject the earlier Julian leap-date `1500-02-29`, the unsupported cutover-year `1582-10-10`, and Gregorian non-leap-century `1700-02-29`; they accept `1583-01-01`, `2000-02-29`, and the year-9999 boundary. Persisted absolute targets are not narrowed or rewritten.

New hidden-NSWindow regressions use actual native field-editor insertion and control target/actions. They verify UTC 10:15 → Moscow preserves 10:15Z and immediately displays 13:15; active date editing across midnight updates both wall fields; pending input before source/format/seconds choices; edited and untouched field selection transfer; invalid and ambiguous input; explicit second occurrence; tick draft preservation; and exact history without duplicate end commits. No application, production profile or personal scene was opened. Root subsequently re-smoked the repaired build successfully; details are below.


Countdown canvas resize now follows plain-text transform semantics: proportional handles scale both digit axes; Shift scales them independently; stored `textScaleX/Y` is applied to each newly rendered countdown value. Notes retain their fixed-font reflow behavior. A rotated countdown regression covers the opposite anchor, base style/deadline preservation, compound scales, Undo/Redo, SceneStore round-trip and dynamic presenter output at successive instants.


Final repair validation on 2026-11-13: all seven suites passed via `bash scripts/test.sh`; universal build, strict signature, `x86_64 arm64`, read-only diagnose and diff checks passed. Diagnose retained 58 events / 19 countdowns / 39 period cards and selected `upcoming-01` after the preceding event expired. The existing lock-suite constraint warning remains. Repaired native UI re-smoke and independent final acceptance are complete. Actual lock/sleep/multi-display and long-duration checks remain unclaimed for the new layer kinds.


## Accepted native checkpoint — 13 November 2026

Final code `377bbe8`. Both task reviews and the final whole-stage integration review accepted the result with no open actionable findings. [Review record](reviews/2026-11-13-notes-countdowns-review.md).

Root's actual native smoke used only a separate generated QA document at `/private/tmp/lockscreen-countdown-qa-xqwa62c1/Scene`. It confirmed:

- New countdown defaults to 24 hours and focuses date; a partial `2027-` stays focused while the displayed seconds change.
- Preset information remains in the sidebar; the canvas contains only the countdown value. Total-hours format showed `999:33` without seconds. Returning to custom restored its saved date/time.
- New York's repeated `2026-11-01 01:30` offered first UTC−04:00 and second UTC−05:00 choices; an expired custom deadline displayed zero.
- Repaired active UTC `10:15` → Moscow shows `13:15` immediately. Moving focus afterward does not change the deadline. Invalid partial date blocks timezone changes with an inline explanation and retains the current zone.
- Countdown corner resize changed 320×80 to approximately 499.26×124.815, visibly enlarging live digits; Undo/Redo restored geometry, and Enter focused date controls.
- Restart restored the saved deadline `2026-12-14 13:15 Europe/Moscow`, geometry and text display scale. The value recomputed from the current clock. The QA application was closed normally.

The universal executable has SHA-256 `2520d37f4e7ef92aaed1b09c7aa6babca42157c48234597940e98ce6fb805e80`. Bundle source revision is `51983bc-dirty`: validation/build preceded the identical repair source commit `377bbe8`. Bundle version remains development `0.4.0 (4)`.

The first notes/timers app copy acquired user-created layers between checks. That scene is user work, not disposable test data. It was left unchanged and also copied locally to `LocalScenes/2026-11-13-preserved-b5a70247`, excluded from Git by its local ignore file. Do not use or delete it for future tests. No installation, remote push or automatic lock was performed.
