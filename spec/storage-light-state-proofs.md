# Root-bound state lookup proofs

Scope: a standalone storage primitive for the maintainer's light-state investigation. It verifies
one key against a caller-supplied trusted complete-state root. It does not select trusted heads,
implement consensus/finality, open a database or expose partial data through `FullStateTrie` or
`StateStore`. No node-mode startup, networking, persistence or application integration is authorized
by this contract. Full/light schemas and databases remain separate future work.

Authority: pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`text/merklization.tex`, state Merklization M/B/L. Reuse canonical `state_layout` encodings and the
real Blake2b primitive. This proof container is a local API, not a JAMNP-S or other wire format.
No external proof-format compatibility is claimed.

## Trust and data contract

The caller supplies the exact root and query key. The root must already identify a trusted,
well-formed complete GP state trie; matching a proof cannot establish that root's provenance,
chain identity, finality or the validity of unvisited subtrees. The verifier returns a lookup bound
to that exact root/key, never a recomputed root from partial state or a complete-map entry count.

An untrusted `StateProof` owns root-to-terminal canonical 64-byte nodes and a raw value only for
presence. Inputs remain stable during the synchronous call. At most 249 nodes are permitted:
248 branch levels and one leaf. Caller-selected node and value ceilings may be smaller and apply
before hashing or allocating owned output. Verification uses bounded fixed scratch. Only a fully
validated successful lookup copies the value into private immutable storage. Copies of the lookup
retain that storage; extracted bytes are independent copies.

Branch direction follows the query's MSB-first 248-bit key. The root and right children compare
all 256 digest bits. Left children compare exactly the committed low 255 bits; the discarded high
bit is never invented or required to be zero. A selected zero child proves absence only when the
path ends there. A terminal different-key leaf proves absence only if its key shares every
traversed query prefix bit. A matching leaf proves presence after the supplied raw value reproduces
its exact canonical leaf encoding, including the 32/33-byte embedded/hashed boundary.

A zero root with no nodes proves absence. A nonzero root with no nodes, or a path stopping at a
nonzero child, is incomplete and proves neither absence nor presence. Extra nodes after an empty
child/leaf, malformed canonical encodings, mismatched links, too-deep branches, mismatching leaf
prefixes and unused absence payloads are rejected. There is one accepted representation; trailing
nodes are not ignored. Default/failure results expose only reasons. A successful lookup explicitly
distinguishes Present/Absent; absent lookups cannot expose bytes. Real primitive refusal is typed
BackendFailure and never becomes absence.

## Complete-revision proof production

`FullStateTrie.prove(key, limits)` produces the same detached `StateProof` directly from an
initialized immutable complete revision. It follows only the selected key path, with no full
record export, global sorting or reconstruction of unrelated subtrees. A first walk preflights
the exact node extent and, for a matching leaf, copied raw-value bytes. Only then does a second
walk allocate one exact node buffer and one matching-value buffer. Empty roots produce empty
proofs; a selected empty child or a different-key leaf produces absence evidence with no raw value.
The original revision and all retained forks remain unchanged on every outcome.

Generation reuses cached full child hashes to encode branches without hashing them. Encoding an
inline leaf is also hash-free. A terminal long leaf requires exactly one real raw-value hash to
reconstruct its canonical encoded node, including when that different-key leaf proves absence.
The absence proof omits the raw value, so its `valueBytes` limit may be zero; encoding the terminal
node still uses the source revision's already validated per-value policy. Provider refusal exposes
BackendFailure and retires any partially filled private output. Node/value quota refusals occur
before output allocation or hashing. Default revisions return Uninitialized rather than empty-root
evidence. The result supports the existing `TrieResult.takeValue` owning transfer without copying;
the copying `value` accessor remains available.

The producer makes no claim about the root's chain/finality authority. Callers pair the proof with
an independently trusted complete root and the exact query when invoking `verifyStateProof`.
Maximum output is 249 fixed nodes (15,936 node bytes) plus caller-bounded matching raw value bytes;
allocator rounding and descriptor storage are separate from these logical byte extents. Generation
walks at most 498 nodes and makes at most one hash attempt. These are algorithmic bounds, not a
measured latency claim or a global memory cap across retained proofs.

## Completion verification

`make unit SUITE=storage_state_proof` uses independent complete-map roots and a detached
test-only physical-record path producer to cover empty,
singleton, shared-prefix maps, both branch directions, present-empty and 32/33-byte payloads. Tamper
every path position, supplied value, root, query and canonical header/padding; test missing/trailing
nodes, zero children, the maximum depth, limits before hashing, actual primitive refusal and exact
retained input/output isolation. Compiler/runtime witnesses protect result and lookup ownership.
A 1,000-cycle lifecycle witness returns to the exact occupied ARC baseline. Exact observer counts
require one hash per supplied path node plus one raw-value hash only for present long values;
no unvisited subtree or full-map hashing is performed. The maximum accepted path has 249 nodes
(15,936 node bytes), independent of complete-map size; one additional long-value hash gives a
maximum of 250 primitive attempts. This is an algorithmic bound, not a measured latency claim.

Local checked macOS ARM64 evidence uses pinned Nimony ARC/Clang release with bounds/assertions
enabled and the maintained native runner. Runtime guard builds retain ThinLTO; exact-head Linux
CI remains separate. The source-owned compiler privacy fixtures and runtime failure family cover
default/failed result extraction, default lookup access and absent-value extraction, with real
success controls. Full logs and source/compiler/library identities remain under ignored
`build/storage-db24-*`.

M1 framing is complete. Complete state serialization, whole-block JAM parity, light database/cache
policy and trusted-head selection remain open. This primitive is not a deployable light node.


Producer verification uses `make unit SUITE=storage_proof_production` for independent full-map
roots, unsorted maps, both polarities, matching and different-key singleton terminals, selected
empty children, empty/32/33/256-byte values, 248/249-node ceilings, present-value ceilings and
zero-byte absence allowance at a long terminal. Exact public allocator calibration checks held
proof storage against one exact node buffer plus its copied payload; owning result transfer
allocates no additional storage. Mutation of proof bytes cannot change the source revision or
verified retained lookup. Detached proofs survive all source owners, and old/new fork proofs
remain bound to their respective roots. A 1,000-cycle workload includes successful generation,
partial-output provider refusal and recovery, with exact occupied ARC retirement.

`full_state_trie_replay` additionally verifies generated proofs for every present entry in the
seven pinned published pre/post mapping pairs and authenticated deletion proofs at the published
post-state roots, across forward/reordered/inverse retained revisions. Existing trie/privacy,
owned export and proof-verifier suites cover the unchanged consumers. Local evidence stays under
`build/storage-db25-*`; exact-head heavy Linux verification remains separate.
