# Bounded retained light proof retrieval

This standalone storage feature makes previously verified canonical evidence available
without requiring a complete trie or repeating authentication. It extends the existing
[light image format](storage-light-snapshots.md); encoding, pinned GP path semantics,
root trust and checksum rules remain unchanged. Application/startup integration and
consensus root selection remain gated. Historical M1 framing completion is not complete
state serialization or full JAM client completion.

`PreparedLightSnapshot.prove(key, LightProofReadLimits)` returns a detached `StateProof`
for a retained query. `entries` bounds examined entry headers; `proof.nodes` and
`proof.valueBytes` independently bound output. All selected output limits pass before
allocating either output buffer. Successful output owns its path and raw value: callers
may mutate or retain it after releasing the image without modifying cached evidence.
No hashing, file IO, image-sized copying or unselected payload copying occurs.

The canonical sorted image is scanned from its first entry. Each examined header costs
one entry allowance, including a header whose greater key establishes unknown status.
Unselected payloads are skipped using previously validated extents. Exhausting the scan
allowance before resolving the query returns `LimitExceeded`, even when another cache
lookup could identify the key. Reaching the end requires no additional allowance; an
empty image reports unknown with zero allowance. Work is linear in examined entries
plus selected output bytes; no index or resumable traversal is retained.

A missing retained query returns `ProofFailure` with `LightCacheError.UnknownKey`.
That is local lack of evidence, never an absence proof. A retained authenticated absence
returns the original successful proof, including zero nodes for the empty complete root.
A present empty value and absence may both have empty raw values; consumers interpret
proofs through the existing verifier against an independently trusted complete root.
The default image returns `Uninitialized`. Refused results expose no partial proof.

`LightFileCache.preparedSnapshot` returns the currently selected immutable image while
its writer is usable. It allocates no encoded copy and performs no IO or new durability
barrier. Default/closed writers return `Uninitialized`; poisoned writers return
`RecoveryRequired`. A previously retained image owns no file lock or directory lease,
and survives later publications, uncertainty, close, reopen and removal of the files.
Previously retained evidence keeps its original root/knowledge and freshness semantics;
retrieval does not assert consensus provenance or current durable selection.

Completion checks compare exact paths/raw values with the complete-trie producer and
verify extracted present, empty-present and absent proofs against an independent flat-map
root. They cover exact/short scan and output budgets, early sorted termination, unknown
keys, zero-node absence, empty images, default handles, forgetting, detached mutation,
owned-input restoration and 1,000 ARC lifetimes. Real file checks cover hash-free/no-write
image retention, reopen, post-rename directory-sync failure, fresh-reader poisoning and
retained proof access after closing and removing the files. Existing tagged-result and
resource ownership guards remain applicable without a new mutable backing surface.

## Local verification

The new retrieval suite and affected snapshot/file-cache suites pass through the checked
native runner. Extracted proofs match complete-trie transport, including independently
verified empty-present and absent outcomes. Provider refusal does not affect extraction:
zero hash calls are observed. Exact/short scan, path and value ceilings, early/end-of-scan
unknown resolution, detached mutation and proof lifetime after source retirement pass.
Real file retention, reopen, directory-sync uncertainty, poisoning and removal pass.
The final 1,000-cycle lifetime check holds 5,280 occupied ARC bytes before and after.
Twenty-one runtime result/owner guards, six positive controls, seven privacy rejections
and actual file-owner duplication rejection pass. Formatting and inventory pass.
These local results do not claim exact-head Linux CI or production power-loss qualification.
