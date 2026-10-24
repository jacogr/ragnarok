# Invocation-local dynamic jump targets

## Scope and invariant

This is an implementation optimization under the existing Gray Paper/PVM control contract.
Pins, opcode semantics, checked ARC/Clang ThinLTO builds and public APIs remain unchanged.
An indirect jump first computes the existing wrapped 32-bit address, handles the halt sentinel,
and rejects zero/odd addresses. Only then may execution reuse a validated table ordinal.

Four private scalar entries retain the complete ordinal and its validated basic-block target.
A miss runs the existing table lookup and block-membership check; only complete successful facts
replace an entry. The ordinal modulo four selects a slot, but the full ordinal decides a hit.
Invalid entries, missing ordinals and operand-byte targets continue to panic. Cached facts never
certify affordability, paid gas, a register mutation or the completion of an instruction.

The private execution cache has one immutable program and one invocation lifetime. Both host
callback forms preserve that program across replies, so target facts may survive those replies.
Nested execution, a new call and public single-step execution start with empty entries. No global
state, heap allocation, preparation pass, program reference, memory image or callback is retained.
The four slots are an implementation choice, not a caller resource default or protocol limit.

## Verification

`pvm_execution_cache` independently frames two host/jump blocks with table ordinals0/4 that
collide and ordinal3 in another slot. Repeated hits and replacements alternate host identities.
Each callback checks every register, the exact PC, paid flag and independent100-gas block debit.
Every callback executes a second immutable program whose ordinal0 targets another block; complete
single-step CPU parity checks that nested invocation before the outer program resumes.

The matrix covers dynamic, complete-plan and lazy-memo pricing with both callback forms. After
warming the cache, it checks the halt sentinel, zero/odd addresses, operand-byte/out-of-code
targets and an absent ordinal, with nonzero high register bits proving the existing32-bit wrap.
It checks complete final/source CPU snapshots and one-less simulation-limit refusal before host
side effects. The focused cases also join1000 balanced ARC cycles. Existing jump-table,
destination, gas-plan/memo and host memory replacement/paid fault-retry suites remain controls.

## Local performance evidence

A separate diagnostic copy traced the small maintained indirect-call guest:2000 queries used
only ordinals0/1/3. The small memory-fill and sieve guests visited6/23 distinct ordinals once.
Trace instrumentation contributes no timing samples and does not predict instruction counts.

Two independently built paired comparisons used the same frozen maintained guests at limits1000
and100000, all three pricing modes, checked build flags, full gas/register/memory/source checks,
and reversed process order. Each comparison retained936 validated invocations, including cold
samples. The second comparison's large-workload CPU medians in milliseconds were:

| Guest | Policy | Before | After |
| --- | --- | ---: | ---: |
| Indirect calls | Dynamic | 31.354 | 30.088 |
| Indirect calls | Complete plan | 30.772 | 29.529 |
| Indirect calls | Lazy memo | 30.857 | 29.407 |
| Memory fill | Dynamic | 14.008 | 14.246 |
| Memory fill | Complete plan | 13.491 | 12.611 |
| Memory fill | Lazy memo | 14.440 | 13.794 |
| Sieve | Dynamic | 18.114 | 17.648 |
| Sieve | Complete plan | 13.469 | 12.181 |
| Sieve | Lazy memo | 13.340 | 12.678 |

The indirect-call improvement repeated at roughly3–5% across the two comparisons. Dynamic
memory-fill varied around neutral; no improvement is claimed for that case. Changes in other
workloads include generated-code/frame effects and cannot be attributed solely to cache hits.
Raw samples, preparation records, exact source hashes and binaries remain under
`build/pvm11/scalar-copy/{jump-cache-paired,jump-cache-final-paired}.json`, with trace and selected
native logs under `build/pvm11/jump-cache/`. These are Apple M1 Max observations, not Linux or
whole-JAM throughput evidence. M1 framing remains complete in its documented scope; full state
serialization and whole-JAM/STF equivalence remain open. Fuzzing remains paused pending Daybreak.
