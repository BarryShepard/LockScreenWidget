# Independent scoped review: final Stage A fix wave

Reviewed supplied base `71323f4` through `17d1c781e3f8cdc973cf9abed96514d7a55dc22d` and narrow follow-up `9ac681b9a57028436d9526018d7a0f33a34f281a` on 10 November 2026. **Final verdict: accepted within this scoped code review.** All six original findings are **ADDRESSED**. The one new Important IME regression found at `17d1c78` is **ADDRESSED** by `9ac681b`; no remaining Critical/Important breakage was found in these fixes. Native/secure-lock validation remains separately bounded below.

Scope: the six exact findings in `docs/reviews/2026-11-10-stage-a-review.md`, `final-fix-brief.md`, the supplied fix diff (read once), changed code and directly relevant surrounding paths, regression tests, `final-fix-report.md` and its available test/build logs. This is not another review of unchanged Stage A code. No source mutation, application interaction, window creation, clipboard access, production store access, display reconfiguration, secure lock, subagent or full-suite/build rerun was performed. The initial pass used only the supplied diff; root subsequently authorized a read-only `git diff 17d1c78..9ac681b` for the narrow follow-up. The only workspace write is this report. One concrete unresolved IME question warranted the focused headless probe below.

## Six original findings

| Original finding | Verdict | Code and regression evidence |
| --- | --- | --- |
| 1. External-display global/display-relative geometry | **ADDRESSED** | `OverlayPanel.init(screenFrame:)` initializes without an explicit screen and then uses global `setFrame`. `LockScreenController.createPanels()` supplies the UUID-matched screen frame directly and no longer rederives it from `panel.screen`. Actual panel-frame assertions cover positive x, negative x/positive y, and negative y. The private space adapter is unchanged. This resolves the coordinate-contract error; it does not establish real multi-display or secure-lock behavior. |
| 2. Recognizable truncated PNG replacement and mixed batch | **ADDRESSED** | All image imports reach `SceneStore.importImages(data:)`; it validates every input before creating the first asset. PNG-signature inputs must have bounded complete chunks, valid CRCs and a zero-length IEND before AppKit validity/dimension checks. The noisy opaque 128×64 fixture remains recognizable at 256 bytes and is rejected. Regression tests check data/file imports, failed replacement, mixed batch, asset directory and original bytes, scene/selection, Undo and pending Redo. Write failures also roll back newly created batch assets. |
| 3. Shift held before selected single/group drag | **ADDRESSED** | Mouse-down retains selected members; mouse-up toggles from the original selection only when no drag occurred. The existing move transaction therefore receives the full selection. Native event tests cover selected single/group movement, initial-axis locking, one Undo, sub-threshold Shift-click removal, and addition without history. Escape/Option-copy cancellation paths remain in the tested suite. |
| 4. Debounced saved active text absent from lock consumer | **ADDRESSED** | Successful `saveIfNeeded()` publishes the saved optional snapshot before showing saved status. The production controller receives it while the input remains first responder; first input and existing text are tested through the real debounce. Marked text does not enter that snapshot or force focus changes during debounce, and completion retains one scene Undo. See the separate regression below for ending a marked-only insertion. |
| 5. Discarded provisional first insertion disables fallback | **ADDRESSED** | `hasCommittedDocument`, `desiredDocument` and `savedDocument` distinguish no document, a provisional save, and an intentional empty document. Immediate plain-text type/delete/Escape cancels the pending save without creating a document. After debounce, the matching provisional document is removed and nil is published, restoring the actual countdown consumer. Existing documents are restored and intentionally committed/reopened empty documents persist. The blocked recovery path returns before store writes/removals; its test preserves damaged bytes. |
| 6. Static personal scene invalidated on every tick | **ADDRESSED** | Refresh/settings rendering now targets only legacy countdown views. Equal scene publication returns early; actual scene changes set the personal view's snapshot, and actual size changes invalidate it. `displayIfNeeded` preserves AppKit's normal redraw requests. The request-observing test follows the controller-to-view path across ticks, settings and identical publication, then checks resize, explicit AppKit redraw and real edits. Polling/order retries remain present. |

## Important regression discovered at 17d1c78, now resolved

### P2 — Do not commit a blank new layer when a marked-only insertion ends — ADDRESSED at 9ac681b

The added `!field.hasMarkedText()` guard at `Sources/SceneCanvasView.swift:219` leaves the scene element's text empty during initial IME composition. `finishText()` still decides whether to discard a new empty layer using **`field.string.isEmpty`** at line 236. During composition the field string is nonempty even though the scene text is empty, so the layer survives and `state.finish(from:)` records a committed blank element.

This has a concrete production entry path: `mouseDown(with:)` calls `finishText()` before transferring focus at line 114. Starting a new text layer, entering marked text only, and clicking elsewhere on the canvas can therefore finalize an empty model layer. `SceneEditorWindowController.update(.committed)` at lines 116–119 sets `hasCommittedDocument = true`, saves and publishes that layer. On a fresh profile the visible composition has no text and the legacy fallback is permanently disabled until an explicit subsequent edit. Existing text may similarly fail to receive its in-progress composition, but the new blank first layer alone is sufficient to establish the regression.

Focused probe used the production scene sources, a UUID temporary directory and an unattached `SceneCanvasView`, with **no NSWindow or UI interaction**:

1. Create a new text element with `canvas.createCenteredText()`.
2. Obtain its NSTextView and call `setMarkedText("ка", selectedRange: ..., replacementRange: ...)`.
3. Call the production `canvas.finishText()` method used by canvas mouse-down.

Commands:

```text
swiftc -swift-version 5 -module-cache-path /tmp/teotw-review-marked-modulecache -framework AppKit Sources/Scene*.swift /tmp/teotw-review-marked-probe.swift -o /tmp/teotw-review-marked-probe
/tmp/teotw-review-marked-probe
```

Both exited 0. Output:

```text
before marked=true fieldLength=2 modelLength=0
after layers=1 modelLength=0 commits=1 canUndo=true
```

The new debounce tests preserve marked input while active and then commit via `insertText`; they do not end a marked-only insertion. Reconcile/discard composition coherently before finishing a session, without interpreting a nonempty marked field as committed model content. Add a focused regression for finishing the first marked-only insertion through the relevant canvas path and verify the intended document/fallback and Undo behavior. Native IME smoke remains useful, but is not needed to establish this model/history mismatch.

## Evidence limits and non-blocking notes

I inspected `/tmp/teotw-final-fix-tests-final.log` and the focused controller/default/universal build logs. The full-suite log includes all reported passing groups, including PNG integrity, active text persistence and lifecycle. The build logs end with the app path. The implementation report supplies successful command exits, signature/architecture/diagnostic checks and final artifact SHA-256 `5c6e900599f3d8f741e0a2b0b73be93acfcd28873514822fdf246f802dc774b8`. This review did not rebuild or independently recompute that hash.

The PNG validation is a structural/CRC completeness guard for PNG, not a complete semantic PNG decoder or a strict validator for every AppKit codec. Other formats retain their prior AppKit behavior. That limitation does not negate the supplied recognizable truncated-PNG regression; it should remain explicit rather than be presented as universal image-integrity validation.

The full/focused controller logs contain the AppKit constraint-constant warning described in the report. Its origin was not isolated. The changed production code introduces no new layout constant; the extremely large text-container height is outside the changed lines. The warning alone is not evidence of a new Important layout defect in this wave. Native text/IME smoke should watch the resulting layout, and its result must not be inferred from compilation or these headless checks.

Physical monitor reconnection/layout changes, external image paste, Finder drop, actual panel visibility and protected lock-screen rendering remain outside this review. Root owns the planned isolated native smoke. The marked-only insertion issue above was the only load-bearing code issue discovered in the fix wave; the follow-up assessment below resolves it.


## Narrow follow-up assessment: 17d1c78..9ac681b

**Verdict: ADDRESSED. No new Critical/Important issue found in this follow-up.** The diff changes only the provisional-discard condition in production, with focused tests in the existing two suites. `finishText()` now checks the edited layer's accepted **model** text, so a marked-only insertion removes its blank provisional layer rather than generating a committed scene. It does not issue an unmark/insert call or promote a marked suffix into accepted content. New layers with accepted prefixes retain those prefixes and use the existing single history boundary; preexisting layers retain their accepted text.

I inspected the exact authorized follow-up diff, directly relevant code, added tests and `/tmp/teotw-ime-editing-final.log`, `/tmp/teotw-ime-controller-final.log`, `/tmp/teotw-ime-build-universal.log`. The editing tests cover direct finish, native Escape command, focus loss and canvas mouse-down, each with marked-only text and accepted-prefix-plus-marked-suffix text. They assert zero commits/no Undo for discarded provisional input, and one commit with Undo/Redo for accepted input; the existing-text case adds no Undo. Controller tests wait through the real debounce and compare scene/store/consumer for finish/Escape/focus routes, including nil document/countdown fallback. Blocked-recovery additions verify that the damaged original remains intact. These checks address the reproduced mismatch and its persistence consequence without reopening accepted earlier code.

The available focused logs show all these groups passing, together with the previously relevant PNG/Shift/history, text persistence and lifecycle groups. The report records focused suite exit 0 and successful universal build/signature/architecture/diagnostic checks. No redundant suite/build or probe rerun was needed for this one-condition change. The AppKit constraint warning remains in the focused controller log; the earlier limitation assessment is unchanged.

The replacement artifact SHA-256 reported by the implementer is `a2b94f840f0fcc0090bb8c863746ca4b4439b8c0dd5f6b67e4c846ebbe7b8886`, superseding the earlier `5c6e9005…` executable. This review did not rebuild or independently hash it. Root's native smoke against the earlier artifact is separate evidence and must not be represented as execution of this follow-up build.
