# Safrole ticket admission: first slice

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

The caller must preserve the parent slot before time advancement. A future working-state adapter
will coordinate the existing roster rotation and entropy/time substeps, retaining parent inputs
for later schedule/marker rules. Supplying authenticated header entropy, posterior disputes
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

## Remaining PR work

Next: a bounded working-store adapter for atomic C(4) publication, preserving unrelated chapters,
with hash refusal, byte/write budgets and retained historical snapshot tests. Schedule generation,
epoch/winner markers, seal authentication and complete Safrole/block execution remain separate
increments. Keep the parent accumulator available for those future schedule/marker rules rather
than treating the admitted candidate's accumulator as every stage's input.
