# Atomic computed state and chain-view advancement

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
authenticated block/accumulation state; vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Consume only ComposedComputedState, exact original full StateStore and selected
ChainView. Verify both live handles still retain the original parent. Match
complete original Parameters and authenticated framing domains to the selected
head. Publish to a private store through publishComputedState, encode the actual
admitted sealed header, capture its actual posterior, and use advanceView.
Replace live state/view only after all stages succeed. Retain original computed
publication and real child; preserve selected precise nested refusals. No guest
replay, state recomposition, fabricated snapshot, light-state root substitution,
reorg or finality inference.

Author coherent nine-active-validator inputs before original roots, signing and
computation. Keep old bounded six-active/nine-frame fixtures available unchanged
by default; never relax production profile checks to accommodate them.

Completion: genuine complete computed path with state/head advanced together,
parent aliases and explicit finality preserved; replay, invalid source, missing
state/view, stale/equal-root owners, profile/complete-parameter mismatch, late
capture and direct-child failures leave both handles unchanged; default/private
payload guards, detached ownership and 1000-cycle ARC; changed fixture consumers.

Next: exercise computed execution with observable committed service effects.
M1 framing complete; full serialization, whole-block parity and full chainspec
equivalence remain open.

Observed local evidence: genuine computed execution with nine original active
validators produces the real slot-2 direct child. Both live handles adopt the
exact prepared state; retained aliases and explicit parent finality survive.
Missing/default/stale/equal-root-owner and complete-parameter refusals preserve
both handles. Actual native hashing refusal reaches late CaptureFailure/Invalid
after private state publication; an independently captured different head
reaches ViewFailure/NotChild. Neither leaks the private state into live handles.
The earlier six-active/nine-frame profile still refuses as ProfileMismatch.
Detached receipt and 1000 complete child/view cycles pass with ARC unchanged at
1079904/1079904 bytes. Existing computed publication and roster consumers also
pass fresh 1000-cycle checks (684096/684096 and 320176/320176 bytes).
Twenty-eight optimized runtime guards, nine compiler guards, 35 verification
tooling tests, inventory and pinned formatting pass. Local macOS checked-release
evidence only; remote CI was not requested.
