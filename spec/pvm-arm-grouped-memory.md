# ARM64 grouped memory and paid continuation

**Qualified architectural candidate.** The paid-continuation and publication-proof
changes pass local and Linux correctness qualification. Reusing the certified
branch targets reduces the Linux DOOM cost from 4.23% to 1.42% against the accepted
parent. That residual cost is repeatable, not flat; minimal/Pinky also regress,
while long sieve improves. The reviewed net decision is to carry the architectural
foundation forward with these costs explicit. Final review/readiness is recorded
on the PR; later tuning is separate from correctness qualification.

## Scope and authority

Accepted parent: `a0997ac1469113ba1f65b4f4bdde9c9462cf138e`. GP0.8.0 and the
existing memory-ordering, gas and source-attempt contracts remain authoritative.
Pinned Nimony `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`, ARC, checked release,
Clang and ThinLTO remain unchanged. The held byte-loop PR1877 is not a dependency.
Public defaults and x86 lowering are unchanged.

An opt-in ARM body covers one complete charged source suffix, bounded to16 source
operations/16 memory operations, ending in a positively cached conditional.
Interiors contain indirect memory opcodes120–130 and supported pure arithmetic.
Hosts, dynamic jumps and unsupported instructions retain accepted workers.
At least one load, store and shared window are required. A zero-window candidate
keeps accepted execution.

Header discovery checks the ordinary charge handler, exact sealed source span
and ordered emitted facts. Folded opcode2 consumes source attempts without an
executable node. A mixed-specific probe initializes only nonexecutable records,
including earlier ordinary refusal, and preserves unavailable-storage and
262,144-coordinate bounds. Eight eligible unpaid, full-gas/full-budget visits
after branch certification justify publication. These are visits, not a claimed
count of observed backedges. Priced frames skip mixed discovery. A retained
unpriced probe retires on a priced invocation instead of remaining permanently
ineligible for promotion.

## Execution and ownership

Canonical `flatReserve` charges gas and reserves the full source span before
native entry. Partial budgets, insufficient gas, barriers and prepaid entry use
the original header. Native code does not manage gas or quota.

The ordinary five-word context contains exit kind, descriptor pointer, bitmap
word count, bitmap pointer and completed lowered operations. Kind1 completes
the conditional, returns a certified target and clears paid state. Kind2 returns
the exact first unexecuted memory operation, publishing only completed-prefix
register writes. Its wrapper retains paid state/tagged reservation and invokes
the sealed fact's canonical one-operation worker. Earlier stores are never
replayed. Existing attempted-exit refund restores only the unattempted tail.

Prefix masks precede the current load's write registration. A later failed load
to an already-written destination retains the earlier value. Future writes and
uninitialized physical registers never spill. Constant prefix counts in exit
stubs avoid per-operation runtime accounting. Only referenced guard exits are
emitted; later members of a shared window need no paid-exit stub.

Cold planning records every write event, including repeated assignments. Up to
two groups each contain at least two accesses through a base unchanged between
first and last access. The first member proves a nonwrapping bounded window,
canonical address range and complete descriptor. Descriptor `len-7` is checked
before span subtraction. Write groups additionally require a writable window
within one already-dirty guest page. Failure returns to that first operation;
checked execution determines later faults in source order.

Pointers occupy distinct x4–x16 lanes absent from all source operands, including
branch operands. Cache writes never enter guest spill masks. Loads/stores retain
their original order and alias behavior. Ungroupable accesses within a grouped
body retain individual guards; wide stores prove every touched dirty-page bit.

No invocation pointer is retained. Arena ownership, twelve-byte entry records,
one-MiB storage and ordinary1,023-publication ceiling stay unchanged; connected
execution keeps its reserved slot. Oversized emission refuses normally. Optional
receipt builds add two instrumentation lanes; those lanes and updates compile
out of ordinary timing builds. No runtime attribution switch is preserved.

## Verification

The original published source passes native, forced-storage-refusal and
interpreted witnesses locally. After review fixes, ordinary and receipt-instrumented
native witnesses pass. A new active-probe receipt reproduces the priced admission
bug before the fix, then verifies fresh and retained-stream complete/lazy priced
execution installs or retains no observer; eligible unpriced work is its positive
control. These cases also run under the existing CI owner-receipt mode, without
an additional test lane. The
original ARM witness remains intact. Added literal/checked-machine cases cover:

- Aliasing store/read/store, unused guest-slot preservation and repeated base
  writes that must refuse grouping.
- Earlier native stores surviving a later group decline; future invalid memory
  returning to the first group operation without an early guest fault.
- Clean/read-only/missing pages, page63→64 bitmap-word boundary, and short
  descriptors refusing without subtraction underflow.
- Mapped highest-page accesses at0xfffffff8, with the store page predirtied so
  it exercises the address guard. Reserved-byte access produces Panic/PC0.
- Leading-noop14-operation/10-memory execution, two published windows and exact
  paid/gas/partial-budget accounting.
- A source-built15-memory body emitting1,046 ordinary words after exit compaction, refusing publication
  above the existing limit and retaining checked behavior.

## Historical measurement record

The baseline census has10,122,320 checked memory attempts over ten DOOM ticks;
twenty sites account for45.523%. The11-operation/eight-memory block has stable
132-byte and32-byte windows. The preserved extension also admits the audited
14-operation/10-memory block. Corrected untimed13-call validation confirms both
windows publish and DOOM output matches. The extension records102 windows,
2,820,537 attempts and2,753,789 passes. Census byte PCs are `fact.pc`, not
`f.sites` instruction ordinals; production admission contains no guest PC.

Comparisons fix input, compiler and flags and use one canonical source/output/
cache coordinate, saving binaries after builds. Earlier per-operation-body,
bitmap, borrow and admission variants remain preserved with their losing or weak
receipts. Removing a proven retain/release cost did not improve timing.

The best cross-binary screen appeared about1.2–1.4% faster. A final private
same-executable preparation-only on/off comparison does not attribute that gain:

| DOOM tick, same executable | Mixed off | Mixed on |
| --- | ---: | ---: |
| Mean of six steady process medians | 18.6343 ms | 18.6555 ms |
| Median of six steady process medians | 18.5605 ms | 18.6270 ms |

Each process runs13 fully checked calls, excluding samples0–2. Three balanced
ABBA changes are -0.493%, +0.622% and +0.221%; overall mean change is+0.114%.
The same-image interpreted control validates output at24.76ms with zero native
activity. All runs match DOOM output.

Off mode exactly matches accepted activity:910 fragments/16,066,627 native calls/
152,738,024 lowered operations/175,428 bytes. On mode records954 fragments/
15,854,488 calls/158,456,891 operations/206,428 bytes, including1,599,740 mixed
calls,1,566,389 complete bodies and33,351 declines. More native coverage and
fewer transitions did not demonstrate a CPU gain.

The preserved extension also screens flat/slower:18.4795/18.5125ms flanking
baselines versus18.586ms candidate. It is distinct from the final on/off
experiment's16-source/8-memory policy; the draft includes its tested16-memory/
folded-noop/resource-refusal machinery for reuse.

Attribution executable SHA-256:
`81a48b05f2e23dd76978d24f9f5762aeb42621e04cd8280b9baebeb117fc9d93`.
Input SHA-256:
`574821fb1c5f9dc94cae96a28859f513128233e9a3a8833e7ad201b135d8653e`.
The private attribution switch is absent from this draft. Full per-sample data
and identities are in ignored
`build/pvm-mixed-memory/evidence/attribution-summary.json`; peer preservation
manifests bind both ordinary source variants to final-source witness logs.

## Exact published-source reassessment

The following local M1 results compare published head
`a18bb78a6a2f7eb0c8045c21057d4d7ffaac59a8` with accepted parent `a0997ac1`,
before the priced-probe fix and exit compaction. Eight canonical-path images
cover both sources, two drivers and native/interpreted modes. Interpreted role
images are byte-identical. All88 timed processes pass full fixture validation;
each has13 calls, excluding the first3 from steady medians. Negative is faster.

| Workload | Initial two orders | Two ABBA repeat cycles |
| --- | ---: | ---: |
| Sieve100k | +1.34% / +2.45% | not repeated |
| Sieve10m | +2.19% / +3.61% | +1.15% / +1.52% |
| Minimal | +6.41% / +6.94% | +6.92% / +7.48% |
| Memset | +1.48% / +0.49% | not repeated |
| Pinky | +6.42% / +3.96% | +4.56% / +3.74% |
| DOOM init | -0.30% / -0.54% | not repeated |
| DOOM tick | -3.51% / -4.46% | -4.44% / -3.95% |

Separate diagnostic runs confirm grouped code executes in the regressing
workloads. This is broader lowering, not replacement of the one-store dirty-loop
or direct-read-first specialization; it can subsume existing pure/branch body
fragments. Aggregate activity cannot isolate every displaced fragment or global
code-layout effects. These are local results, not Linux evidence or a measured
ours/PolkaVM-interpreted ratio.

Evidence is preserved in ignored `build/pvm-mixed-memory/evidence/reassessment/`:
`results.json` (56 processes), `repeat.json` (32 processes), `activity.json` and
`summary.md`, copied from the speed peer's exact-head screen. Reviewed follow-up
changes need their own source-identified timing. Keep draft pending that
qualification. Review found no further memory/accounting/pointer-lifetime defect;
shared opcode/table lowering remains a possible maintenance simplification.
The architectural benefit does not erase measured costs, and future multi-block
resident execution still needs charging/exit/register-liveness integration.


## Reviewed-runtime follow-up

Exact corrected runtime `f0ce1d010091e02cf09e1883f80b65c90e8680f9` was compared
with the same accepted a099 images: four workloads, two balanced ABBA cycles,
32 native processes with13 complete-state-checked calls each. All pass.

| Workload | Candidate CPU change, cycle0 /1 | Emitted bytes, a18 / f0 |
| --- | ---: | ---: |
| Sieve10m | +1.04% / +0.97% | 469,016 / 457,376 |
| Minimal | +5.92% / +3.83% | 2,704 / 2,592 |
| Pinky | +3.89% / +3.68% | 229,920 / 221,088 |
| DOOM tick | -4.54% / -4.37% | 231,692 / 223,956 |

Fragment/call/lowered-operation/branch/header counters match a18 for these
workloads. Exit compaction reduces code size without removing measured work.
The local DOOM improvement and smaller-workload regressions persist; neither
should be hidden by the architectural case. Raw evidence is preserved under
`build/pvm-mixed-memory/evidence/reassessment/followup-f0ce1d01/`. One focused
Linux ARM replay run completed for this runtime; its results are recorded below.
No broad CI labels were requested.
A follow-up enabling the same admission checks in the existing ordinary CI
witness receipt changes diagnostic coverage only, not the timing configuration.


## Linux ARM qualification and performance hold

[Run 41282897012](https://github.com/jacogr/ragnarok/actions/runs/41282897012)
qualifies runtime f0 against a099 with the pinned checked ARC/Clang ThinLTO toolchain.
All 20 builds, 84 primary processes, 138 controls and 60 fresh-process replays pass.
The owner and reviewer independently verified artifact 13073778241 ZIP digest:
`8fb78a5cc1993343867bf5d2978aa104dbb2990dd16b6fd69d8ffeab9a843672`.
Full evidence is retained under ignored `build/pvm-mixed-memory/ci-41282897012/`.

Each replay role/case has six fresh processes with 13 checked calls each. The first
three calls are warmup; values below are medians across steady process medians.

| Workload | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| DOOM tick | 27.915406 | 29.094872 | +4.23% |
| DOOM init | 235.105442 | 236.634450 | +0.65% |
| Minimal | 5.309608 | 5.887812 | +10.89% |
| Pinky | 81.265020 | 87.799760 | +8.04% |
| Sieve10m | 282.814182 | 272.973038 | -3.48% |

DOOM tick candidate processes span 28.916744–29.125268ms, entirely above parent
27.820040–28.037060ms. Primary forward/reverse public native tick is 29.111/29.105ms
versus 27.981/27.991ms parent; the raw ours/PolkaVM-interpreted ratio is 0.727/0.725.
These public calls include invocation memory and immutable publication. Reference
raw calls and separately reported invocation lifecycle retain their distinct
accounting; retained-core reset/call values are not public-call ratios.

Additional coverage does not uniformly reduce transitions. Pinky native calls
grow 38,430,574→45,188,334. Minimal retains 1,300,039calls but adds mixed whole-header
work. DOOM native calls fall 16,066,627→15,973,728 while code grows 175,428→223,956bytes.
These are activity receipts, not proof of the causal CPU cost. Readiness remains
on hold while one isolated experiment tests repeated post-publication branch
certification; no CPU improvement is inferred from activity counts alone. No additional CI
was requested for this verdict update. The existing paid continuation, alias, resource and
source-accounting correctness findings remain positive.


## Reuse the publication certificate at promoted entry

`flatArmMixed` now relies on its publication-time branch certificate, matching
the existing pure whole-block path. Both conditional arms were resolved before
publication. Later fusion changes preceding nodes, not the terminal. Temporary
budget patching always sets the checked barrier and is restored at run exit;
the mixed worker's existing barrier guard excludes it. Stream reuse moves the
cache and source-bound offsets together only for the exact immutable plan. No
callback or source mutation occurs during native execution. Probe/publication
checks and gas, quota, paid continuation, target and completed-count validation
remain unchanged.

A private same-executable experiment includes both original and certified workers;
an immutable startup choice selects the worker only during cold publication.
There is no hot mode field/flag or native-emitter change. Both modes pass ordinary
and instrumented witnesses with byte-identical output. Balanced and repeated local
ARM comparisons attribute improvements of5.64%minimal,3.90%Pinky and2.14%DOOMtick
to omitting the hot recheck. Long sieve is flat(+0.03%). Native activity fields
match, excluding compilation time. An earlier cross-image long-sieve5%regression
is not reproduced within one image, demonstrating the importance of the control.

Guest binary SHA-256:
`927cb7eadac1475273046ad6690f276d061beaf10777bee694868cffb63784fc`.
DOOM binary SHA-256:
`0fa536b28ae2bc575b6c34d3c046fdf3932560ecb0250ec5eaca381d3d788584`.
Raw result SHA-256:
`fe44fefcb227e782ce394b2f08d17facd7137c6eb24c8343afd64fb34a9d37b3`.
Evidence is preserved under ignored
`build/pvm-mixed-memory/evidence/same-image-certificate-7bd/`. The private startup
switch and duplicate worker are not shipped. This is isolated local attribution,
not Linux qualification of the new candidate; the prior performance hold stands
until the updated runtime is qualified, as recorded below.


## Updated Linux qualification and net tradeoff

[Run 41285448250](https://github.com/jacogr/ragnarok/actions/runs/41285448250)
qualifies exact runtime a3bc509341ad25dce54ab1ea12495532d8713f9b against a099. All
20 builds, 84 primary processes, 138 controls and 60 fresh-process replays pass, including
the five maintained fresh/retained pricing receipts. Artifact 13075427646 ZIP
SHA-256 is `3ac1ef3ae52556cb91493a130026a6eea03b5ec200303c8ef9e75f032e9fda77`.

Replay values are medians across six steady process medians per role/case, each
from 13 checked calls with three warmups excluded. The raw reference column is
from the separate primary forward/reverse comparison: our public invocation
including memory/publication divided by PolkaVM's raw interpreted call.

| Workload | Parent ms | Candidate ms | Change | Raw ours / PolkaVM interpreted |
| --- | ---: | ---: | ---: | ---: |
| DOOM tick | 27.865870 | 28.261120 | +1.42% | 0.696 / 0.702 |
| DOOM init | 235.324036 | 231.555470 | -1.60% | 0.378 / 0.370 |
| Minimal | 5.316988 | 5.563096 | +4.63% | 1.009 / 1.020 |
| Pinky | 81.253464 | 84.088522 | +3.49% | 0.953 / 0.960 |
| Sieve10m | 282.366378 | 273.772452 | -3.04% | 0.820 / 0.821 |

Tick ranges 27.810364–27.955260ms parent and 28.147144–28.351880ms candidate do
not overlap. The smaller cost must not be described as statistical flatness.
Initialization varies more, so its favorable median is not a standalone win
claim. All primary Native activity records match f0, excluding compilation time;
the change removes repeated host-side certification rather than changing guest
coverage or native instructions. Full verified evidence is preserved under
ignored `build/pvm-mixed-memory/ci-41285448250/`.

The reviewed architectural tradeoff accepts the quantified smaller costs in
exchange for generic side-effecting Native continuation, reusable window proofs
and certificate reuse, with a stable long-sieve gain and positive local M1
evidence. The maintainer explicitly permits positive architecture/other-workload
value; no DOOM speedup is required. This decision does not erase the measured
Linux regressions or infer future speedups.

The private same-image attribution above excludes three warmups and reports mean
process medians. Using medians across those same steady process medians gives
minimal -5.75%, Pinky -3.97%, tick -2.13%, sieve +0.03%; no additional run was needed.
This isolates the hot-check cost but remains distinct from shipping
source qualification and accepted-parent workload ratios.

An actual public prepared-call diagnostic identifies a next memory lead: tick
guest accesses touch 355 of 4,285 mapped pages, while one checkpoint marks 275 pages
written but only 6 net changed. Instrumented entry is about 2.15 ms; diagnostic scans
perturb caches, so this is not a timing improvement. A descriptor-only simulation
with eager backing should first test materialized-window hit/retarget behavior
before any lazy virtual backing or OS ownership change. The current native
context is borrowed at each call and only a fully materialized contiguous window
may be advertised. No lazy backing is implemented by this PR.
