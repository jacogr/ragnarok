# Accumulation provision union and fulfillment

## Scope and authority

Implement the state-side set union and `fnprovide` application of GP 0.8.0
`accumulation.tex`, revision `07f041dabd073f9018b418e9ee72e79dd2185401`, SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`.
Build on retained [provision effects](accumulation-provisions.md) and
[host dispatch](pvm-accumulation-provision.md), reusing the existing
[preimage fulfillment kernel](preimage-transition.md).

Prepare an immutable union from explicitly supplied owned implication contexts. Deduplicate exact
numeric-service/raw-byte pairs across contexts; the same bytes for different targets remain distinct.
Retain source contexts and independently captured union bytes under explicit context, traversed-item,
per-blob, aggregate-traversed-byte and encoded-byte ceilings. Duplicates still consume traversal/copy
budget. Canonical numeric-service/raw-byte ordering is only deterministic transport for this set.

Apply the prepared union to an explicit complete post-accumulation working store and candidate slot.
Recheck each request there: deleted services, dropped requests and already supplied histories are
ignored. Still-outstanding requests receive exact bytes and the singleton availability timestamp.
All writes/root publication are atomic; malformed state, backend failure and resource refusal expose
no partial map. Preserve metadata, storage, unrelated chapters and extrinsic statistics.

This is a pure state planner/application boundary. The caller chooses the contexts, actual posterior
map and slot. It does not certify terminal context selection, merge per-service account mutations,
execute later rounds, integrate a block extrinsic or publish a complete block transition. Terminal
normalization is implemented in the maintained PVM adapter. The
[terminal-bound wrapper](accumulation-terminal-provisions.md) now selects contexts and verifies the
invocation slot from actual completed executions without changing this explicit lower-level API.

## Completion tests

Check repeated/permuted contexts, duplicate versus distinct targets, raw lexicographic prefix/empty
ordering, copied ownership and retained-source lifetime, exact/one-short local budgets, default
owners and full-width ordinals. Compare literal complete request/preimage bytes and complete-map
roots after fulfillment, cancellation/deletion/already-supplied filtering, and repeated application.
Verify late malformed state, hashing and store-policy rollback; replay existing preimage vectors to
protect shared-kernel behavior. Add result/privacy/nominal guards and 1,000-cycle ARC release.


## Implemented API and ownership

`prepareAccumulationProvisions` preflights every source handle, contribution count and blob extent
before copying. It sorts private copies by numeric service/raw bytes, removes only identical pairs,
proves the exact canonical encoded size and captures an immutable value set. Source handles are
borrowed stably during preparation and retained independently afterward. Traversed duplicates count
against item/byte ceilings; `provisionPlanInfo` distinguishes those inputs from unique items/bytes.
`provisionSourceAt` uses a full-width nominal source ordinal and returns the original immutable
context handle, never a replaceable payload span.

`PreparedPreimageValues` is a separate lower-level value-set certificate from `AdmittedPreimages`.
It captures canonical ordering, raw bytes and content/request identities without certifying prior
extrinsic solicitation or producing extrinsic statistics. Application shares the existing atomic
`fnprovide` kernel and rechecks every current target request. Cached identities make empty, cancelled
or already-fulfilled application avoid all hashing. Extrinsic admission retains its original
prior-solicitation checks, error ordering, metadata and source ownership.

## Local verification

Passed `make unit SUITE=accumulation_provision_integration`, `preimage_transition` and
`pvm_accumulation_provision`. The first suite covers A/B/A duplicate traversal, shared bytes for
different targets, numeric 1/256 ordering, empty/proper-prefix blobs, detached source retention,
copied-input isolation, exact/one-short policies, literal histories at zero/ordinary/uint32-max
slots, complete embedding-map roots, cancellation/deletion/nonempty filtering and a real guest
provide result. It requires no hashing for repeated fulfilled application and checks failed
preparation, late key/root refusals and successful writes across 1,000 ARC cycles.
Occupied bytes remained 204,976 before/after; the other suites retained 10,864 and 770,160 bytes.
The existing preimage suite preserves its sixteen pinned published-vector projections.

Fourteen strict runtime guards and eleven privacy/nominal compiler probes passed. Python discovery
passed 423 tests with five skips; inventory/provenance, pinned formatting and diff checks passed.
Two new source expressions were rewritten to avoid pinned formatter issues; no compiler/toolchain
or upstream source was modified. Logs and guard JSON are under
`build/accumulation-provision-integration/`. These are local macOS checks, not exact-head Linux CI
or complete accumulation/STF evidence.

The [terminal-bound wrapper](accumulation-terminal-provisions.md) now connects actual terminal-selected
effects and invocation slots to this planner. Merging posterior account state, establishing common
round/parent provenance, later rounds and complete block publication remain subsequent work. M1's documented
framing baseline remains implemented; full state parity retains the parked pin-upgrade qualification.
