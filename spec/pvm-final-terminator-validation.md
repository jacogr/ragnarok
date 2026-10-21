# Final terminator validation: pending behavior selection

This isolates GP-PVM-004 in the [discrepancy register](graypaper-discrepancies.md).
Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` admits final
fallthrough/conditional opcodes as members of T, then performs destination checks
at execution. Pinned PolkaVM `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`
public interpreter module loading rejects these programs before any instruction.
No production behavior, program acceptance rule or JAM preparation policy changes.

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

## Reproduction and pending scope

```sh
make unit SUITE=pvm_final_terminator_validation
rustup run 1.99.0 cargo run --release --locked --offline --manifest-path tests/reference/polkavm_memory/Cargo.toml --target-dir build/polkavm-memory-reference-target --bin validation
rustup run 1.99.0 cargo fmt --manifest-path tests/reference/polkavm_memory/Cargo.toml -- --check
```

Before changing code, select whether to retain the paper's runtime semantics or
adopt a scoped load-time rejection. The latter requires choosing the owning layer:
raw program decoding, JAM guest preparation, or an explicit fixture-loader adapter.
It also needs a decision about representing rejection as a local preparation
failure versus a guest panic. A broad loader change can prevent otherwise successful
prefix work from running and invalidate previously supported raw programs.
Do not silently infer this policy from the earlier memory/gas exceptions.

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
PolkaVM. The precise witness and failure-stage choice remain open; no new behavior
or pin adoption follows from this research alone.

## Observed local evidence

All three native witnesses pass, including the conditional whose taken target is
valid entry0 and whose missing fallthrough alone causes panic. The public checker
confirms exact validation failures at4/6 and the executing trap control. Pinned
formatting passes2585 Nim sources plus both Rust format checks; upstream-lock and
local documentation-link checks pass. Inventory passes219 failure families/2562
probes/341 native suites. Evidence is local checked-release macOS/ARC/Clang LTO
and pinned Rust release; no remote CI or full upstream Rust suite is claimed.
Logs remain under `build/pvm-final-terminator-*`. Loading/execution policy remains
pending maintainer feedback; these fixtures do not change the production decision.
