# Authorization pool transition

The first bounded non-PVM execution slice implements Gray Paper **0.8.0**, revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/authorization.tex` (pool-update equation),
`text/notation.tex` (leftmost sequence subtraction and newest suffix), and
`text/merklization.tex` (C(1)/C(2)). The unique guarantee-core condition comes from
`text/reporting_assurance.tex`. Source identities remain recorded in [pins.json](pins.json).

## Behavior and scheduling

`src/state/authorization.nim` consumes immutable pool/queue snapshots, an explicit core profile,
a nominal header slot and the core/authorizer projection of already validated guarantees.
For each core it removes the oldest matching used authorizer, appends the queue item indexed by
`slot mod 80`, and retains the newest eight hashes. Duplicates and ordering are preserved.
Subtraction with no matching hash leaves the original sequence intact; this does not establish
that the originating guarantee is valid. Duplicate core projections and out-of-range cores reject.

Queues must be **post-accumulation**. `advanceAuthorizationState` reads C(1)/C(2) from the working
store, requires exact component decoding, computes the complete replacement and atomically writes
only C(1). It does not rotate or rewrite C(2). Accumulation is responsible for queue changes.
A future block executor must schedule this stage accordingly and publish its working state only
when the entire block succeeds. A successful subsystem call is not whole-block validation.

`advanceAuthorization` returns a caller-owned serialized C(1) entry. The store adapter returns
an immutable committed snapshot; historical snapshots and retained values remain valid. Failure
and default result alternatives expose no entry, root or progress. Success extraction requires
checking `error == None`; discriminators and payload fields are private.

## Boundaries and resources

The caller chooses `AuthorizationConfig`; no tiny/full profile is inferred. Native scratch extents,
core conversions and aggregate output hash/byte budgets are checked before payload allocation.
The store adapter checks raw entry sizes before copying, then applies the codec's full input
budgets. Queues have exactly 80 hashes per core; input pools contain at most eight. Pure transition
budgets constrain the output, while immutable input owners retain their original decode policy.
The store's independent map/write/node budgets still apply.

Failures distinguish invalid configuration/state/core, duplicate projections, policy limits,
native extent overflow, missing entries, default stores and backend hash refusal. Failed decoding,
policy checks and root construction leave the old store head unchanged. ARC ownership is acyclic;
allocation failure remains fail-stop. Full-state roots require a complete map. Test-only partial
maps below demonstrate integration, never complete JAM state commitments.

This slice does not validate guarantee ordering, signatures, authorizer membership, package
eligibility or authorization PVM code; derive authorizer hashes; execute accumulation; validate
slot chronology; or implement a complete block executor. These remain separate stages.

## Reproducible evidence

`davxy/jam-test-vectors` revision `d3c089c9a1d5352ad353626d7a2db8589f137b2a`
provides all six `stf/authorizations/{tiny,full}/progress_authorizations-{1,2,3}.json` cases.
Their exact Git blobs and SHA-256 values, plus the published ASN schema and family README, are
pinned in `pins.json`. The fixture helper validates provenance and serializes supplied state;
it contains no pool-transition reference algorithm. Its ignored manifest retains source hashes,
profiles, slots, use counts and generated-payload identity.

Native `authorization_transition` compares exact output bytes for all six published cases and
checks store integration with unchanged queues and an unrelated entry. Derived three-entry roots
are independently recomputed by the existing trie calculator; the fixture family does not publish
full-state roots. Authored cases cover oldest-only duplicate removal, empty/full pools, queue
wraparound and maximum uint32 slot, immutable sources, posterior queue scheduling, nominal core
errors, shape/profile errors, output limits and exact boundaries.

Native `authorization_transition_failure` injects immediate and delayed hash refusal, verifies
rollback/recovery and historical snapshots, rejects missing/malformed/suffixed state, and proves
budget refusal precedes hashing. After warmup, 1,000 scoped cycles require equal live allocator
occupancy; this is workload-specific evidence. Four isolated result misuse probes require the
intended checked precondition and `AssertionDefect`; three compiler probes reject private payload
access, retagging and passing a core index as a slot.

Run `make check-modules check-python check-unit check-guards`. Reports and fresh ARC/provenance
evidence live under `build/tests/`. Live networking behavior is unchanged by this increment.

The next suggested bounded execution slice is recent-history advancement, with its own pinned
state-transition vectors and scheduling contract. The remaining M1 specification checkpoints in
[state-clarifications.md](state-clarifications.md) are unchanged.
