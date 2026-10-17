# Validator roster rotation: first commit

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

## Deliberate first-commit boundary

This is a **roster plan**, not a completed Safrole transition. No state store is modified, no C(7)
write is proposed, and no new epoch ring root is yet computed. The existing standalone roster
codec's staging tag is used only to capture a structural pending-roster snapshot. It is not a
replacement C(4) serialization or an instruction to overwrite staging.

Next commits in this PR must derive the pending Bandersnatch ring root under the maintained
primitive API, integrate the complete C(4) fields without silently changing schedules/accumulators,
and publish coordinated C(4)/C(8)/C(9) changes atomically. Ring padding/invalid-point policy,
backend refusal, budgets and historical snapshot lifetimes require focused evidence there.
Until that work is complete, callers must not publish this plan as a complete rotation.

Tickets, fallback schedules, epoch/winner markers, seal/VRF authentication, complete disputes and
full Safrole/block execution remain outside this planner. Those stages must supply their own
validated inputs and shared epoch-ordering contract. Wall-clock admission is not implemented here.

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
Run `make check-modules check-python check-unit check-guards`; generated provenance, source hashes,
logs and fresh ARC evidence live under ignored `build/tests/`. Networking behavior, all existing
corpora and [M1 specification checkpoints](state-clarifications.md) are unchanged.
