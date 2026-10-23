# Compact exact duplicate preflight

Scope: reduce ordinary raw/serialized record duplicate scratch while preserving exact full
32-byte identity, shape/limit/duplicate/error precedence, local hashes, callback ordering and
complete admission. There is no truncated physical identity, trusted flag, format change or
new public API. Existing ordered collection preflight remains unchanged.

## Conservative proof and fallback

After the existing whole-input/body shape and quota checks, empty/singleton inventories need
no duplicate scratch. Larger unordered inventories first collect the first eight full physical
digest bytes into private `uint64` keys. Explicit byte shifts preserve every prefix bit; numeric
sort order need not match physical address order because only equality matters. If all prefixes
are distinct, full digests necessarily differ: any equal full digest would have equal prefixes.
This is an exact sufficient proof, independent of cryptographic randomness.

A prefix collision is inconclusive. Equal first/last record prefixes immediately select the
original full-width check without allocating compact scratch; they never directly return a
duplicate error. Otherwise sort the compact keys and identify complete repeated-prefix groups.
With no group, all full identities are distinct. With sparse groups, collect and compare full
32-byte addresses only for those groups. Every possible full duplicate must be in such a group;
all other prefixes differ from every other record, including the groups. Only full-width equality
can return `DuplicateNode`, and every record still requires local integrity afterward.

Sparse groups may contain at most one quarter of all records. Their full-address vector therefore
contains at most eight bytes per original record beside the compact key vector. Dense groups
retire compact scratch and use the original all-address check. Sorted group compaction never
overwrites unread keys, keeps membership order unique and checks the exact selected count before
full-width sorting. Default private plans conservatively select the all-address check. Endpoint
facts are copied during existing bounded input scan and only choose an inconclusive fallback;
they never authorize uniqueness or skip input integrity.

The primary ordinary key vector is eight rather than 32 bytes per record; library sorting may
also own workspace. Fallback can add work and allocator/OS page retention can affect whole-process
RSS. Qualify normal and collision paths separately rather than asserting a universal memory/time
improvement. No input is reordered or mutated, no borrowed address escapes, and no compact key
substitutes for a complete physical identity.

This proof replaces only duplicate scratch. Every raw encoder/decoder still verifies each
local node hash after successful structural/duplicate preflight; every graph admission still
proves full routes/topology/roots/counts/quotas. A structural inspection summary conveys no local
integrity or complete-graph authority. Invalid canonical fields and extents still refuse before
prefix allocation; true duplicates still refuse before hashing or callback preparation.

## Verification

`storage_duplicate_preflight` compares every case with an independent quadratic full-byte oracle,
without sorting or prefix extraction. Empty/singleton/boundary/larger synthetic inventories cover
distinct prefixes and high bits, constant and mixed prefix collisions, final-byte discrimination,
implicit wrap duplicates, sparse interior prefix/full collisions and explicit final duplicates. Raw batch/collection encoders, raw
validation, target/collection decoders, inspection and prepared delivery retain exact reasons,
hash attempts and callback ordering under real provider refusal. Reserved zero addresses still
win before duplicate/integrity checks. A real complete fixture retains exactly three strict
hashes, successful decoding and zero-hash inspection. A larger real batch with one altered interior
prefix proves that every earlier nonselected record still hashes before the exact mismatch; synthetic invalid identities never gain
integrity from a successful inspection. The suite requires 1000 scoped ARC cycles.

Affected record shape/delivery/ordered-collection, journal, repository/image admission, file,
managed, replay-cost and disk-store suites remain scoped checks. Record/frame privacy, pinned
formatting and inventory remain publication checks.

Qualification compares parent `4c2fde3c` with identical checked ARC/Clang release/LTO native
builds, compiler, providers and allocator. Producers finish before fresh consumer observation.
The ordinary batch uses the real exporter's child-before-parent order for a fixed 65536-entry
empty-value graph (131071 records, 11075592 bytes). One derived batch has distinct synthetic
full digests sharing a zero eight-byte prefix, intentionally invalid node hashes; another has
exact interior and endpoint repeated digests. These exercise dense fallback, sparse group comparison
and allocation-free endpoint fallback separately. Fresh consumers read
one bounded file buffer and perform eight shape/duplicate inspections under provider refusal,
checking exact reasons/counts, zero hashes and exact occupied-heap release. External observation
binds both independently produced directions to identical immutable file SHA-256 identities,
keeps ordinary/collision/duplicate results separate, and records whole-consumer peak plus native
inspection intervals without subtracting independent peaks. Full evidence belongs under ignored
`build/storage-db22-*`.

The measured runtime is `e8b6bb75`, parent `4c2fde3c`. All 16 affected native suites pass,
including expanded sparse-group integrity and exact 1000-cycle release. Five record/frame privacy
checks, pinned formatting and inventory remain separate publication evidence. An initial candidate
`f233a7ed` exposed broad-fallback overhead; its full48-consumer report remains at
`build/storage-db22-measure/resources.json`. The refined runtime retains conservative endpoint
fallback and bounds sparse full comparisons without changing any public contract.

The final64-consumer panel covers ordinary input, all-shared prefixes, an interior duplicate and
a tail duplicate; a separate16-consumer panel covers dense mixed groups with unequal endpoint
prefixes. Each includes both independent producer directions, both binary orders and two repeats.
Every consumer succeeds with exact typed reasons, zero hashes, unchanged input bytes and exact
occupied-heap release. The dense mixed-group fixture intentionally retains invalid node hashes
and unique full identities, so inspection succeeds while strict decoding still rejects it.

| Input case | Parent / candidate median whole-child peak | Parent / candidate native interval for eight inspections |
| --- | ---: | ---: |
| Ordinary | 18.5 / 14.0 MiB | 141.33 / 88.53 ms |
| Shared endpoint prefix, distinct full digests | 18.5 / 18.5 MiB | 158.45 / 158.73 ms |
| Interior full duplicate | 18.5 / 14.0 MiB | 138.99 / 94.89 ms |
| Tail full duplicate | 18.5 / 18.5 MiB | 139.38 / 140.87 ms |
| Dense mixed prefix groups | 18.5 / 20.046875 MiB | 184.43 / 207.44 ms |

Ordinary peak falls24.3% and its native interval37.4%. All ordinary candidate peaks are14.0MiB;
parent ranges18.484375–18.5MiB. Endpoint/shared-prefix fallback keeps the same observed peak.
Interior duplicate median time is lower, but candidate observations include a289.10ms outlier
(range94.22–289.10ms); do not infer a universal latency guarantee from that median. Tail fallback
has a1.1% higher median within overlapping ranges. Dense mixed fallback incurs8.4% higher median
RSS and12.5% higher median time; candidate peaks range20.046875–20.15625MiB. Compact discovery and
allocator page retention can add work/RSS before the unchanged broad fallback. These retained
negative observations are part of the feature's tradeoff, not a universal memory-ceiling claim.

`build/storage-db22-revised-measure/resources.json` and
`build/storage-db22-dense-measure/resources.json` retain every full receipt, ordered command/result,
fixture SHA-256, native interval and source/compiler/library/binary/build identity. Reproduce with
`build/storage-stack-build.py` and the matching `storage-db22-{revised,dense}-measure.json`, then
the matching observer script in new private evidence directories. Fixed sources are
`build/storage-db22-{revised,dense}-inspect-workload.nim.txt`. Selected native and compiler privacy
results are `build/storage-db22-selected-checks.json` and `storage-db22-private-guards.json`;
format/inventory logs share the same ignored prefix. Later unit-only coverage adds a real altered
interior prefix witness without changing measured runtime sources.

## Limits

The bounded input remains whole and colliding prefixes still require the original full-width
check. No general recovery speed, deployment RSS ceiling, integrity bypass or larger-than-RAM
storage claim follows. There is no provider/compiler/allocator, StateStore or application change.
M1 framing is complete; full JAM state serialization and whole-block parity remain open. Scoped
local checks remain distinct from exact-head Linux CI and routine performance CI is unchanged.
