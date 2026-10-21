# Incremental StateStore integration

Scope authorized by the maintainer after the standalone storage stack merged: db #1 owns three
stacked PRs for StateStore contract coverage, incremental in-memory commitments, and consumer
validation/measurements. State #5 confirmed it has no pending overlapping changes and remains idle.
GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` M/B/L and existing pins stay unchanged.

## Frozen public contract

Keep the exported StateStore/StateStoreSnapshot/StateValue types and operations source-compatible.
Enumeration is sorted by every serialized key byte; missing keys differ from present-empty values.
Values, bounded copySlice results, snapshots and private forks retain their exact owners after
updates and destruction. Forks inherit complete-map and batch limits. Failed batches preserve
snapshot identity and values; only successful candidates publish. Empty batches retain identity.
Successful nonempty batches publish a new StateStore snapshot even if an absent delete or identical
put leaves the root unchanged. Independently constructed equal mappings do not share identity.
BackendFailure means a required cryptographic operation failed; backend call counts are not a
public contract, and cached unchanged subtrees need no new cryptographic operation.

`make unit SUITE=state_store_contract` freezes sorted iteration, independently recomputed complete
roots/counts, 0/1/32/33-byte leaves, deep prefixes, exact snapshot identity, retained slices, forks,
input/output mutation isolation and atomic invalid/duplicate/limit refusals on the original store.
Existing store, observer failure, slice, published replay and checkpoint suites remain mandatory
consumer evidence when the commitment implementation changes.

## Planned implementation and completion checks

Retain the sorted mapping for keyAt and bounded value slicing. Each private snapshot also owns one
immutable FullStateTrie revision. Validate the existing store batch before adapting writes and
publishing the sorted map and trie together. Keep stateTrieRoot as an independent test oracle,
not a second production commitment path. Check required-hash failures, exact topology ceilings,
retained forks and ARC release before enabling all existing consumers through this same API.

The fixed public workload `tests/performance/state_store_workload.nim` observes Blake2b call counts
and occupied ARC bytes for 128/1024 entries, 33-byte values, 64 single-key changes and retention
windows of one/eight snapshots. Capture a baseline before implementation with the same pinned
checked optimized ARC/Clang/LTO build and maintained crypto observer. Compare identical source and
inputs after integration; report memory tradeoffs explicitly. Occupied/peak bytes are live memory
observations, not total allocation counts. These counters make no wall-clock latency claim.

Disk adoption, journal/checkpoint/canonical-head atomicity, durable pin policy, full/light startup
selection and all other consumer adoption remain separately gated. This tranche adds no M1 or
complete state-serialization claim. No public StateStore backend selector or alternate execution
path is introduced.

## In-memory adoption

StateStore now privately retains a FullStateTrie in each snapshot beside its existing sorted
mapping. The complete-map constructor and every update use the incremental trie for commitments;
stateTrieRoot remains independent and test-only at this boundary. Existing validation/error
precedence, sorted keyAt and owner-bound value slicing remain in the state layer. Adapted writes
borrow stable input only for the synchronous call; both owners are private before publication.
A single head assignment publishes their matching root and mapping after all checks succeed.

Empty batches retain the exact snapshot. Successful nonempty absent deletes still allocate a new
StateStore snapshot, even if the underlying trie reuses its revision and needs zero hashes.
No required backend invocation is skipped on a changed path; failure there discards every new
node and leaves old snapshot identity/bytes unchanged. Forks retain the same immutable trie and
inherit all mutation ceilings. Sorted-map descriptors still copy with O(n) work. Leaf payloads
currently have separate owned copies in the sorted map and trie; measure that explicit memory
cost before proposing a different shared representation or changing the slice API.

The observer-linked `state_store_incremental` suite uses a complete 256-leaf balanced mapping:
a 33-byte single-key replacement requires exactly ten Blake2b calls (two leaf, eight branches),
including when applying the same mutation on an independently retained fork. First/fifth-call
failures prove atomic rollback; the independent whole-map calculator checks the final root and
every sorted key/value. Absent deletes and empty batches need zero calls; retained values/slices
survive both original and fork owner destruction.
