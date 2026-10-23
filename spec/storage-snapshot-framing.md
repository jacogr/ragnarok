# Single-buffer snapshot framing

Scope: remove the overlapping encoded body and final frame from opaque repository snapshot
encoding. The actual managed snapshot consumer uses the new path. Record and snapshot domain
bytes, format, full digest/edge identities, checksum, root order and admission policy are unchanged.
Changes stay in standalone storage, supporting tests and this feature contract.

## API and ownership

`encodeFramedRepositorySelection(selection, recordLimits, prefixBytes, suffixBytes, outputLimit)`
returns `RepositoryResult[seq[byte]]`. It writes the same canonical record collection between
zero-filled caller reservations. The full-width `uint64` extents are nonnegative requested byte
counts, not policy ceilings; `outputLimit` bounds the entire allocation independently of the
record codec's body ceiling. Preflight checks the admitted body, host-size maximum, reservations
and remaining space by subtraction before addition, narrowing or allocation. Default selections
return `Uninitialized`; impossible extents and quotas return `LimitExceeded`, with no output.
The public result retains its existing success-only extraction and once-only transfer contracts.

The only source is an opaque immutable admitted selection. No mutable input array, callback or
trusted flag can bypass local integrity or complete-graph admission. Reserved bytes grant no
record/graph authority. Callers own their outer framing and integrity contract; returned bytes
are detached and may be mutated without affecting any source or subsequent encoding.
`encodeRepositorySelection` uses the same writer with zero reservations and preserves its API.

Snapshot encoding keeps its existing schema, inherited policy, root/context/count and total-size
preflight. After sorting detached roots, it reserves the exact header/root/context prefix and
32-byte checksum suffix. The writer allocates one final buffer and writes records at their final
offsets. The snapshot codec fills metadata and context, hashes the existing prefix once and fills
the checksum. There is no separately allocated body and no body-to-frame copy. Failed checksums
still return `BackendFailure` without exposing a partial frame. Decoding remains fully strict.

## Verification

The existing `storage_selection_encoding` suite now covers zero, odd and larger independent
prefix/suffix reservations, exact/one-short whole-frame ceilings, exact body bytes, zero-filled
reservations, full-width `high(int)`, above-host and `high(uint64)` overflow refusals without
allocation or hashing, an independent short body ceiling, default sources, detached mutation,
once-only transfer and large-buffer exact release. Snapshot exact-size success and one-short
refusal retain the checksum count: one on success, zero on quota refusal. Existing raw strict
encoding, empty/historical unions, provider refusal and 1000 ARC-cycle witnesses remain present.
Affected snapshot/owner, retention, managed compaction, bootstrap, migration, crash/sync-refusal
and maintenance suites verify real consumers.

Qualify memory only against the parent `d82cdcb2` with identical checked ARC/Clang release/LTO
sources, compiler, providers and allocator. The fixed native probe uses public bounded managed
file IO to read one snapshot buffer, strict complete snapshot decoding, input retirement, opaque
root selection, one re-encoding, exact checksum/extent/root/count comparison and exact ARC release.
Fixture production completes in separate processes. Both producer directions and consumer orders
must agree on bytes; fresh whole-consumer peak receipts include strict load and encoding, exclude
producer construction and are not in-call peak observations. Local source/build/receipt identities
and full logs belong under ignored `build/storage-db17-*`.

The measured implementation is `37f5ca86`, parent `d82cdcb2`. All 12 affected native suites
pass, including the expanded framing witnesses and 1000-cycle ARC checks. Exact repository and
selection privacy diagnostics, pinned formatting and inventory remain separate publication checks.

The fixed macOS ARM64 fixture has 65536 entries with 256-byte values and 131071 physical nodes.
Both producer versions create the exact same 27,852,929-byte snapshot, SHA-256
`26c8cffefd633aebf71b1e616b9dd0dfb5677a2b632ef0590dd1b5663e8b46e5`, checksum
`3bebfd4642e2b54461713c698ee37146fbe486c7a37d841928643b6aa2b50dfb`.
Eight fresh observations per binary cover both producer directions, both consumer orderings and
two repeats. These observations use one managed-file input buffer in both versions and must not
be compared directly with the earlier text-plus-byte loading experiment in the selection contract.

| Whole-consumer observation | Parent | Candidate |
| --- | ---: | ---: |
| Median peak RSS | 93.0 MiB | 66.40625 MiB |
| Observed peak range | 93.0–93.0 MiB | 66.390625–66.421875 MiB |
| Re-encoding checksum calls | 1 | 1 |
| Final owned output allocation | 28,311,552 bytes | 28,311,552 bytes |

Median peak falls 28.6%. This reflects removing the simultaneously live body buffer, with the
same final output allocation and graph representation. Every consumer verifies identical
checksum/extent/entries/nodes, unchanged input bytes, native success and exact occupied-heap
release after encoding. Strict load still performs the same integrity and graph admission.
`build/storage-db17-measure/resources.json` retains all ordered receipts, source/helper/compiler/
library/binary identities, producer and consumer commands and results. Reproduce with
`build/storage-stack-build.py build/storage-db17-measure.json`, followed by
`build/storage-db17-observe.py` in a new private evidence directory. The fixed native probe is
`build/storage-db17-snapshot-workload.nim.txt`; affected native logs and compiler privacy evidence
are `build/storage-db17-selected-checks.json` and `build/storage-db17-private-guards.json`.

## Limits

The graph and one entire output frame remain resident; arbitrary metadata reservations also
consume their exact requested space. This does not provide streaming, larger-than-RAM storage,
a deployment ceiling, a format migration, new durability guarantees or cross-workstream integration.
M1 framing is complete. Full JAM state serialization and whole-block parity remain open. Scoped
local checks do not substitute for exact-head Linux CI; routine performance CI is unchanged.
