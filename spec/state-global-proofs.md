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
