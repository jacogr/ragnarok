# Physical repository traversal and retained-reader ownership

This storage-only batch starts from merged storage stack #601 at `a000136d`. It preserves the
pinned Gray Paper 0.8.0 commitment rules, public state/store APIs, strict recovery, independent
checkpoint-import trust and all managed file formats. State #6 owns ancestor/download interfaces.

## Measurement contract

`make unit SUITE=storage_traversal_cost` isolates physical repository ownership from temporary
full-state tries and raw transport objects. Three repetitions cover 1,024/8,192 entries, 16/256-byte
values and key offsets zero/29. The latter has a 232-bit common prefix. Sixteen sparse updates
retain the initial root and last eight successor views. Every key/value is checked against authored
mappings before/after owner close; complete scope release must return occupied memory to baseline.

Evidence records occupied bytes with nine readers, after close and with only the final immutable view,
real publication/extraction hash attempts and descriptive phase timing. The publication timing
includes scenario preparation; hash counts are reset immediately before the sixteen updates.
Occupied bytes are current-thread native heap accounting, not RSS or an allocation-event count.
No generic throughput, disk cache or physical power-loss claim follows from these observations.

Generated checked native C shows two candidates: graph traversal duplicates the borrowed
`TrieRecord` including payload, and changed publication duplicates old payloads into every table.
The first experiment will remove only the graph's temporary record copy; a separate dependent
experiment may introduce private immutable record owners while keeping detached public transports.
Both require identical maps, roots, hash counts and rejection behavior, retained-reader lifetime,
independent clones and measured before/after evidence. No caller-controlled trust bypass is planned.

## Merged baseline

All 24 samples pass complete-map and exact scope-release checks. With 8,192 entries and 256-byte
values, nine shallow readers occupy 40,725,264 bytes versus 4,526,272 for only the final reader;
deep readers occupy 44,329,744 versus 5,116,096 bytes. Owner close leaves those readers usable
and does not release their occupied storage. Extraction makes zero hash attempts. The baseline
uses pinned checked Nimony native ARC on macOS ARM64; timing is descriptive only.

## Borrowed graph fields

Graph traversal now reads scalar fields directly from the immutable physical table rather than
duplicating a local `TrieRecord`. All route/cycle/completeness/budget checks remain in place.
Checked generated C contains no record-duplication call in the graph routine, versus one in the
baseline routine. All 24 matching workloads retain identical occupied-byte and hash counters,
complete mappings and exact scope release; this change removes transient payload copies without
claiming a retained-memory reduction. The repository malformed graph regression remains required.

## Private immutable record owners

Changed revisions now own sorted tables of private ARC record cells. Each newly admitted record
copies caller bytes once; later tables share the immutable cell. Public lookups, map extraction and
record/image exports continue to deep-copy payload bytes. Raw images still validate and copy their
inputs. Existing native-worker graph-alias exclusion and join-before-retirement remain mandatory;
sharing private ARC cells does not introduce concurrent graph access. There is no public cell or mutable access to stored records. Cell sequences reserve capacity
and append initialized nonnil owners; no nil placeholder is treated as an admitted record.

At 8,192 entries, shallow nine-reader occupied bytes fall from 23,006,544 to 4,014,928 for 16-byte
values and from 40,725,264 to 5,984,848 for 256-byte values. Deep-prefix results fall from
26,611,024 to 4,842,576 and from 44,329,744 to 6,812,496 bytes respectively. All 24 cases preserve
complete maps, publication/extraction hash counts and exact final scope release.

The per-cell owner costs memory with only one reader: the 8,192-entry shallow cases increase by
375,616 occupied bytes, and deep-prefix cases by 449,600 bytes. This is an explicit tradeoff for
bounded retained histories, not a claim that every lifetime uses less memory. Physical record/value
ceilings and descriptor-overflow refusals remain unchanged. `storage_record_owners` checks caller
input/output mutation, independent mutable forks/clones, stale identity, retained views after close
and 1,000 ARC release cycles.

## Selected clone sharing

A validated selection clone now allocates an independent sorted table and fresh public view
identity while sharing only selected private immutable cells. It retains no source table or view,
accepts no serialized input and grants no additional root/finality authority. Exact inherited trie
policy and physical record/value ceilings are checked before allocation, including the original
descriptor-overflow bound. The source selection's index order remains unchanged.

The workload additionally measures occupied bytes above an already-owned selection during clone
creation, checks zero hash attempts and compares every selected map. Fork/detachment tests return
a clone across a helper boundary where its source owner, source views and selection all retire.
The original policy, stale-identity, omitted-root and ARC tests remain; an explicit narrowed value
ceiling refusal is added. No private record payload is ever returned through a public mutable view.

For 8,192 entries with 256-byte values, additional occupied clone storage falls from 4,882,528
to 135,360 bytes for shallow keys and from 5,232,992 to 151,744 bytes for deep-prefix keys.
All 24 matching cases preserve complete maps, zero clone/extraction hash attempts, publication
hash counts, the reader-memory observations and exact final scope release. This measures only
additional clone ownership above an already-owned selection, not total process memory.

## Byte-prefix route verification

Starting from merged stack #614 at `e1cb3ce0`, complete graph validation compares full prefix bytes
and masks only the high routed bits in the final partial byte. At depth248 it compares exactly
31 bytes; no access to byte31 occurs. Unvisited low key bits remain unconstrained. This replaces
up to248 bit tests per leaf with up to31 byte tests, preserving the complete-key routing contract.

`storage_prefix_routes` independently authors and hashes two-leaf graphs at all248 divergence
depths with zero, all-one and alternating common prefixes. It accepts present empty values and
rejects first/interior/final wrong edges despite valid local hashes, leaving the owner unchanged.
The24 matching checked native traversal samples preserve maps, occupied bytes and every hash
counter. Timings are descriptive; no general speedup is claimed without controlled timing tools.

Next work stays within physical storage: reuse multi-root scratch without sharing per-root visited
state, canonicalize selected inventories once, reduce repeated serialized admission work, then add
bounded read/maintenance capabilities with explicit authority, lifetime and budget contracts.

## Reused multi-root scratch

Root selection and raw/serialized image admission allocate the physical visited array once per
operation, rather than once per root. Between roots, they clear exactly the recorded branch/leaf
positions and retain the collection buffer capacity. Counts and route prefixes start fresh for each
root. The union's retained bitmap remains separate: it cannot suppress per-root cycle, route or
value-limit checks. Empty roots do not skip the reset. This reduces allocation sites from one per
root to one per operation; no wall-clock claim follows from that structural count.

`storage_retention_plan` includes reverse root order with an intervening empty root; `storage_image`
continues to admit multiple individually bounded graphs whose union exceeds a single-root value
budget, and rejects omitted-root orphans and malformed unions. Both retain exact ARC release.

## Canonical immutable selections

Selection construction sorts unique retained physical indices once. Repeated record exports and
independent clones read that canonical order directly, removing one index-array allocation/copy
and sort from each operation. Public retained-root request order remains unchanged; encoded image
roots retain their existing canonical ordering. Detached public payloads and fresh clone identities
remain mandatory. Opposite root orders produce identical physical transport, and retained owners
remain independent after source close. The24-case workload must preserve roots, counters and memory.

## Serialized revision admission

`publishEncoded(expected, input)` synchronously decodes untrusted revision bytes under the exact
live repository policy, then privately reuses only that decoder's record integrity checks. Full
base, identity, generation, topology, route, metadata, conflict and orphan admission checks remain.
Raw `publish` always revalidates mutable transports. Neither API accepts a skip flag or trust token.
All failures preserve the prior owner; success owns bytes independently of caller input. This is
physical admission, not canonical chain authority or checkpoint trust.

`storage_encoded_publication` counts genuine hashes (three for the initial graph, two for its sparse
delta), tests all truncated delta extents, altered bytes, self-consistent wrong routes, narrowed
physical ceilings, stale identities, decoded-then-mutated raw input and retained maps after close.
It requires1000 exact ARC release cycles. Disk replay adoption is a separate dependent change.

## Fused journal replay boundary

`replayJournalFrame` and explicitly selected `replayContextJournalFrame` require exact outer frame
consumption, checksum integrity and the expected view's contiguous generation before serialized
publication. The live repository supplies the inner physical policy. Context is copied before
publication and returned only with a complete admitted revision. A new `InvalidRevision` refusal
represents stale, noncontiguous or invalid complete graph admission; codec diagnostics remain
selected under `InvalidRecords`. Existing detached frame decoding remains independently checked.

The focused suite covers genuine outer+inner hash counts, all truncated contextual extents,
checksum tampering, generation skips, false graph metadata, context/frame quotas, detached caller
mutation and1000 ARC cycles. Replay alone does not select a disk head or authorize repair.

Replay reads the immutable expected view's scalar repository policy, refusing an oversized inner
body before outer checksum hashing. The observer suite requires zero hash attempts on that refusal.
`repositoryLimits(view)` returns only copied policy scalars, never graph ownership or mutable bytes.

## Legacy journal replay adoption

Strict single-file open/recovery uses atomic fused replay for each exact frame after independent
chain/schema admission. Replayed context advances only after a complete admitted revision. Normal
open still refuses incomplete tails; explicit repair still requires the independently supplied
exact generation/root prefix token, preserves complete successors and synchronizes before/after
truncation. File identity, bytes, publication and uncertainty behavior remain unchanged.

Required local regressions cover the file repository, published complete-map replay pairs and
real interrupted-write recovery. Managed replay adoption follows independently.

## Managed journal replay adoption

The managed owner independently admits CURRENT, its bound snapshot and paired journal header,
then uses the same fused replay for each exact contiguous frame. No alternate epoch scan, fallback
head or inferred checkpoint/finality authority is introduced. Confirmed-prefix repair requires the
same independent exact generation/root token and refuses complete corrupt/successor frames.

Required local regressions include real managed append recovery, corruption/short-write failures
and application-level explicit managed recovery. Snapshot admission and worker ownership stay intact.

## Exact real-file replay cost

`storage_replay_cost` closes/reopens both physical layouts with both full-node schemas,16/64-byte
values,16 sparse updates and three repetitions. The independently counted35 physical record
checks plus18 identity/frame/snapshot checks require53 real hashes for inline values and70
when17 distinct long values each require their separate value hash. All journal bytes remain
identical; complete maps, generation17, context and retained readers are checked after close.

The1K/8K managed workload additionally asserts replay hashes equal stored physical nodes plus
18 outer checks and any long-value hashes. Compacted reopen requires selected nodes plus two
outer checks and the same retained value hashes. Persisted checksums/bytes remain baseline-bound.

The12 matching1K/8K managed samples preserve every persisted snapshot checksum and byte extent,
selected/physical count, publication/compaction/reopen hash count and complete map. Journal replay
removes272 redundant hashes with inline values and288 with long values. Timing stays descriptive.

## Early image metadata refusal

Raw and serialized images share scalar/root-inventory preflight: nonzero generation, nonnegative
and policy-bounded selected counts, possible empty/nonempty target metadata, canonical unique
roots including the selected root, and host-bounded inventories. Known impossible metadata now
refuses before physical decoding/copying/hashing. It carries no integrity authority: accepted
metadata still requires every record hash, graph route, per-root budget and orphan check.

The decoder observer requires zero hashes for invalid generation, excess selected entries and
missing selected-root membership. Existing malformed image, empty-current union and ARC coverage
remain. Error precedence for impossible metadata is explicitly before physical transport errors.
