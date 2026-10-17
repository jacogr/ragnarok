# Safrole ticket admission

Target: Gray Paper **0.8.0**, revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/safrole.tex`, The Extrinsic and Tickets (`ticketsextrinsic`, `enforceticketlimit`,
identifier ordering/disjointness, accumulator union/truncation and submitted-ticket retention).
The Bandersnatch appendix and [the maintained primitive contract](bandersnatch.md) define proof
verification. Existing Gray Paper hashes remain unchanged in `spec/pins.json`.

## Input and output contract

`src/state/ticket_admission.nim` implements `admitSafroleTickets`. It borrows exact serialized
C(4), fixed owned ticket records and posterior entropy[2] synchronously. The caller supplies
parent/new slots and explicit chain/resource parameters. The C(4) input must already contain
posterior pending validators and their ring root, while retaining the prior accumulator and
schedule. The result is a complete immutable candidate C(4) snapshot; no state store is modified.

The caller must preserve the parent slot before time advancement. The working-state adapter described below reads the staged
C(4)/C(6)/C(11) from one immutable store snapshot. The caller coordinates roster rotation and
entropy/time, retaining parent inputs for later schedule/marker rules. Supplying authenticated header entropy, posterior disputes
results and correct stage inputs remains the caller's responsibility. This API does not prove
those earlier stages occurred or treat an isolated candidate as an executed whole block.

On successful admission, pending validators, ring root and every schedule slot are unchanged;
only the ticket accumulator is replaced. Copied immutable codec ownership retains the candidate
after source buffers, proofs and local native setups leave scope. No borrowed bytes escape.
The result discriminator and payload are private; default/failed alternatives expose only their
reason and successful extraction requires the checked contract.

## Protocol rules

- Parent/new slots must strictly advance; a zero epoch or unsupported tail/profile rejects.
  Tiny uses epoch 12, tail 10, block limit 3; full uses 600, 500, 16.
- New submissions must fit the explicit block limit and must be empty at/after the target epoch's
  tail start. Empty submissions remain valid there.
- Each new attempt must be less than **ceil(2*epoch/pending population)**. This follows resizing,
  rather than assuming a fixed two-attempt profile. Old accumulator attempts are not revalidated
  against a different posterior population.
- Verification uses exactly ASCII **`jam_ticket_seal` || posterior entropy[2] || E1(attempt)**,
  48 bytes, with empty additional data. There is no dollar byte, count, compact attempt, slot,
  terminator or extrinsic encoding in the transcript. The existing external JAM ticket evidence
  in [the primitive tests](../tests/test_bandersnatch.py) independently establishes this domain.
- Only the successful primitive's 32-byte output becomes an identifier. Proof bytes are never
  interpreted as an already authenticated score. The chain's 3*cores capacity selects the
  pinned setup domain, including after roster resizing. The current SRS bounds cores to 2..341.
- Submitted identifiers must already be strictly increasing. No sorting or duplicate-removal
  fallback is applied. Membership against the prior accumulator compares identifiers alone,
  regardless of the stored attempt. The prior accumulator itself must be strictly ordered and
  unique; invalid source state is not repaired.
- The Gray Paper's disjointness equation refers to the prior accumulator without an epoch
  qualifier. That check is retained even on crossing. The union's prior side is then empty on
  any epoch crossing, including a multi-epoch skip; otherwise it is the unchanged old contest.
- A bounded linear merge retains the lowest epoch-sized prefix. **Every submitted ticket must
  survive**: a valid proof whose score would be discarded rejects the entire candidate.
  A smaller local accumulator ceiling refuses the operation instead of accepting fewer winners.

Positive epoch/population and native typed extents are proved before division, twice-epoch
arithmetic, narrowing or allocation. Per-chapter bytes, codec population/schedule/accumulator
policies and submitted/output counts remain explicit. All serialized C(4) bytes must be consumed;
truncation and suffixes reject. Allocation failure remains fail-stop.

Nonempty batches create one scoped trusted-SRS setup and reuse it across their proofs. Every
success/refusal releases that native owner. Empty batches create no setup and make no proof call.
Setup/backend/panic refusal becomes `BackendFailure`; malformed or non-verifying proofs become
`InvalidProof`. These remain distinct from an invalid attempt, order, duplicate, submission window
or non-retained ticket. The existing primitive's audit/exceptional-point limitations still apply.
No dependency/compiler patches or insecure proof-generation features are introduced.

## Evidence and reproduction

Vector revision `d3c089c9a1d5352ad353626d7a2db8589f137b2a` supplies 28 unchanged JSON cases:
`stf/safrole/{tiny,full}/publish-tickets-no-mark-{1..9}.json` and
`publish-tickets-with-mark-{1..5}.json`. Exact blob SHA-256 values are added to `spec/pins.json`;
no gitlink advances. The helper verifies those pins before transporting supplied proofs,
posterior entropy/root/roster inputs and expected accumulator values. It contains no proof,
ordering, selection or transition implementation.

Native `ticket_admission` verifies exact rejection causes and compares the complete candidate
bytes against a deliberately scoped projection: published posterior accumulator, supplied
posterior pending/root, and the **prior schedule**. These checks do not claim full Safrole STF
conformance; published post-state schedules, markers and other stages are not executed here.

Authored checks cover altered entropy, eligible-but-changed attempts, late proof mutation,
intra-batch duplication, duplicate identifiers with a different stored attempt, non-retained
scores, noncanonical source contests, skipped-epoch reset, cross-epoch disjointness, local
ceilings, default/overflowing epoch lengths, repeated/wrapped slots, truncated/suffixed state,
empty-tail admission without a backend setup and escaped immutable owners. Native setup live
counts must return to zero on successful and refused calls. This is scoped lifecycle evidence,
not a general leak or cryptographic audit. Two privacy compilation checks and two isolated
runtime misuse probes protect result extraction.

Run `make check-modules check-python check-unit check-guards`. Prepared fixtures, exact source
hashes, native logs and reports live under ignored `build/tests/`. Existing independent corpora
remain unchanged. Networking behavior and [M1 specification checkpoints](state-clarifications.md)
are outside this increment.

## Atomic working-store adapter

`src/state/ticket_state.nim` adds `admitSafroleTicketsState`. The caller supplies the retained
parent slot and target slot. Run roster/root rotation first, then entropy/time advancement, then
this admission step on the private working store. Exact C(11) must already equal the target slot;
C(6) must be exactly 128 bytes. The adapter obtains entropy[2] from that same retained snapshot,
checks the C(4) byte ceiling before copying it, and delegates complete admission to the core.

Only C(4) is published, through the existing atomic one-write store batch. C(6), C(11) and every
unrelated chapter remain byte-for-byte unchanged. A fully validated candidate identical to the
stored C(4) returns the prior snapshot, without a store hash or write-budget requirement. Empty
same-epoch tail admission therefore works with zero permitted writes and unavailable primitive
backends. Default stores, missing required chapters, wrong stage time and malformed values refuse.

The publication result has a private discriminator/payload with the same reason family as core
admission, extended by `MissingState`. Failure exposes no snapshot, accepted prefix or root.
First/late commitment hash refusal and all value/map/batch budget refusals preserve the complete
prior mapping and its root. Retained snapshots and explicit extracted byte copies remain independent
of later store replacement or caller mutation. No callback, borrowed pointer or ownership cycle is
introduced. Re-encoding copies only a candidate already validated under the same finite policy.

This is substep atomicity: an admission failure does not undo prior changes in the private working
store. Canonical whole-block publication must wait until all stages succeed. Matching recorded time
does not authenticate earlier stages or the header; the caller must supply the correct validated
pipeline context and retain parent values. Partial light state must not be hashed through this
complete-map store as a full chain state root.

The additional native `ticket_state` profile runs all 28 source projections after the **actual**
entropy/time store implementation. Eighteen accepted cases compare all four posterior entropy
words to their upstream values as well as the exact projected C(4); ten refused cases propagate
the exact protocol cause and preserve the complete staged mapping. Input rotation remains supplied
by the existing fixture projection; this is not full Safrole STF execution.

Authored publication cases cover setup/verification refusal, first/late store-hash refusal, zero/
one-write budgets, exact/one-byte-below batch/per-value/whole-map byte ceilings, every missing/
truncated/suffixed required chapter, stage-order refusal before native work, the pre-copy C(4)
ceiling, recovery, escaped snapshots, extraction-copy mutation and both schedule alternatives.
A scoped 1,000-cycle empty-admission workload requires identical live Nim allocation occupancy;
its fixture/store allocations remain retained throughout. Native setup live counts also return
to zero after calls. These are workload-specific lifecycle checks, not a general memory audit.
Two additional compiler privacy checks and two isolated runtime extraction probes protect the
publication result. Runtime assertion probes run in the independent `check-failures` CI group.

## Next bounded work

Ticket admission and its C(4) adapter are complete within this documented scope. The next
[schedule selection and atomic working-store publication](sealer-schedule.md) are implemented. [Header epoch/winner marker validation](safrole-markers.md) is implemented separately. Seal authentication
and complete Safrole/block execution remain later increments. Retain the parent accumulator
through all stages rather than using newly admitted tickets for schedule/marker selection.
