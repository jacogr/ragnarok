# Encoding opaque immutable repository selections

Scope: serialize a validated `RepositorySelection` directly and use it in managed snapshot
encoding, without constructing a detached whole-graph `RecordCollection` or rehashing immutable
records already admitted by the repository. Record and snapshot formats remain byte-identical.
Changes stay in standalone storage, supporting tests and this feature contract.

## Authority and API

`encodeRepositorySelection(selection, limits)` returns `RepositoryResult[seq[byte]]` with owned
canonical record-collection bytes, `Uninitialized` or `LimitExceeded`. It accepts only the opaque
selection minted by complete root/route/count/union admission. It accepts no raw record array,
callback, trusted boolean or validation token. Private immutable cells retain their locally
verified hashes and complete physical edges. Sorted unique selection indices choose the exact
physical inventory. Caller root order cannot change collection address order.

The existing selection extent calculator bounds every record, value and output byte before
allocation. One exact body buffer receives canonical tags, complete digests, 31-byte leaf keys,
raw values and complete branch edges. The writer's final cursor must equal the measured extent.
In particular, full physical left edges must never be replaced by the masked JAM B encoding.
No source owner or mutable payload alias escapes. `RepositoryResult.takeValue` transfers a
successful payload once and leaves only `Uninitialized`, with the same guarded ownership
contract as existing record/snapshot transfer APIs.

Snapshots retain existing schema, policy, root-count, context and total-size preflight. They copy
and canonically sort only root identities, obtain scalar generation/commitment, take the encoded
body, frame it and hash the new outer checksum once. They no longer hold detached descriptors and
copied leaf values beside the body and final frame. Body and frame buffers still overlap; this
is not streaming IO or a claim of bounded working-set storage.

Raw mutable collection/export encoders still validate shape, budgets, duplicates and every local
hash. Decoders still verify outer checksums and every local record hash, then complete graph,
root, route, count, orphan and policy constraints. An opaque source's previous integrity does not
apply to modified detached transports. Public callers obtain selection authority only through existing complete admission.
Encoding an admitted selection can succeed while the hash backend is unavailable; encoding its
new outer snapshot checksum must still fail. This removes redundant work rather than weakening
untrusted admission or returning failed digests as valid roots.

## Verification and acceptance

`storage_selection_encoding` compares exact bytes with detached strict codec output, requires
zero body hashes even under backend refusal, tests exact/short record/value/per-value/encoded
limits, transferred buffer ownership, later detached mutation and strict raw hash mismatch,
empty and reversed/duplicate historical root unions, decoder integrity, one outer checksum,
checksum failure and 1000 scoped ARC cycles. A larger body witness bounds retained output to the
single buffer plus allocator rounding and verifies exact release. Existing snapshot, owner,
image, compaction, migration, bootstrap and IO-failure consumers remain affected checks.

Qualify memory/hash changes only with identical fixed snapshot bytes and matched checked native
parent/candidate builds. Parent is `0257544a`; temporary reports, source identities and commands
belong under ignored `build/storage-db16-*`. Producer construction must finish in a separate
process before observing consumer peak RSS. Preserve both producer directions and reversed
consumer ordering, complete roots, checksums, immutable input bytes and native success/release
verdicts. The measured code head is `9c446a14`; subsequent edits add result-guard witnesses and
documentation without changing runtime sources. Fifteen selected native suites pass, including
compaction write/sync refusal, managed maintenance and migration consumers. The existing repository
runtime family passes all 11 exact assertion/diagnostic probes, including default/failed/consumed
transfer rejection, plus a valid transfer control. Repository/selection compiler privacy, inventory
and pinned formatting checks are retained separately.

The fixed macOS ARM64 ARC/Clang checked release/LTO experiment prepares a 65536-entry map with
256-byte values in a separately completed producer. Each fresh consumer strictly decodes the
same snapshot, retires input text/byte owners, re-encodes the admitted selection, checks the exact
outer checksum, 131071 physical nodes, full root and byte extent, and returns its encoding owners
to the pre-encoding occupied-heap level. Both parent and candidate produce byte-identical fixtures.
The maintained child-resource observer measures whole native consumer peak RSS, including strict
load and encoding, and excludes producer construction. It is not an in-call peak measurement.

| Metric | Parent | Candidate |
| --- | ---: | ---: |
| Complete snapshot bytes | 27,852,929 | 27,852,929 |
| Encoding hash attempts |196608 |1 |
| Median consumer peak RSS | 162.94MiB | 109.05MiB |
| Final owned encoding allocation | 28,311,552 bytes | 28,311,552 bytes |

Eight fresh observations per binary cover both producer directions, both consumer orderings and
two repeats. Parent peaks are 162.9375 MiB in every observation; candidate peaks range 109.046875–109.0625 MiB.
Median whole-child peak falls 33.1%. Source bytes remain unchanged after every consumer. The final
owned encoding footprint is identical; no resident graph-layout saving is inferred. Hash attempts
during encoding fall from 196608 (all physical nodes plus long values and outer checksum) to one
outer checksum. Strict loading still verifies the same complete graph and all local hashes.

Complete evidence: `build/storage-db16-measure/resources.json` includes both producer checksums,
fixture SHA-256 identities, every native command/result, source/compiler/library/build identities,
full child resource receipts and ordered observations. The build config/script are
`build/storage-db16-measure.json` and `build/storage-stack-build.py`; the fixed source and observer
are `build/storage-db16-snapshot-workload.nim.txt` and `build/storage-db16-observe.py`.
`build/storage-db16-selected-checks.json` and `storage-db16-transfer-guards/results.json` retain
native consumer and transfer-contract results. No general disk-recovery speed or deployment
memory-ceiling claim follows from these scoped local observations.

## Limits

The complete graph remains resident and snapshot bytes still require whole-body/frame allocation.
No disk schema change, power-loss guarantee, allocator/provider/compiler modification or
state/application integration is introduced. M1 framing is complete; full JAM state serialization
and whole-block parity remain open. Local evidence is separate from exact-head Linux CI; no new
routine performance matrix or CI request is implied.
