# Direct initial complete-trie construction

Scope: construct an initial immutable complete map without repeated path copying. This changes
only `src/storage/full_state_trie.nim`, its existing dedicated tests and this feature record.
The [full trie contract](full-state-trie.md) and pinned merklization authority remain unchanged.

## Construction and failure contract

The constructor still synthesizes Put descriptors and uses the same policy, duplicate, payload,
final-map and native-extent validation as mutation. It retains separate complete-map ceilings and
restores the caller's mutation limits. After validation, a private builder recursively partitions
the sorted unique keys at the first one-bit identity for the current depth. It allocates each
final physical node once instead of allocating then retiring insertion paths. Singleton partitions
copy one leaf; multiple keys retain every required shared-prefix branch. Empty partitions allocate
nothing. Sorted ranges share every earlier bit, so each bit boundary is monotonic. Distinct
31-byte keys split before depth248. Binary-search midpoint arithmetic uses a bounded difference.

Exact topology limits still reject before crypto. Left/right bottom-up hashing and long-value
encoding are unchanged. A failed digest discards all partially cached private nodes. Published
revisions, retained leaf owners, ordinary mutation/path sharing, provider/allocator/compiler,
public API, disk formats and StateStore implementation remain unchanged.

## Verification and measurement

Acceptance requires independent full-map roots/counts, both prefix polarities at all248 divergence
positions, mixed and reversed initial maps, exact/short policy refusal before hashes, all constructor
hash-failure prefixes, restored mutation ceilings and exact ARC release. The existing suites own
these cases; supporting tests and docs are part of this feature PR.

Measurements compare parent `11dfed4b9f79da8a3fa9b3fc84d93b37a35d8583` and the candidate on the
same fixed maintained public StateStore workload, compiler/providers, ARC/Clang checked release
LTO profile and host. Reports and complete commands stay under ignored `build/storage-db13-*`.
Measured results will be recorded after validation; no performance claim is made yet.

## Limits and next work

This changes initial graph construction, not retained layout or the resident physical repository
graph floor. Complete revisions remain resident; there is no bounded-working-set or speed claim
for disk recovery. M1 framing is complete; full JAM state serialization and whole-block parity
remain open. Next work depends on measured evidence, without filling the15-PR batch cap.
