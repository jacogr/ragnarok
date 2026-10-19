# Accumulation-bound lookup preimage integration

## Scope and authority

Bind the existing lookup-extrinsic fulfillment operation to the exact
[combined activity candidate](accumulation-activity.md). Authority remains GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`,
`preimagesareordered`, `fnprovidable`, `fnprovide` and the posterior preimage account equation.
Reuse the [preimage transition](preimage-transition.md) interpretation, namespace and canonical
history encoding. No pins, protocol arithmetic, codecs, PVM semantics or namespaces change.

## Contract

Only PreparedAccumulationActivity can construct PreparedAccumulationPreimages. Retain that exact
source; use its original-parent AdmittedPreimages and complete activity successor. Derive the slot
from the same authenticated block through its retained validator/timestamp/finalization/admission
graph. No alternative input, admission, slot or posterior map is accepted from callers.

Before fulfillment, bound the admitted item traversal and total payload bytes independently of the
prior admission policy. Full-width ceilings compare actual counts without narrowing. Fork the exact
complete source map with inherited store ceilings, then call the existing integratePreimages once.
It rechecks posterior requests, ignores missing accounts/requests and canonical nonempty histories,
and fulfills each still-outstanding pair with raw bytes and a one-slot history at the authenticated
slot. Cached admission identities avoid rehashing blob identities or readmitting against posterior
state. Request/value key derivation and complete-map Merklization may still hash.

No replay of accumulation or earlier provision effects, no second statistics update and no mutation
of any earlier snapshot occurs. The immutable acyclic owner retains source, copied admitted
counts/slot and the complete private successor. Failure/default results carry reasons only;
integration failures retain a separately guarded PreimageTransitionError. Defaults are distinct
from initialized empty extrinsics. Empty input still uses the checked complete-map operation.

This extends the supported report-only private candidate. Deferred-transfer recursion, remaining
account/privilege effect merging, whole-block validation/publication and light-state proofs remain
separate. Do not claim every PVM account effect is already represented by the supported merger.
M1 framing is complete; full state serialization and accumulation/block parity remain open.

## Completion tests

Use genuine signed empty, supplied-only and combined block histories, plus real executed guests
which already fulfilled a submitted pair. Compare exact literal one-slot histories and raw empty/
nonempty values; reconstruct complete expected maps independently and compare roots. Check source
admission still points at the original parent, immutable source requests, earlier C(3/13/14/15/16),
account timestamps, unrelated state, copied facts and detached source/snapshot lifetime. Repeated
preparation must yield equal roots without consuming the source.

Reject default and detached input types; enforce exact/one-below item and payload limits before
hashing, including full-width policy tests. Inject immediate key-derivation and late Merklization
backend refusal, require unchanged source root/bytes and successful retry, and exercise 1,000 ARC
success/refusal cycles. Add strict runtime extraction and compiler privacy/nominal probes. Run the
new native suite, affected fixture consumers, source-owned inventory, Python and pinned formatting.
Reuse unchanged pure preimage vector/cancellation/malformed-state algorithm evidence; this wrapper
introduces no caller-selected posterior map to synthesize unsupported account effects.

## Local verification

Passed `make unit SUITE=accumulation_preimages`: signed empty, supplied-only, combined incoming/
available and epoch-crossing histories match independently reconstructed full-map roots. Exact
literal histories and raw empty/nonempty preimages pass, preserving C(3/13/14/15/16), all original
account metadata/timestamps and opaque state. A genuine first-round guest fulfills the submitted
service-42 pair before this adapter, which then integrates only the remaining outstanding values;
the guest's independent service-99 provision also survives. Source reuse, original-parent admission,
scoped source release, copied observations and detached snapshot lifetime pass.

Exact and full-width fulfillment policies pass; one-below item/payload policies and default sources
refuse before hashing. Backend failures at the first and second derivation hashes and final Merkle
hash leave the original activity map unchanged, and retry succeeds. The 1,000-cycle scoped success
and early/late refusal workload retains 1,164,480 occupied bytes before and after.

Six strict runtime result-extraction probes and five compiler privacy/nominal rejections passed.
`make unit SUITE=accumulation_activity` passed with its unchanged 1,751,968 occupied bytes before/
after 1,000 cycles, covering existing signed fixture defaults. `make unit SUITE=accumulation_execution` also passed,
retaining 1,066,800 occupied bytes before/after 1,000 cycles. Python discovery passed 451 tests
with seven skips. Source-owned inventory passed: 117 failure families, 1,713 probes and 182 native
suites. Pinned formatting and diff checks passed. The unchanged preimage algorithms, codecs,
request namespace, PVM implementation and store retain their prior subsystem evidence.

Logs are retained under ignored `build/accumulation-preimages/`; these are local macOS results,
separate from exact-head Linux CI and full block/STF parity. Next bounded work is binding
post-accumulation authorization-pool advancement to the same authenticated candidate. Remaining
transfer/account/privilege merging and whole-block publication stay open. M1 framing remains
complete; full state serialization and accumulation/block parity remain open.
