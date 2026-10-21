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
