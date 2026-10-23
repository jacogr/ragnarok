# Bounded light proof batches

This standalone storage feature extends [retained proof retrieval](storage-light-proof-retrieval.md)
with `PreparedLightSnapshot.prove(keys, LightProofBatchLimits)`. It returns a complete
`seq[LightStateProof]` in caller request order, using the existing authenticated canonical
image and unchanged V1 encoding. Each proof owns its nodes and raw value independently
of the image and other output. Inputs are borrowed and must stay stable during the call.
Application/startup wiring and consensus root selection remain gated; historical M1 framing
completion does not mean complete state serialization or a complete JAM client.

## Resource and failure contract

`queries` bounds request count, sort scratch and output descriptors. Native descriptor
allocation bounds pass before allocation. Query descriptors are sorted privately; duplicate
keys return `ProofFailure.DuplicateKey` before scanning evidence. The image is scanned once
in canonical order, recording validated selected spans in those descriptors. Each examined
entry header consumes one `entries` allowance, including skipped entries and a greater key
that proves a sorted gap. Unselected payloads are skipped without copying or charging them
against selected-output limits. The scan stops when every requested query is resolved.

`proof.nodes` and `proof.valueBytes` bound each selected proof. `nodes` and `valueBytes`
separately bound the sum of all selected paths and raw values. Repeated path nodes are
charged for each detached proof; this is independent proof transport, not a deduplicated
multiproof. Aggregate additions use subtraction guards before addition. Private query
scratch may be allocated before refusal, but no result sequence or proof buffer is allocated
until every query, scan allowance, per-proof ceiling and aggregate ceiling passes.

Default images return `Uninitialized`, including for empty requests. Valid images accept
empty requests with zero allowances. Query policy and native allocation checks precede
duplicate detection. Thereafter failures are resolved in canonical query/entry order.
Exhausting the entry allowance before resolution returns `LimitExceeded`. Reaching the
end needs no additional header allowance; a sorted gap or end before finding a query
returns `ProofFailure.UnknownKey`. A later unknown query or limit failure returns no
successful prefix. Retained authenticated absence is a successful original proof, including
zero-node evidence for the empty complete root; unknown keys never become absence proofs.

No hashing, file IO, complete-image copy or retained index is introduced. Request sorting
costs O(q log q); scanning costs O(examined entries), followed by copying selected proof
bytes. Scratch is O(q), independent of image size. The existing single-query overload and
its limits remain unchanged. This feature makes no latency or RSS improvement claim.

## Ownership, trust and completion checks

Batch retrieval accepts images from preparation, owned restoration or a light file owner's
`preparedSnapshot`. Retained evidence survives later forgetting/publication, writer closure
and file removal. Its independently chosen chain/root and original knowledge do not become
consensus freshness or a new durability receipt. Existing poisoned-writer access rules apply.

Completion checks cover all 32 subsets of a five-query fixture with reverse request order,
exact/short query, entry, per-proof and aggregate ceilings, maximal uint64 policies, skipped
long values, empty requests/images, duplicate/unknown/default requests, late failures and
zero-node authenticated absence. Exact complete-trie transport and independent complete-map
root verification check present, empty-present and absent proofs. Detached mutation, output
outliving its source image, read-only restoration, forgetting and real file reopen/close/removal
exercise ownership. Success and late-failure scratch/output retire over 1,000 ARC cycles.
Runtime misuse probes instantiate the complete batch result and its selected proof reason,
with separate successful controls; private result fields and image ownership stay unchanged.

## Local verification

The batch suite and affected single-query/snapshot suites pass through the checked native
runner. All 32 query subsets match complete-trie transport and verify against an independently
calculated complete-map root. Reversed requests, exact/short resource ceilings, maximal uint64
policies, zero hashing under provider refusal and skipped unselected values pass. Detached
mutation, source-image retirement, read-only restoration, forgetting and actual file
reopen/close/removal pass. The 1,000 success/late-unknown/late-limit ARC cycles retain 13,136
occupied bytes before/after. Twenty-three snapshot runtime guards and thirteen positive
controls pass, including the new complete-batch result and selected-reason contracts.
Formatting and verification inventory pass. These are local checked native results;
exact-head Linux CI and production power-loss qualification are not claimed.
