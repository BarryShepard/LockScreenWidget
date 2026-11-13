# Notes and countdowns: accepted review

Final code: `377bbe8`. Whole-stage range: `15b0d8a..377bbe8`. Task findings were fixed before the final integration review. Native UI evidence is recorded in [verification](../native-notes-countdowns-verification.md).

---

## task-1-rereview.md

# Task 1 scoped re-review

Reviewed `3e7ae46..5b874e6` and the appended task report, scoped to the three Important findings and regressions introduced by their fixes. No code/index/HEAD mutations, broad scans or suite reruns were performed. Reported focused/full-suite/universal-build checks are existing evidence; root owns the concurrent isolated actual UI retest.

## Verdicts

- **Spec compliance: ready for Task 1 acceptance**, subject to root's separate actual UI smoke completing successfully.
- **Quality: ready.** All three previous Important findings are addressed. No new actionable Critical, Important or Minor findings in this fix diff.

## Resolution of previous findings

1. **Native bottom-padding clipping — resolved.** `Sources/Features/SceneEditor/Controllers/SceneCanvasController.swift:214` supplies the shared content rectangle only for notes. `Sources/Features/SceneEditor/Views/SceneCanvasView.swift:8` clips native drawing in local coordinates and restores graphics state; line 255 updates the clip on geometry changes and invalidates drawing. The input frame, text container, side-edge mouse handling, IME and transform anchoring remain intact. Ordinary text gets a nil clip and retains its previous drawing path. The new bitmap regression verifies visible ink inside and no ink below the padded content area. As accurately documented, the 0°/30° cases rasterize local input; separate existing tests check container coordinate rotation, rather than claiming a transformed-window raster comparison.

2. **Committed note deleted after clearing — resolved.** `Sources/Features/SceneEditor/Controllers/SceneCanvasController.swift:233` no longer checkpoints creation on mouse-down. Zero-motion gestures preserve the original provisional snapshot. The first nonzero motion checkpoints creation and clears `newText` when the commit is real (line 248), so later empty text cannot trigger provisional deletion. Width-history registration and IDs remain unchanged. The tests cover zero-motion provisional removal, actual-motion committed retention, and Undo/Redo of clearing. Inspection of returning to the gesture origin and finishing/cancelling an active width gesture found no additional history defect from this change.

3. **Cross-axis padding reduction — resolved.** `Sources/Shared/Scene/Controllers/SceneTextLayout.swift:51` retains the configured inset and clamps only available content dimensions to zero. Tests check both narrow and short notes and restoring the normal frame. The shared native clip and renderer use the resulting empty content rectangle consistently.

## Additional coverage

The fix adds private-pasteboard payload roundtrip, duplicate payload/style preservation with structural Undo/Redo, and marked-only provisional note handling. This addresses the main prior coverage gaps without duplicating the entire generic input suite. Existing full-suite results remain relevant because the checkpoint timing adjustment also applies to ordinary text. The documentation clearly distinguishes automated local clipping checks from root's actual UI verification.

---

## task-2-rereview.md

# Task 2 scoped repair review

Range: `51983bc..377bbe8` (`fix: preserve countdown edit context and scale live digits`). Reviewed the complete supplied repair diff, appended implementation report, final changed controller/view code and focused regressions. Scope was the three reported findings and breakage introduced by their fixes; the original full review was not repeated.

## Verdict

All three findings are addressed. No open Critical, Important or Minor actionable finding in this scoped repair. Code/spec compliance and quality pass for the agreed repair scope, including the explicitly narrowed wall-time editing range. Root's actual native re-smoke is separate acceptance evidence and was still in progress when this review was written.

## Addressed findings

1. **Important: active wall field reinterpreted after timezone choice.** `SceneCountdownInspectorView.swift:94–108` captures the selected action/index and represented layer before `makeFirstResponder(nil)`, then sends the captured action after the native end-edit callback. This prevents synchronous rendering from replacing the intended menu selection. `SceneCountdownInspectorController.swift:92–107` captures original layer, target, source and timezone in a tokenized edit context; stale context is rejected, valid input is resolved in its original zone, and commit targets the original ID rather than the current selection. Both view and controller clear tokens before reentrant work. Selection preparation ends wall editing before rendering another layer. `Tests/SceneCountdownTests.swift:241` onward exercises actual hidden NSWindow field editors and control target/actions for UTC 10:15 → Moscow 13:15, midnight rollover, no later duplicate commit, correct Undo ordering, source/format/seconds choices, edited and untouched selection transfer, invalid input and explicit repeated-time resolution. The change also blocks source/timezone reinterpretation of unresolved drafts while preserving independent format choices and tick stability. No new persistence/timer behavior is introduced.

2. **Minor: hybrid Gregorian historical cutover.** `SceneCountdownPresentationController.swift:42,55` consistently restricts wall display and input to complete Gregorian years 1583–9999. Controller messages explicitly state that range (`SceneCountdownInspectorController.swift:75,81`), and tracked verification/handoff documentation records it. Absolute persisted targets remain valid and unchanged. This is the agreed bounded correction, not a claim of proleptic support for 0001–1582. Focused tests at `Tests/SceneCountdownTests.swift:55–60` reject the unsupported historical examples and Gregorian-invalid 1700 leap day, and accept the first supported year and year-2000 leap day. Existing year-9999 and modern DST coverage remains.

3. **Important: countdown digits did not follow canvas resize.** `SceneTransformController.swift:122` now accumulates `textScaleX/Y` for countdowns using the existing plain-text path, leaving the note exception unchanged. No new scaling algorithm or rendering layer was added. `Tests/SceneCountdownTests.swift:202` onward checks rotated proportional and Shift resize, opposite anchor, compounded independent axes, unchanged base typography/deadline, Undo/Redo, temporary SceneStore round-trip, and the actual dynamic presenter's persisted scales and changing values at consecutive instants.

## Verification boundaries

The new tests exercise observable behavior rather than merely mirroring the added condition. Read-only code inspection found no new cache/tick, note geometry, source-preservation, draft-resolution or history regression from this repair. The implementation report records all seven suites, universal build, strict signature, both architectures and diagnose passing; this scoped review did not rerun them. No additional probe was necessary because the defect-specific native field tests and direct code path answered the remaining questions.

No application operations, source/index/HEAD mutations, remote operations, private document/clipboard/Space access, or old smoke-scene access occurred. Only these ignored review documents were written. Root's user-owned original NotesTimersSmoke scene was not inspected or modified. Actual lock, sleep/wake, physical multi-display and long-duration behavior remain outside this review.

---

## final-review.md

# Final notes/countdowns integration review

Range: `15b0d8a..377bbe84e1f2b9af295c1f8ec48eda52474300ad`. This is a bounded whole-stage integration review following the accepted Task 1 and Task 2 reviews and repairs. It examines cross-task behavior and backward compatibility, without reopening accepted fixes or expanding into protected-screen testing.

## Verdict

**Ready for stage acceptance and handoff.** No new actionable Critical, Important or Minor integration finding. No blocking issue was found.

## Integration assessment

- Schema version 1 is retained. Synthesized optional note/countdown decoding preserves old text/image documents; notes resolve missing payloads to defaults, while countdown payload and timezone validation reject malformed new timers. Unknown element kinds retain normal decoding failure behavior. Existing scene transfer and snapshot history preserve the optional payloads.
- Kind capabilities route notes through native text editing, and countdowns through date/source controls. Shared typography applies only to typography-capable selected elements; note background/padding edits are scoped to notes. Image replacement remains scoped to images.
- Note layout and countdown transforms coexist: notes retain fixed font/padding and reflow within their frame, including group transforms; countdowns reuse the existing plain-text scale path, and the dynamic presenter applies those persisted scales to each new value. Rendering keeps the note background visible during input and clips prepared note content.
- AppDelegate supplies the same existing clock instant to scene editor, legacy editor and lock controller. Dynamic refresh changes presentation content only. Cache identity uses scene plus rendered countdown values, preserving static/minute/expired invalidation behavior and avoiding per-tick persistence or history. The lock route and panel lifecycle remain structurally unchanged.
- Preset selection uses the existing catalog eligibility semantics and Moscow deadlines. Absolute custom deadline/timezone survive source changes. Expiry and elapsed time after a pause are recalculated from the supplied current Date. The accepted strict wall-time range, explicit repeated-time resolution, original-layer edit context, and captured native menu action remain consistent with shared scene history.

## Evidence and limits

Reviewed the stage plan, supplied complete-stage diff, final source at the relevant model/presentation/controller/view boundaries, accepted per-task re-reviews, targeted test assertions, and tracked verification record. Existing reported evidence includes seven passing suites, universal build, strict signature, both architectures and diagnose; no suite was rerun and no additional probe was necessary.

Root reports successful actual isolated native note/timer smoke and repaired timezone/resize/restart re-smoke on the final build. That root-owned evidence is accepted as reported, not claimed as independently reproduced here. The tracked verification/handoff text still describes that re-smoke and this review as pending; root should update those statuses while preparing the final handoff.

Actual protected-screen rendering with the new layers, physical multi-display behavior, actual sleep/wake and long-lock observation remain explicitly unclaimed. These previously excluded manual checks are not new acceptance blockers. No source/index/HEAD mutations, suite runs, application operations, remote operations, personal document/clipboard access or old smoke-scene access occurred. Only this ignored review report was written; user README changes remain untouched.
