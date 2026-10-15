# Language recommendation: Nim

Date: **2026-10-15**. Scope: the measured M1 codec, M2 crypto and M3 networking evaluation,
including three prospectively tracked implementation increments. This records the implementation
agent's recommendation; it does not record a final maintainer decision. The maintainer's personal
language preferences are excluded from this assessment.

**I recommend Nim for the main implementation, with Odin as the strongest alternative.**
This is an engineering recommendation supported by our measurements and implementation
experience. We have not demonstrated a defect-rate winner.

## Where we are

The three candidates have passed the bounded M1/M2/M3 workloads. QUIC feasibility no longer
separates them: each supports the maintained LSQUIC adapter, retained connections, cancellation,
backpressure, recovery and bounded crypto offload. Nim's earlier dependency-patch burden has also
been removed. These are bounded POC results, not full protocol coverage or production readiness.
See the [parity record](mojo-parity.md) and [adapter replacement](quic-adapters.md).

The tracked development evidence now looks like this:

| Across three equivalent increments | Nim | Odin | Mojo |
| --- | ---: | ---: | ---: |
| Compiler repair cycles | **1** | 6 | 7 |
| New production implementation LOC | **552** | 715 | 753 |
| Confirmed post-compilation implementation defects | 0 observed | 0 observed | 0 observed |

Every language has occupied each implementation-order position once. Sequential learning and
shared agent context remain limitations. These numbers support lower observed implementation
friction for Nim; zero observed defects across all three does not establish superior reliability.

The LOC totals cover new production code in the three tracked increments, not the whole project.
Tests, drivers, shared infrastructure and reused implementation are excluded. Earlier untracked
repair counts remain N/A. Intentional rejection probes are excluded from repair counts.
See the [recorded comparison](ai-ergonomics.md#subsequent-matched-implementation-evidence) and
[hash-linked cumulative ledger](ergonomics/increment-totals.json).

## Why Nim

**The strongest reason to choose Nim is ownership.** Our immutable snapshots, seed storage and
retained Rust owners use private ARC-managed storage with automatic final cleanup. The current
Odin and Mojo implementations leave more release and alias-lifetime obligations to callers.

From implementing these paths, I consider those recurring obligations more consequential than
occasional syntax repairs: they can survive compilation and fail only during cancellation, early
returns or shutdown. Nim's [documented destructor mechanisms](https://nim-lang.org/docs/destructors.html)
support that design, although foreign pointers, cycles and concurrent access still require
explicit care. This is an architectural judgment, not evidence of a measured lower defect rate.
See the [ownership comparison](ai-ergonomics.md) and the actual
[snapshot storage](../nim/src/owned.nim), [seed cleanup](../nim/crypto/primitives.nim) and
[Rust-owner cleanup](../nim/bandersnatch/bandersnatch.nim).

Performance gives me enough confidence to recommend Nim, while preserving a substantial
qualification:

- Standard bulk copies removed much of the original large-payload discrepancy.
- Checked LTO report performance is competitive. Our four-digest pipeline measured roughly
  **79.5 µs Nim, 124.0 µs Odin and 81.7 µs Mojo**.
- That pipeline includes different crypto providers, so it is not a language-only victory.
- Odin retains a meaningful integer-sequence advantage: approximately **3–3.6×** against checked
  Nim LTO in the large sequence cases.

Those are Mac measurements on authored workloads. They do not establish full-client throughput
or justify assuming every remaining hotspot will be easy to optimize. The recommendation retains
ARC/Clang LTO with assertions, bounds, range, field and overflow checks enabled.
See the [report performance evidence](work-report.md) and
[remaining sequence gap](checked-bulk.md).

## Alternatives

**Odin would be my second choice.** It offers strong measured codec performance, useful static
checks and better explicit allocation-failure control. Its additional ownership bookkeeping is
the principal reason I place it behind Nim for this implementation workflow. Its smaller
implementation in the latest round—83 lines against Nim's 89—is also evidence that Nim does not
win every task. See the [latest matched round](assurance-crypto.md).

**I would not select Mojo from the current evidence.** It reached parity without private runtime
hooks or dependency patches, but added more SDK/FFI integration work, has less complete allocation
instrumentation in our adapter, and has supplied no demonstrated advantage sufficient to offset
those costs. This assesses the pinned implementation and toolchain; it is not a claim that Mojo
cannot support this project. See the [parity and resource observations](mojo-parity.md) and
[development evidence](ai-ergonomics.md).

## What could change the recommendation

I would reconsider Nim if representative Linux client workloads show the remaining checked-codec
costs materially limiting throughput, or if recoverable allocation exhaustion becomes a firm
architectural requirement.

The unresolved Ed25519 acceptance-policy discrepancy also needs resolution before
consensus-sensitive verification is considered complete, regardless of language. Ordinary-key
fixture agreement does not resolve exceptional-point policy differences. See the
[crypto interpretation](../spec/crypto.md). Backend/dependency security review, independent JAM
interoperability and full-client implementation remain outstanding work.

The latest local test results and CI wiring are recorded in the individual reports; this
recommendation does not infer a new Linux CI pass from local success or workflow configuration.

## Suggested direction

**Select Nim, retain checked ARC/Clang LTO and the narrow maintained native adapters, and move
beyond language-comparison slices.** Further small codec rounds would refine the ergonomics
evidence; I do not currently expect them to change the choice.
