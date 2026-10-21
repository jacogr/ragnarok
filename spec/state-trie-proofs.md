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
