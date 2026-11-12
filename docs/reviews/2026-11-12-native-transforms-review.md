# Native transforms final review — 12 November 2026

Initial review range: `54695b7..7a7e2bf`. Final reviewed code: `8a58d57`.

The stage review and follow-up findings below are historical; the final scoped verdict accepts the fixes. Runtime checks and manual gaps are recorded in [verification](../native-editor-transforms-verification.md).

---

## final-review.md

# Final whole-stage review — 54695b7..7a7e2bf

## Strengths

- Transform geometry remains in a focused controller and uses the starting snapshot. Single rotated anchors, proportional group scaling, group rotation, and crop source-position preservation are coherent with the specification. Crop does not mutate source assets.
- Optional text display scales preserve old documents and stay separate from typography. Shared rendering and native input now use the same logical text layout units; the exact saved wrapping reproduction has a regression test.
- Canvas transform previews, completion, cancellation, double-click precedence, full-edge hit testing, and controller-provided cursor feedback integrate with the existing MVC structure. The prior review findings have been addressed rather than merely documented away.

## Issues

### Critical

None identified.

### Important

1. **[P2] Native text-width gestures cannot be undone with Cmd-Z while editing remains active.**

   - Location: `Sources/Features/SceneEditor/Controllers/SceneCanvasController.swift:231`; related dispatch at `Sources/Features/SceneEditor/Views/SceneCanvasView.swift:21`–`24` and `Sources/AppDelegate.swift:137`.
   - The width gesture commits only to `SceneEditingStateModel` history and leaves the native text view focused. The app's Cmd-Z menu targets the responder chain, where `SceneInputView.undo:` exclusively invokes its private text UndoManager. No width operation is registered there. Immediately after a completed side drag, Cmd-Z therefore does nothing when the text history is empty; with earlier typing, it can undo that typing instead of the most recent width gesture. This misses the one-Undo-per-gesture behavior in the very editing mode where the gesture is available.
   - Focused execution confirmed the gap: after changing width from 100 to 130, `window.firstResponder === input` was true, native `canUndo` was false, and scene `canUndo` was true. Invoking the focused responder's `undo:` left width at 130. The existing regression calls `state.undo()` directly, and the supplied production smoke exits editing before Cmd-Z; neither exercises this route.
   - Integrate width operations with the active native Undo/Redo ordering and the controller's text-session checkpoint, while preserving normal typing/IME undo. Add a responder-routed regression that completes a width drag, keeps editing active, invokes Undo and Redo, and verifies width/wrapping plus unchanged text/font. Include typing before/after a width gesture to prevent undoing the wrong operation.

### Minor

None requiring action in this stage.

## Recommendations

Fix the native history integration above, then rerun its focused regression and the affected editing suite. Retain the explicit pending native crop, IME/cursor, and secure-lock checklist; these are separate acceptance limits, not demands for remote merge or secure-lock execution before local stage completion.

## Assessment

**Ready for local stage completion: No — with one fix.**

The implementation broadly meets the transform, persistence, rendering, and architectural requirements. The remaining issue is a concrete native interaction gap: the new text-width gesture is committed to a history stack that the currently focused editor's standard Undo command cannot reach.

## Checks and evidence limits

- Read the reviewer template, stage plan, editor-spec sections 5/7/8, implementation report, progress ledger, and previous review/re-review reports. Inspected the final full-range diff and current integration source, including renderer/presenter, model validation, text layout, native input, scene history, and menu/toolbar dispatch. Large initial tool output was truncated; affected source portions were retrieved separately.
- Accepted root-reported passing full suites, universal build, strict signature, architecture, and diagnostic checks without rerunning them. Accepted root's `7a7e2bf` production smoke observations for saved scaled text, width wrapping, post-exit Undo, rotation/edit alignment, and boundary double-click. These observations were not independently repeated here.
- Ran only a focused temporary AppKit probe derived from the existing native gesture test, compiled against current scene sources. Probe: `/private/tmp/transform-review-undo-xy9vmbj9/Probe.swift`. It used a temporary SceneStore, no personal scene or clipboard, and exited successfully after printing the unresolved native Undo behavior. It did not open a visible UI or lock the Mac.
- No source, index, HEAD, branch, user README/backlog edits, or remote state changed. Only this requested review report was written in the checkout. The existing constraint warning was not treated as a new finding.

---

## final-rereview.md

# Scoped final re-review — 7a7e2bf..c306560

## Original finding

**Addressed:** A completed width gesture is now registered in the active native input's UndoManager (`SceneCanvasView.swift:27`–`37`), and its callback moves scene history while resetting the text-session checkpoint (`SceneCanvasController.swift:243`–`250`). Native Undo/Redo can therefore reach width operations without leaving editing. Root independently observed active-input Cmd-Z restore width 391.07/height 70 after a drag to approximately 276.939/140, followed by active-input Cmd-Shift-Z restoring the narrower state. This reviewer did not repeat the visible UI smoke.

## New breakage in the bridge

### Important — [P2] Text between width gestures can desynchronize the two history stacks

- **Location:** `Sources/Features/SceneEditor/Models/SceneEditingStateModel.swift:90`, together with `Sources/Features/SceneEditor/Controllers/SceneCanvasController.swift:249`.
- Reconciliation recognizes a native typing Undo only when the entire newly calculated scene equals the last scene checkpoint. That is not guaranteed: native text Undo calls `textChanged`, whose fit uses the editing session's original `minimumHeight`, while width gestures fit with `minimumHeight: 1`. A block initially taller than its text can therefore return to identical text but a different height. Reconciliation leaves the committed typing entry on the scene stack. The next native width Undo blindly calls `state.undo()` and consumes that typing entry instead of its width entry.
- **Confirmed reproduction:** Existing `base` text in a 100 × 100 frame; enter editing; type `A`; drag width to 130 (height becomes 38); type `B`; drag width to 150. Invoke native `undo:` three times while editing. Observed states: width 130 / `baseAB`, width 130 / `baseA`, then width 130 / `baseA`. The third Undo should restore width 100, but leaves the first resize in place.
- This is a narrow interaction defect, not evidence of general corruption or a crash. It is nevertheless load-bearing for this fix: native operations are consumed in the wrong order, directly violating the promised width/typing history integration. The pre-existing height-fit behavior by itself is not being reopened as a separate finding.
- **Fix:** Make scene/native history reconciliation identify the corresponding text checkpoint reliably even when derived layout changes, and ensure a width callback acts on its own scene history entry. Do not weaken the comparison to text alone without considering other document edits. Add the interleaved `type → width → type → width` regression with an initially taller frame, checking full geometry, Undo/Redo order, and finish without duplicate entries.

## Other scoped checks

- The new regression covers typing before and after two consecutive widths, multiple native Undo/Redo operations, post-finish scene Undo, and finish immediately after width Undo. It does not put typing between widths or vary frame height, which explains why the confirmed mismatch is missed.
- Width history registration occurs only on completed changed gestures, so existing no-op and Escape cancellation routes do not register a width operation. The native marked-text guard remains in place, and the new history-end text synchronization checks `hasMarkedText()` before forwarding accepted text. No additional actionable IME/cancellation defect was identified in this diff.
- Reviewed only the complete supplied fix diff and appended report, with relevant line references. Accepted the reported passing suite/build/signature/architecture/diagnostic checks without rerunning them. Uncommitted documentation and user README/backlog edits were untouched.
- Ran one bounded focused investigation in `/private/tmp/width-history-review-vac9c9m0/Probe.swift`, compiled against current scene sources: first isolated the height mismatch, then verified the interleaved history failure. Both executions exited successfully; AppKit emitted a service-connection diagnostic. Used a temporary SceneStore, no personal data or clipboard, no visible UI, no remote operations. No source/index/HEAD mutations were made; only this requested report was written in the checkout.

## Verdict

**Original finding: addressed. New bridge issue: open. Ready for local completion: No, with the single P2 fix above.**

The simple active-input width Undo/Redo path is fixed and manually verified. Interleaved typing and width edits still have one reproducible ordering failure in the newly added history bridge.

---

## final-rereview-2.md

# Narrow residual verification — c306560..8a58d57

## Finding verdict

**Interleaved typing and width history with an initially tall frame — ADDRESSED.**

- `Sources/Features/SceneEditor/Controllers/SceneCanvasController.swift:59` now reconciles the edited text's derived height separately. It verifies that the actual height is the result of the existing editing fit, normalizes only that height, and compares the entire remaining snapshot. It does not discard differences in width, position, text, style, other elements, or selection.
- `Sources/Features/SceneEditor/Models/SceneEditingStateModel.swift:107` and `:111` restore the exact stored checkpoint on successful native text Undo/Redo reconciliation, preserve its history ID, and emit the committed update. The controller refreshes and updates `initialText` at lines 69–70, preventing finish from adding the same transition again.
- `Sources/Features/SceneEditor/Controllers/SceneCanvasController.swift:255` captures the width gesture's history ID; line 260 uses it for Undo/Redo. `SceneEditingStateModel.swift:89` and `:97` reject mismatched chronological entries, so a width callback cannot silently consume an unrelated typing or document operation.
- `Tests/SceneEditingTests.swift:237` reproduces the exact reported sequence: 100 × 100 `base`, type A, width 130, type B, width 150. Lines 241–249 verify the height mismatch is exercised and compare complete snapshots through every native Undo/Redo. Lines 251–264 check scene history after finish and finish after native width Undo without a duplicate entry. Lines 16–18 separately verify mismatched Undo/Redo IDs cannot consume unrelated entries.

## Fix-introduced breakage

No new actionable Critical or Important issue identified in this scoped diff. Ordinary scene Undo/Redo still uses the current top entry, while targeted native width operations require their own ID. No-op finish continues to produce no history entry. This fix does not alter native input routing, marked-text guards, or gesture cancellation.

## Verdict

**Ready from code review: Yes. All reported transform-stage findings are addressed.**

The exact residual failure has a covering native regression, and the correction preserves full snapshots and history ordering while restricting the normalization to the known derived-height difference. Root's concurrent production smoke and the separately pending manual acceptance checklist remain distinct evidence; this review does not claim their execution.

## Checks

- Read the complete `c306560..8a58d57` diff package and appended implementation report, then verified relevant current source/test line references. No broader stage review or speculative probe was performed.
- The report states that the focused scene suite, all suites, universal build, strict signature, architecture, diagnostics, and whitespace checks passed. These were not independently rerun; the exact regression covers the previously reproduced defect, so no additional probe was needed.
- No source/index/HEAD changes, app actions, personal data, clipboard, or remote operations. User README/backlog edits and root's pending documentation changes were untouched. Only this requested review report was written.
