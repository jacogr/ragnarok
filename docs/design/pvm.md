# Polkadot virtual machine

[Design overview](../design.md) · [PVM source map](../../src/pvm/README.md)

[Program capture](../../src/pvm/program.nim) owns immutable code and structural facts.
[Machine snapshots](../../src/pvm/machine.nim) own CPU metadata and sparse memory.
[Execution](../../src/pvm/step.nim) combines those owners with invocation-local
staging, budgets and host callbacks. Reusable facts and exclusive native cache
ownership cross through prepared program and engine boundaries.
[Interpreter qualification](../../spec/pvm-interpreter-readiness.md)

## Native failure and proof boundaries

Production native execution belongs to `NativeSession`, which admits copied source certificates,
keeps executable images under an exclusive owner and validates returned receipts before using them.
Cold emitters return refusal for malformed operands, incomplete certificates and invalid relocations;
a failed child cannot contribute a partial prefix to a publishable enclosing image. Checked execution
retains authority when an optional native image is refused; native refusal does not invent a guest
gas debit or a successful execution result.

The old `ArmJit` and `X86Jit` caches and direct invocation APIs remain only for independent historical
emitter, arena, ABI and refusal proofs. Their assertion-based contracts require the test-only
`pvmLegacyNativeWitness` profile. Selecting either ISA alone does not declare those owner types or
constructors. Ordinary read qualification checks that the constructors remain unavailable; direct
proof suites explicitly declare their separate profile. Keep production admission and execution on
the fallible `NativeSession` path instead of reviving these legacy caches.

## Reusable execution policy

[Gas planning](../../src/pvm/gas/plan.nim), [checked dispatch](../../src/pvm/internal/handler_stream.nim)
and [native admission](../../src/pvm/internal/native_pipeline.nim) own their respective
pricing, invocation and reuse contracts. The [engine record](../../spec/pvm-engines.md)
keeps the scope and qualification of the available engine identities.

Prepared execution admits the full source and resource limits up front, then fills
block metadata on resolution. Its exclusive stream cache owns that derived metadata;
the immutable program and admission identity remain shareable. Source-global instruction
ordinals preserve native adjacent-block proofs regardless of visitation order. Fact and
PC-map payloads use direct storage for small extents and bounded chunks for larger code; the logical resource
extents remain those admitted for the whole source.
See the [checked stream owner](../../src/pvm/internal/handler_stream.nim).

Fusion reconstructs a bounded original block from immutable source and admission ranks before
binding it to executable offsets. The [source IR](../../src/pvm/internal/handler_fusion_source.nim)
contains logical edges and copied operands; it needs no checked catalogue, worker, CPU or memory.
The [overlay adapter](../../src/pvm/internal/handler_fusion.nim) independently proves the current
layout, price, operands and worker ownership. A refused binding stays checked; asynchronous
lowering receives only the complete copied, physically linked request. The
[native graph contract](../../src/pvm/internal/native_fusion.nim) owns bounded scalar SCC eligibility
and count receipts. Both lowerers preserve ordinary internal continuations and add bounded compact
external entries. A compact side exit returns before entering another receipt mode.

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
