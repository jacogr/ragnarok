# Assured successor guest outcomes and aggregated gas

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation
service gas aggregation, checkpoint implications and storage host pricing;
vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Author each existing guest/code/funding/gas mode before any initial computation,
then use genuine computed publication, successor signatures and assurances,
admission, queue, PVM execution, termination, composition and atomic publication.
Do not patch completed reports, insert ready work for assurances or supply fake
terminal observations. Seven modes cover commit, panic, underfunded write,
checkpoint commit/panic and both original out-of-gas programmes.

Independent gas oracle: each one-byte-key/two-or-three-byte-value write costs
2442+ceil(3358/1024)+ceil(valueBytes*216/1024)=2447. Two writes cost4894;
checkpoint adds103. This straight accumulation body has one prepaid basic block,
including its host instructions. The existing1000-cycle analysis bound caps its
successful charge at997. Thus the checkpointed two-write body costs at most5994,
below the actual two-report allowance7000. Original report credits remain3500;
other modes retain10000 per report. No protocol budget or engine limit changes.
Both formerly exhausted guests must now Halt/Regular and select second write
bytes22/23, rather than reusing their first-block exceptional-state oracle.

Completion: assert actual first-versus-successor terminal/dimension/gas and exact
selected storage/metadata for all seven modes; two report operands become one
invocation, exact histories/statistics and full chain parameters survive canonical
slot3 publication, and old state/view aliases remain unchanged. Exercise real
local effect-byte refusal and replay rejection. Repeat1000 full seven-mode cycles
(7000 actual successor guest executions/compositions/publications) with fresh ARC
proof. Selected native suite, source-owned inventory/tooling, formatting and
byte-identical predecessor evidence are required. Existing production result
contracts are already covered; this integration increment introduces no new
production result API.

Next: extend real guest input consumption through the computed/assured path.
M1 framing complete; full serialization, whole-block parity and full chainspec
equivalence remain open.

Observed local evidence: all seven genuinely authored first/successor pairs pass
exact terminal, implication dimension, storage footprint, balance, code identity
and parameter checks. Both original3500-gas outcomes are OutOfGas/Exceptional;
their actual two-report successor allowance7000 produces Halt/Regular, consumes
more than4894 and no more than5994 gas, and commits second write22/23. Ordinary
panic still selects absent storage, checkpointed panic selects first write21/22/23,
underfunded writes still leave storage absent, and normal/checkpointed commits
retain their respective selected bytes.

Each actual successor consumes both report operands in one service42 invocation,
records prefix2/history3/ready0, updates timestamp3 and activity refinement0/
accumulation2/actualgas, publishes exact prepared state and retains original
parameters, old parent/view aliases and finality1. Replay refuses. Every mode
with selected writes rejects a final byte ceiling one below its actual size at
RunnerFailure/CompletionFailure/BatchFailure/LimitExceeded, preserving the parent.

The native guest assertions initially passed100 cycles, but the existing harness
requires exactly1000. The suite was corrected to1000 without changing that guard
or reducing per-cycle work. Final7000 successor executions plus complete state
composition/publication retain3162032/3162032 occupied bytes. Pinned semantic,
35 verification tooling tests, inventory and formatting pass. Inventory remains
194 failure families/2436 probes and discovers266 native suites; no new production
result API or duplicate contract family was added. All3436 prior source/config
inputs remain byte-identical. Local macOS checked-release evidence; remote CI
was not requested.
