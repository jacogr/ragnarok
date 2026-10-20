# Immutable incremental complete-state trie

Scope: the first increment of [the storage direction](../docs/design/state-storage.md),
implemented in [`src/storage/full_state_trie.nim`](../src/storage/full_state_trie.nim).
Authority: Gray Paper 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` M and B/L, with unchanged [pins](pins.json).

## Representation and public contract

An initialized `FullStateTrie` owns a complete serialized full-node mapping and explicit
`FullStateTrieLimits`. A private revision owner distinguishes empty initialized state from a
default handle. Nodes form an immutable acyclic ARC graph. Leaves own copied complete 31-byte
keys/raw values; branches own nullable children. Every node caches its complete hash, entry
count, nonempty node count and aggregate value bytes. Only newly built unpublished nodes may
receive hashes. Empty subtrees have the zero identity; shared-prefix unary branches remain
real protocol nodes. A singleton is a leaf at every depth, including after deletion collapse.

`newFullStateTrie(entries, limits)` accepts unsorted borrowed entries, rejects duplicates,
and copies caller payloads. Construction applies complete-map ceilings independently of
subsequent mutation ceilings. `commitment` returns copied `StateTrieCommitment` metadata.
`lookup` returns a retained `TrieValue`, `MissingKey` or `Uninitialized`; present-empty values
are successful. A value retains its leaf after all revision handles retire. Byte extraction
copies, so neither source nor returned buffer mutation can change a retained revision.

`apply(revision, writes)` returns a new immutable revision; copied source handles naturally form
independent branches with the same policy. It accepts one Put/Delete per full key, rejects duplicate
identities and payload-bearing Delete, and treats absent Delete as a no-op. An empty batch or a
batch containing only absent deletions retains the original revision identity without hashing.
`sameTrieRevision` compares initialized owner identity, never equal-root equivalence.

Default/failed `TrieResult` values carry reasons alone. Private status/payload access and guarded
success extraction prevent retagging or reading absent data. Default revision commitment and
value reads require checked preconditions. Allocation exhaustion keeps the project's fail-stop
policy; no recoverable OOM result is promised.

## Atomic update and bounds

1. Bound batch count and native sorting extent, validate mutation tags, per-value size and aggregate
   write bytes, then sort fixed key/index descriptors and reject duplicates.
2. Use original-tree lookups to subtract every replaced/deleted entry, then add all Put extents.
   Check exact final entry/value budgets with subtraction before addition. Check native entry
   addressing and a conservative 249-nodes-per-entry bound before node-count arithmetic.
3. Path-copy deletions (including replaced keys), then insert owned Put leaves. This ordering keeps
   intermediate entry/value totals within the proved source/final extents, regardless of caller
   order. Branch construction collapses empty/singleton subtrees and caches exact summaries.
4. Check the exact final topology ceiling before any cryptographic call. Hash new nodes bottom-up,
   reuse previously committed nodes without mutation, and return a new revision only on complete
   success. Any backend refusal drops the private candidate, including partly filled caches.

The complete node ceiling measures the entire revision, not just new hashes. Long values add their
raw-value hash as required by B/L. Paths have at most 248 branches. Batch sorting uses O(w) fixed
scratch; edits use O(w*248) node work/allocation before ARC releases superseded candidates, and
copy new value bytes. Construction uses the same edit path for n initial entries. This first
implementation makes two path-copy passes for replacements; no latency or measured speedup is
claimed. Retaining more revisions retains more shared graph storage; these per-map/batch limits
are not a global history-memory cap.

## Completion verification

- `full_state_trie`: compare exact roots and entry/node counts with the unchanged complete-map
  calculator across deterministic mixed multi-key sequences, all 248 divergence positions with
  zero/one prefixes, singleton/empty collapse, present-empty and 32/33-byte value boundaries.
  Check input/output mutation, detached values, retained revisions, independent branches,
  duplicate/invalid batches and exact/short/max policy counters.
- `full_state_trie_private`: include the implementation only in this test executable to compare
  actual subtree owner identities. The maintained primitive observer counts affected-path hashes,
  refuses each possible successful hash prefix, and proves unchanged source/lookups after failure.
  Verify policy/topology refusal before hashing, cached singleton collapse and 1,000 scoped
  success/refusal/recovery ARC cycles with fresh allocator evidence.
- `full_state_trie_replay`: use the existing pinned `store` fixture provider to replay all seven
  published pre/post mapping pairs. Compare original independently checked roots, node counts and
  every value for forward, reversed and inverse batches, historical revisions and held views.
- Runtime misuse probes require `AssertionDefect`, the intended precondition and nonzero exit;
  genuine valid controls run under the same checked optimized native profile. Compiler privacy
  probes protect revision/value owners and result alternatives.

Reproduction uses the three `make unit SUITE=...` commands in the module README, the registered
`full_state_trie` failure family, compiler privacy guards and `make check-inventory`.
Local evidence and exact-head Linux CI are separate; no power-loss evidence is implied.

## Observed local evidence

Checked optimized macOS ARM64 native runs pass all three selected suites. Published replay retains
all fourteen original mappings from seven pinned pairs, with forward/reordered/inverse updates.
The white-box suite observes five actual hash attempts for a two-key change while retaining the
untouched subtree identity, and rejects every hash prefix without changing the source. Its 1,000
success/refusal/recovery cycles return occupied ARC memory to 192 bytes (192 before/after).
Constructor failure and one-below final topology/payload policies also refuse before publication.

Seven strict runtime rejection probes, six valid native controls and four compiler privacy probes
pass. Local logs live under `build/ci/trie-*`; guard diagnostics and results are retained under
`build/tests/trie-boundaries/` and `build/tests/guards/`. Native suite logs and fresh fixture/ARC
evidence are retained under `build/tests/native/`. Inventory, pinned formatting and whitespace
checks pass. These observations cover the standalone module and its tests; exact-head Linux CI
remains separate and remote checks have not been requested.

## Next boundary

Integrate the proven trie behind `StateStore` while preserving snapshot identity, sorted
checkpoint enumeration, ceilings and atomic publication. Whole-map checkpoint restoration may
build the trie once; changed-node disk persistence follows later. This increment adds no store
integration, disk format, worker, revision-reclamation policy or partial light-state API.
M1 framing is complete; full state serialization and whole-block JAM parity remain open.
