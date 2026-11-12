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

Prepared execution admits the full source and resource limits up front, then fills
block metadata on resolution. Its exclusive stream cache owns that derived metadata;
the immutable program and admission identity remain shareable. Source-global instruction
ordinals preserve native adjacent-block proofs regardless of visitation order. Fact and
PC-map payloads allocate in bounded chunks as code is resolved; the logical resource
extents remain those admitted for the whole source.
See the [checked stream owner](../../src/pvm/internal/handler_stream.nim).

The [Services owner](../../src/app/services.nim) inventories production runtime consumers and
the ownership, aggregate retention and competition contract required before wider integration.
The [scheduler](../../src/pvm/internal/native_pipeline.nim) documents current image capacity
and selection limits. The [migration record](../../spec/pvm-async-migration.md#selection-and-resource-work)
tracks the remaining integration boundary.

## Accumulation successor boundary

Execution owns stopped continuation and the immutable finalized successor. State
consumes that exact owner and performs history, statistics, authorization and consensus
composition before exact-parent publication. A detached map does not confer execution
authority. [Shared boundary](../../spec/pvm-state-successor.md)
