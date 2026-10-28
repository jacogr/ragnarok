# Initial accumulation round

## Scope and authority

`src/state/accumulation_round.nim` implements initial prefix planning from GP 0.8.0
`accumulation.tex`, equations `accseq` and `finalstateaccumulation`, at Gray Paper revision
`07f041dabd073f9018b418e9ee72e79dd2185401` (source SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`). It joins the
[priority queue](accumulation-queue.md), [operand preparation](accumulation-operands.md) and
[invocation inputs](accumulation-inputs.md). It neither invokes a PVM nor publishes state.

Given configured report gas `R`, block gas `B`, core count `C`, parent allowances `f` and the
priority reports `r`, the initial budget is `max(B, R*C + sum(f.values))`. Initial transfers
are empty. The planner reserves all allowances and selects the largest whole-report prefix
whose declared digest accumulation gas fits the remainder. A later inexpensive report cannot
bypass an earlier unaffordable report. Zero-cost reports still belong to the maximal prefix.
Only selected reports become operands, and the original report/digest order is retained per service.

Dispatch follows `n > 0`, where initially `n = prefix length + allowance dictionary length`.
A zero-valued allowance still introduces an invocation; an entirely empty round does not dispatch.
The returned service inputs contain no transfers and include each applicable free allowance once.

## Configuration and provenance

`AccumulationRoundConfig` supplies explicit nominal gas parameters and finite decoding, traversal,
operand and input ceilings. Chain constants are caller configuration: this API does not authenticate
`R` or `B` against a network profile. The ordinary GP parameters are `R = 10,000,000` and
`B = 3,500,000,000`; tests also use explicit authored policies to exercise tight boundaries.
Core counts must agree with the decoded privilege snapshot, and the block adapter additionally
requires agreement with the genuine admitted block's frame profile.

`planInitialAccumulation` accepts a validated pure queue and C(12) snapshot. Its result is a pure
projection, not a block certificate. `planBlockInitialAccumulation` accepts only a genuine
`BlockAccumulationQueue`, follows its admission back to the exact admitted **parent** map and
loads C(12) there. Missing, malformed, suffixed or over-budget values fail; no empty default,
posterior-state substitution or alternate representation is accepted. The complete chapter extent
is checked before copying bytes. Bound results retain the original queue and parent-derived plan.

Immutable acyclic storage retains the privilege roles/assigners as well as its allowances, complete
prepared inputs and exact report-prefix provenance. Extraction returns retained handles or copied
metadata. Caller-array mutation and release of parent handles cannot change a prepared round.
Default/refused results carry only a reason; their tags and success storage are private.

## Arithmetic and local bounds

GP gas is a natural below `2^64`. Allowance addition and `R*C + sum(f.values)` are proved before
performing Nimony's wrapping arithmetic. Unrepresentable initial contexts return `GasOverflow`;
there is no saturation. `2^64 - 1` is valid. The report scan compares individual digest costs with
remaining gas before subtraction, so a mathematical report sum above the gas domain simply makes
that report unaffordable. It does not wrap, partially charge the report or cause a false overflow
refusal of an otherwise representable plan.

The configured report ceiling bounds the entire priority sequence before scanning. The operand
ceiling also bounds inspected digest work, including a blocking digest in a rejected report.
Uninspected later reports need no digest traversal. Allowance count and native typed-storage bounds
precede collection; existing operand/input preflights independently enforce bytes, rows and service
union limits before publishing anything. Resource refusal never returns a smaller successful prefix.
A gas-budget stop is ordinary successful selection; a local resource stop is a typed failure.

## Verification

`tests/unit/state/test_state_accumulation_round.nim` checks 670 independently derived contexts: five gas
policies over six unchanged published tiny/full queue scenarios and 128 authored report queues.
The davxy pin remains `d3c089c9a1d5352ad353626d7a2db8589f137b2a`; existing blob hashes are verified.
The gas policies and allowances are authored test inputs, not published STF execution outputs.
The Python oracle enumerates every prefix with arbitrary-precision sums; native code scans using
bounded subtraction. Tests compare budget, allowances, selected prefix, declared report reservation,
dispatch, service membership/gas and every complete C.2 operand byte. All seven work-result tags
appear. There are 134 unrepresentable initial budgets.

Literal tests cover exact fit, strict priority, zero costs/allowances, maximum gas, overflowing
allowance sums and multiply-add, partial-report refusal, invalid/default/profile inputs and resource
ceilings. Genuinely signed blocks bind parent C(12), with missing/truncated/suffixed chapters signed
into their real parent roots. Inputs remain usable after source handles leave scope; 1,000 complete
success/late-refusal cycles require unchanged live ARC occupancy. Strict runtime extraction probes
and compiler privacy/nominal-gas probes preserve failure/ownership boundaries. Independent Python
witnesses anchor the oracle's prefix, floor, dispatch and full-width arithmetic.

These tests verify planning and input preparation, not complete accumulation execution or its STF.

## Next bounded work

[Service code contexts](accumulation-service.md) now bind one prepared service to account/code,
retained inputs, admitted-parent state and the authenticated slot. The next bounded step constructs
the initial execution context and invocation arguments with the PVM boundary. Later `accseq` rounds
still require genuine gas usage and newly deferred transfers; execution-dependent publication remains
open.
