# Publish an assured successor and its direct-child chain view

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, full-state
accumulation publication and direct-child header linkage; vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Consume only ComposedAssuredState. Require the live state and chain head to retain
its exact original parent owner, matching frame domains and all original chain
parameters. Publish the actual maintained composition into a private handle,
encode its authenticated header under the existing capture ceiling, capture the
real child, then append through maintained advanceView. Replace both live handles
only after every potentially refusing operation. Retain source, exact published
snapshot and actual child in immutable acyclic ownership.

Completion: authentic view through blocks1/2 advances to3, retaining finality1,
source aliases, full original parameters and exact composed state. Replays,
default/stale/equal-root replacement parents and mismatched parameters refuse
without changing either handle. Real late hashing/capture and wrong-parent append
failures preserve both handles after private publication. Check default/copy/
detached lifetime,1000 success-plus-late-refusal ARC, strict optimized result and
compiler privacy/nominal guards, inventory, tooling and formatting.

This bounded direct-child append is not fork choice, reorg handling or new finality
validation. Next: extend actual successor guest input/effect scenarios. M1 framing
complete; full serialization, whole-block parity and full chainspec equivalence
remain open.

Observed local evidence: actual prepared predecessor publication reconstructs
view1/2 with exact physical map2 ownership. Atomic publication captures slot3,
retains all29 original parameters, links the full parent hash and prior state
root, adopts the exact prepared map, retains three view entries and finality1.
Source aliases keep map2/timestamp2 and view1/2; child storage remains21/22/23
with timestamp3. Under-quorum six-vote publication genuinely reaches slot3 with
unchanged timestamp2 and pending assignments retained.

Replay, defaults, equal-root different-owner state, stale-view owner and changed
block gas refuse precisely while both live handles remain unchanged. Actual
forced hashing failure preserves CaptureFailure/Invalid after private adoption;
a different structurally captured head preserves ViewFailure/NotChild after
private adoption. Neither failure exposes an installed receipt. Copies and
detached receipt lifetime pass. One thousand success-plus-late-capture-refusal
cycles retain2111008/2111008 occupied bytes, without initial guest replay.

All32 strict optimized runtime guards,9 compiler privacy/nominal guards and35
verification tooling tests pass. Inventory discovers194 failure families,2436
probes and265 native suites. Pinned formatting passes2330 Nim files and the Rust
crate. All3420 predecessor source/config inputs remain byte-identical, so earlier
composition/execution evidence is reused. Local checked-release macOS evidence;
remote CI was not requested.
