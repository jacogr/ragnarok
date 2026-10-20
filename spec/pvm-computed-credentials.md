# Credentials verified against original computed transcripts

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
reporting_assurance.tex guarantees/guarantorsig and C.2 credential cardinality/order.
Vector revision remains `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume ComputedGuarantors, a nominal GuaranteeSlot and two/three borrowed
GuaranteeCredential records. Reject all other counts and non-increasing validator
indices before querying assignments. Snapshot the bounded fixed records before
querying or native verification; retain exactly that verified copy on success. Re-query every index against the same opaque
context for evaluation-slot/selected-roster/core/Phi eligibility before any
signature verification. Recover the original ComputedGuaranteeTranscript through
that context's retained computed source; verify exact fixed jam_guarantee domain
plus original canonical-report hash using each owner-selected Ed25519 key and the
maintained ordinary Ed25519 backend. Accept no replacement report/message/key or
loose assignment as authority. Never add slot/credential wrappers to the transcript.
No report re-encoding, rehashing, guest execution, signing or state publication.

Complete success retains exact source context, evaluation slot and fixed copied
credentials in a private acyclic owner. Guarded fixed count/slot and nominal-index
credential queries do not confer constructor authority. Assignment failures retain
only their typed reason under a guarded cause accessor; no partial successful
credential prefix escapes any refusal. Backend verify=false maps to InvalidSignature,
matching the existing verifier's contract; exceptional-point acceptance policy is
unchanged. Canonicality requires unique indices, not an invented distinct-key rule.

Completion plan: real current two/three signatures; genuine same-rotation slot
change without transcript change; larger prior9 roster across active6 epoch;
count/order/duplicate, future/stale/index/core/offender refusals; modified first/
last signatures and foreign domain/hash/report messages; all assignment checks
precede signature failures; original message equality with independent canonical
report hashing; zero new Blake2b calls under backend refusal; copied caller inputs,
detached lifetime, exact retained provenance and 1000-cycle ARC release including
late signature failure; strict runtime and compiler privacy/nominal guards.

Next: canonical source-bound guarantee materialization and reporter-key extraction.
Report inclusion, full transition-policy/chainspec equality, exporter trust,
availability/finality and signing remain open. M1 framing is complete; full state
serialization and whole-block parity remain open.

Local evidence: checked optimized macOS ARM64 `make unit
SUITE=pvm_computed_credentials` passes genuine original PVM/configuration/anchor/
posterior assignment contexts and ordinary Ed25519 signatures. Both canonical
pairs and triples succeed. The retained message equals a fresh composition over
the original complete canonical report bytes, including exact ASCII domain.
Changing evaluation slot within the same rotation preserves valid signatures;
future/stale slots, wrong cores, selected-roster indices and cumulative offenders
retain precise guarded assignment causes. Prior-epoch indices 7/8 genuinely verify
against previous 9 while the current roster remains 6; those indices refuse under
current selection.

Counts 0/1/4, reversed/duplicate indices, altered first/third signatures and real
signatures on foreign domain, report-hash or another computed report's message
refuse. A damaged first signature with a later wrong-core assignment still returns
AssignmentFailure, proving all assignment preflight precedes cryptographic verdicts.
The bounded fixed credential input is copied before querying or native calls;
retained success stores exactly those verified bytes. Caller record/query/metadata
mutation cannot replace the completed owner. Original map identity and detached
source/credential lifetime remain intact. Under Blake2b-backend refusal, genuine
verification still succeeds and invalid signatures still refuse with zero new
Blake2b attempts. Maintained Ed25519 verification remains real, with unchanged
backend acceptance policy.

Fresh warmed 1000-cycle ARC occupancy is 238096/238096 bytes, including repeated late
third-signature refusal. Eleven strict optimized result/accessor/selected-cause
probes and seven compiler privacy/source/slot/ordinal guards pass with genuine
controls. Formatted semantic checks, inventory, 20 affected tooling tests and pinned
formatting pass. All prior source/build inputs and specification/toolchain pins
are unchanged. Remote CI has not been requested.
