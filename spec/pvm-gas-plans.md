# Bounded reusable block gas plans

`src/pvm/gas/plan.nim` offers optional immutable whole-program prices for repeated execution of
one captured `Program`. This is an implementation policy over the existing Gray Paper pipeline
model and approved wrapped branch-target interpretation; it changes neither guest gas nor program
admission, instruction semantics, exception precedence, serialization or dependency pins. The
existing `GasCycleLimit` execution APIs retain dynamic pricing and their invocation-local cache.

## Preparation and ownership

The [plan constructor and lookup](../src/pvm/gas/plan.nim) own the complete-pricing
contract, payload and work limits, exact source identity and block-start validation.
The plan is an optional local pricing policy over the existing guest gas model.

## Execution boundary

Overloads of all four single-step APIs, `execute` and both `executeWithHost` callback forms take
a `GasPlan` in place of a cycle limit. They verify owner identity and run the same capability,
affordability, evaluation, fault, response and publication paths. Direct table lookup replaces
pipeline simulation; an interior PC still resolves its containing block. A mismatch returns
`InvalidGasPlan` without publishing progress. A matching paid fault retry retains its original
charge. Attempt/host budgets, CPU values, staged memory and decoder caches remain invocation-local.

Host execution retains the supplied plan value across synchronous callbacks. A caller supplying
its plan from mutable callback context must first copy the handle into a local and then borrow
the context exclusively; passing `context.plan` alongside `var context` is rejected by Nimony's
alias checker. Callbacks may replace their original context handle and nested invocations may
reuse a plan without changing the outer policy. No callback or context is retained in a plan.

## Verification and observed scope

The native suite compares all1,796 independent gas-domain rows at zero, just-insufficient and
exact fuel through every single-step API and recursive execution. It checks complete CPU/outcome
state, source immutability, strict owner identity, byte/block/cycle refusals, interior/high PCs,
both callback forms, nested/context replacement, dispatch budgets, zero-ordinal host refusal and
paid memory-fault repair. Private-field compiler rejections and runtime guarded-result failures
include successful controls. One thousand parent/alias/child/partial-failure ARC lifetimes retain
unchanged occupied memory. AddressSanitizer and affected ordinary/host/retry consumers supplement
these focused checks; local evidence does not substitute for exact-head Linux CI.

The maintained synthetic and frozen real-sieve comparisons measure dynamic and planned modes
separately against pinned PolkaVM `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` interpreted
JamV1 Sync/Full/L2Hit. Planned mode must report validated preparation time and resource identity
in addition to all execution samples and complete result validation. The frozen sieve artifact,
expected state and11 synthetic fixtures are unchanged. Compiled comparison remains deferred.

Initial checked ARC/Clang ThinLTO measurements on the recorded M1 Max host reduced the100,000-limit
sieve execution from18.064 to13.354 ms, versus5.939 ms for PolkaVM. Additional preparation was9.964 ms
for3,843 blocks and1,257,216 payload bytes: roughly2.11 repeated executions amortized that cost.
The1,000-limit case required roughly25 repetitions. These are workload-specific execution and
cold-cost observations, not whole-JAM throughput. Callback-heavy synthetic guests were about18%
slower in planned mode; it is optional and does not replace the default dynamic policy. An
additional hot cache did not recover that cost and regressed arithmetic, so it was rejected.
Final confirmation measured17.956/13.273/5.896 ms (dynamic/planned/reference), with9.867 ms
preparation and the same2.11-run amortization at100,000. All930 Python tooling checks pass
(three documented skips). Raw distributions, reversed process order, source hashes, toolchain and hardware metadata remain
in the benchmark reports; no noisy observations are discarded.

Next work is reducing execution overhead and measuring more representative repeated guests.
Fuzzing remains deferred until maintainer Daybreak access. M1 framing completion remains scoped;
complete state serialization and whole-block/JAM equivalence are still open.

Synchronous price-owner borrowing and its isolated lookup benchmark are recorded in
[pricing owner borrows](pvm-pricing-owner-borrows.md).
