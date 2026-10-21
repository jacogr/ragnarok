# Final terminator validation at JAM preparation

This isolates GP-PVM-004 in the [discrepancy register](graypaper-discrepancies.md).
Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` admits final
fallthrough/conditional opcodes as members of T, then performs destination checks
at execution. Pinned PolkaVM `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`
public interpreter module loading rejects these programs before any instruction.
The maintainer approved a scoped compatibility exception at shared JAM guest
preparation. Raw program decoding and execution remain paper-aligned.

The [native witnesses](../tests/unit/codec/test_pvm_final_terminator_validation.nim)
verify the existing paper behavior: load r7=7 over99, then final fallthrough or
conditional branch to entry0 with missing fallthrough. Both blobs decode, the prefix
executes, and panic retains7. A trap-ending positive control behaves the same at
full recursive exit. Two steps complete; one step refuses locally. All source CPU
aliases remain unchanged. Prepaid gas isolates validation/execution from pricing.

The [public reference checker](../tests/reference/polkavm_memory/src/bin/validation.rs)
uses the same literal code and mask, with no private hooks or source patches. Raw
ProgramBlob parsing succeeds for all three. Code validation and Module::from_blob
reject final fallthrough/conditional at offsets4/6; the trap control executes and
retains A0/r7=7. These differing observations are intentional fixtures, not a claim
that loading parity passes.

## Reproduction and approved scope

```sh
make unit SUITE=pvm_final_terminator_validation
rustup run 1.99.0 cargo run --release --locked --offline --manifest-path tests/reference/polkavm_memory/Cargo.toml --target-dir build/polkavm-memory-reference-target --bin validation
rustup run 1.99.0 cargo fmt --manifest-path tests/reference/polkavm_memory/Cargo.toml -- --check
```

`initializeMachine` now rejects a final fallthrough or conditional as
`InitializationError.InvalidProgram` before materializing memory pages. Authorization,
refinement and accumulation already use this shared boundary and retain their
existing typed failure mappings. Rejection publishes no CPU or partially initialized
memory and executes no prefix or host call. It does not fabricate a guest panic or
change invocation-level gas normalization.

The raw decoder/stepper and inner-machine decoder keep their paper behavior. This
exception only narrows JAM preparation's final terminator rule; it does not adopt
other PolkaVM validation restrictions or eagerly validate static/dynamic targets.
A final trap, static jump, indirect jump, load-immediate/static jump or
load-immediate/indirect jump remains admissible. A conditional/fallthrough with a
present final trap successor remains admissible too.

The initializer suite covers all22 final members of T, each with0/1/24 operand
padding bytes and reachable/unreachable suffixes, plus the original conditional
witness, present-successor controls, a runtime-invalid static target and source
preservation. The raw three-case witness remains unchanged.

Require both actual implementations' observations, pinned sources, selected native
suite, reference-tool checks and inventory. M1 framing remains complete; full state
serialization, whole-block parity and full chainspec equivalence remain open.

## Upstream discussion context

The2026-10-21 [upstream review](graypaper-discrepancies.md#upstream-discussion-review-2026-10-21)
found explicit prevalidation discussion in merged PR508, including
[the proposal](https://github.com/gavofyork/graypaper/pull/508#discussion_r2733227344)
and [reviewer agreement](https://github.com/gavofyork/graypaper/pull/508#discussion_r2735584016).
This establishes relevant design intent. It does not explicitly resolve why a final
fallthrough/conditional, admitted by the pinned T-based predicate, is rejected by
PolkaVM. The precise formal rule remains an upstream question; our scoped preparation
exception follows explicit maintainer approval, with no pin adoption.

## Observed local evidence

All three native witnesses pass, including the conditional whose taken target is
valid entry0 and whose missing fallthrough alone causes panic. The public checker
confirms exact validation failures at4/6 and the executing trap control. Pinned
formatting passes2585 Nim sources plus both Rust format checks; upstream-lock and
local documentation-link checks pass. Inventory passes219 failure families/2562
probes/341 native suites. Evidence is local checked-release macOS/ARC/Clang LTO
and pinned Rust release; no remote CI or full upstream Rust suite is claimed.
Logs remain under `build/pvm-final-terminator-*`. The raw interpreter evidence remains applicable after the preparation-only change.

The approved preparation check passes the initializer matrix and its existing
1000-cycle ARC lifecycle (2320 bytes before/after). The public pinned PolkaVM
checker independently passes all132 final-terminator/padding/reachability cases,
including exact rejection offsets. The raw three-case suite still passes.
Inventory remains219 failure families/2562 probes/341 native suites.

## Actual JAM caller coverage

The existing authorization-invocation, refinement-bootstrap and accumulation-machine
suites carry the missing-successor witnesses through real historical code lookup,
hashing, envelope preparation and mandatory entry selection. Authorization returns
`InitializationFailure` with `InvalidProgram`; refinement and accumulation return
their existing `InvalidProgram` alternatives. No failed result exposes an invocation
or CPU. Unreachable bad suffixes still refuse; present-trap successors prepare and
produce ordinary guest Panic when executed. Source code/bootstrap aliases survive
refusal unchanged. These are original fixtures with existing helper/link profiles.

All three caller suites pass in checked release with their existing1000-cycle ARC
checks: authorization975472, refinement25202592 and accumulation269248 bytes,
each unchanged before/after. The longer accumulation fixture uses its own64-byte
program budget so refusal is semantic rather than local limit exhaustion.
