# ARM64 resident byte read/store loop

## Scope

**Performance hold:** correctness qualifies, but Linux ARM DOOM tick regresses.
Keep this machinery in draft; it is not ready for master.

This opt-in ARM increment starts from accepted master
`a0997ac1469113ba1f65b4f4bdde9c9462cf138e`. Existing GP gas, source-attempt,
memory, fault and ownership contracts remain authoritative. Nimony
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`, ARC, checked release, Clang and
ThinLTO remain unchanged. X86 lowering and public backend defaults are unchanged.

One complete charged source block may contain optional folded opcode 2 followed
by `124 / 149 / 120 / 149 / 171`: byte read, source update, byte store,
destination update and conditional. Source, value, destination and bound must
have four distinct register roles; both updates preserve their own base role,
and the branch compares destination with bound. Strides and displacements come
from sealed source facts. Admission contains no guest PC or fixed stride.

A cold structural match installs a bounded per-header probe. Publication requires
a positively cached conditional with exactly one self-loop arm, plus 64 eligible
unpaid header visits with complete quota/gas and no partial barrier. These are
eligible visits, not a claim that every observed branch took its backedge.
Cold operands are source PCs; self-loop certification uses resolved executable
offsets only. The existing dirty-word loop and connected-region caches remain
available. A separate POD cache shares the existing arena and ordinary
1,023-publication limit, preserving the reserved connected-region publication.

## Execution and ownership

The native body retains all thirteen guest registers between iterations. Before
each iteration, it checks complete gas and five or six original source attempts,
a writable destination descriptor, an already-set destination dirty-page bit,
and a readable source descriptor. Byte effective addresses wrap modulo 2^32;
pointer updates retain their 64-bit register semantics. Conservative readable
bounds and unrepresented sparse regions decline to checked execution.

All current-iteration guards precede guest register or memory mutation. A guard
failure restores gas, quota and context, publishes prior completed iterations,
and replays the untouched current iteration through the original charged worker.
That worker owns first-touch dirty marking, source fault ordering, partial
budgets, prepaid blocks, exact PCs and repair/retry behavior. Native execution
never appends dirty pages or sets a clean bit.

After admission, the native load precedes source update, store, destination
update and conditional. Overlapping copies observe earlier stores, including
when a store changes the next source byte. Native exits publish the complete
register bank and exact remaining gas/quota. Attempt consumption equals completed
blocks times source span; native operation statistics count five lowered
operations even when a folded no-op makes the source span six.

Only scalar source coordinates and immutable code are retained. Each call
borrows current descriptors and dirty bitmap through the existing eight-word
context. D20-D22 preserve gas, quota and context while guards use X2/X3/X17 as
scratch; X17 must be restored after the bitmap mask before reading descriptors.
No new executable-memory owner or retained invocation pointer is introduced.

## Verification

The full ARM witness retains previous dirty-word, connected-region and guarded
load checks. New source-built fixtures cover folded/no-noop spans, a relocated
valid block, paid/gas/attempt boundaries, overlap, cross-page first touch,
read/store faults after completed native iterations and sparse descriptor
refusal. Literal propagated bytes and post-fault registers/memory supplement
full-state comparisons with single-step execution. The overlap fixture records
533 completed native blocks in five calls; the basic fixture records 14 in
three calls. Both include guard declines.

Native, executable-storage-refused and interpreted witness builds pass locally.
The qualifier requires genuine resident basic/overlap receipts in native mode
and rejects those receipts in refused/interpreted mode. Parser controls reject
missing checks, duplicate receipts and counts consistent with one call per
iteration. No presentation or source-organization test is added.

## Local evidence and qualification gate

Ignored receipts are preserved in `build/pvm-byte-loop/local-receipts/`, with
SHA-256 identities. A separate instrumented copy confirms selection of the
intended DOOM source header 503995, source stride 1, destination stride 320,
source span 6 and price 50. Shipping code contains no selection PC or profiling
switch.

Three balanced ABBA cycles exclude three warmups and retain complete DOOM CPU,
register, memory/permissions and ordered-output checks. The private same-binary
cache on/off control gives:

| DOOM CPU median | Cache off | Cache on | Change |
| --- | ---: | ---: | ---: |
| JIT tick | 18.68575 ms | 18.26650 ms | -2.24% |
| Interpreted tick | 24.80375 ms | 24.82125 ms | +0.07% |
| JIT init | 172.35250 ms | 173.38625 ms | +0.60%, mixed pairs |
| Interpreted init | 296.70875 ms | 296.89950 ms | +0.06% |

All three JIT tick pairs improve (-2.37%, -2.35%, -1.85%). Native calls over
13 tick samples fall from 16,066,627 to 15,243,416. This control precedes the
final cold quota/gas eligibility filter; that filter and the production-clean
source subsequently pass the witness and exact-parent whole-DOOM checks.

The final production-clean exact-parent comparison shows 19.96825 -> 18.17975 ms
JIT tick (-8.96%), but interpreted tick also changes 26.09375 -> 24.59825 ms
(-5.73%). The larger cross-binary improvement cannot all be attributed to this
loop. Use the same-binary result for local attribution. No init improvement is
established by the isolated control.

## Linux ARM verdict: preserve in draft

[Focused run 41271378548](https://github.com/jacogr/ragnarok/actions/runs/41271378548)
passes native correctness/refusal qualification and complete application checks.
It binds implementation `058fe1db2ff70100b2e81b919df084407bb94204` to accepted
baseline `a0997ac1469113ba1f65b4f4bdde9c9462cf138e`. Subsequent fixture-only and
whitespace-only review fixes do not change measured runtime behavior; the updated
smoke check and fresh local native witness pass.

Six fresh processes per role/case retain thirteen checked calls with three
warmups excluded. Medians across process medians are:

| Case | Previous JIT CPU | Candidate JIT CPU | Change | Paired direction |
| --- | ---: | ---: | ---: | --- |
| DOOM tick | 27.755056 ms | 28.509064 ms | +2.717% | all six slower |
| DOOM init | 233.923802 ms | 234.077540 ms | +0.066% | mixed |
| Pinky | 81.261468 ms | 81.536050 ms | +0.338% | all six slower |
| Minimal | 5.317780 ms | 5.322862 ms | +0.096% | mixed |
| Long sieve | 282.756936 ms | 271.891332 ms | -3.843% | all six faster |

DOOM tick paired changes are +2.676%, +2.790%, +2.171%, +2.645%, +3.145% and
+2.651%. The forward/reverse complete public timings also regress:
27.715/27.645 -> 28.411/28.478 ms. Candidate / PolkaVM-interpreted call is
0.709/0.709 against reference 40.065/40.150 ms. Candidate interpreter call is
32.654/32.522 ms. These reference ratios use the ordinary forward/reverse
cohort; the six-process replay cohort separately establishes the regression.

DOOM tick still captures the mechanism: publications 910 -> 911, native calls
16,066,627 -> 15,243,416, lowered operations 152,738,024 -> 155,233,223, emitted
bytes 175,428 -> 176,072. Long sieve, Pinky and init retain identical native
publication/call/operation/code-byte counts across roles. Their timing changes
are not evidence of new loop activity. No cause for the architecture-dependent
performance difference is established.

The application receipt SHA-256 is
`3e514dc089e86111dc9aaddfc97fb3bb573dfd0b2414be09c14d18be7c86d7a3`.
Raw evidence is preserved under `build/pvm-byte-loop/linux/tests/`, including
`pvm-native/results.json` and `pvm-arm64-applications/results.json`/`summary.md`.
The artifact is `pvm-comparison-arm64-1` on the linked run.

DOOM is the primary real workload, so the sieve result does not justify merging
this candidate. Keep the PR draft without readiness labels or extra CI. Reuse
the guard/literal-test machinery only with new measurements. A focused future
diagnosis should isolate same-image Linux cache on/off and the shared dirty-loop
handoff cost before crediting a narrower instruction-count improvement.

The next general architecture target is the mixed32/64-bit memory region with
20 checked sites and 45.523% of checked-memory attempts. A bounded mixed-memory
source block needs a paid interior continuation that preserves earlier committed
stores on decline. It should start from accepted master and qualify independently,
without depending on this held candidate.
