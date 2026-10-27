# Experimental preparation admission

This is local engine policy, separate from JAM gas, source-attempt quotas and guest exits.
The production backend adapter remains separate work. It must supply genuine program/state
owners, select deployment limits, map local errors and bound concurrent plans/frames.

## Caller-selected limits

`FlatLimits` is copied into each immutable plan. Its nominal fields bound code bytes, decoded
facts, logical jump entries, retained memory pages and emitted execution nodes. Changing the
caller's original limits later does not change an admitted plan. Zero budgets are valid and
refuse the corresponding nonempty work. Values above the supported implementation ceilings return
`FlatError.InvalidPolicy` before plan allocation.

| Component | Compatibility default | Supported policy ceiling |
| --- | ---: | ---: |
| Code bytes | 4,194,304 | 4,194,304 |
| Decoded facts | 4,194,304 | 4,194,304 |
| Jump entries | 1,048,576 | 1,048,576 |
| Retained pages | 1,048,576 | 1,048,576 |
| Emitted nodes | 8,388,608 | 2,147,483,646 |
| Frame preparation source-span units | 67,108,864 | 18,446,744,073,709,551,615 |

These defaults preserve the old constructor's input range while adding a finite stream cap;
they are not proposed production deployment limits. Applications should choose explicit budgets.
The code/fact/jump ceilings retain the laboratory range; larger valid application profiles need
separate qualification rather than silently changing these limits.
Dense maps remain proportional to admitted code bytes. Facts and block-price entries are bounded
by the fact budget, jump metadata by the jump budget, private regions and immutable snapshots by
the page budget, and all three execution arrays by the node budget. A node has 16 argument bytes,
one handler pointer and a four-byte source site: 28 logical bytes on 64-bit hosts, before capacity
and allocator overhead. Each retained page has a 4,096-byte payload even when inaccessible.

These are component admission bounds, not a precise process-RSS quota. Sequence spare capacity,
transient growth, allocator overhead, shared source owners and other application subsystems are
outside that number. Environmental allocation failure is not converted into a recoverable policy
error by this change. There is no global bound on the number of live plans/frames in this local
module; the application adapter must provide it.

## Typed construction

Use `prepareFlatPlan(source, cycles, limits)` and `prepareFlatFrame(plan, images, info)`.
`FlatResult[T]` has private alternatives: refused results expose only `error`, while a successful
result transfers its admitted owner through `takeValue`. Taking a value resets the result to
`Uninitialized`; frame regions are moved rather than deep-copied. The plan accepts an already
decoded immutable program; the frame accepts the experiment's trusted CPU-state representation.
This admission API is not a replacement for the production machine/state boundary.

Code/fact/jump/page policy refusals have distinct `FlatError` values. Invalid memory shape is
separate from page exhaustion. No partial plan/frame is published. `replaceFlatMemoryChecked`
returns a `FlatError` and leaves the original frame intact on refusal. Old `newFlatPlan`,
`newFlatFrame` and `replaceFlatMemory` remain asserting conveniences for known-valid local
witnesses and benchmark fixtures; application admission must use the checked surface.

## Transactional execution-stream admission

Interior entries can prepare overlapping suffixes. A suffix's exact non-noop node count is
sealed during the existing reverse fact pass; one extra count occupies existing padding in the
48-byte fact on supported 64-bit targets. Its source-attempt count remains independent. The
admission cost is constant-time: compare header plus non-noop nodes with the remaining frame
node budget before the first stream append, allocation or PC-map write for that suffix.

Admitted offset links are never evicted or recycled during execution. Cached suffixes remain
usable at an exactly full cache. If a new suffix cannot fit, `preparationError(frame)` reports
`StreamLimitExceeded` and `runFlat` reports the existing local `InvalidPreparedProgram` reason.
It does not report a successful guest panic, out-of-gas or snapshot. Earlier attempted source
work in that invocation is not rolled back; no successful invocation result is claimed. Positive
execution requests remain refused on this frame, including after CPU/memory reset. Reconstruct
from a retained valid input if a different policy is needed. A zero-attempt request still returns
its ordinary source-quota refusal without executing or preparing instructions.

Each suffix admission is atomic, not the entire lazy preparation graph: a conditional may admit
one valid arm before its other arm refuses. Previously admitted entries stay internally valid;
the refused suffix itself writes no partial entries. A fixed node ceiling prevents unbounded
suffix duplication but is not an eviction/reuse policy, nor a guarantee that every valid program
fits every chosen budget.

## Preparation source-span allowance

The node ceiling alone cannot limit repeated preparation of heavily folded suffixes. Each cold
admission also reserves `suffix.sourceCount + containingBlock.sourceCount` from an independent
cumulative frame allowance, before map allocation, pricing or stream writes. The first term
covers the emission scan; the second covers the whole source span submitted to `blockGas`,
including for paid interior entries. These are source-span reservations, not actual decoder
visits, native instructions, guest gas or CPU cycles. The existing `GasCycleLimit` independently
bounds each pricing call. Plan decoding is separately bounded by code/fact/jump admission.

`flatPreparationUnits` reports the reserved total. Reuse of an admitted suffix reserves nothing.
Reset, checked memory replacement and both host reentry paths retain the total with their code
cache; replacement cannot replenish the allowance. A refusal reports `PreparationLimitExceeded`
through the same sticky local preparation channel and changes neither the stream nor its used
allowance. If both node and source-span ceilings would refuse, node admission is checked first.
As with the other policies, this budget is independent of successful guest execution semantics.

## Host refusal and retry

A host posterior's retained page count is checked without copying payloads, before extracting
changed pages or a complete image array. An oversized or invalid response returns the existing
local `InvalidHostResponse`; the stopped host invocation and immutable observation remain
usable for a corrected response. This differs deliberately from a sticky execution-cache
failure. Checked complete memory replacement validates admission before moving any old cache
or state into the replacement.

## Local evidence

`checks/resource-boundary.nim` exercises construction reasons, consuming results, copied policies,
folded noops versus exact emitted nodes, independent preparation-span exhaustion, both real host
reentry paths, full-cache reuse, overlapping suffix refusal, sticky
execution failure, zero attempts, control-transfer exhaustion, invalid pages, transactional
replacement and repaired host response. `checks/entry-boundary.nim` also compares private memory
against the independently executed prefix on source-quota refusal. The performance and complete
state comparison is recorded in [the final paired report](findings/resource-bounds.md).
