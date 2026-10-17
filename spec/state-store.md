# Owned in-memory state store

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` M and B/L. The store accepts already serialized 31-byte keys and raw
values. It reuses [the existing root calculator](state-trie.md); it neither changes T(state)
nor interprets service namespaces. Sources and vectors remain at [their pins](pins.json).

## First increment

`src/state/store.nim` provides an owned map with atomic mutation batches and retained immutable
versions. This is the storage foundation for execution, not state-transition execution, a disk
backend, trie-node database, proofs or incremental root updates.

- `newStateStore(entries, limits)` validates the complete mapping/root before copying caller
  bytes into private ARC storage. Duplicate initial keys reject. Input order is irrelevant.
- `snapshot(store)` retains the current version as an opaque `StateStoreSnapshot`. The name is
  distinct from the existing typed-composition `StateSnapshot` in `codec/state_composition`.
- `snapshot.lookup(key)` returns either a retained `StateValue`, `MissingKey`, or an initialization
  error. A present empty value is successful with length zero. The view retains its exact owner;
  it exposes a length and an explicitly copied byte sequence, never mutable backing storage.
- `snapshot.commitment` returns copied root/entry/node metadata. Prior snapshots and lookup views
  remain valid after updates, handle copies and destruction of the originating store.
- `store.apply(writes)` accepts one mutation per key. Put inserts/replaces, Delete removes, and
  deleting an absent key is an idempotent no-op. A Delete with a payload rejects. Duplicate batch
  keys reject even for identical writes; there is no order-dependent last-write-wins policy.

A batch preflights its count, tags, individual/aggregate write bytes and exact final-map count/
value bytes. Two sorted merge passes count then construct the private candidate. Old published
values remain immutable; new caller values are deep-copied. The existing root calculator checks
node budgets and computes the candidate root. Only complete success publishes the new head.
Any policy, duplicate or backend failure drops the candidate and leaves the prior head unchanged.
An empty batch retains the existing snapshot without hashing.

All count/byte arithmetic is checked before addition/allocation under Nimony's wrapping integer
semantics. Explicit batch limits supplement `StateTrieLimits`. Allocation exhaustion retains the
project's fail-stop policy. Limits apply per map/batch, not globally to caller-retained historical
snapshots; callers control their retention. Worst-case sorting is O((n + w) log(n + w)) including
root construction; updates recompute the full root. There is no performance claim in this increment.

Stores are single-threaded value handles. Copying a store creates another independently updateable
handle sharing immutable prior state. Borrowed initial entries and writes must remain stable for
the call. ARC owners are acyclic; no callback, foreign pointer or mutable sequence is exported.
Default and failed tagged results expose only their reason. Successful payload extraction and
initialized-view access have checked contracts; private fields remain inaccessible to callers.

## Verification and next increment

Two native Hastur suites run in `make check-unit`: the production crypto profile exercises owned
inputs/outputs, missing/empty values, mixed insert/replace/delete, stable snapshots, independent
handles, all small resource ceilings and atomic failures. A 64-batch deterministic history is
checked against a separate four-slot model after every update. The observer profile injects first-hash
and late-hash refusal, checks rollback/recovery and no-op/preflight behavior, and asserts equal
live allocator occupancy across 1,000 isolated success/failure cycles after warmup.
Four privacy probes run in `make check-guards`. The all-source gate discovers the new module.
Existing trie/root corpora continue to own independent Merklization conformance evidence.

Next: replay the pinned published pre/post mappings through this store as initial state plus
explicit write differences, checking every lookup and both roots. That will test storage updates;
it will not claim execution of the blocks that produced those states. Published storage replay is
not yet evidence supplied by this first increment. The request-domain release checkpoint and all
other [upstream policy dispositions](state-clarifications.md) remain unchanged.
