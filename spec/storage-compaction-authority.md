# Exact source authority before managed compaction work

Scope: reject stale/default/foreign managed maintenance views by exact immutable owner identity
before allocating a complete current-root selection. Preserve all actual retained-root graph
checks, epoch selection, byte formats, publication, synchronization and uncertainty contracts.

## Public identity and admission

`matches(view, otherView)` compares two initialized opaque `RepositoryView` owners, returning
false when either is default. Equal roots, generations, limits or physical contents do not imply
an exact source binding. Views copied from the same immutable owner match in either order, even
after originating handles close. A clone, restored image or independently initialized managed
owner has a distinct identity despite equal metadata. The query allocates nothing and performs
no graph, hash or IO work; its O(1) complexity is not a cryptographic timing guarantee.
`matches(selection, view)` retains its existing semantics through this same identity query.
Neither overload creates a view, bypasses admission, changes ownership or grants chain authority.

Managed compaction first preserves active/poisoned checks, obtains its current opaque immutable
view and compares that exact owner with the caller's expected view. Stale authority returns
`StaleView` before epoch/root selection or IO. The old path allocated and traversed a complete
current-root selection solely to call its source-identity comparison. Current views already
carry complete admission: publication, snapshot decoding, initialization and compaction mint
private immutable repository owners only after their corresponding complete-graph checks.
There is no public raw view factory or writable source field.

For matching expected views, the existing epoch check and explicit requested-root selection
remain. That selection still independently validates every complete root, route, topology,
quota and union; output serialization, clone, checksum, staging, barriers, CURRENT replacement,
cleanup and recovery uncertainty are unchanged. Default or poisoned managed owners still
refuse before source comparison. Retained old readers remain valid without authorizing fresh
maintenance against a different current owner.

## Verification

`storage_managed_compaction` now checks symmetric exact-current matching, all default-view
combinations, a foreign equal-root/equal-generation view minted from the seed, 1000 repeated
foreign/default refusals including invalid requested roots, unchanged epoch/current owner and
exact scoped occupied-heap release. It retains stale prior-generation refusal, invalid retention,
complete historical/current graph restoration, old readers, changed physical owners, unchanged
state generation, continued publication, strict reopen and repeated successful compaction.

Affected retention/selection, managed publication, maintained compaction-cost, write-crash,
sync-refusal, maintenance, disk-store and migration consumers remain scoped checks. Compiler
privacy guards and pinned formatting/inventory remain publication checks.

Qualification uses matched checked ARC/Clang release/LTO native builds against parent `167e7b35`
with identical compiler/providers/allocator. Producers independently initialize the same managed
8192-entry, 32-byte-value graph (16386 physical nodes). Fresh consumers strictly open it, create
a foreign equal-metadata immutable owner, then time 256 actual managed compaction refusals with
a native monotonic timer. Fixture construction, strict reopen, cloning and reporting remain
outside that interval. Every consumer checks zero hash attempts under provider refusal, exact
occupied-heap release, unchanged current root/generation/epoch, explicit native lease close and
native success. An external observer verifies all managed file names, sizes and SHA-256 identities
before/after; both independently produced fixture directions must be byte-identical. Full ordered
samples, source/build/binary identities and logs belong under ignored `build/storage-db19-*`.

The measured code is `82888e65`. All 11 affected native suites pass, alongside exact repository/
selection compiler privacy, pinned formatting and inventory checks. Forty fresh native consumers
cover both independent producer directions, both binary orderings and five repeats per ordering.
Every managed file is byte-identical between producers and unchanged by every refusal consumer.

| Native interval for 256 stale refusals | Parent | Candidate |
| --- | ---: | ---: |
| Median | 254.6266 ms | 2.167 microseconds |
| Observed range | 233.5485–288.2052 ms | 2.000–2.541 microseconds |

This fixed aggregate observation removes mandatory complete current-root traversal/allocation from
an invalid maintenance request. The short candidate interval is sensitive to timer and compiler
optimization effects; do not divide it into a per-call latency guarantee or extrapolate a general
compaction speedup. Source/fixture inputs, checks, ownership and checked build profile are fixed.
The native probe reports only after owners retire. Hash backend refusal remains active throughout
the measured interval and neither implementation attempts a hash.

`build/storage-db19-measure/timing.json` retains every ordered observation, native command/result,
whole-child elapsed time (a separate scope), immutable file identities and source/helper/compiler/
library/binary/build identities. Reproduce using `build/storage-stack-build.py` with
`build/storage-db19-measure.json`, then `build/storage-db19-observe.py` in a new private evidence
directory. The fixed source is `build/storage-db19-authority-workload.nim.txt`; selected-consumer,
privacy, format and inventory logs share the `build/storage-db19-` prefix. These scoped local
results are separate from exact-head Linux CI.

## Limits

The actual retained-root union still requires complete traversal and the graph remains resident.
No successful-compaction, general recovery throughput, deployment memory ceiling or power-loss
claim follows from stale-refusal timing. There is no disk format, provider, allocator/compiler,
application or StateStore implementation change. M1 framing is complete; full JAM state
serialization and whole-block parity remain open. Scoped local checks remain distinct from
exact-head Linux CI; routine performance CI is unchanged.
