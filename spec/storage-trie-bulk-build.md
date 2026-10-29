# Direct initial complete-trie construction

Scope: construct an initial immutable complete map without repeated path copying. This changes
only `src/storage/full/state_trie.nim`, its existing dedicated tests and this feature record.
The [full trie contract](full-state-trie.md) and pinned merklization authority remain unchanged.

## Construction and failure contract

The constructor still synthesizes Put descriptors and uses the same policy, duplicate, payload,
final-map and native-extent validation as mutation. It retains separate complete-map ceilings and
restores the caller's mutation limits. After validation, a private builder recursively partitions
the sorted unique keys at the first one-bit identity for the current depth. It allocates each
final physical node once instead of allocating then retiring insertion paths. Singleton partitions
copy one leaf; multiple keys retain every required shared-prefix branch. Empty partitions allocate
nothing. Sorted ranges share every earlier bit, so each bit boundary is monotonic. Distinct
31-byte keys split before depth 248. Binary-search midpoint arithmetic uses a bounded difference.

Exact topology limits still reject before crypto. Left/right bottom-up hashing and long-value
encoding are unchanged. A failed digest discards all partially cached private nodes. Published
revisions, retained leaf owners, ordinary mutation/path sharing, provider/allocator/compiler,
public API, disk formats and StateStore implementation remain unchanged.

## Verification and measurement

Acceptance requires independent full-map roots/counts, both prefix polarities at all 248 divergence
positions, mixed and reversed initial maps, exact/short policy refusal before hashes, all constructor
hash-failure prefixes, restored mutation ceilings and exact ARC release. The existing suites own
these cases; supporting tests and docs are part of this feature PR.

Measurements compare parent `11dfed4b9f79da8a3fa9b3fc84d93b37a35d8583` and the candidate on the
same fixed maintained public StateStore workload, compiler/providers, ARC/Clang checked release
LTO profile and host. Reports and complete commands stay under ignored `build/storage-db13-*`.
The measurement head is `10609f5980008383356aab6422ee7fb08d40ff10`; subsequent edits are
documentation only. Checked native runs on macOS ARM64 pass 15 affected suites: public/private trie,
fixture replay and footprint; StateStore API, contract, incremental, refusal and replay;
checkpoint update/bank replay; node export; disk and managed disk stores; disk hash failure.
Four strict privacy guards, inventory and pinned formatting also pass. Constructor coverage
includes all 252 possible failing digest prefixes through a 251-node deepest-path graph with a
long value, followed by recovery and exact owner release. The 1,000 existing ARC cycles now also
exercise partial constructor failure. Expanded public cases cover all 248 divergence positions
in both polarities and 300 reversed mixed complete maps against the independent root calculator.

The maintained `make measure-state-store` comparison against the parent produces identical
initialized, sampled peak and retained occupied-memory observations and identical update hash
counts (640 for 128 entries;1152 for 1024 entries), in two complete samples each. The 15-case
public trie footprint table also matches the parent's table byte for byte. This optimization
reduces intermediate construction work, not retained graph size. Memory observations are occupied
Nim heap at named checkpoints, not allocation totals or process RSS.

A separate bounded public StateStore probe constructs the same unsorted 8192-entry, 33-byte-value
map 32 times per process. Each iteration checks the independent root, 17151 physical nodes and
exact graph retirement. Baseline and candidate compile the identical probe bytes (SHA-256
`70c0c1b760fe9e6871f2ecd2f918ab5b4a77b8e9bb58786118684ee0f7841f79`) against archived
parent/candidate sources, with the same maintained native build profile and observer library.
Neither `hyperfine` nor `valgrind` is installed here. Python `perf_counter_ns` measures serial
fresh processes with 3 warmups and 10 paired samples in each ordering, after native verification
has finished. Both orderings are retained, including outliers:

| Run order | Parent median | Candidate median | Median time reduction |
| --- | ---: | ---: | ---: |
| Parent then candidate |256.41ms |185.48ms |27.7% |
| Candidate then parent |256.09ms |187.45ms |26.8% |

Sample ranges were248.17–447.02ms/180.85–447.21ms in the first order and
250.06–332.07ms/179.97–262.53ms in reverse. Candidate was faster in 18 of 20 paired samples.
This supports retaining the direct builder for this construction workload. It is not a general
StateStore throughput claim: repeating the original mixed workload in 10 samples of 16 processes
per binary/order changed medians by only 2.8% and 1.9%, within the observed timing spread, so that
whole-consumer speedup remains unproven. All fresh mixed-workload outputs still matched the
saved hash/memory rows exactly.

Local evidence: `build/storage-db13-selected-checks.json`, `storage-db13-private-guards.json`,
`storage-db13-source-identity.json`, `storage-db13-state-store-measurements.json`,
`storage-db13-fixed-consumer-timing.json`, `storage-db13-construction/timing.json`, and the
fixed probe/build/timing script `storage-db13-measure-construction.py` under `build/`.
These records include complete commands, source/compiler/library identities and raw timings.
No CI labels were requested; local evidence does not establish exact-head Linux CI.

## Limits and next work

This changes initial graph construction, not retained layout or the resident physical repository
graph floor. Complete revisions remain resident; there is no bounded-working-set or speed claim
for disk recovery. M1 framing is complete; full JAM state serialization and whole-block parity
remain open. Next work depends on measured evidence, without filling the 15-PR batch cap.
