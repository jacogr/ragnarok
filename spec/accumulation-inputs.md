# Accumulation invocation inputs

## Scope and pinned authority

`src/state/accumulation_inputs.nim` implements the input projection in GP 0.8.0
`accumulation.tex`, equations `accpar` and `accone`, at Gray Paper revision
`07f041dabd073f9018b418e9ee72e79dd2185401` (source SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`). It extends
[report operand preparation](accumulation-operands.md) with explicit deferred transfers and
always-accumulate allowances for one caller-selected round.

For each service in the union of report-digest service IDs, transfer destinations and allowance
keys, preparation computes:

- the original transfer sequence filtered by destination;
- followed by the report operands in their already established report/digest order;
- gas equal to its free allowance (or zero), plus matching transfer gas, plus matching digest gas.

Numeric service order determines only outer enumeration. A zero-valued allowance still introduces
a service, even with an empty input sequence. Repeated transfers are retained, including zero gas
and zero balance; transfer source IDs do not introduce services. Work errors remain ordinary
operands and contribute their declared accumulation gas. No account existence, balance, minimum
gas, code availability or PVM outcome is inferred during this projection.

## Round context and ownership

`prepareAccumulationInputs` accepts a completed report-prefix projection, a borrowed array of fixed
`DeferredTransfer` values, an explicit numeric sorted unique array of `AlwaysAccumulate` pairs and
local resource limits. Duplicate or unordered allowance keys fail without normalization or a
last-value-wins policy. The existing C(12) codec supplies that same canonical dictionary order.

For initial `accseq`, the caller supplies the applicable C(12) always-accumulate dictionary; later
recursive calls supply an empty dictionary, as the specification requires. The API deliberately
accepts explicit per-round context rather than implicitly reusing initial free allowances.
It does not certify that a caller's allowances came from a particular parent state or that transfers
came from a prior execution. Binding those inputs to actual execution context remains separate.

The private acyclic owner retains the exact report-prefix source, copies every transfer field and
retains immutable C.2 operand owners without copying their payloads again. Metadata is copied, and
input extraction returns a private tagged transfer/operand value with guarded variant accessors.
Caller-array mutation and release of source/parent handles cannot alter previously prepared inputs.
Failed/default results carry only a reason; ordinal domains, result storage and input tags are private.

## Bounds and gas arithmetic

Independent input, allowance and service ceilings bound traversal and retained storage. Combined
row counts and native allocation extents are proved before descriptor allocation, and the entire
union and all gas sums are validated before materializing input arrays. A refused context never
publishes an earlier service or partial sum.

GP `accounts.tex` and `overview.tex` define gas as a natural less than `2^64`. Addition here is
mathematical addition: a service sum above `2^64 - 1` returns `GasOverflow`, with neither wrapping
nor saturation. This is a boundary refusal for an unrepresentable explicit context, not a claim
about complete-block validity or a substitute for `accseq`'s gas-dependent prefix selection.
`2^64 - 1` itself is accepted. Nimony's wrapping arithmetic is preserved; subtraction-based checks
prove each addition before it is evaluated.

## Verification evidence

`tests/unit/state/test_state_accumulation_inputs.nim` replays 146 independently derived contexts over
six unchanged pinned accumulation queue inputs (tiny/full at three prefixes) and 128 authored
report prefixes. Vector revision is `d3c089c9a1d5352ad353626d7a2db8589f137b2a`; original source/hash
checks remain in force. Transfer and allowance contexts are explicitly authored test data, not
published expected execution outputs. The independent Python oracle uses unbounded arithmetic,
dictionary union and sequence filtering. Native comparisons check complete C.2 bytes, exact service
and inner input order, every gas sum and overflow verdict; 57 generated contexts exceed the gas domain.

Literal tests cover empty rounds, privilege-only services, zero allowances, transfer copying and
source mutation, maximum gas and overflow, duplicate/unordered allowances, exact/one-below limits,
invalid native extents, default handles and hostile indices. A 1,000-cycle success/late-refusal loop
requires unchanged live ARC occupancy. Independent Python witnesses anchor the oracle's field
ordering and mathematical arithmetic. Compiler probes protect private storage and nominal indices;
strict runtime probes require the selected-success or selected-variant diagnostic.

These checks establish input preparation only; they do not execute the complete accumulation STF.

## Next bounded work

[Initial round planning](accumulation-round.md) now selects the gas-bounded prefix and binds
initial allowances to admitted-parent C(12). Later rounds still require genuine execution outcomes
and newly deferred transfers. Service-account execution-context binding is the next bounded step.
