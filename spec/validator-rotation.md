# Validator roster and ring-root rotation

Protocol target: Gray Paper **0.8.0**, revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/safrole.tex` Key Rotation
(`validatorkeys`, `valcount`, rotation tuple and `blacklistfilter`), with `text/header.tex`
strict parent-slot ordering. Existing source SHA-256 pins cover these definitions.

## Implemented planner

`src/state/validators.nim` provides `planValidatorRotation` over four immutable codec snapshots:
staging, pending, active and previous. It takes the prior/target slots, explicit positive epoch
length, the **posterior** offender set from disputes, and explicit resource policies.

Within an epoch it preserves pending, active and previous. On any epoch crossing it returns:

- Pending: staging records with each offending Ed25519 identity replaced by a completely zeroed
  **336-byte validator record**, including Bandersnatch, Ed25519, BLS and metadata fields.
- Active: the original pending roster.
- Previous: the original active roster.

Filtering preserves every ordinal and the complete population; it does not remove, compact,
sort or deduplicate validator records. Non-offenders retain every byte. The comparison uses only
the Ed25519 key; opaque metadata and other key fields cannot determine offender membership.
A multi-epoch skip rotates once from the original input tuple, not once per skipped epoch.
All three populations may differ, while each remains an allowed multiple of three in 6..3*cores.
Staging is never mutated or published by this API.

The input offender set must be strictly increasing and unique by full-key octet order, matching
the existing canonical C(5) contract. Duplicates/descending keys reject; no sorting fallback.
Canonicality and caller offender ceilings are checked even when no epoch change occurs. Membership
uses binary search rather than a quadratic full-roster/full-offender scan. No borrowed offender
bytes survive the synchronous call.

All four input owners are validated against the selected roster policy before output allocation.
The existing codec's size preflight checks native typed/wire extents and per-roster byte/count
limits. Default owners reject. No profile is inferred and equal/backward/wrapped slots reject.
Empty/zero-filled key bytes remain structural values, not claims of cryptographic validity.
The epoch length remains uint64 through division, including the maximum value, without slot
addition/multiplication. Zero is rejected before division.

The filtered pending roster is newly captured in immutable acyclic ARC storage. Old pending/active
owners can be shared read-only for the other posterior rosters; callee-local origins need not stay
alive. Returned handles expose only the existing copied record/count APIs. A caller may replace
its copied handles but cannot mutate retained storage. Result defaults/failures carry only a reason;
success payload and discriminator are private and extraction requires the supported checked contract.
Resource ceilings apply per roster plus offender count; no aggregate whole-state budget is claimed.
Allocation failure remains fail-stop.

## Atomic working-state publication

`src/state/validator_state.nim` adds `rotateValidatorState` over the complete-map working store.
It reads exact C(4), C(7), C(8), C(9) and C(11) values. Caller-selected per-chapter byte ceilings
are checked before copying, followed by exact codec consumption and population validation.
Its separate guarded result publishes only a completed immutable snapshot; default/failed
alternatives expose no root, snapshot or partial progress.

On crossing, it computes the filtered pending ring through the maintained Bandersnatch adapter,
then encodes and atomically publishes **C(4), C(8) and C(9)** in one store batch. C(4)'s existing
sealer schedule and ticket accumulator are preserved exactly, for both schedule alternatives.
Staging C(7), parent time C(11) and unrelated entries are untouched. Inside an epoch the fully
validated call returns the prior snapshot without setup, ring commitment, hashing or writes.

The ring setup uses the chain profile's **3*cores capacity**, not the current roster length.
This distinction is observable: full `enact-epoch-change-with-set-resize-1.json` moves from 1023
pending validators to six, but its published commitment uses the full domain. A six-capacity
setup produces a different root; the full-profile setup reproduces the exact supplied root.
There is one policy, with no alternate-root fallback. The current trusted SRS limits the adapter
to 2..341 cores (maximum 1023 members). This is a bounded implementation policy, not an assertion
that Gray Paper mathematical populations have a universal 1023 ceiling.

Each crossing creates a scoped immutable native setup from the pinned public ceremony SRS.
It is released on every success/refusal return; no setup cache or background owner is introduced.
This prioritizes a simple correct lifecycle over optimizing a once-per-epoch operation.
The existing `commitRing` normalizes only invalid encodings/subgroup failures to the specified
padding point, preserving member order. It does not rewrite stored roster keys or re-filter
old pending/active rosters. Valid identity-member refusal and the backend's remaining audit
limitations are inherited from [the primitive contract](bandersnatch.md), not silently repaired.
Any setup/commit refusal becomes `BackendFailure`, with no proposed state publication.

A failed posterior C(4) encoding, aggregate store budget or candidate-root hash leaves all
three chapters and the complete prior root unchanged. Retained input/output snapshots outlive
callee-local owners and later store-handle replacement. Allocation failure remains fail-stop.
Limits bound the individual chapters, offender traversal and aggregate store writes/map; no
claim of arbitrary-memory allocation recovery or whole-block atomic execution is made.

**Stage ordering:** run this substep exactly once after obtaining posterior disputes offenders
and before `advanceEntropyTimeState`, while C(11) still contains the parent slot. This API does
not advance time or mark a block applied; repeating it before time advancement would rotate
again. Future block orchestration must stage these operations on a private working store and
publish a canonical block only after all stages succeed. Do not call this against partial light
state or treat its substep snapshot as an executed full-block result.

Tickets, fallback schedule generation, epoch/winner markers, seal/VRF authentication, complete
disputes and full Safrole/block execution remain outside this roster/root increment. Those stages
must supply validated inputs and use the shared epoch-ordering contract. Wall-clock admission is
not implemented here. The next bounded increment can implement Safrole ticket admission before
schedule/marker generation, with independently published proof and rejection cases.

## Evidence and reproduction

Sixteen pinned Safrole JSON sources at vector revision
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` provide unchanged roster projections:

- Tiny/full `enact-epoch-change-with-no-tickets-{1,2,3,4}.json`, `skip-epochs-1.json`,
  `skip-epoch-tail-1.json` and `enact-epoch-change-with-padding-1.json`.
- Full `enact-epoch-change-with-set-resize-{1,2}.json`.

Fourteen accepted sources compare every byte of the three posterior rosters; two repeated-slot
sources verify typed failure. These are projections, not claims of executing the complete STF.
The fixture helper validates exact Git-blob SHA-256 pins before transporting supplied tuples and
expected results. It contains no rotation/filtering reference algorithm. Identical complete roster
byte strings share fixture storage only; records within any roster are never deduplicated.

Native `validator_rotation` compares published outputs, unchanged inputs, explicit offender
canonicality and count budgets, a one-byte-below/exact 2017-byte six-record budget, late-owner
profile rejection, zero/maximum epoch lengths and slot boundaries. Literal first/last-offender
checks inspect **all 336 null bytes**, preserve non-offender bytes and retain differing population
sizes. Returned plans outlive source owners; source/extracted-copy mutation cannot change them.
After warmup, 1,000 scoped cycles require identical live allocation occupancy. This is
workload-specific ARC evidence, not general leak freedom or an allocation-failure audit.

Two compiler rejections protect result payload/discriminator privacy. Two isolated runtime probes
require the intended result precondition plus `AssertionDefect` for default/actual failed plans.
The additional `validator_state` suite compares all sixteen supplied roster/root projections,
including both resizing sources and tiny/full offender padding, and compares C(4) bytes while
retaining prior schedule/accumulator fields. That projected C(4) is deliberately not the complete
published STF post-state. An authored ticket schedule/nonempty accumulator verifies the alternate
branch. Setup/commit refusals, first/late candidate-root hash refusals, every missing/truncated/
suffixed required chapter, exact/one-byte-below aggregate write budgets, recovery and retained
snapshot lifetimes reject partial updates. Live native setup counts return to zero after calls.
The existing 1,000-cycle ARC evidence remains for the roster planner, not repeated SRS creation.
Two additional compiler privacy probes and two isolated runtime extraction probes protect the
publication result. No Python production transition algorithm or duplicate reference is added.

Run `make check-modules check-python check-unit check-guards`; generated provenance, source hashes,
logs and fresh ARC evidence live under ignored `build/tests/`. Networking behavior, all existing
corpora and [M1 specification checkpoints](state-clarifications.md) are unchanged.
