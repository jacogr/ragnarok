# Adjacent add32 and unsigned-immediate branch fusion

Select existing `flatRegisterBranchCold[131, 83]` for genuinely adjacent
`add_imm_32` and `branch_lt_u_imm` source facts. The cold worker executes the
ordinary arithmetic and branch path and returns its actual outcome. It installs
the existing fused worker only when the second handler is the positively cached
branch worker for both original arms. The fused worker uses the shared register
and branch equations and checks the second-source budget barrier before branch
operands or prepaid-state mutation. A folded noop between facts cannot select it.

Original PCs, independently addressable branch entry, prices, source attempts and
refunds remain authoritative. Charged-shape recognition, continuation limits,
jump-40 handling and native eligibility retain their existing contracts. This PR
contains only fusion and its supporting verification; duplicate host-resume cache
clearing is handled independently by #1981.

## Semantic witness and qualification contracts

The registered `pvm_stream_all_opcodes` profile enables `pvmStreamFusionReceipt`,
a read-only internal boolean observer of the selected worker and original source
facts. It introduces no frame fields or hot counters and is absent from ordinary
production profiles. Sanitizer and native ARM/x86 qualification controllers consume
the registered receipt define, bind the requirement record and complete source-owned
golden output, and reject missing activation, incomplete output or backend/refusal
flag loss. These integrations belong to the fusion witness, not performance tooling.

The witness composes public scalar `stepOnce` calls, whose single-step plan cannot
select the fused worker. Independent literals cover signed-32 extension, wrapping,
high input bits, negative immediates, unsigned comparison and equality; alias and
cross-lane cases distinguish source from updated destination. Adjacent/noop-gap
code, first/interior entry, paid/unpaid state, six gas values and eight attempt
budgets produce 9,984 prefix comparisons. Additional assertions cover cold refusal,
actual warm activation, invalid-target refusal, stream movement, changed-source
non-consuming rejection and a retained code lifetime with alternating register
state and both branch outcomes. These added plans disable native selection even
in a native-enabled build, so the receipt proves common-interpreter execution.

Only expected halt/panic PC is normalized to zero, matching the existing recursive
execution contract; budget, out-of-gas and other exits retain the raw scalar PC.
All registers, gas, paid state, remaining attempts, source ownership and actual
activation assertions remain authoritative.

## Retained bundle evidence and performance hold

Earlier local and Linux qualification at immutable runtime
`52e72e4b7a9ebf8ec6f8ff40cee9e4d995d22d65` covered a bundle containing both this
fusion and the host-resume clear removal. Those results remain bundle evidence;
they are not relabeled as qualification or standalone timings for the split trees.
The original prefix/golden, native/refusal and source-bound packets remain retained.
This fusion-only cleanup head has no newly requested Linux or timing run.

The canonical x86 timing observations
[42042845187](https://github.com/jacogr/ragnarok/actions/runs/42042845187) and
[42050923473](https://github.com/jacogr/ragnarok/actions/runs/42050923473) measured
that bundle and retain the sieve performance hold. The separate corrected work
collection [42080828163](https://github.com/jacogr/ragnarok/actions/runs/42080828163)
ran on orchestration commit `39c316e5f06197cb9def63e28fcb91460f4c77fa`, comparing
parent `e2858bf5bc0cf34fd82a71ffd91b35336f8399c1` with the exact bundled runtime `52e72e4b`.
Its official artifact SHA256 is
`73a0de42ec71d147c58e8108c982cd83101d5633c6cb562ac9bf2ebe8db3f188`.
The failed earlier run 42074655607 and explicitly offline recovery remain distinct.

The complete sieve1000 diagnostic verified 156 state-checked calls, native counters,
all 104 numbered parts, eight empty final dumps and per-part all-event agreement
between line and machine passes. All twelve reused calls have equal per-function
instruction/branch work and actual call-edge counts across heads after verified
native address rebasing. The new named cold-branch handler has zero observed work
in this cohort. Small first-call increases are confined to `flatResolve` selection
checks. Code and generated-native addresses differ, and instrumentation itself
changes layout. These counts do not establish a production latency cause or speedup.

The one-off fixed-pair Python/workflow machinery has been retired from the current
PR tree. Its exact a1191f0c/39c316e5 commits, raw artifacts and sealed independent
audits remain available in history. No instrumentation data is promoted into
canonical timing/latest evidence. #1979 remains on performance HOLD with no LGTM;
fusion has not been established as the cause. Separation keeps the review and
qualification decisions independent.
