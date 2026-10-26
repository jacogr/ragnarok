# Polkadot virtual machine

[Design overview](../design.md). Detailed feature contracts live in `spec/`; routine increments
update their feature contract rather than appending progress here.

`src/pvm/program.nim` now validates GP 0.8.0 program blobs and decodes all operand
formats into copied values backed by an immutable program owner. See
[the program decoding contract](../../spec/pvm-program.md). This is the first PVM
increment. `src/pvm/machine.nim` adds immutable CPU snapshots and sparse paged memory
with atomic scalar stores; see [the machine/memory contract](../../spec/pvm-machine.md),
including the approved PolkaVM memory exception ordering. `src/pvm/registers.nim`
evaluates all 85 register-only instruction mutations against a copied register file;
see [the register semantics contract](../../spec/pvm-registers.md). The internal
`src/pvm/internal/register_ops.nim` module shares typed arithmetic between that
guarded public evaluator and private charged dispatch, with copied scalar outputs
and no retained execution state. `src/pvm/gas.nim`
calculates whole-block pipeline costs with bounded storage and a local cycle limit;
[the gas contract](../../spec/pvm-gas.md) records independent witnesses and approved
PolkaVM wrapped branch-target pricing. `src/pvm/step.nim` now charges whole blocks and
executes register, control-flow and scalar memory steps into immutable machine snapshots, preserving
the full state on out-of-gas and the specified single-step terminal PCs; see
[the stepping contract](../../spec/pvm-step.md). Memory faults retain the paid block charge
and permit repair/retry without double charging. Complete single-step capability now
includes host suspension, and bounded iterative execution applies recursive exit rules;
see [the execution contract](../../spec/pvm-execution.md). Standard initialization and
host dispatch now have separate [initialization](../../spec/pvm-initialization.md)
and [host execution](../../spec/pvm-host-execution.md) contracts. The
[readiness map](../../spec/pvm-interpreter-readiness.md) records current interpreter
comparisons and remaining JAM/specification gates.

## Reusable execution policy

An optional immutable `GasPlan` retains one captured program and a complete bounded table of
existing block prices. Preparation has explicit payload, block-count and per-block cycle limits;
execution keeps CPU, memory staging, attempt budgets and callbacks local to each invocation.
A bounded [lazy memo](../../spec/pvm-gas-memos.md) instead learns successful prices on demand
under one fixed source/policy, with exclusive worker use and private monotone facts. The dynamic-pricing API remains available. See [the ownership, refusal and measurement contract](../../spec/pvm-gas-plans.md).

An optional [prepared execution owner](../../spec/pvm-prepared-blocks.md) retains a bounded,
lazily populated representation of visited instructions: selected handlers, decoded operands,
static targets and whole-block prices. Segments bound preparation storage without introducing
guest block boundaries. The owner shares immutable program facts across fresh executions; CPU,
memory staging, paid gas and host callbacks remain invocation-local. This tier reuses private
semantic helpers in `step.nim` and leaves the existing interpreter as the default.

## Accumulation successor boundary

Execution owns stopped continuation/reentry selection and the immutable
`PreparedFinalAccumulation` successor, including selected effects, output/gas
history, complete state and authenticated original block provenance. State's
`prepareAccumulationComposition` consumes that owner and state-only policies;
state owns history/statistics/authorization/consensus composition and exact-parent
final publication. Neither side accepts a detached map as a replacement execution
certificate. See [the shared boundary contract](../../spec/pvm-state-successor.md).

## Runtime engine selection

The application selects `ragnarok`, `polkavm-interpreted` or `polkavm-native` explicitly,
with Ragnarök as the default. Invocation-local policies carry this selection through initial
and later accumulation, authorization, refinement and nested machines; no global mutable
selector or upstream environment default participates. `step.nim` retains the checked host
continuation and guest/local error contracts, with optional implementation in
`internal/backend_execution.nim`. Completed observations report the actual engine.

An optional maintained `native/polkavm` C ABI owns opaque Rust instances using the pinned
public upstream API. Nim retains unsigned protocol gas, instruction/host budgets, host
dispatch and state/effects publication. Instruction tracing provides exact attempt boundaries;
this correctness profile is not a throughput qualification. One instance stays resident across
host callbacks. Only pages addressed by guest stores are read for publication, changed pages
are captured together into immutable memory, and only changed host pages are synchronized.
See [the runtime contract](../../spec/pvm-runtime-backends.md) for capabilities and refusals.
