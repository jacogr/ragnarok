# Frozen actual-successor service reconstruction

Execution accepts only an initialized CurrentRefreshPlan: original complete logical namespace
identities/raw keys, cached request physical keys, genuine update and policies were frozen at
whole-output admission. Existing service IDs, raw keys, preimage hashes and request hashes/lengths
stay fixed. Metadata and storage/preimage payloads plus request histories come solely from the
actual immutable successor. No caller-supplied replacement target or execution quota is accepted.

Every native output descriptor, original raw key, actual copied payload and metadata/history
wire was admitted before allocation/decode/copy. Metadata uses the existing 105-byte exact schema;
histories use the existing three-slot 13-byte decoder with exact-consumption refusal. Original
metadata/request codec reasons remain distinct from invalid plans, missing values and trailing
histories. A refused late stage drops all actual partial output; it exposes no successful prefix.

The guarded result returns fully detached mutable supplied declarations. They have no complete-map,
trusted-root, installation or producer-event authority. Full existing current-state and raw-key
matching must still validate them against the actual qualified successor. Reconstruction hashes
nothing and cannot be redirected by mutating fixed copied policies/info or prior returned output.
Canonical shared ARC ownership, including alias retirement, remains gated before enqueue or after
actual collection/join; cancellation/Done never releases the worker lease.

Observed locally: native reconstruction, existing full current/raw-key qualification, detached
metadata/raw-key/payload/history mutation isolation and default-plan refusal passed. Copy/decode
execution hashed nothing;1,000 ARC cycles retained141,792 bytes before/after. Four strict runtime
guards, five compiler privacy/nominal probes and genuine signed control passed, with pinned final
format checking and inventory. This is local checked evidence, not full STF or trusted-root authority.
