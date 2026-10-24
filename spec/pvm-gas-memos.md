# Bounded lazy reusable block prices

`GasMemo` learns successful block prices for one captured `Program` and one fixed local cycle
policy. It complements the existing immutable [complete gas plan](pvm-gas-plans.md): construction
allocates a bounded empty price table and performs no pipeline simulations. Only requested blocks
are priced. Existing dynamic execution remains the default; no guest gas, instruction, memory,
response, serialization or pinned specification/dependency semantics change.

## Ownership, limits and refusals

`newGasMemo(source, limits)` validates a genuine nonempty source, native allocation/conversion bounds
and the caller's payload ceiling before allocating eight bytes per code byte. That ceiling excludes
the retained program and allocator/reference headers; it is not a complete resident-set guarantee
or allocator-exhaustion recovery contract. Constructor work is bounded by table initialization.
The cycle ceiling applies separately to each missing-price simulation; execution retains its
existing attempted-instruction and host-dispatch work budgets. A zero cycle ceiling is a valid
lazy policy: an unpaid block query fails locally, while an already paid continuation needs no
new simulation. Construction can succeed without pricing a block this invocation will never visit.

The opaque handle shares a private mutable memo identity when copied. Its program identity, cycle
policy and table extent never change. Successful positive facts occupy exact block-start slots;
zero denotes absence. Each slot is written once, and bounded occupancy increases only after a
successful simulation. Invalid/default/operand/interior addresses and exhausted simulations store
nothing. Full-width address bounds precede native conversion. Repeated hits cannot bypass a stricter
policy because every handle permanently retains its original cycle ceiling. Separately captured
identical bytes or another decode profile do not match.

Only controlled memo operations can mutate facts. Source/configuration and storage stay private;
`gasMemoInfo` returns copied observations and `programOf` retains an immutable child independently.
Failed/default tagged results carry reasons without a selectable payload. Rebinding a caller's
handle cannot replace another call's retained private policy. Use a memo exclusively within one
worker, including synchronous nested calls; immutable complete plans remain the sharing option
for concurrent executions. No global cache, callback, context, CPU or memory owner is retained.

## Execution boundary

`execute` and both `executeWithHost` forms accept a memo in place of `GasCycleLimit`. They validate
source identity and retain the existing invocation-local hot price cache. Cold misses consult the
memo and use the original simulator under its fixed cycle limit. Affordability, paid-block flags,
CPU/memory mutation, fault precedence, attempt/dispatch budgets and immutable publication use the
existing paths. Single-step APIs retain their current dynamic/immutable-plan interfaces.

Facts are prices, not evidence that gas was paid. An unaffordable block or later local refusal may
leave successful facts in the memo without exposing machine progress. Paid memory-fault repair does
not charge again. Callbacks can perform nested execution or replace their own memo handle without
changing the outer retained program/policy. Copy a context-held handle into a local before borrowing
that context mutably; a direct `context.memo` argument alongside `var context` is compiler-rejected.

## Completion checks and observations

The native suite checks all 1,796 independent prices, repeated successful hits, failed queries with
unchanged occupancy, strict owner identity, copied observations, exact/short byte ceilings, zero
cycle policy and complete execution parity at affordability boundaries. Host tests cover both reply
forms, shared budgets, zero-ordinal refusal, nesting, context-handle replacement and wrong-policy
refusal before callbacks. Interior executable entry still charges its complete containing block;
interior pricing queries remain refused. Paid fault repair and 1,000 parent/alias/child/failure ARC
lifetimes protect state and ownership. Runtime result failures, genuine positives, private-field
rejections, full-build alias rejection, actual AddressSanitizer and affected legacy consumers
supplement these checks. Exact-head Linux CI remains separate from local evidence.

Both maintained comparisons now include explicit memo mode. Strict prefix/suffix framing requires
empty initialization, every execution and final bounded occupancy. Reports retain all warmups and
show initialization plus the first cold execution separately from warmed medians. A memo's first
execution includes learning work; excluding that cost would overstate reuse benefits. Constructor
CPU below clock resolution may be zero, with positive wall duration retained. Source/fixture/binary
identities and unchanged checked ARC/Clang ThinLTO/JamV1 interpreted profiles qualify measurements.
Compiled comparison remains deferred, and existing frozen guests are unchanged.

Canonical M1 Max observations measured large-sieve warmed CPU at 17.783 ms dynamic,
13.181 ms with a complete plan and 13.322 ms with a memo. Memo initialization took 0.102 ms,
compared with 9.625 ms complete pricing. Initialization plus first-cold execution was 17.015 ms
for the memo, 17.794 ms dynamic and 22.942 ms for the complete plan. The memo learned 1,015 blocks;
the smaller input learned 208 blocks. Both policies use 1,257,216 payload bytes. At the smaller
input the memo's cold total was 0.657 ms versus 0.627 ms dynamic, so cold reuse is not a universal
win. These are workload-specific preparation/reuse observations, not whole-client throughput.

The synthetic runner instantiates memo host calls in a separate checked binary. Combining all
three host specializations in one driver changed legacy host-loop code generation by about 15%,
even with unchanged legacy helper interfaces; an unchanged legacy driver isolated this effect.
Wrong compiled-mode labels are actual failing controls. Two paired confirmations with the parent
binary retained full-state checks: one kept legacy host rows within 0.7%, while another showed
roughly 1–4.5% slower rows across the workload set. These local variations are retained rather than
interpreted as an optimization gain. No checking or ABI relaxation is used. Typed shared bodies
keep instruction, budget and callback semantics together while preserving legacy frame layouts.

The rejected prepaid-register dispatcher and compact/dense complete-decoding experiments remain
outside production: small/uneven gains or their additional memory cost did not justify adoption.
Fuzzing remains deferred until maintainer Daybreak access. M1 framing is complete in its documented
scope; full state serialization and whole-JAM/STF equivalence remain open.
