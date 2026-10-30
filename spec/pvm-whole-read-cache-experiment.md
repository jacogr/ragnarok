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
