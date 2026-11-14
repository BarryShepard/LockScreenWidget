# Scoped review: exact affine group resizing

13 November 2026. Base `46eaef5`, local working diff. One read-only reviewer under requesting-code-review; no cascaded review.

Scope: optional affine residual and backward-compatible storage, exact group composition, transformed selection/SAT, individual resize/crop anchors, shared renderer, native text mapping and click routing. User README and AGENTS.md excluded.

Reviewer found no significant issues in the inspected paths. Reviewer did not execute tests or builds. Native runtime checks were the implementer's responsibility.

After review, runtime probes refined native hit routing to a single canvas inverse-coordinate check. Full integration testing then found a hidden zero-size canvas problem; a minimal AppKit reproduction confirmed it. The implementation now uses a non-singular provisional map until layout, initializes containers with positive dimensions, and defers native redraw until geometry is installed. Regression and final verification results are recorded in `../native-affine-groups-verification.md`; no second general review was requested for these scoped corrections.
