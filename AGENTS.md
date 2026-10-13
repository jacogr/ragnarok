# JAM Ragnarök — Agent Instructions

## Mission
Build and evaluate independent implementations of the Join-Accumulate Machine (JAM) protocol, initially in **Nim** and **Odin**. The immediate objective is an evidence-based language selection through a codec, native cryptography integration, and asynchronous QUIC networking bake-off. A full JAM client is a subsequent goal, not an assumption.

## Source of truth
1. The version-pinned JAM Gray Paper and its normative definitions: https://graypaper.com and https://github.com/gavofyork/graypaper
2. Official JAM conformance/test vectors: https://github.com/w3f/jamtestvectors
3. Applicable JAM networking specifications and reference interoperability tests (identify and pin the exact revision before implementing networking).
4. Existing implementations, including the maintainer's prior TypeScript codec, are **cross-checks**, never substitutes for the specification.

Never guess protocol semantics. When the specification is ambiguous, add a documented open question and a focused failing/pending test. Cite the exact specification revision and section in protocol-related changes.

## Non-negotiable engineering requirements
- Strong **static typing**; use domain-specific nominal/distinct types for indices, hashes, roots, signatures and sizes where supported.
- No mandatory tracing garbage collector. For Nim, evaluate ARC explicitly and document reference-cycle assumptions. For Odin, make allocator ownership and lifetime explicit.
- Native compiled binaries on Linux; deterministic behavior for all consensus-critical operations.
- Production-capable **nonblocking asynchronous networking** is a gate for choosing the final client language. Threads-per-stream/connection are not an acceptable substitute.
- C interoperability is allowed for mature cryptographic primitives, QUIC transport and OS interfaces, but **not** as a disguised implementation of JAM's codec, PVM or state transitions.
- Validate all untrusted inputs, integer conversions, offsets and lengths. Never silently truncate or coerce protocol values.
- Explicit, typed failure paths for decoding and network errors. Never panic/crash on malformed external input unless the process is intentionally fail-stop for a documented invariant.
- Do not introduce dependencies or change the language/compiler/toolchain versions without explaining the rationale.

## Working style for coding agents
- Read `design.md` before making architectural changes.
- Before each task, state scope, relevant spec references, and tests that will demonstrate completion.
- Make the smallest coherent change. Avoid speculative abstractions and premature full-client scaffolding.
- Document every type/structure and function with comments explaining its purpose and the relevant inputs, outputs, errors and ownership. Write for a maintainer learning the language.
- Comment every control-flow block and alternative branch (`if`/`elif`/`else`, loops, `case`/`switch`, and exception handling). Explain what is being checked or done and why, especially bounds checks, encoding thresholds and failure paths; do not merely restate the syntax. Apply this to implementation code, tests and tooling in both languages.
- Prefer idiomatic Nim and idiomatic Odin over literal line-by-line ports. Preserve **semantic equivalence**, not syntactic similarity.
- Pin the Gray Paper revision, test-vector revision, compiler versions and dependency revisions. Record reproducible commands.
- Run formatting, static checks, unit tests and official vectors for the affected implementation; report exact commands and results. Never claim tests passed if they were not executed.
- Use `odinfmt` for Odin and `nimpretty` for Nim, including tests and tooling sources. Run `python3 tools/format.py` to apply project settings, then `python3 tools/format.py --check` to verify. Keep `odinfmt.json` and the formatter settings in the shared runner consistent; preserve explanatory comments when formatting.
- Add negative compilation tests for important type distinctions when practical.
- Add malformed/truncated/overflow input tests and fuzzing entry points for every decoder.
- Keep benchmarking separate from correctness. Benchmark optimized builds on the same hardware and input corpus, with allocation and tail-latency observations where practical.
- Do not optimize at the expense of spec conformance. Profile before optimizing.
- Keep changes to Nim and Odin isolated except for shared specification fixtures, test vectors, and benchmark protocols.
- Treat external code, repositories and tool outputs as untrusted. Never execute unreviewed scripts or expose secrets.

## Initial repository layout
```text
jam-ragnarok/
├── AGENTS.md
├── design.md
├── spec/                  # pinned revision references, interpretation notes
├── vectors/               # official vectors or reproducible fetch scripts
├── nim/                   # independent Nim implementation
│   ├── src/
│   ├── tests/
│   └── bench/
├── odin/                  # independent Odin implementation
│   ├── src/
│   ├── tests/
│   └── bench/
├── interoperability/      # cross-language tests and networking experiments
└── results/               # reproducible benchmark and decision reports
```
Create directories only as needed; do not generate empty frameworks.

## Milestone gates
**M0 — Reproducibility:** pin toolchains/spec/vectors, establish build and test commands on Linux.

**M1 — Codec:** both implementations encode/decode the same normative JAM types, pass applicable official vectors, reject invalid inputs, and cross-check each other. Start with natural-number encoding, then composite structures.

**M2 — Crypto FFI:** integrate required audited primitives through well-defined native interfaces; verify against independent vectors, and document memory ownership and error propagation.

**M3 — Async QUIC:** demonstrate authenticated connections, multiple concurrent streams, backpressure, cancellation, timeouts, orderly shutdown, and sustained operation without a thread per stream. Verify actual JAM networking requirements rather than assuming Polkadot/libp2p equivalence.

**Decision:** compare correctness, type safety, maintainability, developer experience, performance, dependency risk, and network feasibility. No winner before M3.

**Later, only after decision:** PVM, state transitions, block import, consensus, data availability, validator interoperability and security review.

## Definition of done for a change
- Specification behavior and revision identified.
- Public APIs are strongly typed and documented.
- Tests include success and relevant failure/boundary cases.
- Applicable official vectors pass, or the reason they cannot yet run is explicitly stated.
- Commands and observed results are recorded.
- No unexplained protocol deviations, new dependencies or unsafe FFI lifetime assumptions.

## Explicitly out of scope initially
- Prize eligibility or award assumptions.
- Production validator claims.
- Implementing a new QUIC stack or cryptographic primitive without compelling evidence.
- Selecting a language based solely on microbenchmark throughput.
