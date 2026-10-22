# Exact complete-state serialization manifests

Authority: current Gray Paper pin `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
T global/service serialization, current request domain and accepted compact C13
policy. Reuse existing composition and service codecs without changing equations,
pins, storage APIs/formats, Services or proof/RPC root-authority policy.

Consume a genuine [validated complete-source global owner](state-global-snapshot.md)
and explicitly declared service metadata, raw storage keys/values, preimage hash/
value pairs and request identities/histories. Reject `StateService.captured`: opaque
physical keys do not establish their logical namespace. Caller inputs are borrowed
only during matching. Independent service/count/node/per-value/aggregate/raw-key
policies bound source inspection and composition before value copies or hashing.

Compose through existing codecs and require equal complete entry cardinality plus
exact key/value agreement for every unique composed entry. No extra, omitted,
renamed or altered source row may survive. Do not use root equality as a substitute
for exact bytes. Duplicate keys and backend/codec refusals retain their precise
composition reason; no failure returns a partial manifest. Success retains only
the exact original source/global owner and fixed observations; temporary composed
buffers retire, and caller descriptor mutation cannot change the certificate.

This proves exact structural serialization against the declared service manifest.
It does not verify preimage content hashes, account balances/footprint relationships,
profile/transition consistency, signatures, Thin VRF, trusted roots or STF validity.
The explicit manifest supplies otherwise non-reversible logical key identities;
it is not discovered from opaque trie digests. Full current-pin/JAM parity remains
open, with historical release vectors distinguished from current normative evidence.

Completion witnesses: mixed independent global bytes plus metadata/storage/preimage/
request rows; reordered services; empty values; maximal valid and reserved request
lengths; omitted/extra/changed rows including equal-count key substitutions; opaque/
duplicate/default refusals; independent exact/short limits and backend rollback;
complete retained source identity, detached caller lifetime, strict runtime/privacy/
partial-domain controls and fresh 1,000-cycle ARC release.

Local checked macOS verification: the new module and both native/guard drivers
pass pinned semantic compilation. The mixed native suite and its1,000-cycle
success/refusal workload retain454,592 live bytes before/after warmup. Independent
exact/short source/count/node/value/aggregate/raw-key policies refuse before hashing;
backend refusal retains the precise composition reason without a matched prefix.
Three strict runtime assertions, a genuine complete-map success control and five
compiler privacy/source-domain rejections pass. Existing codec algorithms and
all287 earlier production-module checks are unchanged and reused; this module
adds their exact-map binding. Evidence remains under ignored
`build/state-manifest-*` and `build/tests/state-manifest-guards/`.
Linux CI and complete current-pin state/STF parity remain separate evidence.

Next bounded consumer is typed checkpoint decoding under an independently supplied
expected root, preserving existing checkpoint bytes and all nested refusal reasons.
Callers must obey the existing single-threaded store and canonical ARC lease rules;
these adapters do not authorize access to a graph leased to a proof worker.

The [expected-root checkpoint consumer](state-validated-checkpoint.md) now delegates
to this exact validator after existing checkpoint integrity and global validation.
The [usage guide](../docs/state-validation.md) documents all three bounded stages.
