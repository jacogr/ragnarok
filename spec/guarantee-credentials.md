# Guarantee credential verification

`src/state/guarantee_credentials.nim` adds credential certification on top of the
[guarantor assignment foundation](guarantor-assignments.md). It consumes a stable borrowed batch
of guarantees and completed posterior active/previous rosters, entropy, slot and canonical offender
set. It creates an immutable `VerifiedGuaranteeCredentials` owner only after the whole batch passes.
The certificate also retains candidate time and current active population, including empty batches,
through its copied `verifiedGuaranteeContext` accessor. Assignment planning derives these values
from that exact verification rather than accepting another loose clock/population projection.
The existing block coordinator still ends after availability; this module does not publish C(10).

## Normative checks

Gray Paper v0.8.0, commit `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/reporting_assurance.tex`, Work Report Guarantees (`guarantee`, `guaranteesextrinsic`,
`guarantorsig`, `reporters` and the immediately following erasure-shard equality):

1. At most one guarantee per core, in strictly increasing core order. Each has exactly two or
   three credentials with strictly increasing, unique validator indices. Complete report owners
   and their encoded extents must satisfy the current structural/aggregate-byte policy.
2. The report slot selects the current rotation or its immediate predecessor; future/stale slots
   and indices outside the selected roster are refused. The existing assignment planner applies
   posterior offender nulling and selects previous-epoch entropy and roster when appropriate.
3. Every signer must be assigned to the report's core. That core must also be active under the
   **current** population, even when the selected previous roster was larger.
4. Each report's erasure-shard count must equal the **current** active population, including reports
   with previous-rotation credentials. Structural count validity alone does not prove equality.
5. Ordinary Ed25519 verifies exact ASCII `jam_guarantee || BLAKE2b-256(canonical complete report)`.
   Report slots and credential wrappers are not added to this transcript. The existing maintained
   backend's exceptional-point acceptance policy remains unchanged and unresolved as documented.
6. Reporter membership uses the selected roster's actual Ed25519 **key**, not the validator index
   or signature occurrence. The owner exposes a deterministic lexicographically sorted unique set.

See [pins.json](pins.json) for source hashes and the unchanged vector revision. Caller policy bounds
canonical aggregate bytes and distinct reporter keys independently. Malformed-source preflight
happens before assignment/transcript hashing. A batch is bounded to 341 records and three credentials
per record before allocation; safe subtraction precedes aggregate-byte addition.

## Ownership and refusal

The private acyclic ARC owner retains the exact assignment plan, copied guarantee metadata,
immutable report children and copied reporter identities. It exports only checked counts and fixed
copies/retained report handles. Mutating or releasing caller records or extracted copies cannot
alter the certified owner. Its name deliberately certifies credentials, not complete report admission.

Private tagged results expose exact codec and assignment causes only in their selected alternatives.
Default/refused results contain no certified values or progress. Owner/index errors are typed;
result and typed-cause extraction use supported checked-build contracts. A bad later signature,
reporter-budget refusal or later transcript hash failure discards all earlier batch work.

The context supplied to this pure verifier must come from completed Safrole/disputes stages.
It does not authenticate that context, prove a parent-state root, or evaluate authorizer pools,
services/code hashes, accumulation gas, recent/lookup anchors, dependencies, package uniqueness,
post-assurance capacity or state publication. Future admission consumes the certified owner together
with the required parent/staged state context; loose extracted records are ordinary values.

## Evidence and reproduction

Thirty unchanged tiny/full report STF JSONs from davxy/jam-test-vectors commit
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` exercise the composed codec/credential boundary:

- Eight successful projections cover current/previous rotations, multiple reports and repeated
  guarantors under different rotations/cores. Native assertions compare the exact supplied reporter
  key set, including full 1,023-validator tables.
- Twelve malformed projections stop in the existing codec: core/shard domains, validator ceilings,
  insufficient credentials and credential/guarantee ordering.
- Ten well-formed rejected projections fail credential verification: wrong/banned signatures,
  wrong core assignments and future/stale slots.

These are projections of original STF inputs/expected credential outcomes, not claims of complete
reports-STF execution. Python checks source hashes, pools repeated roster encodings and transports
supplied bytes/verdict labels. All protocol assertions and the implementation run in Nim. Selected
reports have empty segment-root lookups, enforced explicitly by transport; no field is silently lost,
input repaired, signature replaced or codec relaxed.

Authored native cases cover two/three signatures, population shrinkage with historical signers,
currently inactive cores, structurally valid wrong shard counts, full-report/domain binding,
canonical source preflight before crypto, selected-roster index bounds, exact aggregate/reporting
budgets, reporter-key deduplication, empty/default owners and retained-copy mutation. A 1,000-cycle
success/early-refusal/first-transcript/second-transcript workload requires equal live allocation
occupancy. Five compiler privacy probes and four runtime result/typed-cause probes protect the API.
This is bounded ownership evidence rather than a general memory audit.

Reproduce with `make check-modules check-unit check-failures check-guards check-python` using the
pinned nightly, ARC and checked Clang LTO. Generated source evidence and fixtures stay in `build/`.

## Next bounded work

[Authorization-pool and service/code-hash/gas policy](report-policy.md) is implemented separately.
[Recent/lookup anchors](report-anchors.md) are also implemented separately.
[Package/dependency checks](report-packages.md) are now separate stages.
[Post-assurance capacity and assignment planning](report-assignments.md) are also implemented.
Next publish C(10) atomically through the block coordinator. Accumulation/PVM execution remains later work.

The [block-bound report planner](report-admission.md) now composes these checks over the real
coordinator result and its retained parent/staged context. Atomic C(10) publication and complete
block-coordinator rollback remain the next bounded increment.
