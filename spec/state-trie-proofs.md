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
It never requires or returns the neighboring value, including hashed long leaves.
Forged leaf placement and irrelevant supplied bytes refuse without lookup authority.

Complete-map generation preflights all payload/count/topology/path ceilings and duplicate
keys before hashing. It commits each node once, retains only the selected canonical path,
and never copies an absent neighbor value. Source order and storage remain unchanged.
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
