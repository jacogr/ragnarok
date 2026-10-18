# Disputes and derived block offenders

Target: Gray Paper **0.8.0**, `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/judgments.tex` (extrinsic constraints, verdict thresholds, non-positive assignment removal,
posterior sets and header marker), composed with `header.tex` and `safrole.tex`.
Vector revision remains `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

## Context and validation

`src/state/disputes.nim` reads exact complete parent C(5), C(8), C(9), C(10) and C(11).
Rosters and epoch selection precede Safrole rotation. A verdict may select the parent's epoch or
one less; epoch zero never wraps. Its exact quorum and one-third threshold use the **selected
population**, including a resized previous roster. Every judgment is verified with ordinary
Ed25519 over ASCII `jam_valid` or `jam_invalid` followed by the raw report hash.

Existing canonical codecs enforce strict report/judge/evidence order and uniqueness within each
sequence. Contextual validation rejects previously judged reports, invalid quorums/splits,
unrecognized or previously punished evidence keys, wrong posterior report classes, invalid
signatures and new good verdicts without fault evidence. Culprits sign `jam_guarantee` plus the
raw report hash. Evidence keys may belong to either parent active or previous roster. There is
**no minimum culprit count** for a bad verdict under 0.8.0.

C(5) unions good/bad/wonky reports and cumulative offenders into canonical sorted sets. The header
marker instead preserves the literal **culprits followed by faults** sequence. A key appearing in
both sections occurs twice in that marker and once in the cumulative state set. No implementation
fallback sorts/deduplicates a malformed input or accepts an alternate signing domain.

Only newly bad/wonky verdicts remove assignments. Compare B(the complete canonical assigned work
report), not its package hash; clear both the guarantee and registration together. Good and
unrelated assignments retain all original fields. Existing complete-state child codec constraints
remain enforced; existing parent guarantee signatures are not reauthenticated by this stage.

## Ownership, limits and publication

Planning returns an opaque immutable `DisputesPlan` with retained complete parent context,
C(5)/C(10) snapshots and checked marker extraction. Refused/default results contain no plan or
partial state. Independent finite ceilings cover input, parent chapters, roster populations,
posterior set sizes and serialized bytes. Unique insertions are charged before allocation.
Allocation exhaustion remains fail-stop; cryptographic refusal returns a typed failure.

`publishDisputes` rejects a plan applied to a different complete parent root. It changes only
C(5)/C(10) through an atomic write batch and preserves no-op budgets. Planning and failed
publication leave all original entries/root unchanged.

`src/state/block_transition.nim` adds `advanceBlockState`: #27 admission binds one block, disputes
come from that block's own extrinsic, and the literal marker is checked against its own header.
Safrole receives the derived complete posterior offender set, never a caller-supplied projection.
Disputes and Safrole run on a private store handle. One final handle replacement publishes all
accepted changes; any later signature, marker, policy or publication failure discards private
changes. The original `advanceBlockSafrole` remains a lower-level API for independently validated
offender inputs; the new composed entry point requires none.

Full-node complete maps only: this does not turn partial light-node mappings into state roots.
Wall-clock policy, other extrinsics, complete block execution/import and PVM remain open.

## Published evidence and an explicit fixture incompatibility

All **60** pinned tiny/full disputes STF JSON blobs are individually hash-pinned in `spec/pins.json`.
Transport helpers serialize supplied fields and expected answers; native tests own transition,
signature, error, marker and posterior-byte assertions. No reference transition replaces Nim logic.

**58** published cases match their original expected acceptance/rejection (19 successes, 39
rejections), including previous-epoch and resized-previous-roster quorum cases. The remaining two
published `progress_invalidates_avail_assignments-1.json` cases are nominally positive upstream but
contain documented dummy assignment guarantees with **zero credentials and zero erasure shards**.
Those are not valid complete C(10) children under our existing codecs. Both unchanged inputs are
explicit `InvalidState` regressions, recorded separately in fixture evidence; these are not counted
as passing positive STF parity. Upstream's [disputes README](https://github.com/davxy/jam-test-vectors/blob/d3c089c9a1d5352ad353626d7a2db8589f137b2a/stf/disputes/README.md)
describes these dummy assignments. No production relaxation or fixture repair is introduced.

Separate authored cases use valid complete reports/guarantee framing and actual Ed25519 signatures
to test bad/wonky clearing, good/unrelated assignment retention, repeated cross-section offender
markers, bounded growth and assignment-hash refusal. A 1,000-cycle success/refusal workload checks
unchanged live Nim allocation occupancy; this is bounded ownership evidence, not a memory audit.
Ten unchanged signed trace blocks also execute admission, disputes and Safrole together. A labelled
authored block stages a real new offender, then fails Safrole authentication; every original map
byte/root survives. Changing its marker is rejected before ordinary seal verification.

Reproduce with `make check-modules check-unit check-failures check-guards check-python`.
Prepared byte transports, hash identities and reports remain under ignored `build/`.

## Next bounded work

The stacked [availability transition](availability-transition.md) verifies assurances and updates
post-disputes C(10). Next: guarantor assignments and guarantee validation/new assignment, followed
by the remaining non-PVM execution pipeline.
