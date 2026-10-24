# Reuse the execution loop's validated instruction

## Scope and completion checks

Pinned Gray Paper 0.8.0 and all tool/reference pins remain unchanged. After register
result reuse, recursive execution still calls the operand decoder to validate the
current PC and then repeats that lookup inside private single-step dispatch.
Reuse the first private `ProgramResult[Instruction]` in the dispatch helper.

Keep exported stepping/execution APIs unchanged. Single-step callers still derive
one validated instruction from the supplied machine's own immutable program/PC.
The recursive loop obtains its result from the same program/PC before applying the
existing invalid-entry guest panic rule. A private helper consumes only those two
paths; it must retain default-owner, terminal-debt, capability, gas, memory and
snapshot checks. No unchecked mutable instruction or caller-selected owner enters
that helper. Keep all public result/ownership contracts and local budgets intact.

Require focused stepping/execution and both host-callback consumers, invalid terminal
PC/default/debt outcomes, the complete deterministic reference/native set including
dependent arithmetic chains, stable ARC observations and matched checked benchmark
binaries. Retain only a repeatable measured improvement, with raw samples and source
identities. Compiled performance and full upstream differential fuzzing stay deferred.

## Observed evidence

Selected `pvm_step`, `pvm_execution`, `pvm_host_execution` and `pvm_host_failures`
pass with stable occupied memory over 1,000 ARC cycles. These retain invalid imported
PC/default/debt, capability, budget, host failure and immutable-alias witnesses.
All fifteen pinned interpreted reference/native pairs pass, including all 85
dependent arithmetic operations and per-block shortages. The standard interpreted
benchmark, pinned formatting and inventory pass. No exported API or pin changes.

On Apple M1 Max/macOS, fixed-input matched checked ARC/Clang LTO binaries have
100 measured samples per workload/variant with three process warmups and reversed
process order halfway through ten pairs. Medians in microseconds:

| Workload | Before | After | Before / after |
| --- | ---: | ---: | ---: |
| Arithmetic, 10,000 iterations | 2,338.73 | 1,973.77 | 1.18× |
| Aligned memory, 1,000 iterations | 596.65 | 546.00 | 1.09× |
| Crossing memory, 1,000 iterations | 757.67 | 704.65 | 1.08× |
| Aligned host/memory, 1,000 iterations | 840.44 | 779.25 | 1.08× |
| Crossing host/memory, 1,000 iterations | 1,013.81 | 954.79 | 1.06× |

Every paired arithmetic median improves, with ratios 1.156–1.196; smaller changes
retain their complete samples rather than selecting favorable passes. Raw inputs,
binary/source hashes, load observations and samples are retained locally under
`build/pvm-execution-decode-profile/`. There is no affinity/frequency isolation or
exact-head Linux timing claim. Normal Actions reporting remains interpreted-only.

## Sustained decoded working sets, 2026-10-24

The maintained Pinky frame executes32,055,270 PVM instructions. A separate checked
diagnostic snapshot of the current32-slot decoder cache records30,934,880 actual
decoder calls: roughly96.5% of execution requests. This excludes pricing probes.
Complete reference CPU/gas/pages/permissions/source checks still pass; instrumented
timings are discarded. A small256-entry spill prototype still decodes roughly63%
of requests and slows planned Pinky. A4096-entry prototype instead identifies enough
reuse to justify a larger bounded working set. These counts guide the experiment;
they are not native hardware instruction or latency measurements.

The original32-slot natural/paired fast path remains first. Only after32,768
successful decoder misses does an invocation allocate one private4096-entry spill
with2048 two-way sets. Complete successful scalar `ProgramResult[Instruction]`
copies carry their original PC tags. Failed decodes never insert or advance the
saturating threshold counter. Multiplicative hashing selects eleven bits; replacement
alternates the two ways without a growing counter. Hits neither promote into the
small table nor alter replacement state. Decode/allocation/replacement work remains
in a non-inlined cold helper; successful spill reads stay directly in the lookup.

This preserves small-invocation behavior while charging a bounded memory cost only
under sustained decode pressure. The measured checked target has56-byte instructions
and64-byte instruction results:262,144 bytes of results plus2048 replacement flags,
or258KiB of payload before ARC/allocator overhead. A new invocation starts empty;
there is no input-sized growth, program preparation, opcode fusion or public resource
option. Other targets may have different object layouts.

The spill stores no program/machine/memory/callback owner and no guest balance. The
invocation's immutable program stays retained independently across host continuations;
nested calls and later calls own different caches even at identical PCs. The lookup's
cursor borrows only the private spill owner during a callback-free synchronous read;
no mutation or owner replacement occurs before a hit returns its copied result.
Each actual instruction still consumes one attempt and performs normal capability,
gas, control, host/fault and source-snapshot checks. Cached operands do not certify
paid gas or authorize an address from another program.

An exact final-candidate diagnostic records1,357,193 actual decodes,28,907,860 spill
hits and1,790,217 small-cache hits for the same32,055,270 requests. All state checks
pass. The raw baseline/capacity study and final counted sources are under
`build/pvm12/decoder-counts/` and`build/pvm12/decoder-final-counts/`; those durations
are not benchmark evidence.

### Qualification and observed timing

The cache suite builds4500 distinct literal addition instructions and executes ten
rounds, crossing both the allocation threshold and the4128 available positions.
Varying immediates expose wrong-PC hits. Dynamic, complete-plan and cold/warm lazy
policies must match the complete public-single-step CPU/gas result, exact attempt
boundary, unaffordable entry and unchanged source. The independent two-byte framing
helper admits code below16KiB with a32KiB caller blob policy for these larger cases.

Dense host cases re-enter the original program after a nested dense invocation with
different operands at identical PCs. Both callback APIs, second-callback refusal and
one-less step budget retain exact CPU/context/source behavior in all pricing modes.
Four repeated dense host groups have balanced occupied memory. The existing1000-cycle
ARC loop now also creates/destroys a sustained-pressure decoder spill every cycle;
the observed occupied-memory count is unchanged before/after all1000 cycles.

Against the preceding lazy-price-cache layer`4f55311b`, matched checked ARC/Clang
ThinLTO binaries retain two opposite process orders on seven real inputs and all
three pricing modes:1092 complete-state-checked invocations. CPU medians in
milliseconds on M1 Max/macOS, with preparation excluded:

| Input | Pricing | Parent | Decoded spill | Change |
| --- | --- | ---: | ---: | ---: |
| Indirect calls100,000 | Dynamic | 26.253 | 24.502 | -6.7% |
| Indirect calls100,000 | Complete plan | 26.186 | 24.180 | -7.7% |
| Indirect calls100,000 | Lazy memo | 26.462 | 24.644 | -6.9% |
| Pinky frame | Dynamic | 2,714.199 | 2,553.535 | -5.9% |
| Pinky frame | Complete plan | 664.095 | 489.726 | -26.3% |
| Pinky frame | Lazy memo | 743.845 | 569.726 | -23.4% |

An additional936-invocation control comparison reproduces the indirect-call gains
at roughly7–8%; a separate52-invocation planned-Pinky comparison reproduces its26%
gain. Sieve and memory-fill differences mostly remain within3%, so no improvement
is claimed there. Smaller synthetic workloads are qualified separately. An owner-only
cursor in the public operand decoder removed a retain/release pair in generated C
but improved planned Pinky less than2%; it was rejected. The public operand decoder
is unchanged. No exact-head Linux performance or whole-JAM throughput is claimed.

The selected cache, host-memory-reentry and mixed-policy suites pass; the cache ARC
report retains238144 occupied bytes before/after1000 cycles with its larger shared
fixtures alive. The original429-invocation calibrated census, nine affected Python
guards, inventory and pinned formatting pass. Two complete synthetic comparisons each
validate1716 invocations. The first synthetic timing run overlapped formatting and
is retained as noisy evidence; the uncontended repeat does not reproduce its large
mixed-bit regression. The smallest planned four-instruction case changes from0.125
to0.166µs (one observed sample quantum), and some other small cells vary a few
percent. There is no universal small-invocation speed claim. Raw data and the exact
source/binary identities are under`build/pvm12/decoded-large-paired.json`,
`build/pvm12/decoded-synthetic/` and the adjacent build/guard logs.


## Wider bounded spill qualification, 2026-10-24

The selected spill now has16,384 copied instruction-result entries and8192
replacement flags. The original32-entry first lookup and32,768-successful-miss
allocation threshold are unchanged. Multiplicative hashing selects thirteen bits
and the second way is8192 positions above the first. No additional tier, owner,
lookup policy, unbounded growth or public option is introduced. The earlier4096-entry
results above remain historical measurements of that prototype.

At the checked target's64-byte result layout, the selected payload is1,056,768
bytes (1032KiB), four times the earlier258KiB budget, plus ARC/allocator overhead.
This is an explicit memory/time tradeoff per active sustained-pressure invocation;
nested invocations have independent budgets. Small invocations still allocate no
spill. Results retain only copied scalar facts, and all normal capability, gas,
permission, local-budget and source-snapshot checks remain enabled.

A source-snapshotted deterministic capacity study preserves all32,055,270 Pinky
requests and full reference state. Actual decodes fall from1,357,193 at4096 entries
to126,281 at8192 and41,256 at16,384. Instrumentation durations are discarded.
Uninstrumented prototypes in two opposite process orders (three warmups and ten
samples each) improve planned Pinky about11.9% at8192 and14.5% at16,384; preceding
single-frame screens show11.5% and17.0%. Those local Apple M1 Max/macOS measurements
choose the candidate, not a universal or Linux speed claim. Exact snapshots,
binaries and samples are under`build/pvm12/decoder-capacity-study/`,
`decoder-capacity-4096/`, `decoder-capacity-8192/`, `decoder-capacity-16384/` and
`decoder-capacity-*-confirm.json`.

The native cache suite adds17,000 distinct literal additions, exceeding the16,416
total positions. Three rounds cross the allocation threshold and force replacement.
All CPU/gas values agree with public single stepping, including cold/warm policies,
exact/one-less attempt budgets and unchanged source. Independent three-byte JAM
framing and an explicit larger test-only policy budget admit this corpus; production
limits are unchanged. Existing dense nested-host tests and1000-cycle allocation/
retirement controls remain. The owning decoder layer passes this extended suite
with238144 occupied bytes before/after1000 cycles. The resolved full stack also
passes the combined cache/price suite at238720 before/after1000 cycles. Selected
host-memory-reentry and mixed-policy reference suites pass on the owning layer.

The maintained comparator against the previous stack tip`40e0de0b` passes1,092
complete-state invocations, both assertion controls and final identity checks.
Pinky CPU medians improve17.6% dynamic,15.3% complete-plan and17.2% lazy memo.
A second936-invocation control comparison does not reproduce the first small-sieve
planned6.5% slowdown (repeat0.9%); other long controls mostly remain within3%.
No small-guest speed improvement is established. Two synthetic comparisons pass
3,432 invocations. A first dynamic aligned-host6.8% slowdown becomes0.7% on repeat;
planned memory cases remain roughly2–3% slower. The four-instruction dynamic case
moves0.584 to0.625 microseconds in both runs, one observed sample quantum. All
regressions/outliers/cold samples remain visible; the larger cache is a measured
Pinky/memory-budget tradeoff, not a universal win. Reports are under
`build/pvm12/decoder-16384-full/`, `decoder-16384-repeat-controls/` and
`decoder-16384-synthetic/`. Pinned formatting covers the changed Nim files;
production sources match the measured prototype exactly after native restacking.
Complete-JAM parity remains open.

## Direct-mapped bounded lookup qualification, 2026-10-24

The selected spill keeps16,384 genuine instruction results and indexes one slot
with the low fourteen PC bits. A complete successful-result/full-PC comparison
still decides every hit; truncating the index never truncates the authority tag.
Successful misses replace exactly that slot. The original32-entry natural/paired
lookup remains first, and the32,768-successful-miss promotion threshold is retained.
The invocation owns all facts through synchronous reads and host continuations;
new/nested invocations retain separate owners and immutable source snapshots.

This removes the per-request multiplicative hash, second spill-way probe and8192
replacement flags. At the qualified64-byte result layout, spill payload changes
from1,056,768 bytes (1032KiB) to1,048,576 bytes (1024KiB), with the same16,416 total
small/spill positions. Ordinary invocations still allocate no spill. Collisions
fall back to the existing checked decoder, and failed decodes never replace facts.
All instruction attempts, gas/capability checks and host/fault boundaries remain.

A source-frozen diagnostic preserves all32,055,270 Pinky requests and complete
reference state. The earlier two-way mapping makes41,256 actual decodes and
3,737,260 second-way hits; the selected direct mapping makes75,048 decodes,
about0.23% of requests, while eliminating the second probe. Larger direct32,768/
65,536-position prototypes make38,920/38,689 decodes at twice/four times the result
payload. The selected mapping keeps the existing position budget. These are
algorithmic counts, with instrumentation timings discarded; snapshots and all six
mapping observations are under`build/pvm12/decoder-lookup-study/`.

Two complete CI attempts compare runtime candidate`d95fdc9e` with parent`b518cac1`
on Ubuntu24.04, using the same current drivers, pinned checked ARC/Nimony/Clang
ThinLTO profiles, frozen inputs and two reversed process orders. Both attempts
pass2,808 real/synthetic invocations, another2,808 identical-source controls, six
exact assertion controls per comparison and the complete candidate/PolkaVM
interpreted real-guest pack. Source/input/compiler/binary identities are rechecked.
Pinky process-CPU median changes are:

| Pricing | First attempt | Repeat |
| --- | ---: | ---: |
| Dynamic | -12.6% | -17.8% |
| Complete plan | -12.8% | -17.2% |
| Lazy memo | -15.4% | -14.7% |

The runners report AMD EPYC9V74 and9V45 respectively. Each ratio compares binaries
within its own job; absolute times across those machines are not compared. All21
real-guest and33 synthetic workload/policy cells remain in the raw tables. Smaller
cells have explicit tradeoffs: first-attempt memo synthetic arithmetic/host loops
slow about5–7%, while those cells are neutral/faster in the repeat. Repeat planned
aligned/sparse-memory controls slow about8–9%, with near-neutral first-attempt
values. Identical-source controls also retain several-percent small-cell variation.
The supported speed claim is the repeated large decoded-working-set improvement;
smaller workload and code-layout/microarchitecture sensitivities remain visible.
Cold samples and plan/memo preparation costs are retained without outlier removal.

The native cache suite covers17,000 distinct additions, exact/one-less budgets,
cold/warm policies, complete CPU/gas/source parity, nested hosts and invalid entry.
Direct-slot aliases retain distinct full PC tags and operands. All1,000 ARC cycles
remain balanced at238720 occupied bytes before/after. Selected host-memory-reentry
and mixed-policy reference suites pass. Production pins and public APIs retain
their established contracts; this adds no prepared instruction representation.

CI evidence: [run40102267534, both attempts](https://github.com/jacogr/ragnarok/actions/runs/40102267534).
Local downloaded reports are under`build/pvm12/ci-40102267534/` and
`build/pvm12/ci-40102267534-attempt2/`. Broader whole-JAM performance, full state
serialization/parity and compiled execution remain outside this qualification.

## Promoted-table probe order, 2026-10-24

After promotion, probe the existing direct table before the two small ways. The
recorded direct-mapping study has30,763,791 spill hits among32,055,270 Pinky
requests, so most of these requests can avoid two unsuccessful small-way checks.
An unpromoted invocation performs one nil-table test before the unchanged small
lookup. Promotion threshold, capacity, exact successful-result/full-PC tags,
miss insertion/replacement and invocation ownership remain unchanged. A direct
collision can still fall back to either genuine small-way result.

Selected cache-pressure/full-state, step, host-reentry and mixed-policy suites
qualify correctness and balanced ARC. Prior desktop spill-first screening on the
old mapping was unproven; the changed direct mapping and Linux paired/noise job
justify the fresh Linux measurements recorded below.


[CI40107423219, attempts1 and2](https://github.com/jacogr/ragnarok/actions/runs/40107423219)
compares runtime `af5d81fa207d576d0a96665491883b925e51279f` against parent
`6af95c35df9c3f933315841204d9178efc23ce5e`. Each passes2808 paired full-state
invocations,2808 identical-source controls, native assertion refusals and the
pinned interpreted guest pack. First/repeat Pinky CPU changes are -6.6/-8.9%
dynamic, -9.5/-8.8% planned and -8.5/-9.3% memo. Publication preserves exact
runtime/driver/build/pin inputs across subsequent profiler/documentation-only
native restacking; source equality is recorded separately from exact-head CI.

The cost is repeated on small, unpromoted work: dynamic synthetic arithmetic
+5.5/+5.9%, crossing memory +3.3/+3.3%, mixed bits +3.1/+3.4%, alternating blocks
+3.7/+5.2%. Planned minimal1000 is +3.8/+3.7%, and planned memset100000 is
+2.2/+3.9%. Some planned synthetic cells also regress roughly3–5% on repeat.
Arithmetic10000 executes30001 instructions, below the32768-miss threshold, so
it receives the extra nil-table probe without a promoted-table benefit. Tiny
memo changes fluctuate across attempts; host same-source variation reaches
10–17%, so no host gain is established. These regressions are part of the
selected large-working-set tradeoff. All21 real and33 synthetic cells, both
orders, cold observations and raw noise controls remain in the CI artifacts and
`build/pvm12/ci-40107423219/` plus its `-attempt2` sibling. No universal speed
claim or complete-JAM parity claim follows.

## Borrowed complete cache entries, 2026-10-24

The private lookup returns a nullable pointer to a complete genuine cache entry
instead of copying its64-byte result at every hit. Successful cold decoding still fills
the existing fixed small array and bounded direct spill under the original replacement
policy, then returns the small destination's address. Failures return nil without filling,
evicting or advancing replacement; the two private consumers retain their existing
Panic/InvalidHostSuspension mappings and never select a failed payload.

This differs from the earlier rejected stack-scratch experiment: neither consumer adds
an auxiliary miss-result frame or keeps a pointer to a callee's local decoder result.
Every nonnil address points into an invocation-owned fixed array. The spill owner remains
retained by that invocation. Neither consumer performs another instruction-cache lookup,
replaces cache storage, calls a host or exports the address while consuming the borrowed
fact. Instruction evaluation only mutates separate CPU, memory, price and target state;
host-response validation completes before the next callback. Subsequent lookups may evict
an entry only after the prior borrow's last use. Public decoder results remain copied
values, with unchanged guarded accessors and contracts. No new instruction representation
or prepared execution tier is introduced.

Acceptance requires all existing eviction/capacity, malformed-entry, policy, nested-host
and source-snapshot witnesses, balanced ARC observations, address-sanitizer stack controls,
and an incremental paired Linux comparison. Earlier desktop scratch-borrow timings do not
qualify this candidate; dispatch inlining and direct-cache ordering have since changed.

The candidate passes seven selected native cache/execution/mixed/host/reentry/failure/
metered-repair suites, including their declared1000-cycle balanced ARC groups.
Generated C represents every private hit result as a pointer passed to the evaluator,
with no additional caller miss-result frame. AddressSanitizer passes the complete cache
and frozen mixed-memory host-reentry cases with stack-use-after-return detection enabled;
a separate positive stack-escape control is detected. These checks cover instrumented
stack/scope addresses; the pinned native allocator does not individually poison heap
objects, so they do not establish complete heap/leak coverage. The incremental comparison below supplies timing evidence for this exact runtime.


[Standalone CI40116035877](https://github.com/jacogr/ragnarok/actions/runs/40116035877)
compares runtime13fa3134 directly with published parent67df0628 on one AMD EPYC9V45
runner. The rejected adaptive dynamic-target experiments are absent from both sources.
All2808 paired full-state invocations,2808 identical-source controls, assertion controls
and the interpreted reference pack pass. Both process orders improve Pinky CPU by
14.54/13.27% dynamic,21.03/19.08% planned and12.55/13.65% memo. Corresponding Pinky
controls vary -0.94/-2.50%, +1.90/-1.42% and -1.39/-3.08%. Long indirect calls improve
14.60–20.53%, long sieve7.27–16.35%, and dynamic memory fill12.92/13.52%. These are
within-run ratios; absolute times from other CPUs are not combined.

All21 real and33 synthetic cells, cold observations and both orders remain retained.
Short sieve1000 memo regresses4.11/3.78% (about5us), above its -1.41/+0.85% controls.
Tiny arithmetic1 planned costs20/4.5ns more (+8.32/+1.83%); dynamic/memo tiny cases
vary by tens of nanoseconds. Long memo memory fill changes -6.75/-0.67% against
-1.20/+9.36% controls, and planned synthetic host changes overlap their controls;
neither is claimed as an established gain. Dynamic and memo host reductions remain
visible with their corresponding controls in the raw artifact.

The exact standalone runtime passes all seven selected native cache/execution/mixed/
reentry/failure/repair suites and their declared1000-cycle balanced ARC groups. Cache
and frozen mixed-memory reentry ASan runs pass with a positive stack-escape control;
native-allocator heap/leak coverage is not claimed. Documentation-only native rebases
preserve the measured runtime, drivers, build configuration and dependency pins.
