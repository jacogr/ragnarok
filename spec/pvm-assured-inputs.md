# Guest consumption of actual assured report inputs

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, host fetch
selector15, C.2 operands and accumulation storage; vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Append original test guest modes for first, second and maximum-width absent
operand indices. Author these instructions before original refinement, code
commitments, parent state roots and signed reports. Keep the existing dual-entry
layout: PC0 jumps to empty refinement output, PC5 genuinely fetches invocation
bytes and writes them to storage. Compact load_imm instructions keep the same
bounded envelope; no report, result or captured invocation is patched.

The independent byte oracle is C.2 operand tag0 followed by packageHash. Selector15
selects a record without the list count prefix; offset1/length3 therefore copies
its first three package-hash bytes. First and second actual report prefixes must
differ. The maximum uint64 index is absent, leaves original RW bytes21/22/23
unchanged, and must not wrap to index0. The original single-input block makes the
second-index guest absent; the genuine assured two-input successor makes it
present. Preserve original gas credits, funding and all chain parameters.

Completion: actual Halt/Regular results, exact first/successor storage, one
invocation with two operands, source identity, real byte-copy/host-call/effect
refusals, original state/view aliases, canonical history/statistics and atomic
publication. Run1000 cycles of all three actual successor executions/compositions/
publications with fresh ARC evidence. Recheck the seven existing original storage
and assured-outcome modes because the shared fixture helper changes. Existing
production result contracts remain covered; no new production API is introduced.
Source-owned inventory/tooling and pinned formatting are required.

Next: extend real guest consumption to report-list framing and clipped input
ranges. M1 framing complete; full serialization, whole-block parity and full
chainspec equivalence remain open.

Observed local native evidence: the first-index guest persists the actual first
package-hash prefix in both historical and successor invocations. The second-index
guest leaves initial memory untouched for the original single-input invocation,
then persists the actual distinct second package-hash prefix from the two-input
successor. The maximum uint64 index preserves initial21/22/23 bytes and does not
wrap to either present record. All three genuinely Halt/Regular and record one
self-write/three bytes with original credits10000 then20000. Actual gas exceeds
2804 and is at most3801: selector15 request3 costs357, write costs2447, and the
single prepaid block is at most997 under the unchanged analysis bound.

Actual copy cap2 refuses selected three-byte fetches with DispatchFailure/
LimitExceeded. One allowed host dispatch refuses before the storage host with
ExecutionFailure/HostCallLimitExceeded. Final byte ceiling2 refuses the real
fetched write with CompletionFailure/BatchFailure/LimitExceeded. Every refusal
preserves the original parent and view. Successful composition/publication keeps
exact bytes, footprint38/item1/balance50, timestamp3, history3, activity reports2/
refinement0/actualgas, all29 parameters, finality1 and unchanged old aliases.

One thousand three-mode execution/composition/publication cycles retain
1406672/1406672 occupied bytes. Both affected original seven-mode suites were
rerun successfully: computed storage retains2933856/2933856 and assured outcomes
retain3162032/3162032 bytes over1000 cycles each. Only the original shared guest
factory changed among3440 predecessor inputs;3439 remain byte-identical. All
production code is unchanged. Pinned semantic checks,35 verification tooling
tests, inventory(194 families/2436 probes/267 native suites) and formatting2333
Nim files plus Rust pass. Local macOS checked-release evidence only; remote CI
was not requested.
