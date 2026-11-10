# Polkadot virtual machine

[Design overview](../design.md) · [PVM source map](../../src/pvm/README.md)

[Program capture](../../src/pvm/program.nim) owns immutable code and structural facts.
[Machine snapshots](../../src/pvm/machine.nim) own CPU metadata and sparse memory.
[Execution](../../src/pvm/step.nim) combines those owners with invocation-local
staging, budgets and host callbacks. Reusable facts and exclusive native cache
ownership cross through prepared program and engine boundaries.
[Interpreter qualification](../../spec/pvm-interpreter-readiness.md)

## Reusable execution policy

[Gas planning](../../src/pvm/gas/plan.nim), [checked dispatch](../../src/pvm/internal/handler_stream.nim)
and [native admission](../../src/pvm/internal/native_pipeline.nim) own their respective
pricing, invocation and reuse contracts. The [engine record](../../spec/pvm-engines.md)
keeps the scope and qualification of the available engine identities.

## Accumulation successor boundary

Execution owns stopped continuation and the immutable finalized successor. State
consumes that exact owner and performs history, statistics, authorization and consensus
composition before exact-parent publication. A detached map does not confer execution
authority. [Shared boundary](../../spec/pvm-state-successor.md)
