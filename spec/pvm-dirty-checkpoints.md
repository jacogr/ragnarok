# Dirty-page checkpoints

## Scope and authority

This changes local execution-memory bookkeeping under the existing handler-stream and machine
contracts. Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, pinned dependencies, checked
memory exception ordering, gas, attempts, source PCs and host response validation are unchanged.

## Representation and ownership

Each frame admits a page-index buffer with capacity equal to its mapped page count. A successful
scalar store adds an index only when its existing dirty bit first changes from zero to one.
Full-span store validation still precedes both bookkeeping and byte mutation. Cross-page stores
record both pages. The buffer cannot grow beyond its admitted capacity: every recorded index is a
unique member of the validated mapping. It belongs to invocation memory, never the prepared stream.

An untouched checkpoint returns its immutable source memory immediately. Sparse checkpoints copy
and sort only dirty indices, binary-search those pages in the sorted source images, and publish
actual changed bytes through the existing checked replacement API. Repeated observation does not
consume the dirty epoch. Writing original bytes back still produces no page replacement.
When at least one eighth of mapped pages are dirty, publication retains the existing linear walk;
this avoids sorting almost the complete mapping. Successful host resume and reset clear only
bitmap words named by dirty indices and empty the index buffer without releasing its capacity.
Transactional mapping/permission replacement constructs fresh bookkeeping with the new frame.

The sparse enumeration cost is O(D log D + D log P), with P mapped and D dirty pages; the dense
path remains O(P). Untouched publication and clearing are O(1); clearing a written epoch is O(D).
The additional admitted index storage is four bytes per mapped page. This increment does not
remove full initial memory materialization, host changed-root discovery, or the O(P) immutable
root-vector copy when bytes actually change. Those remain separate follow-up work.

## Completion evidence

`pvm_stream_regions_and_host` adds independent literal-byte witnesses over a257-page mapping:
untouched hosts, sparse and fully dirty maps, descending writes, the highest guest page, a store
crossing both a page and bitmap-word boundary, repeated writes, write-then-restore, repeated
observations, accepted host checkpoints, reset before accepting a response, and retained earlier
snapshots. Existing memory opcode/fault/permission, host repair, and native/refusal suites remain
semantic controls. No test depends on the private index-list layout.

Baseline production is `4a29188758026f062e2b970b96df2665d8764d4e`. Native validation and matching
baseline/candidate measurements run in CI; results are pending. No throughput improvement is
claimed from source complexity alone. In particular, allocation/setup cost and dense-store
throughput must be checked alongside host-heavy execution before accepting the optimization.
