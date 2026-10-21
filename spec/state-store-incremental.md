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
