# Resident ARM memory cycles

The linked memory cycle keeps the prefix, dirty loop and read tail in native control, but each
fragment loads and publishes guest registers separately. This change shares the existing dirty
and direct-read lowering cores, then composes them with the prefix in one resident-register
image. Standalone publishers continue to use the same cores with their original wrappers.

This is an ARM implementation of the existing admitted source graph, not broader guest opcode,
pricing or memory permission support. GP 0.8 remains authoritative, as pinned in
`spec/toolchain.json`; source admission and checked fallback retain their existing order.

## Source ownership and publication

The Frame reconstructs dirty and direct-read IR through the same sealed-source builders used
by their standalone publishers. The candidate owns its temporary IR sequences, source charge
coordinates and typed word-store roles. It contains no invocation pointers and never recovers
instructions from published executable memory. Those temporary sequences are released after
publication; the existing exclusive prepared owner retains its immutable arena.

The resident publisher validates the same dirty child and cached direct-read arms, plus the
candidate's exact scalar coordinates. Only a single leading direct read is eligible. Its guards
precede every read destination/suffix mutation; a general multi-read span could fail after
speculative writes and remains on the standalone path.

A larger resident image must fit the existing 1,024-word image limit, one-MiB arena and ordinary
1,023-slot ceiling, leaving the pure region's reserved slot. A rejected resident candidate leaves
publication status available so the existing smaller linked driver can publish. It does not
replace a valid entry or weaken checked fallback. The copied active-mode getter proves which
publisher actually succeeded.

Cold graph discovery is a non-inlined helper. A cheap status check while borrowing the native
owner keeps its source construction and temporary IR out of successful hot read dispatch; the
borrow ends before the helper receives the mutable Frame.

## Resident machine state

Guest slots use X4 through X16. X0 through X3 and X17 are scratch/context; platform X18 is
untouched. The driver saves X19 through X30 in its aligned 96-byte frame, retaining register/state
pointers, gas, attempts, progress counts and last-completed header in its existing saved bank.
The dirty core retains its existing caller-saved SIMD temporaries and word-store lowering.

At root entry, load the union of all segment reads and writes, including word-store roles.
Loading write-only lanes is deliberate: a zero-work or early-refusal exit may publish the final
write union, and each untouched lane must still hold its original guest value. One epilogue
publishes that write union and the fresh context. Values remain resident across the prefix,
dirty body and direct-read tail, with no child BL or intermediate guest-register publication.

The dirty core retains exact byte/word memory, alignment, permission and first-touch guards.
Only completed dirty bodies change its progress counts. A zero-body refusal keeps the prefix
as the last completed header; it must not be confused with a completed dirty header. Direct-read
refusal refunds the unstarted tail's full price/span and publishes earlier completed phases.
The original Frame adapter resumes the appropriate checked header with its exact CPU, gas,
attempt, paid and PC state. Nondefault pricing, prepaid or partial entries keep checked dispatch.

The fourteen-word invocation context remains fresh. Code, descriptors and dirty bitmap pointers
are borrowed only for the current call. Outer native calls still mean C-to-arena entries.
The dirty-entry diagnostic counts semantic entries into the dirty core, including an early
refusal, even when the core is composed without a physical BL. No outer-bridge or added guest
coverage claim follows from this register-residency change.

## Functional evidence

Private pinned-Nimony ARC/Clang ThinLTO checks retain the complete maintained ARM and forced
refusal witnesses, including the existing 7,236 memory-cycle Frame cases per mode. An additional
12,328 cases per mode cover four uses of write-only slot 12: prefix shift, prefix bound, dirty
result and signed-read result. They sweep sixteen gas values, 0..66 source attempts and prepaid
entry against independent `stepOnce`, comparing all registers, PC, gas/deficit/paid state,
remaining attempts, memory bytes/permissions and immutable source snapshots.

These programs omit the prelude store so first-touch is visible. After warming, read-only and
missing dirty memory must return after an actual native prefix, with zero completed dirty bodies,
words and tails. Exact progress deltas and the active resident getter prevent silent linked or
checked fallback from passing these controls. Fresh stream transfer is checked as well.

The remaining eleven native/refusal/ownership records, both runtime-policy suites, pricing-owner
suite and plain witness pass. Native/refused witnesses are rerun on the combined cold-discovery
variant. Literal backend tests additionally exercise the resident ABI, empty descriptors/bitmap,
zero and partial work, late read refusal after prior writes, pure-region coexistence, write-only
lanes, actual word groups and resident-size refusal followed by successful linked publication.
The resident backend receipt is 47 native / 3 forced-refusal cases; the Frame receipt is
12,328 in each mode, with zero receipts in a plain build. All 16 mocked qualification tests
cover complete, missing, truncated and duplicate receipts independently in every mode.

Eight canonical application images pass four independent duplicate-image controls. One complete
unclocked DOOM call passes all application CPU/page/source/event checks. A separate diagnostic
image proves actual resident prefix, dirty, read and word work, with native work/code identical
to the untouched performance image. Its 923 publications, 845,196 outer calls and 13,454,725 guest
operations match the linked baseline; code grows from 200,676 to 201,556 bytes, an 880-byte cost.

## Local ARM application evidence

The baseline is merged master `ba98b8db2811510aa5a13488d30ece8bb7eb84ba`. The Apple M1 Max uses
pinned Nimony `63fed6cb`, checked ARC and Clang ThinLTO. Four balanced fresh processes per source
role execute thirteen complete-state public calls; each process contributes its CPU median over
samples 3:13. Two PolkaVM interpreted processes provide the raw denominator. The combined source
includes register residency and outlined cold discovery; do not attribute its change to either
component alone.

| Workload/backend | Baseline CPU ms | Candidate CPU ms | Change |
|---|---:|---:|---:|
| DOOM tick JIT | 14.124 | 13.961 | -1.15% |
| DOOM tick interpreter | 22.996 | 22.480 | -2.25% |
| DOOM init JIT | 114.893 | 114.877 | -0.01% |
| DOOM init interpreter | 242.109 | 239.354 | -1.14% |
| Minimal JIT | 4.058 | 4.078 | +0.49% |
| Pinky JIT | 63.650 | 63.745 | +0.15% |
| Memset JIT | 2.481 | 2.476 | -0.19% |
| Sieve 10m JIT | 198.630 | 202.174 | +1.78% |

DOOM tick improves in all four pairs with nonoverlapping ranges. Minimal and sieve are slower
in all four, also with nonoverlapping ranges: retain both costs. JIT init, Pinky and memset have
overlapping ranges; three init/Pinky pairs are slower and two memset pairs improve. Interpreted
tick improves in three pairs and init in all four; both source ranges overlap.
No causal attribution for interpreted changes is established.

Matched raw DOOM tick ratios, ours / PolkaVM interpreted, are **0.323 JIT / 0.520 interpreter**;
init is **0.167 / 0.348**. All 76 process logs strictly reparse. Native guest work and outer entry
counts match the baseline; only tick's resident image adds 880 bytes. Other application code
footprints match, within-role activity/code is deterministic, and interpreted native counters
remain zero. No x86 or full-block throughput claim follows.

The earlier resident-only eighteen-process tick screen is separately retained: JIT -1.31%, but
only two of four pairs improved with overlapping/bimodal ranges. Outline-only cohorts also remain
separate and mixed. None is substituted for the combined source's broader cohort.

Ignored evidence: `build/pvm-resident-memory-cycle/` and `build/pvm-resident-outlined/`. Combined
Frame SHA-256: `efa3c90c2099de37c56208773b702b3486c7e34bd15691cdd36282bc63a456d1`.
Backend SHA-256: `3532ea5cbc8bbd023ee898efe94fcef66e028f0584e49c3ae3bc6b79c6d15403`.
Combined raw SHA-256: `137d6eb6b6e4153d1135c3a9b4de096e94d3941695ddb99cc93d07961e2c8165`.
Resident-only raw SHA-256: `078a2f18a6217c41439c035bd8b82e3f0c0ce9e644a6715c91893399a2bbbc5c`.

The exact promoted source qualification and focused Linux ARM evidence are recorded below.
The local prototype cohorts retain their separate source and process identities.


## Exact Linux ARM qualification

[Focused ARM run 41345118553](https://github.com/jacogr/ragnarok/actions/runs/41345118553) passes
at runtime/test/controller head `678e8010e43aee1d103fccd617d72c6aee49b793`, against merged parent
`ba98b8db2811510aa5a13488d30ece8bb7eb84ba`, with interpreted pairing enabled and no broad CI
labels. Exact-head Smoke passes as well. Subsequent evidence-only documentation preserves the
qualified runtime, test and controller files.

Each process executes thirteen complete-state public calls and contributes its CPU median over
samples 3:13. The JIT replay cohort has six fresh processes per role. The separate primary
interpreter cohort has two. Do not combine those cohorts when calculating changes or raw ratios.

| Workload / JIT replay | Baseline CPU ms | Candidate CPU ms | Change |
|---|---:|---:|---:|
| DOOM tick | 21.920 | 21.316 | -2.75% |
| DOOM init | 146.090 | 146.565 | +0.33% |
| Minimal | 5.203 | 5.258 | +1.04% |
| Pinky | 81.628 | 82.422 | +0.97% |
| Sieve 10m | 267.048 | 276.659 | +3.60% |

DOOM tick improves in all six pairs with nonoverlapping source ranges. Pinky and sieve are
slower in all six pairs, also with nonoverlapping ranges. Minimal is slower in all six with
ranges overlapping; init is slower in four with overlap. Retain these observed costs alongside
the real application and resident-lowering architecture gains.

The primary interpreter cohort is slower in both DOOM pairs: tick 28.110 to 28.613 ms (+1.79%)
and init 316.825 to 320.447 ms (+1.14%), each with nonoverlapping ranges. Other primary interpreter
changes are Minimal +0.09%, Pinky +2.54%, memset +0.51%, and sieve 10m +0.70%. Primary JIT memset
improves by 0.88%. These are observed timings; no causal attribution for interpreted changes is
established by the native-register-residency implementation.

Matched **primary** raw ratios, ours / PolkaVM interpreted, are **0.530 JIT / 0.714 interpreter**
for DOOM tick and **0.232 / 0.510** for init. Replay numerators are not mixed with primary
reference timings. Native guest operations, outer calls, branches and headers match the parent
in all fourteen primary comparisons; only tick adds 880 executable bytes. All within-role
activity/code fields are deterministic, including replays. There is no added-coverage or outer
bridge-count claim.

Root and independent review audits verify 84 primary and 60 replay logs, 42 positive and
96 negative controls, 18 image equalities, 24 fixture pins, 2,575 application role source hashes
and 519 native hashes. The exact native qualification retains all eleven records, both runtime
policy suites and owner move/copy-refusal checks, old backend 19/1 and Frame 7,236 receipts,
and new resident backend 47/3 and Frame 12,328 receipts per native/refused mode. All 16 mocked
controller tests, the pricing-owner suite and plain witness pass locally. Independent source,
IR/ABI/lifecycle/refusal and diagnostic review reports no correctness finding.

Artifact `13098854718`, `pvm-comparison-arm64-1`, is preserved under ignored
`build/pvm-resident-outlined/ci-arm/`. Application report SHA-256:
`eeaa806157305b3034407cf06f00c3e8557d0ad6373c9d38880443e0508a342f`.
Native report SHA-256:
`23cb46c073e9f53b0df5aa3c179589e8bd60c6c4ce40d971e237644477c6612c`.
Original ZIP SHA-256:
`13ecbce3ac5f4077fee167ad67dc6b1f2f503278c1a1fa946655096da42774bc`.
No x86 or full-block throughput claim follows.
