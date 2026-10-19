# Continuation range inputs and posterior-state binding

## Scope and authority

Prepare the range selected by `PreparedAccumulationContinuation` as report-only service inputs,
retaining the original admitted queue and applying its completed initial batch on a private
complete-map fork. Authority remains GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f` (`accseq`, `accone`,
`accpar`, `fnprovide`). Pins, domain bytes and the parked namespace question do not change.

Extend operand preparation with a nominal original-queue start and selected count. Prove start and
count using subtraction before narrowing/addition, retain both range coordinates and the original
queue, and materialize only selected reports. The existing prefix API remains the start-zero path.
No reconstructed queue, replay of completed reports, recurring free allowances or implicit transfer
inputs are permitted. Reuse canonical C.2 and prepared-input codecs and their independent budgets.

After input preflight, derive the exact original admitted parent and candidate slot through the
retained completed source. Apply its actual complete batch privately under inherited store limits.
Return the resulting immutable full-map snapshot together with inputs and source plan only after
complete success. Preserve all nested batch refusal reasons without exposing an earlier input
owner or candidate state. Caller stores and original snapshots remain unchanged.

This prepares a report-only continuation context; later invocation entropy binding, execution,
recursive completion and final publication remain subsequent work. PVM mutations remain protected
by the existing selected-account gate, and outgoing transfers by the continuation planner's gate.
M1 framing remains complete; full serialization and accumulation/block parity remain open.

## Completion tests

Verify selected C.2 fields/order, explicit nonzero starts, full-width range bounds, no completed
prefix payloads, no carried allowances, and exact/short materialization limits. Use signed completed
sources with real provision effects to compare literal posterior histories/blobs and full-map roots.
Check no-op/empty cases, exact input/state source binding for service preparation, authenticated
slot, defaults, detached lifetimes, late batch backend refusal, unchanged caller state and 1,000 ARC
cycles. Run the new suite, owning operand suite, strict extraction/privacy/nominal probes, Python
provenance/reference tests, inventory and pinned formatting.

## API and ownership

`prepareAccumulationOperandRange` takes nominal original-queue start/count coordinates and retains
both with the original queue certificate. It checks `start <= count` before comparing the selected
count against `count - start`, then narrows and traverses only the proven range. The existing
`prepareAccumulationOperands` remains a start-zero wrapper. `operandReportStart` exposes the
retained origin through the same guarded result contract as the existing operand observations.

`prepareAccumulationContinuationInputs` accepts only the genuine continuation plan and independent
materialization limits. Its source supplies the original queue, completed batch, admitted parent
and authenticated slot. It preflights report-only operands and service groups before applying the
actual completed batch on a private fork with inherited store limits. Success retains an acyclic
immutable owner of the source plan, inputs and complete posterior map. Refusals release candidates
and retain only the selected nested reason; a batch refusal preserves the actual failed parent
result with its terminal/provision/store contracts.

`continuationInputs`, `continuationState` and `continuationPlan` retain their respective immutable
owners. `prepareContinuationAccumulationService` resolves from those exact retained inputs and
posterior state at the authenticated slot, preserving the actual service-resolution reason through
`serviceError`. It does not accept a replacement map or source inputs. It returns the existing
prepared service projection; later invocation/entropy certification is deliberately still pending.

## Local verification

Passed `make unit SUITE=accumulation_continuation_inputs` using signed parent-ready reports and
actual terminal executions. A completed one-report prefix leaves reports 65/66 selected from the
original queue, producing exactly two C.2 operands for service 42 and 11 gas, with no repeated
allowance-only service 99 or incoming transfers. Full-width and exact-end range checks, default
owners, independent short operand/input budgets, initialized empty sources and retained lifetimes
are covered. Input preflight and no-op application also succeed with backend hashing disabled.

Real terminal provisions fulfill service 42/99 requests at authenticated slot 2. The private
successor matches a separately authored full-map root with literal fulfillment histories and
preimage rows. Service preparation binds to that successor and rejects source matching against
the original map. Injected late backend refusal exposes the actual nested provision error while
the original request history and caller snapshot remain unchanged. The maintained 1,000-cycle
success/refusal ARC workload retained 524,368 occupied bytes before and after. The owning operand
regression also passed, retaining 22,256 bytes across 1,000 cycles.

Ten checked runtime extraction probes and five strict privacy/nominal compiler rejections passed.
Python discovery passed 441 tests with six skips; inventory reports 102 failure families, 1,548
data-driven probes and 146 native suites. The signed suite reuses the checksum-verified static
report fixture; it adds no generated-corpus dependency or runner behavior change. Pinned formatting
and diff checks accompany the change. Diagnostic iterations reused prepared native libraries;
full logs remain under `build/accumulation-continuation-inputs/`.

These are local macOS checks, separate from exact-head Linux CI. Next work binds later invocation
entropy and execution to this prepared context, then handles recursive completion, outgoing
transfers, final output union and block publication. Existing PVM host implementations and the
selected-account compatibility gate remain unchanged. M1 framing is complete; full serialization
and accumulation/block parity remain open.
