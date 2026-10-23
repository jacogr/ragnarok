# Selective canonical light-image exports

This standalone feature exports selected retained query evidence as a new canonical V1 image.
`select(snapshot, keys, limits, entries)` preserves the original chain identity and independently
chosen complete root while applying an explicit new `LightSnapshotLimits` policy. It complements
[cursor pagination](storage-light-proof-pagination.md): pagination enumerates detached proof
transport, while selection creates a separately validated, reusable image with its own policy.
No application/startup or consensus integration is authorized. Historical M1 framing completion
remains distinct from complete state serialization or full JAM client completion.

## Selection, quotas and validation

Query input is borrowed and must stay stable during the call. Output policy item count and
fixed image extent are checked before query scratch allocation. The bounded span planner shared
with batch retrieval sorts query descriptors, rejects duplicates, scans canonical source headers
at most once under `entries`, and checks every selected proof and aggregate raw-value charge.
Only selected entries consume output item/value/proof allowances; skipped evidence consumes
source traversal allowance. Exact combined fixed-header, node and value extents then pass before
allocating the encoded image. No complete detached proof batch is staged for export.

Successful output is canonical key order regardless of request order. It contains exactly the
requested queries, with original proof bytes. Encoding copies the original chain/root header,
replaces the entry count and computes a fresh checksum. Strict owned restoration checks the
new checksum, bounds and every selected proof against that same complete root before returning
the prepared image; no unchecked verified-lookup adoption is exposed. The encoded buffer moves
into the successful owner. Export therefore performs two checksum hashes plus normal selected
proof verification. This feature makes no latency, RSS or zero-hash claim.

Default source handles return `Uninitialized`. Unknown queries and duplicates return
`ProofFailure.UnknownKey` or `ProofFailure.DuplicateKey`; no successful prefix escapes.
An unresolved query after exhausting traversal allowance returns `LimitExceeded`. Output-policy
and native descriptor/extent errors remain typed and precede output copying or hashing. Checks
that depend on selected evidence run in canonical query order. Every provider refusal returns
`BackendFailure`; the original immutable image, retained cursors and readers remain unchanged.

Explicit output limits may tighten or loosen source policy; all selected evidence is revalidated
under the exact output limits. The source's mutation allowance does not govern a read/export.
Output `cache.writes` governs future mutations, so read-only output with zero writes is valid.
Empty selection yields a canonical empty-knowledge image at the original complete root: omitted
present values and omitted authenticated absences become locally unknown, never protocol absence.
Zero-node empty-root absence remains a successful retained query when explicitly selected.

## File and lifetime boundaries

Export returns a prepared immutable image without IO or a durability receipt. Callers may retain,
copy bytes from or initialize a separate light file namespace using its exact chain/root/policy.
An existing writer with a different policy refuses publication with `InvalidBatch`;
chain/root mismatch remains `WrongIdentity`. Selection never silently changes that writer's policy or selected file. New file creation,
reopen, publication barriers and poisoning continue to use their existing contracts. Exported
images and cache readers outlive the source writer and file removal.

Completion checks compare all 32 subsets of a five-query fixture with independent complete-trie
proof preparation, including exact byte ceilings and zero future writes. They cover unchanged
nonzero chain/root, omitted known/absent queries, default/duplicate/unknown/late-scan refusal,
per-proof and aggregate limits, source read-only policy, empty output and zero-node absence.
Each observed checksum/proof backend-refusal boundary must leave source bytes unchanged.
Success/partial-restoration-failure/retry cycles retire ARC scratch and output over 1,000 calls.
Real source/destination namespaces verify wrong-policy refusal without writes, selected output
initialization/reopen and retained readers after lease closure and file removal. Existing batch,
pagination and owned-restoration consumers, dynamic result/reason guards and privacy checks
cover the shared planner and strict restoration boundary.

## Local verification

Selective export and affected batch, pagination and owned-restoration suites pass through the
checked native runner. All 32 subsets match independent canonical preparation with exact image
ceilings, original nonzero chain/root and zero future mutation allowance. Empty knowledge and
zero-node absence, unknown/duplicate/scan/policy refusal, all observed checksum/proof backend
refusal points and unchanged source bytes pass. Actual source/destination files confirm
`InvalidBatch` for a different output policy with zero writes, then successful independent
initialization/reopen and retained evidence after both namespaces retire. The 1,000
success/partial-restoration-failure/retry ARC cycles hold 19,072 occupied bytes before/after.
Thirty-nine runtime guards, fourteen controls and nine snapshot/cursor/page privacy checks
pass. Formatting and inventory pass. These are local native results, not exact-head Linux CI,
a latency/RSS improvement claim or production power-loss qualification.
