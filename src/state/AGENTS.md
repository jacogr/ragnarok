# State implementation instructions

- The client must ultimately support full-node and light-node operation selected by a command-line
  mode flag. Choose the corresponding database at startup; preserve separate mode-specific
  databases rather than assuming one shared schema or mixing full and light data.
- Full and light modes may also require distinct in-memory stores. Share interfaces only for
  operations with the same semantics; do not force partial light state through complete-map APIs.
- The current `src/state/store.nim` owns complete serialized mappings for full-state execution.
  A light node's verified roots, partial state and proofs need their own appropriate storage
  contract. Never present a root recomputed from a partial mapping as a complete JAM state root.
- Keep state codecs and Merklization primitives reusable. Decide mode/backend selection at the
  application boundary; do not scatter full/light conditionals through codecs or add placeholder
  light-mode functionality before its bounded implementation is authorized.

Read [the protocol interpretations](../../spec/AGENTS.md) for request namespaces and signing/tree
domains. Preserve complete-map provenance through state transitions; partial light state must
never masquerade as a complete serialized state.
