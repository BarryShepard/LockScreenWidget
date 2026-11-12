# Lock panel stability review — 12 November 2026

Initial range: `7444636..285067c`; repaired code: `d180c4d`. Independent review accepted the repair; actual user-visible long-lock stability remains pending.

---

## stage-review.md

# Independent stage review: 7444636..285067c

Verdict: substantially follows the refined plan, but not final-ready until the editor-restoration regression below is fixed. No Critical findings. One Important finding and one Minor lifecycle contract gap. Real secure-lock/long-lock validation remains explicitly pending and is not a review prerequisite.

## Important

### Preserve deferred editor restoration across an inactive session

`Sources/Features/LockScreen/Controllers/LockScreenController.swift:218–224`

The inactive branch sends `.deferEditor`, then clears both `locked` and `suspended`. A subsequent confirmed `.unlocked` wake or poll sees `changed == false` and never sends `.restoreEditor`. Returning with the host's normal `.activeWithoutLockFlag` representation also cannot recover: line 206 ignores that evidence when both flags are false. Consequently a panel test interrupted by switching away from the console leaves the editor hidden on return unless a separate unlock notification happens to arrive. The previous wake path restored it on an unlocked active return. This violates the explicit editor deferral/restoration requirement.

Retain inactive/deferred state independently from whether lock panels are displayed, and complete restoration once unlock is confirmed. Unknown wake must continue to leave restoration deferred. Add regressions for panel test → inactive → unlocked wake and inactive → two normal active/no-lock-key polls.

Focused compiled probe using the real controller, injected session reader, no-op diagnostics, an empty panel factory and no private space creation reproduced:

```
inactive -> unlocked wake/poll completions: [PanelTestCompletion.deferEditor]
```

## Minor

### A refresh can restart lifecycle work after stop

`Sources/Features/LockScreen/Controllers/LockScreenController.swift:103–108`

`stop()` resets the lock flags, but `refresh` has no observing guard. The next refresh with `.locked` evidence immediately enters reconciliation and invokes panel creation again. This contradicts the planned “stopping invalidates recovery” contract. The current application stops the countdown timer before the lock controller, so no ordinary production shutdown regression was established; severity is therefore Minor rather than a claimed user-visible failure.

Keep the `currentDisplay` calculation available before start (LayoutTests relies on it), but guard subsequent lifecycle work once the controller is not observing. Add a stopped-controller refresh regression. The same narrow probe printed:

```
post-stop panel factory calls: 1
```

## Compliance and quality assessment

Typed nil/missing-console evidence remains unknown, off-console evidence hides panels, and active/no-lock-key evidence uses the agreed two-poll policy. Known-lock unknown polls retain the composition, unknown cold start does not display it, and unknown resignation/wake safely suspends panels without asserting unlock. Explicit unlock and inactive cleanup order the content out before tearing down the elevated space. Missing panels retry on the existing tick with a bounded cadence; normal stable ticks neither recreate windows/spaces nor reattach them. Scene content is not invalidated by stable ticks. Cached screen identity/frame signatures are set before panel mutations, suppressing unchanged screen notifications including reentrant copies. Actual screen changes still rebuild, and explicit confirmed-lock wake reattaches. Production space teardown is idempotent; scheduled panel-test callbacks are generation-invalidated, and delayed lock callbacks check observing/lock evidence.

New lifecycle tests use fake private-space adapters/no-op diagnostics. Source revision/PID diagnostics and documentation distinguish repaired paths from the unproven real-world notification source. The installed November 4 app remains outside this change. No user README modification, remote operation, real private-space exercise or automatic lock was performed by this review.

The lock-key decoder also maps a present but non-Bool value to `.activeWithoutLockFlag`. A stricter decoder could preserve `.unknown` for malformed data, but no such actual session payload was observed and the plan specifically addresses the normally absent key; this is not raised as an additional concrete blocker.

Reviewed the full supplied diff, full current controller/space/decoder, related restoration/timer/application wiring and relevant tests. Did not rerun the full suite or universal build; relied on the supplied successful validation report. Ran only the focused local compiled probe above. No source, index or HEAD changes were made; only this review artifact was written.

---

## scoped-rereview.md

# Scoped re-review: 285067c..d180c4d

Verdict: ready for the planned manual retest. No open Critical, Important or Minor findings in the repair diff. The prior Important and Minor findings are closed.

- Deferred editor restoration now has independent state. Inactive cleanup keeps that intent, explicit unlocked wake/poll completes it, and two active-console/no-lock-flag polls also complete it. Unknown evidence does not restore the editor. Restore/discard completions clear the pending state, including stop.
- Refresh calculates currentDisplay before checking observing, preserving the pre-start countdown usage. A stopped controller cannot read session evidence, recreate panels, retry attachment or emit heartbeat through refresh.
- An absent lock key retains the agreed negative-evidence policy; a present malformed value is unknown.
- Added tests exercise inactive interruption followed by unknown and explicit unlocked wake, two-poll missing-key confirmation, stopped refresh suppression and malformed key decoding. The explicit unlocked poll shares the same reconciliation branch as the tested wake. No additional probe is needed for this bounded repair.

Reviewed only the supplied repair diff and appended implementation report for fixes and new breakage; did not repeat the original full-stage review or rerun the suite. The implementer reports successful focused/full tests, universal build, strict signing, both architectures and diagnose. Documentation now correctly records disappearance of the entire composition and the revised build hash.

This readiness verdict does not establish that the user-observed disappearance is resolved. Real long-lock/manual retest and attribution of the earlier notification storm remain pending as documented. No application launch, secure-space exercise, source/index/HEAD modification or remote operation was performed by this review.
