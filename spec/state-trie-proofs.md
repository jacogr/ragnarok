# Bounded state trie proofs

Authority: Gray Paper 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`merklization.tex` node encoding and trie identification equations; vectors remain
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. No pins or node encodings change.

## Scope and planned completion

Implement independently verifiable membership and non-membership paths, complete-map
proof generation, immutable snapshot binding, bounded batches and a versioned local
transport format. This is a state interface, not a JAMNP-S proof protocol or light-node
store. A supplied trusted root is mandatory for verification. Partial proofs never
become complete-map state, authorize mutations, or establish root/chain trust.

Paths retain canonical 64-byte nodes from root to terminal, at most 248 branches and
one leaf. Branch links preserve the exact 255-bit left commitment and full right hash;
no missing high bit is reconstructed. A terminal leaf must share all traversed key
bits. Empty-edge absence and different-leaf absence require explicit verification.
Independent path/value/batch/input-byte ceilings precede copying and cryptography.

First increment captures canonical immutable witnesses, deep-copies caller values,
and rejects leaf-before-terminal, branch terminals, malformed padding and resource
excess. An explicit empty path is distinct from an uninitialized owner. Capture
confers no membership authority. `make unit SUITE=state_proof` checks these boundaries.

Planned review progression: capture; membership; empty absence; different-leaf
absence; complete-map generation; snapshot adapter; atomic verification batches;
generation batches; local encoding; strict decoding; runtime contracts; privacy;
independent corpus; pinned maps; revision branches; backend refusal; ARC release;
chain root binding; chain lifecycle witnesses; documentation.

M1 framing is complete. Full state serialization and whole-block JAM/STF parity
remain open under the existing pinned request-namespace disposition.

Membership verification now authenticates every selected edge and the exact leaf preimage,
including present-empty and the 32/33-byte boundary. Verified lookups retain root/key authority
and expose only detached bytes. Wrong roots, keys, values and backend refusal expose no lookup.

Empty absence accepts only a zero root with an explicit empty path, or a path ending
at an authenticated zero selected edge. Nonzero truncated edges, attached value bytes
and all-empty branches refuse. Terminal branches may not exceed the 248-bit key domain.

Different-leaf absence requires exact shared traversed bits and a distinct full key.
It requires no separate neighboring value payload and an absent lookup returns no value.
Raw inline terminal nodes necessarily contain their embedded bytes; hashed terminals
reveal only the neighboring value hash.
Forged leaf placement and irrelevant supplied bytes refuse without lookup authority.

Complete-map generation preflights all payload/count/topology/path ceilings and duplicate
keys before hashing. It commits each node once, retains only the selected canonical path,
and omits separate value bytes for absent queries. Source order and storage remain unchanged.
`state_proof_generation` compares generated membership/absence against unchanged trie roots.

The snapshot adapter uses only existing complete-map enumeration and owner-bound reads.
It checks all source value extents before copying and leaves the store/revision policy
unchanged. Snapshot-root trust still belongs to the caller; no storage API changes occur.

Batch verification preserves query order and duplicates under one explicit trusted root.
All owners and per-proof/aggregate quotas preflight before hashing; later cryptographic
refusal publishes no successful prefix. Extraction stays bound to the retained batch.

Generation batches share sorted fixed-key scratch and preflight all paths and aggregate
ceilings before any hash. Query order/duplicates remain explicit. Each query commits
the bounded complete topology independently; no multiproof compression or speedup is claimed.

The local RSP1 envelope is magic `RSP1`, E2 node count, E4 supplied-value byte length,
canonical nodes and supplied bytes, with no suffix or padding. Root and query are
intentionally absent: transport data cannot supply its own trust authority. Encoding
checks native and E4 extents plus outer byte ceilings before allocation. This format
is project-local and claims no JAMNP-S proof interoperability.

Decoding validates magic, count/value extents, exact total length and canonical path
structure before publishing a copied witness. Every truncated prefix, suffix, unknown
version, over-limit count and malformed terminal padding refuses. Decode grants no trust.

Strict source-owned runtime extraction probes cover default, capture, verification,
node index, batch, lookup index, encoding and decoding refusals, with the same real
successful accessors as positive controls. A failed build cannot count as a rejection.

Compiler privacy probes reject witness owners, result tags/payloads, verified presence,
root/key identities and batch/set owners. External callers cannot fabricate verified
evidence or replace the root after verification.

Independent unsorted-list/hashlib reference evidence freezes 45 complete inputs, raw
paths and roots under an exact SHA-256 fixture descriptor. Native verification and
generation each compare the frozen commitments and every path node; literal empty
and singleton controls protect oracle behavior. No reference code enters production.

Pinned-map replay verifies every original key/value in all fourteen full published
mappings against its original independent root, plus authored missing keys. This is
proof/root compatibility evidence, not execution of the published STF blocks.

Independent snapshot forks now prove present-empty, replacement and deletion under
their separate roots. Retained witnesses survive source handle retirement; foreign
revision roots refuse, and detached byte mutation cannot affect proofs or snapshots.

The maintained primitive observer refuses every actual generation and verification
hash prefix, including long-value hashing and completed sibling work. Short individual
and aggregate quotas refuse with zero hash calls; recovery preserves the original
witness, trusted root and source values. No fault hook enters production.

A fresh 1,000-cycle ARC witness covers complete snapshots, raw/decoded paths, generated
sets, verified batches, detached bytes and actual late backend refusals. Occupied
allocator memory must return to the warmed baseline; this is workload-specific release
evidence, not a general allocation-failure or process-memory claim.

Chain adapters accept only an explicitly selected guarded block result. They generate
from its retained complete snapshot and verify against its posterior map root, never
the header prior-state root. Failed selections cannot authenticate an empty proof.
This boundary inherits caller selection trust and adds no consensus/fork-choice claim.

Real signed three-child execution/composition now proves each retained head under its
posterior root. The original parent and each header prior-state root reject a later
posterior witness. This preserves retained history semantics without adding proof RPC,
consensus trust or canonical publication behavior.

## Completed bounded proof interface

The local immutable proof feature is complete within the specified ceilings. Local
checked ARC/Clang verification covers structural/membership/absence checks, complete
map and snapshot generation, ordered atomic batches, exact local framing, strict
runtime/compiler guards, frozen independent paths, every key of fourteen published
maps, independent revisions, actual backend refusal prefixes, 1,000 ARC cycles and
real signed successive-head binding. Reproduce using `make unit SUITE=<suite>` for
`state_proof`, `state_proof_generation`, `state_snapshot_proof`, `state_proof_batch`,
`state_proof_wire`, `state_proof_reference`, `state_proof_published`,
`state_proof_backend`, `state_proof_lifecycle` and `chain_state_proof`.

Logs are retained under ignored `build/state-proof-*`; these are local results,
separate from exact-head Linux CI and complete JAM interoperability. No storage API,
format, canonical publication, Services lease or protocol pin changed. No proof RPC,
light-node store or complete state execution is claimed. The [usage guide](../docs/state-proofs.md)
describes trust, byte limits and retained-owner lifetimes.
