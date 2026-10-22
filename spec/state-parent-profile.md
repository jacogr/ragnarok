# Selected configured parent profile

Pins remain Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and vector
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. PVM's concrete next consumer needs an initial
selected logical parent distinct from a completed current transition.

`captureParentProfile` accepts only a selected immutable `ChainView` and explicit limits. It derives
best-head physical snapshot, header/full Parameters, current/core/epoch cardinalities internally;
previous population comes from bounded exact C9 on that same snapshot with no current fallback.
No separately supplied map, header, profile or Parameters can replace original selection.

Allocation-free `blockSnapshotRetention`, `viewRetentionInfo` and guarded `bestBlockContext` inspect
private arrays without copying indexes. View accounting includes fixed ChainView bytes, rolling
snapshot descriptors, each snapshot's key/service index arrays and the separately retained finalized
owner's indexes. Shared immutable map/header payloads are retained rather than duplicated. Chain
capture bounds each key/service index to 16384 and view history to eight plus finality, proving all
fixed-accounting arithmetic. Counts/bytes are observations, not construction or root authority.

All view/index retention admission precedes complete-view and C9 payload copies. Previous bytes and
roster items have independent decode limits. Success privately retains the exact full original view,
including ordered history/full profile/finality or its absence, beside fixed context/profile facts.
`copyParentView` requires a new explicit byte limit before copying the complete view/index arrays.
Default/missing head, missing previous chapter, malformed/trailing values and resource refusal remain
separate guarded results. The structurally captured view does not itself establish consensus trust.

Operations, including fixed projection, copying and alias retirement, run at a stable host boundary
before enqueue or after actual collection/join. No worker, Services, execution, installation, root
policy or storage format changes. This is the first configured-parent seed phase, not logical manifest
capture, mutation propagation or full current-pin STF parity.

Verification requires selected finalized/unfinalized identity/full Parameters, exact/one-short owner,
view/index, previous-byte/item and view-copy policies, zero hashes, default/private/nominal guards,
genuine signed positive control and 1,000 ARC cycles.

Observed locally: native finalized/unfinalized and exact/short admission cases passed; 1,000 ARC
cycles held 279,584 bytes before/after. Nine strict runtime guards, five exact compiler
rejections and genuine signed positive control passed. Inventory and pinned formatting passed
on macOS ARM64 checked ARC/Clang release; Linux CI and full current-pin STF parity are separate.
