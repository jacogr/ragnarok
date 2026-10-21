# Disk state storage

The maintainer authorized disk storage, including application backend selection, on 2026-10-21.
db #1 owns storage and StateStore persistence APIs; state #5 independently owns checkpoint recovery
and startup. GP 0.8.0 and existing compiler/crypto pins remain unchanged. Full/light mode and
memory/disk backend selection are independent. This feature does not implement partial light state.

## Snapshot transport

StateStore exports bounded full/delta physical records directly from its immutable cached trie.
Exports copy raw bytes, grant no authority over the source, and require no cryptographic work.
Default snapshots refuse export; limits preflight descriptor and payload allocation. A disk owner
must authorize exact snapshot identity before using a delta: equal roots alone grant no authority.
Repository restoration can extract detached complete leaves under an independently trusted root
without building an intermediate trie. This avoids reconstructing and hashing a second temporary
trie before constructing a StateStore. Returned leaves remain mutable transport values only.

## External design references

- [Firewood](https://github.com/ava-labs/firewood): physical addresses separate from Merkle hashes,
  explicit retained revisions, and data durability before root publication.
- [NOMT](https://github.com/thrumdev/nomt/blob/master/docs/nomt_specification.md): path-derived page
  identities and subtree packing reduce dependent reads.
- [ParityDB](https://github.com/paritytech/parity-db): atomic batches and distinct visible/durable
  stages, with OS page cache and separate metadata columns.

These sources inform design tradeoffs; no foreign node encoding, dependency or license-bearing
implementation is copied. Our journal remains the correctness baseline. Layout/cache/reclamation
changes require reproducible measurements and recovery tests; no throughput claim follows from
fewer encoded bytes alone. Canonical block authority cannot be inferred from a locally valid root.

## Durable StateStore owner

`state/disk_store.nim` owns one explicit-close, noncopyable `FileRepository` and an ordinary
in-memory `StateStore`. Creation requires an explicit complete snapshot and exclusively creates
the journal. Strict reopen requires independently supplied chain, root and exact local generation,
then constructs one StateStore from checked reachable leaves under explicit caller-selected policy.
No self-authentication, implicit repair, truncation, default database or policy widening occurs.

Updates fork the current immutable snapshot privately, validate/apply the borrowed batch, export
only changed physical nodes, and append/synchronize the journal before replacing the live memory
snapshot. Empty batches retain identity without a frame. Successful nonempty no-ops publish a new
snapshot and a journal generation. Native IO uncertainty poisons the journal: new reads/writes
refuse until close and explicit trusted recovery; already retained snapshots remain readable.
Failed initialization/open releases its lock, preserving any created bytes for explicit diagnosis.
Normal forks remain independent in-memory execution branches, never duplicate descriptor owners.

This first owner exposes durable state revisions only. It is not yet wired into normal application
adoption, canonical block metadata or a startup flag. Those require atomic publication of the
matching application context and coordination with state #5's startup/recovery layer. A successful
storage receipt cannot silently advance the application head or choose consensus authority.

## Publication failures and explicit recovery

`recoverDiskStateStore` wraps the existing independently trusted prefix repair; ordinary open
never repairs. Tests constrain actual child-process writes with `RLIMIT_FSIZE`: zero bytes, one
byte, half a frame and one byte short must fail; exact and ample ceilings are genuine controls.
Poisoned owners refuse new reads, updates and synchronization while held values remain readable.
Strict open preserves incomplete bytes. Wrong trusted generations preserve every byte. Authorized
repair restores the exact complete prefix, permits resumed append, and refuses complete visible
successors or complete checksum corruption. Repair may already be durable if subsequent policy or
cryptographic StateStore restoration fails; no writable owner escapes that later failure.

A separate maintained-crypto-observer suite refuses each required hash stage before update
publication. Every refusal preserves journal bytes, generation and exact old snapshot identity;
the same workload also completes with real successful controls.

## Reproducible real-file workload

`make measure-disk-store` runs the identical 128/1024-key, 33-byte-value workload ten times,
performing 64 deterministic sparse updates, retaining one/eight snapshots and strictly reopening
the result against its independently calculated complete root. Every restored key/value is checked.
Counter samples must agree exactly; source/compiler/crypto/profile/host identities are recorded.
`DISK_STORE_BASELINE=path/to/results.json make measure-disk-store` compares compatible prior
reports. Python tests reject malformed, partial, duplicate, incompatible and unstable observations.

The measured update region includes actual commitment, export, physical admission, frame encoding,
append and synchronization. Full-frame reference encoding and independent root checks are outside
that region. Monotonic publication/reopen durations are stored separately from exact counters;
process duration additionally includes fixtures and reference work, so is not update latency.
Occupied ARC bytes are live observations after completed updates, not internal transient allocation
peaks, allocation counts or RSS. This benchmark does not claim power-loss behavior or production
throughput from synthetic authored mappings.

Initial checked macOS ARM64 baseline, all ten counter samples identical:

| Complete keys | Held snapshots | Update hash calls | Journal bytes | Equivalent full-frame bytes | Maximum observed occupied bytes |
| --- | --- | --- | --- | --- | --- |
| 128 | 1 | 1984 | 92272 | 1690672 | 293568 |
| 128 | 8 | 1984 | 92272 | 1690672 | 402800 |
| 1024 | 1 | 3520 | 471823 | 23133327 | 2311536 |
| 1024 | 8 | 3520 | 471823 | 23133327 | 3037216 |

The equivalent full-frame total is a byte-size reference, not a second database benchmark or a
claim that it fits the configured total-journal budget. Delta persistence uses 98.0% fewer bytes
in the 1024-key workload. The current accumulated sorted record table still copies all descriptors,
sorts them on every append and walks the entire target graph. No disk-addressed paging, bounded
read cache, automatic history reclamation or production-scale efficiency is claimed yet.

## Sorted-index admission

Publication now sorts only newly admitted addresses and linearly merges them with the already
sorted immutable table. Existing full-address conflict checks, complete graph validation, budgets,
failed-publication atomicity and raw byte ownership remain intact. Mixed full/delta transports,
reversed record orders, reused addresses, zero-record revisions and held historical readers are
checked independently. Descriptor copying remains O(history); new-record sorting uses O(delta)
scratch instead of the pinned mergesort's O(history) temporary buffer.

The fixed candidate's ten deterministic samples exactly match the baseline bytes, hash calls and
post-update occupied memory. Ten alternating baseline/candidate runs also agree on every exact
counter. For 1024 entries, publication median totals across 64 updates changed from 51.5/49.5ms
to 42.7/42.6ms for retention one/eight; reopen medians changed from 43.0/42.8ms to 37.5/38.3ms.
Outliers overlap substantially on this shared host. This supports retaining the simpler asymptotic
sorting improvement, not a production latency promise or a claim of reduced post-update live memory.

## Normal restart authority

The maintainer selected local durable-head resume for normal disk-mode restarts: verify configured
chain identity and physical integrity, then resume the app's own previously validated durable head.
External checkpoint imports still require independently supplied trusted application identity and
sealed header. Persisted state root/generation alone is insufficient application context; disk mode
must atomically select matching block identity, sealed header, full parameters and state revision.
