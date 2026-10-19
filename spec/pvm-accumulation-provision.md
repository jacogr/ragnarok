# Accumulation provision host dispatch

## Scope and authority

Connect `provide` (27), `Omega_Aries`, to the retained accumulation effects in Gray Paper
0.8.0, revision `07f041dabd073f9018b418e9ee72e79dd2185401`, `pvm_invocations.tex`
(SHA-256 `67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb`).
The memory-sized gas equation and `definitions.tex` fix cost at
`3980 + ceil(2264 * r9 / 1024)`. No source, vector or toolchain pins change.

The effects dispatcher must charge first, check the uint32 blob-length domain before memory,
read the full natural interval `(r8,r9)`, resolve r7's uint64-max self sentinel without truncating
other service IDs, and call the existing requested-provision operation. WHO denotes unknown targets;
HUH denotes invalid length, absent/nonempty requests or duplicate target/raw-byte pairs; OK denotes
retained regular effects. Inaccessible memory panics without changing r7 or either dimension.
Local copy/retention budgets, malformed state and backend failures remain typed local refusals.
Checkpoint/yield retain existing semantics; no preimage fulfillment or state publication occurs.

Full-width requested lengths can imply a cost larger than uint64. The merged dispatcher computes the full cost with bounded base-2^32 limbs and subtracts
available gas exactly, preserving representable deficits even in that case.
The existing machine represents terminal deficits only through `2^63`; an actual larger deficit
must remain an explicit `GasRangeExceeded` local gate, not wrap, clamp or invent a guest outcome.
This is an implementation boundary inherited from the signed terminal gas contract, not a new
protocol interpretation. Valid uint32 blob lengths always have representable host costs.

## Completion tests

Use actual prepared guest programs to exercise self/other/high/unknown targets, zero and nonzero
blobs, duplicate and distinct-target provisions, request-history alternatives, memory/length/gas
priority, exact charges and deficits, large register values, policy and backend refusals, checkpoint
separation and yield preservation. Compare every retained byte and the unchanged complete map.
Protect failed-result extraction and run 1,000 ARC success/late-refusal cycles. The existing
independent state-effect, codec and crypto tests retain their contracts; authored host witnesses
are not full accumulation STF evidence.


## Implemented boundary

`executeAccumulationMachine` accepts an optional trailing `AccumulationProvisionLimits`.
The default allows no retained items; callers accepting provisions supply finite item, per-blob
and total-byte budgets explicitly. The dispatcher requires the invoking machine’s own context
configuration and recognizes provide even at zero capacity; protocol refusals may still complete
without requiring another retained record. Guest-copy work is bounded by the smaller of the
existing copy ceiling and provision per-blob ceiling. The state-effect operation independently
checks current/new membership and aggregate bytes, reusing the existing canonical request query.

`BackendFailure`, `MalformedState` and `GasRangeExceeded` remain distinct dispatcher refusals;
none exposes CPU progress or effects. The full-width gas algorithm splits the cost into bounded limbs before multiplication, then
subtracts credit with an explicit borrow. It checks the resulting debt against the signed terminal
domain before exposing an out-of-gas response.
The exact signed negative endpoint is accepted. A mathematical charge above uint64 still produces
an exact guest out-of-gas result when its difference from available credit fits the machine domain.
No modulo charge, saturation or alternate representation is accepted.

All existing yield/checkpoint/source ownership contracts remain in force. Provide returns only a
new regular set, preserves the exceptional checkpoint and current yield, and leaves guest memory,
account records and outstanding request histories unchanged. Fulfillment and later publication
require a separate accumulation stage.


## Local verification

Passed the new `pvm_accumulation_provision` and existing `pvm_accumulation_dispatch` suites through
`make unit SUITE=...` on the updated runner. Both 1,000-cycle ARC workloads retained exactly the
same occupied bytes before and after: 770,160 and 431,296 respectively. Host witnesses include
all copied bytes at 0/1/3/1023/1024/1025-byte rounding boundaries, the exact signed negative endpoint
and one beyond it, and a representable deficit from a charge larger than uint64.

Ten affected runtime guards and two existing privacy probes passed. The first new runtime fixture
asserted its exact error immediately before invalid extraction, allowing the compiler to prove the
misuse statically; removing those redundant assertions restored the intended strict runtime probe.
Native unit tests independently require each exact refusal reason. The earlier six passing
unchanged dispatcher guards were retained rather than rerun. Logs preserve the failed fixture
build and corrected verdicts under `build/accumulation-provision-dispatch/{guards,guards-final}.log`.

`make check-python` passed 423 tests with five skips. Pinned formatting, inventory/provenance and
diff checks passed. These are local macOS results; exact-head Linux CI remains separate. No full
accumulation STF, post-accumulation provision integration or persistent publication is claimed.

## PVM merge reconciliation

Execution now uses the merged PVM dispatch API and its maintained full-width gas calculation.
The independent state-side witnesses remain. This layer bounds the guest copy by both the copy
ceiling and per-blob retention ceiling, and preserves malformed account/history as an explicit
local `MalformedState` refusal. It adds no second dispatch path or terminal normalization.
