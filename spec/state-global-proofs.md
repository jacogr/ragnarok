# Global authenticated read interfaces

Scope: extend root-bound partial evidence reads to global state components using the current
pinned Gray Paper and existing state codecs/layout. No wire-format, root-authority, complete-map,
light-mode startup, storage-backend, PVM or compiler/dependency pin change is authorized here.
Public RPC methods/schema remain the RPC owner's boundary.

## Generic query plans

`state/proof_plan` owns a root-free immutable `StateProofPlan`. Explicit caller count/native
extent checks precede copying and sorting; duplicate capture keys refuse. Explicit union counts
exact unique output before allocation and coalesces only equal fixed identities. Sorted ordinal
and iterator access expose fixed copied keys. Default plans are invalid; explicitly captured empty
plans are valid and authorize no facts. Plans never grant verified roots or complete-map provenance.

`state_global_proof_plan` covers shuffled capture, caller mutation, duplicate/default refusal,
exact/short limits, ordinal boundaries, canonical iteration and exact coalescing/empty union.
Existing service plans and callers remain unchanged in this foundational layer.

Next: adapt service selectors without changing their public errors, generalize authenticated
transport/generation, then add bounded typed global readers with missing/absent/malformed
separation and independent selected-root tests. M1 framing/current request namespace are
implemented; full state serialization/STF parity remains open.

## Service compatibility

Existing semantic `ServiceProofPlan` selectors now wrap the generic immutable owner. Their
constructors, guarded result/error spellings, ordinal bounds, count limits and coalescing union
remain unchanged. `toStateProofPlan` explicitly exposes only root-free requested identities,
allowing bounded union with global requests; default service plans convert to invalid generic
plans. There is no implicit converter or public route to forge a semantic service selector.
`state_service_proof_plan_adapter` checks conversion, exact global/service union, source
independence and service error compatibility; existing selector/union consumers remain controls.

## Planned verification and transport

`state/planned_proof` authenticates the exact sorted global/service query set under independent
caller root authority and reuses RPV1 encoding. The shared proof-view decoder has an explicit
expected-plan overload: count and each fixed key must match before witness copying/hashing.
The original unplanned overload retains its existing behavior through the same implementation.
No parallel decoder or alternate representation is introduced. Aggregate/view policies intersect
before atomic proof verification; no failure exposes a verified prefix.

`state_global_proof_transport` uses independently rooted mixed state, every truncated wire prefix,
measured zero-hash scope/budget refusals, every backend-failure prefix, wrong-root authentication
and byte-for-byte compatibility with the existing service encoder.

## Complete-source generation

Generic plans drive `generatePlannedProofs` for complete immutable StateStore snapshots and
`generateBlockPlannedProofs` for one exact retained block's posterior state. Existing service
generation delegates to these paths with unchanged errors and authority. Plan count/native
extents precede key allocation; complete-map preflight remains the established store adapter.
`state_global_proof_generation` covers independently rooted global membership/absence, measured
zero-hash count/map refusals, invalid plans/selections and a genuine signed selected-block root.
No storage implementation or partial-to-complete state conversion is introduced.

## Managed global requests

Generic `StateProofPlan` overloads of query capture and Services admission use the established
single worker, crypto-work preflight, detached plan capture and exclusive canonical/RPC lease.
Global encoding/view refusals expose guarded `ViewFailure/viewError`; legacy service overloads
retain `ServiceFailure/serviceError`. Both preserve exact nested proof failures. Stage capture
remains a separate concrete procedure activation before submission. Both overloads finish that
activation before entering the shared pause/submission path. Cancellation, Done and joined close rules
are unchanged. Native generic execution independently receives the resulting RPV1 under the
selected posterior root; existing service capture/execution/worker/Services suites remain controls.

## Chapter reads and time

`proof_global` selects nominal `StateChapterId` identities through bounded root-free plans.
Duplicate selectors refuse; explicit empty capture is valid. `readProofChapter` bounds the cached
verified byte length before copying and reuses exact typed chapter capture with the caller's
profile/policy. It returns an immutable single-chapter owner, never a complete snapshot.
`readGlobalTime` provides a consistent global result while preserving the established time API.
Missing witnesses, proven absence, malformed present values and resource/configuration refusals
remain distinct. The native `state_global_chapter_reads` suite authenticates independent maps,
checks exact/suffixed/truncated values and measures zero extra hashes during typed reads.

`readGlobalEntropy` returns four copied ordered words under an explicit byte ceiling. Exact128-byte
extent is required; no absent or malformed value becomes default entropy. Native coverage checks
all128 truncated prefixes, trailing bytes, positional bytes, source independence and byte limits.

`readGlobalHistory` retains the current recent-block/dictionary/optional-peak codec and all independent
caller ceilings. The exact whole chapter must decode; native coverage authenticates each truncated
prefix and a suffix, preserves absent versus present-zero peaks, and checks block/byte/configuration
refusals separately from missing or absent chapter evidence.

`readGlobalAuthorization` binds Pools and Queues to separate chapter identities and keeps existing
variable-pool/fixed80-entry queue validation. The native suite covers both kinds, cross-kind missing
witnesses, exact row ordering, detached hashes, malformed boundaries/suffixes, configuration and
byte/aggregate-hash ceilings. Authenticated membership alone does not establish a valid chapter.

`readGlobalValidators` selects only Staging/Active/Previous, bounds complete bytes, and returns the
existing immutable ordered roster with exact population/extent validation. No key-validity claim is
added. Native coverage exercises all three identities, cross-roster missing evidence, fixed null-key
bytes, retained order/source independence, truncation/suffix and population/byte/profile refusals.
