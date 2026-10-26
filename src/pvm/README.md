# Polkadot virtual machine

[Source guide](../README.md) · [PVM design](../../docs/design/pvm.md)

This folder implements the reusable GP 0.8.0 machine and bounded execution primitives.
Protocol invocation contexts and state publication are composed by [state modules](../state/README.md).

| Modules | Contents |
| --- | --- |
| [`program.nim`](program.nim) | Validated program blobs, operand decoding and immutable program storage |
| [`machine.nim`](machine.nim) | Immutable CPU snapshots, sparse memory and checked host memory access |
| [`registers.nim`](registers.nim), [`gas.nim`](gas.nim) | Register mutations and whole-block gas accounting |
| [`step.nim`](step.nim) | Charged single steps, bounded execution and explicit trusted host responses |
| [`initialize.nim`](initialize.nim), [`output.nim`](output.nim) | Standard invocation initialization and bounded halted-machine output capture |
| `host_fetch`, `host_gas`, `host_heap`, [`host_log`](host_log.nim) | Captured fetch inputs, gas responses, shared heap growth and [JIP-1 diagnostics](../../spec/pvm-host-log.md) |
| [`inner_machines.nim`](inner_machines.nim), [`refinement_exports.nim`](refinement_exports.nim) | Invocation-local inner-machine lifecycle and refinement export segments |

Programs, machines and published memory revisions use immutable acyclic ARC ownership. Execution
budgets are explicit; host suspension and terminal results do not authorize arbitrary state
publication. State-owned admission and composition retain their own provenance checks.

The [program](../../spec/pvm-program.md), [machine](../../spec/pvm-machine.md),
[execution](../../spec/pvm-execution.md), [initialization](../../spec/pvm-initialization.md) and
[state-successor](../../spec/pvm-state-successor.md) contracts record exact semantics, verification
and remaining gates. These components alone do not constitute complete JAM block execution.
