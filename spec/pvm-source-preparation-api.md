# Source-only preparation interface prerequisite

This independent prerequisite fixes the cross-agent contract before its implementation. It does
not implement eager compilation or enable a public compiled policy. Ordinary JIT/interpreter
selection, execution, pricing, memory, native generators and existing owner layouts are unchanged.
The existing pinned Gray Paper/program/gas/handler-stream contracts remain authoritative; no
protocol semantics, compiler/dependency pins or executable limits change.

## Stable shared surface

`prepareFlatStream(plan: FlatPlan): FlatResult[FlatStream]` accepts only an already admitted
immutable source plan. It accepts no Machine, registers, memory, callback, invocation gas/budget,
external prices or duplicate resource limits. A future successful implementation must publish a
complete exclusive source-bound stream through the existing success-guarded `takeValue` boundary.
No failed/default result carries a usable owner. This prerequisite provides no successful path.

The stub always returns `FlatError.NativeNotBuilt`: the **source-preparation facility** is not
built, including when ordinary lazy JIT support exists and works. This reason does not disable or
describe ordinary JIT availability. It performs no guest work, callback, allocation, executable
admission or partial preparation. Existing plan ownership remains available to ordinary execution.
Consumers must preserve the typed refusal; they must not invent successful compiled preparation
or silently label an ordinary lazy/interpreted owner as compiled.

Three names append to `FlatError`, preserving all previous ordinals and representation size:

| Reason | Source-preparation meaning |
| --- | --- |
| NativeNotBuilt | The source-preparation facility is absent; the current stub always returns this. |
| NativePlatformUnsupported | Reserved for a built facility on an unsupported native platform. |
| NativeStorageUnavailable | Reserved for failure to admit a real native executable owner. |

`FlatSealedInfo` is a copied plain value: `sealed: bool` and `candidates`, `nativeEntries`,
`checkedEntries`, `capacityDeferred: uint64`. Under `pvmSourceSealingReceipt` only, it additionally
contains `compilationPasses: uint64`. It contains no owner, storage, pointer or invocation state.
`streamSealedInfo(stream: FlatStream): FlatSealedInfo` returns zero/unsealed for every existing
ordinary lazy stream. This is explicitly an unprepared observation, not successful preparation
diagnostics or an ordinary-native-availability probe. Mutating the returned copy cannot change
the stream. The existing seven native-statistic counters and their conditional exports are untouched.

## Separation and verification

Only append-only error names, the copied observation type and the two new unused routines enter
the shared module. No existing routine body or Frame/Stream/Jit storage declaration changes; no
ordinary execution call site invokes the new stub or observation. No runtime guard, field,
metadata owner, compiler/classifier, cached price, destructor, benchmark or profiling harness is
part of this PR. Consequently there is no new default hot-path work to justify with a performance
cohort. Implementation and performance qualification remain separate work and separate PRs.

The focused native suite `pvm_source_preparation_api` checks previous error ordinals/representation
size, default-result refusal, real admitted native-enabled/forced-interpreted plans, repeated
explicit unavailability, unchanged ordinary execution/stream leasing and copied zero/unsealed
observations. Receipt-enabled and ARM/x86 source checks cover the conditional surface. Local
verification is semantic/format/inventory only; linked native execution belongs in CI.
