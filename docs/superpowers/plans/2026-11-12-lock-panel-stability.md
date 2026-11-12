# Lock panel stability implementation plan

> **For agentic workers:** Use subagent-driven-development for one bounded repair task, then independent code review. The user authorized investigation and repair of disappearing/reappearing lock-screen content.

**Goal:** Prevent reproducible controller failure paths that hide a locked composition or leave it absent after a transient error; add useful diagnostics without claiming the reported real-world symptom is proven resolved.

**Architecture:** Explicit session observation (locked, unlocked, inactive, unknown), existing one-second watchdog with bounded retry for missing panels, injectable elevated-space adapter and controller diagnostics. Keep shared rendering and current lock-space mechanism.

**Tech Stack:** Swift5, Foundation/CoreGraphics/AppKit, existing shell/swiftc scripts, macOS15+.

## Global constraints

- Work in existing checkout/branch codex/personal-lockscreen-editor, baseline7444636, no new worktree. All transforms tests/universal build already green.
- User README.md and untracked docs/backlog.md edits exist. Preserve README changes; backlog's prior 'record only' instruction is superseded by user's explicit 'давай' to investigate/fix, update status while preserving observation.
- No automatic lock, personal scene/clipboard mutation, global settings changes, remote push/merge, or production app replacement. No screenshots needed of protected screens.
- Keep noninteractive panel behavior, prompt hide on actual unlock/inactive console, editor restoration, disabled behavior, target-display identity, empty-scene routing and static-scene redraw invariants.
- Existing logs mix old app versions and test runs, so do not attribute actual user disappearance to log transitions without evidence. Repair demonstrated paths, retain manual long-lock validation in backlog.
- Do not introduce a timer beyond existing CountdownController. No unconditional periodic window/space recreation, elevation or reattachment: these may create their own flicker.

## Task 1: Session evidence and recoverable panel lifecycle

**Files:** Sources/Infrastructure/SessionState.swift; Sources/Features/LockScreen/Controllers/LockScreenController.swift; Sources/Infrastructure/LockScreenSpace.swift; Tests/LockScreenControllerTests.swift; any other tests needing initializer changes; scripts/build.sh and Sources/AppDelegate.swift only for source-revision launch diagnostics if useful; docs/backlog.md and new docs/lock-panel-stability-verification.md.

**Interfaces:** Replace ambiguous boolean session reader internally with a typed observation, for example enum LockSessionState { case locked, unlocked, inactive, unknown }; decoder takes injectable session dictionary. Controller accepts an injected session reader. Add narrow protocol for elevated space attach/tearDown and injected factory so tests never create real secure spaces. Inject controller diagnostic sink (default logDiagnostic) so tests do not pollute real application log.

- [x] Add failing decoder/controller regressions. Decode nil/missing console evidence as unknown, explicit off-console as inactive, explicit true/false lock key on-console as locked/unlocked. The private lock key is normally absent on this unlocked Mac (observed --diagnose); distinguish active-console/no-lock-flag evidence from a failed read. Require bounded sustained negative evidence before accepting absence as unlock, so one transient absence does not tear down panels but a missed unlock notification cannot leave them indefinitely visible. Unknown poll must retain an established locked composition, but unknown cold start cannot show it. Actual unlock/inactive must promptly hide and prevent retry. Test real AppKit panels with fake private-space adapter, not real SkyLight during tests.
- [x] Implement clear event reconciliation. A resignation with confirmed locked/on-console evidence must not be mistaken for unlock; inactive console hides panels. Unknown resignation may suspend display until confirmed active/locked for safe user switching; unknown wake must not assert unlock or restore an editor. Add locked/unknown/unlocked/inactive/wake/resign ordering and interrupted-panel-test regression tests. Preserve existing editor deferral/restoration semantics.
- [x] Add recovery for missing panels while display is still wanted using existing tick. Retry after transient panel creation/private-space creation/attachment failure with bounded cadence (e.g.2seconds), no every-tick log flood. Stable panels retain identity, space and contents across prolonged ticks, no static-scene invalidation. Explicit wake/display-change events can retry immediately; disabling/stopping/unlock invalidates recovery.
- [x] Review cached attach behavior: on explicit lifecycle restoration reissue existing-space show/attach rather than treating a previously seen window number as proof it is still attached. Never reattach each normal tick. Keep window-number tracking for teardown and original private API signatures. Test factory failures, attach failure then success, wake restoration and cleanup counts.
- [x] Diagnostics identify session evidence/transitions/source and panel lifecycle recovery plus sparse heartbeat while locked (e.g.30seconds with visible/occlusion info, not user scene content). Add source revision and process ID to launch diagnostics if practical to distinguish installed stale binaries and temporary smoke builds. Tests use injected/no-op diagnostics; log no user text/image paths or clipboard.
- [x] Run focused native lifecycle tests, then full bash scripts/test.sh (private pasteboard host access needed), universal build, strict signature/architectures/--diagnose, git diff --check. No live lock validation claimed.
- [x] Record exact results, diagnosed code paths vs unconfirmed real-world root cause, testing limitations, launch path and manual long-lock/wake/unlock procedure. Update backlog to 'recovery paths repaired; actual long-lock validation pending', not 'resolved'. Commit scoped code/tests/docs, preserving unrelated user README changes.

## Review/completion

- [x] Independent code review against lifecycle invariants, retry behavior, tri-state evidence, no input/lock side effects. Fix concrete findings and rerun affected checks.
- [x] Save current stable build and verification. Leave branch locally without push/merge. Report remaining user-observed validation needed; do not ask the user to approve routine implementation.

## Investigation refinement

The normally unlocked session lacks CGSSessionScreenIsLocked (observed in existing diagnose checks). Therefore absence cannot be treated as unknown forever after a known lock: require a bounded evidence policy for this representation and test a missed unlock notification. Nil session/missing console evidence remains genuinely unknown. Installed /Applications/TEotW.app is a 4 November binary with legacy combined unlock/inactive event label; local build is newer. No application process was running at inspection.

## Live reproduction refinement

User confirmed display stayed on. Root launched current pre-fix build through native UI; user reported composition initially visible, then image disappeared after repeated Escape/Space (key causality unproven). Real diagnostic log13:58:41..47UTC on12November showed up to40 identical locked=true panel setup/attach pairs per second, without lock/unlock/poll transitions; unlock notification13:58:52 cleaned up. Tests were explicitly paused, so this burst was from the running application. Guard screen-parameter handling by a signature of actual display identities and frames: repeated notification with unchanged geometry must retain panel/space identity; actual topology/geometry change still rebuilds. Add100same-event regression and one changed-geometry case, with event-source diagnostics. App was exited via normalCmdQ before resuming tests/build. User will manually retest fresh build; no automatic lock.

## Completion

Code d180c4d; independent review and repair accepted, full tests/universal/signature/diagnose passed. User confirmed short real-lock retest no longer disappears for now. Long observation remains in backlog; no definitive root-cause attribution or production installation. Continuing next spec stage by user request.
