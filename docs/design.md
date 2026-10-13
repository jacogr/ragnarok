# JAM Ragnarök — Design and Evaluation Plan

**Status:** First general-natural codec slice implemented; evaluation ongoing  
**Date:** 2026-10-13  
**Candidates:** Nim and Odin  
**Decision:** Open; no preferred winner by policy

## 1. Purpose
Evaluate whether **Nim** or **Odin** is the better foundation for an independent JAM (Join-Accumulate Machine) client. The project deliberately balances serious distributed-systems engineering with interest in an unconventional, enjoyable systems programming language.

The first deliverable is **not** a validator: it is a reproducible, spec-conforming codec in both languages and evidence that the chosen language can support cryptography and asynchronous JAM networking.

## 2. Context and prior decisions
- The maintainer previously implemented a JAM codec in TypeScript. That implementation may support differential testing, but the Gray Paper remains authoritative.
- Mojo was considered for its modern design and ownership model; insufficiently established first-class async networking is a blocker for a full client at present.
- Nim offers static typing, ARC/ORC memory-management options, C interoperability, and an established async ecosystem. Nimbus is a relevant example of Nim in blockchain infrastructure.
- Odin offers static typing, explicit allocators, C interoperability, native compilation, and a C-like syntax. Its event-loop and QUIC integration must be proven, not assumed.
- Mandatory tracing GC is undesirable. Both candidates must demonstrate safe and comprehensible memory ownership.
- Language enjoyment and maintainability matter, but never override correctness or the asynchronous networking gate.

## 3. Principles
1. **Specification-first:** version-pin the Gray Paper and vectors before coding; record interpretation decisions with citations.
2. **Independent implementations:** no common codec implementation in C; share only fixtures and test methodology.
3. **Strong types:** model domain distinctions in the compiler, not merely in comments.
4. **Determinism:** encoding and consensus-critical logic must be reproducible across hosts and implementations.
5. **Security at boundaries:** bounded reads, checked arithmetic, explicit decoding failures, fuzzing and adversarial tests.
6. **Replaceable infrastructure:** isolate native crypto and QUIC behind narrow, documented adapters.
7. **Evidence over preference:** compare actual test outcomes, ergonomics and networking behavior.

## 4. Architecture (provisional)
```text
                  JAM application / validator (later)
                               |
                Protocol engine (chosen language)
            +------------------+------------------+
            |                  |                  |
          Codec           PVM / state         Networking
       (native)         transitions (later)  JAM protocol (native)
            |                                     |
       Typed values                          Async transport API
                                                  |
                                        QUIC/TLS implementation
                                        (native lib or bindings)

        Cryptographic primitives via audited native libraries
             with narrow, explicit FFI boundaries
```

JAM's actual networking specification, including transport and authentication, must be verified against a pinned revision. **libp2p use in Polkadot does not imply JAM requires libp2p.** A QUIC implementation with suitable C bindings may be a better fit.

## 5. Candidate-specific design

### Nim
- Use explicit fixed-width protocol types and `distinct` wrappers where appropriate.
- Evaluate `--mm:arc` and document any reference cycles; compare ORC only if warranted.
- Investigate Chronos and available QUIC integration; verify version compatibility, callback lifetimes, cancellation and stream handling.
- Avoid unchecked conversions and reliance on compiler configuration to hide runtime range checks.

### Odin
- Use named structs/types for domain separation, fixed-width numeric types, and explicit allocators.
- Define clear ownership for buffers crossing C interfaces and asynchronous callbacks.
- Investigate current nonblocking I/O facilities and external QUIC integration on Linux.
- Verify whether the resulting concurrency model scales without one OS thread per stream.

## 6. Evaluation sequence

### M0 — Environment and baseline
- Choose Linux target(s), compiler versions and reproducible build method.
- Pin exact Gray Paper and official vector revisions.
- Document the maintainer's TypeScript implementation/version if supplied.
- Establish minimal CI for Nim and Odin.

### M1 — Codec bake-off
Implement in the same order in each language:
1. Primitive fixed-width values and byte buffers.
2. JAM natural-number encoding/decoding.
3. Length-prefixed byte strings and sequences.
4. Option/variant/tuple/structured values as specified.
5. Representative nested protocol structures.

**Acceptance:** byte-exact official vectors, round-trip tests, differential comparison, truncated/malformed input tests, overflow checks, and fuzzable decoder APIs. Check canonical encoding requirements from the pinned specification rather than assuming generic formats.

### M2 — Native cryptography integration
Inventory the **actual primitives required by the pinned specification** before choosing libraries. Verify independent known-answer tests, ABI correctness, thread safety, buffer lifetimes and error handling. Do not invent cryptographic implementations for the bake-off.

### M3 — Async QUIC networking proof
Build a small peer-to-peer experiment with:
- authenticated transport consistent with the pinned JAM networking spec;
- concurrent bidirectional streams and message framing;
- backpressure and bounded memory;
- deadlines, cancellation, reconnect and shutdown behavior;
- error handling for malformed/aborted connections;
- observability and sustained-load tests;
- evidence that connections/streams do not require dedicated OS threads.

**Hard gate:** a credible, maintainable asynchronous networking solution. If a candidate fails, do not proceed with it as the full client language merely because its codec is faster.

## 7. Evaluation rubric
Use these as discussion weights, not as a substitute for hard gates:

| Criterion | Weight | Evidence |
|---|---:|---|
| Protocol correctness and safety | 30% | Official vectors, fuzzing, negative tests |
| Async networking viability | 25% | M3 integration and load tests; hard gate |
| Developer experience and maintainability | 20% | Type expressiveness, debugging, code clarity |
| Native interoperability and ecosystem | 15% | Crypto/QUIC bindings, maintenance and ABI risk |
| Performance and resource behavior | 10% | Throughput, allocations, peak memory, tail latency |

Compare using identical inputs, optimized builds, recorded compiler flags and the same host. Track source complexity and time spent on implementation, not just runtime speed.

## 8. Risks and mitigations
| Risk | Mitigation |
|---|---|
| Gray Paper or vectors change | Pin revisions, track upstream changes deliberately |
| Ambiguous protocol behavior | Record question, exact reference and regression test |
| Unsafe FFI lifetimes | Document ownership and test callback/cancellation paths |
| Odin async integration insufficient | Prove M3 before committing to full client |
| Nim reference-counting cycles or overhead | Design acyclic structures, measure and document ARC behavior |
| Cryptographic dependency gaps | Inventory primitives early; prefer audited implementations |
| Premature performance conclusions | Correctness first, controlled benchmarks later |
| Scope explosion | Milestone gates and no full-validator scaffolding in M1 |

## 9. Proposed repository
```text
AGENTS.md
 design.md
 spec/
 vectors/
 nim/src/ nim/tests/ nim/bench/
 odin/src/ odin/tests/ odin/bench/
 interoperability/
 results/
```
The exact directory names and tooling can evolve by an explicit decision.

## 10. Open decisions
- Which Gray Paper revision and test-vector commit should be pinned?
- Which Linux distributions/architectures are required initially?
- Is the existing TypeScript codec available for differential tests?
- Which Nim and Odin compiler versions are sufficiently stable for the trial?
- Which native QUIC library offers the best JAM-compatible transport and FFI surface?
- What are the exact current JAM networking protocol requirements?
- Is future JAM Implementer's Prize eligibility a goal? Verify rules separately; do not assume eligibility.

## 11. Immediate next task
The first **JAM general-natural encoder/decoder** slice is implemented in both languages, with pinned specification/vector revisions and a shared test runner. See [the verification report](../results/natural-codec.md). Complete the remaining **M0** work (Linux reproducibility and CI), then extend **M1** with fixed-width integers, bounded byte strings and sequences, and composite official vectors.

Do not begin PVM, state transitions, or validator networking until the relevant gates are met.
