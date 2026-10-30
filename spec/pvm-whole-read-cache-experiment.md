# One bounded helper-owned backup read-page cache

The final bounded standalone ARM64 experiment starts from the accepted static-width plus compact
fault-PC source6ac63280, retained under the later user's code-size preference. Original failed rules,
noisy tails, rejected native chunk-window and all prior evidence remain separate and unchanged.

A clocks-disabled counter diagnostic of the existing writer passes two full Pinky and two sieve10m
calls with exact state/frame/source/work checks. Pinky has613,063 full load misses of4,934,271 loads
(12.42%); sieve has100,723 of11,272,390 (.89%). Existing writable/spare/read page windows already
cover the rest. This is a cache-thrashing hypothesis; sampled helper share is not exact miss cost.

## One architecture change

Add64 typed readable PageData owner slots **inside the checked writer**, probed only after all three
existing page windows miss. Keep the original per-access owner, prefix, exclusive-end, width and
within-page checks. Only the original complete successful single-page preflight admits an entry.
Use the existing bounded slot-hint hash and exact physical-page identity; collisions are misses.
A backup hit promotes the current owner into the original readPage/tag and uses the original checked
pageScalar operation. Stores retain their existing entire preflight/COW implementation.

Invalidate the affected bucket before every original cloneWriterChunk. Clear all64 retained slots
before every snapshotMemory publication through the shared writer, including unchanged alias seals.
Entries retain typed acyclic owners, never raw chunk pointers or a native lease. No opaque layout
cast, epoch/native guard, native code growth, permission grant, unbounded cache or production edit.
The native emitter, callback table ABI and compact PCs are unchanged. Counters include hits,
preflight admissions and COW invalidations; they are actual variant overhead. Snapshot clearing and
writer allocation are included in their reported lifecycle scopes.

## Gates and evidence

Both compiler cores are byte-identical to the accepted compact core after normalizing their private
machine imports. Both arms include a private machine module to keep helper compilation placement
comparable: baseline machine bytes are production-exact after import relocation; variant includes
the same copy of production machine.nim with only the bounded cache/admission/invalidation additions. All
production files remain reserved to their owners. Independent exact-source and clocks-disabled
actual correctness review precedes timing. Existing142 controls remain;28 all-width image controls
add actual backup hits, alias COW after writable-window eviction, unchanged and changed alias seals,
exact-hash collisions, readonly refusal and warm cross-page atomic refusal. Saved snapshots and
immutable source bytes remain checked. Full Pinky/frame and sieve1000/10m work must be identical.

```sh
make check-pvm-whole-read-cache
make check-pvm-whole-read-cache-compare \
  PVM_WHOLE_READ_CACHE_CORRECTNESS=/absolute/correctness-evidence \
  PVM_WHOLE_READ_CACHE_REVIEW=/absolute/independent-review.json
```

Retain the reviewed complete source/dependency/configuration/compiler/input/archive identities and
clock-only generated projection transition. Every timed cache counter must equal the corresponding
reviewed correctness witness; both arms keep all original helper counts. Same compact generated
image bytes369,832 Pinky/1,482,676 sieve, with3860/17871 static memory sites. Native-memory hits
remain zero: the cache lives behind the checked C callback boundary.

One fixed balanced serial104-process208-call Pinky/sieve pair, both orders,13 fresh owners per cell,
first3 discarded,10 retained,2 calls per owner. Report all raw CPU/elapsed values, medians, means,
ranges, paired observations, constructor/preparation/restore/publication/retirement and host-image
sizes; keep every outlier. No universal5% cutoff: assess modest benefits, resource cost, simplicity,
correctness and transfer consistency honestly. No repeat, capacity sweep, tuning or production/JIT
gain claim. Both arms gasOFF, old pin69e5 and production8bcb held, no gas/default/quota changes.
Original SDK/sysroot/registry completeness limitations and unisolated final destruction remain.

## Final sole-cohort outcome

Independent source/correctness and final retained-data audits pass at measured source
`6af1af10dd070ae7a7217c82c45874d395d18fb5`. The single104-process208-call pair retains80 owners/
160 calls after the fixed discards. Results SHA256:
`fc7c470fead81cfa4cf7d999c2a4c52bec97eada27b639936976cdb40ac289fd`.
Consumed-source archive SHA256:
`65ba8315abc970b3d80ae201fcc7c6d900122511dee440766e6bbba577d1ca05`.
Final independent receipt SHA256:
`ff0744c9cddcc8bbc8f225c791bb8e3f38e86fc5766343c6c07714bf22ce6c06`.

| Workload | CPU medians | CPU means | Elapsed means/medians | Paired observations |
|---|---:|---:|---:|---|
| Pinky |8.879–10.020% better|8.755–10.102% better|same direction, about8.7–10.3% better|10/10 wins in every cell|
| Sieve |0.725–1.024% worse|0.798–1.003% worse|same direction, about0.7–1.2% worse|1,1,1,1 /3,3,0,0 wins|

**Discard as a general improvement under the original cross-workload rule; preserve the research
variant and evidence.** The compact6ac baseline remains accepted. This assessment uses no universal
5%cutoff: the limitation is consistent regression in the other workload. The same directions remain
in full-process CPU/elapsed distributions, including preparation, checks and cleanup. No repeat,
capacity sweep, tuning, default or production/JIT promotion follows this final bounded experiment.

The deterministic cache work is substantial:608,867 backup hits+4,196 full admissions replace
Pinky's613,063 original full load misses;57,455+43,268 replace sieve's100,723. All original checked
callback totals, native guest image sizes and memory semantics remain. Typed page-owner retention
can therefore avoid real duplicate preflight within one execution session, but this cache policy
has a workload-dependent tradeoff. No cache/ARC/compiler-layout component has been isolated as the
cause of the sieve regression. The production entry/checkpoint costs in the architecture report
are separate from this closed standalone caller and remain with their owning implementation lanes.

Resource costs remain explicit:536 additional writer-field bytes before allocator rounding and
64reference clears per snapshot. Host executable files grow16,600/16,584 bytes; actual host text
sections grow3,328/3,120 bytes. The generated guest images grow by zero bytes. Publication clocks
are coarse and do not explain the invocation regression. All CPU/elapsed distributions, means,
medians, min/max, pairs, lifecycle values, four cold builds and host-image identities are retained.

Evidence lives under `build/pvm-whole-read-cache-compare-6af1af10-1793361600164158000/`, including
`summary.md`, immutable `results.json`, `practical-assessment.json`, `all-retained-statistics.json`,
`lifecycle-statistics.json`, `whole-process-statistics.json`, `build-and-host-resources.json`, and
complete byte-preserved `independent-actual/` with `independent-preservation.json`. The prior compact
baseline's original failed threshold and later qualified code-size retention remain unchanged.
This outcome record changes documentation only; no further native execution or CI was needed.
