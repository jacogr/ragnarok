# Single-buffer strict journal framing

Scope: remove the separately encoded body beside the final journal frame in both node-only and
contextual formats. Mutable raw batches retain mandatory shape, quota, duplicate and local hash
validation. The real journal consumers use the new path; no disk domain/format, integrity or
publication/recovery authority changes.

## API, bounds and ownership

`encodeFramedTrieExport(batch, recordLimits, prefixBytes, suffixBytes, outputLimit)` returns
`RecordResult[seq[byte]]`. The batch remains a stable borrowed mutable transport during this
synchronous call. Requested extents are full-width nonnegative byte counts; the independent
nominal output ceiling bounds the entire allocation. The existing exact body preflight still
checks metadata, count/host descriptor limits, canonical unused fields, per-value/aggregate
budgets and encoded extent. Subtraction proves prefix/suffix/body fit beneath both the host
maximum and whole-output ceiling before narrowing, allocation or hashing.

Duplicate rejection and every local integrity hash remain mandatory before output allocation.
Success writes canonical batch bytes between exact zero-filled reservations into one final
owned sequence. The writer must end immediately before the reserved suffix. Reservations grant
no record, graph, root or chain authority. Mutation of returned bytes cannot change the borrowed
source or another encoding. Existing success-only extraction/once-only transfer and precise
record errors remain. Unframed batch and collection encoders use the same strict private writer
with zero reservations and preserve their public APIs and domains.

Both journal encoders preserve generation/context/body/whole-frame preflight and error mapping.
They reserve their existing exact header/context prefix and 32-byte checksum trailer, fill
metadata/context around the already serialized body, hash the same prefix once and fill the
checksum. There is no separate body sequence or body-to-frame copy. Raw hash refusal remains
`InvalidRecords(BackendFailure)`; refusal of the new outer checksum remains `BackendFailure`.
Quota refusals remain `LimitExceeded` before integrity work. Decoding/replay stay fully strict.

## Verification

`storage_journal_framing` covers empty/odd independent reservations, exact/one-short body and
whole-output bounds, record/per-value/aggregate/target/context ceilings, full-width overflow
refusal without allocation/hashing, zero-filled reservations, exact canonical body bytes,
unchanged raw hash counts, once-only transfer, raw mutation/hash mismatch, duplicate-before-hash
refusal, outer-checksum refusal, both exact journal domains, strict decoding/replay, immutable
restored roots/context and 1000 exact ARC cycles. The existing independent frozen empty-frame
vector remains a format oracle. Record/owner/preflight, journal recovery/replay, contextual,
file/managed publication, crash/sync refusal, maintenance, disk and migration suites remain
scoped consumers. Compiler privacy and pinned formatting/inventory remain publication checks.

Qualification compares parent `bdc5c3f0` using identical pinned ARC/Clang release/LTO builds,
compiler, providers and allocator. Separate producers prepare each exact journal domain from
a fixed 65536-entry, 256-byte-value complete graph (131071 nodes). Fresh consumers read one
bounded managed-file input, strictly decode raw transport, retire the input, strictly re-encode,
compare the exact frame length/checksum, require all 196608 integrity/checksum attempts and
release output owners back to the pre-encoding occupied-heap level. Both producer directions
must produce identical bytes. Fresh whole-consumer peak receipts include strict load and encode,
exclude producer construction and never subtract independent peaks. Preserve both binary orders,
all receipts and source/build/fixture identities under ignored `build/storage-db20-*`.

The measured code is `77a02943`. All 15 affected native suites pass, including the new framing
suite and exact 1000-cycle release. Record/frame compiler privacy, pinned formatting and
inventory checks remain separate publication evidence. Thirty-two fresh native consumers cover
both wire domains, both producer directions, both binary orders and two repeats per ordering.
Every native consumer succeeds and verifies exact output retirement and immutable input bytes.

| Fresh whole-consumer observation | Parent | Candidate |
| --- | ---: | ---: |
| Node-only frame bytes | 27,852,856 | 27,852,856 |
| Contextual frame bytes (three context bytes) | 27,852,867 | 27,852,867 |
| Re-encoding integrity/checksum attempts | 196608 | 196608 |
| Median peak RSS, either domain | 94.34375 MiB | 67.765625 MiB |
| Final owned output allocation, either domain | 28,311,552 bytes | 28,311,552 bytes |

Median whole-consumer peak falls 28.2% in both formats. Parent peaks are identical in all samples;
node-only candidate peaks are identical, while contextual candidate peaks range 67.75–67.765625 MiB.
This removes body/frame overlap without changing final output allocation, raw hash work or strict
loading. It does not measure an isolated encoder peak or general disk recovery performance.

Node-only fixture SHA-256 is
`5ef88b26f8eb32d138f67c64419c7baefd44eae15eec088499c66f8e1cad233c`, checksum
`e6c5c54eaf76d6f4aa44ea8cb3dcf3760b59e7214d5f6c336390f8d1a0a29146`.
Contextual fixture SHA-256 is
`ba47434cd0ef3e000aa5bb4e14ac82424d21d5c9b31bbf72d6e1abec3d14bd16`, checksum
`b46200e0727254f463ae6654fabd11730548fac432348212cf9cc4b4a1ac9003`.
Both independently produced versions have these exact identities, unchanged after every consumer.
`build/storage-db20-measure/resources.json` retains all full receipts, commands, native verdicts
and source/helper/compiler/library/binary/build identities. Reproduce with
`build/storage-stack-build.py build/storage-db20-measure.json`, followed by
`build/storage-db20-observe.py` in a new private evidence directory. The fixed native source is
`build/storage-db20-journal-workload.nim.txt`; consumer and privacy results are
`build/storage-db20-selected-checks.json` and `build/storage-db20-private-guards.json`.

## Limits

The raw mutable batch and final whole frame remain resident. This is neither streaming nor an
opaque-source hash shortcut, and does not establish a deployment memory ceiling, recovery speed
or power-loss behavior. There is no provider/compiler/allocator, StateStore or application change.
M1 framing is complete; full JAM state serialization and whole-block parity remain open. Scoped
local evidence is separate from exact-head Linux CI; routine performance CI is unchanged.
