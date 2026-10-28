# Runtime implementation instructions

Read the owning `../docs/design/<module>.md` before changing architectural boundaries.

- Give composite native/thread owners their own explicit non-copyable contracts and lowering
  probes; membership in a non-copyable field alone is not sufficient evidence. Keep worker-pool
  addresses stable until join. Written destructors require explicit `=wasMoved` hooks; delegate
  to child move hooks, retain closed/joined preconditions, and update both hooks when owner fields change.

- Preserve assertions, bounds checks and explicit protocol range/overflow validation in optimized
  builds. Nimony arithmetic intentionally wraps; do not emulate Nim 2 overflow exceptions or treat
  wrapping as a compiler failure. Prove/check sizes before additions, multiplication and narrowing.
  Guard result access with supported contracts. Use ARC/Clang LTO and profile before optimization.
  Initialize every local scalar/pointer explicitly on Nimony; do not assume Nim 2 zero initialization.
  The pinned nightly accepted uninitialized boolean flags and a callback lookup pointer in the peer;
  successful compilation does not prove initialization safety for every scalar kind. See the trial.

Keep JAM codecs, domains, identities, framing and state logic in Nim. Narrow C/Rust interfaces
are reserved for maintained primitives, LSQUIC/TLS and OS interfaces. Compile natively on Linux;
consensus behavior must remain deterministic. Use idiomatic Nim without speculative scaffolding.
