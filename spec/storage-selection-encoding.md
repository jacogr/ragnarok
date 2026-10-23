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
apply to modified detached transports. No new public factory can manufacture selection authority.
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
verdicts. No measured improvement is claimed until those comparisons finish.

## Limits

The complete graph remains resident and snapshot bytes still require whole-body/frame allocation.
No disk schema change, power-loss guarantee, allocator/provider/compiler modification or
state/application integration is introduced. M1 framing is complete; full JAM state serialization
and whole-block parity remain open. Local evidence is separate from exact-head Linux CI; no new
routine performance matrix or CI request is implied.
