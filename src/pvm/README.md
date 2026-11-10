# Polkadot virtual machine

[Source guide](../README.md) · [PVM design](../../docs/design/pvm.md)

This folder implements the PVM from the [pinned Gray Paper](../../spec/pins.json)
and provides bounded execution primitives.
Protocol invocation contexts and state publication are composed by [state modules](../state/README.md).

| Modules | Contents |
| --- | --- |
| [`program.nim`](program.nim) | Validated program blobs, operand decoding and immutable program storage |
| [`machine.nim`](machine.nim) | Immutable CPU snapshots, sparse memory and checked host memory access |
| [`registers.nim`](registers.nim), [`gas/gas.nim`](gas/gas.nim) | Register mutations and whole-block gas accounting |
| [`gas/plan.nim`](gas/plan.nim), [`gas/memo.nim`](gas/memo.nim) | Optional immutable gas plans and bounded reusable price memos |
| [`step.nim`](step.nim) | Charged single steps, bounded execution and trusted host replies at the causing instruction |
| [`internal/native_pipeline.nim`](internal/native_pipeline.nim) | Shared ARM64 and x86-64 compiler scheduling, image credits and invocation leases |
| [`initialize.nim`](initialize.nim), [`output.nim`](output.nim) | Standard invocation initialization and bounded halted-machine output capture |
| [`host/fetch.nim`](host/fetch.nim), [`host/gas.nim`](host/gas.nim), [`host/heap.nim`](host/heap.nim), [`host/log.nim`](host/log.nim) | Captured fetch inputs, gas responses, shared heap growth and [JIP-1 diagnostics](../../spec/pvm-host-log.md) |
| [`inner_machines.nim`](inner_machines.nim), [`refinement_exports.nim`](refinement_exports.nim) | Invocation-local inner-machine lifecycle and refinement export segments |

Programs, machines and published memory revisions use immutable acyclic ARC ownership. Execution
budgets are explicit; host suspension and terminal results do not authorize arbitrary state
publication. State-owned admission and composition retain their own provenance checks.

The [program](../../spec/pvm-program.md), [machine](../../spec/pvm-machine.md),
[execution](../../spec/pvm-execution.md), [initialization](../../spec/pvm-initialization.md) and
[state-successor](../../spec/pvm-state-successor.md) records track specification decisions,
verification and remaining gates. The [host response](../../spec/pvm-host-response.md),
[gas plan](../../spec/pvm-gas-plans.md) and [async JIT](../../spec/pvm-shared-async.md) records
link back to their source contracts and retain qualification evidence.
