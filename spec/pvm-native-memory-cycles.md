# Native memory cycles

## Execution and ownership boundary

One source-shaped ARM driver connects a complete pure prefix, an existing dirty self-loop and
an existing absolute-read/conditional tail. The prefix ends in the already-cached explicit
fallthrough instruction. The dirty child's other arm reaches the tail; one sealed tail arm
returns to the prefix and the other leaves all three blocks. Admission uses decoded facts,
complete source spans, cached targets and the exact exclusive plan/JIT owner. No guest PC is an
admission rule. Default pricing, unpaid entry and an absent partial-budget barrier are required.

The prefix is emitted in full through the existing arithmetic builder. Its explicit fallthrough
counts as a completed source operation. The existing dirty and read-tail images remain immutable
and are called with same-arena relative `BL` instructions. The dirty child's four-byte lowering
and its permission/dirty guards remain unchanged. The prefix and tail source spans include folded
no-ops; native operation counts and source-attempt spans remain distinct.

A fresh fourteen-word context borrows only this invocation's register file, three descriptors
and dirty bitmap. Its first eight words retain the dirty-child ABI; other words hold completed
block/word/child counts and the last completed header. The driver preserves X19–X30 in an aligned
96-byte frame; children use caller-saved registers. It changes X1 from dirty context to read
descriptors for each child. No invocation pointer or memory content is retained in a cache/image.

## Gas, attempts and exact fallback

At prefix/tail entry, zero attempts wins first; otherwise gas insufficiency precedes partial-span
fallback. A complete prefix reserves its full price/span and executes atomically. The dirty child
reserves its own source bodies, including word groups, without a second driver charge.

A dirty guard returns its original unstarted header with prior complete blocks committed. A read
child's refusal guarantees no guest mutation: the driver refunds only that unstarted tail's
price/span and returns its original header. Checked execution then owns the exact fault/panic/paid
state. Read content is fetched on every visit, including when it aliases bytes just stored.

The adapter validates returned targets, monotone gas/attempts and exact weighted source/price
conservation. It records the last completed header for the existing deferred reservation endpoint,
clears paid state only at complete boundaries, and resumes saved checked workers on zero, partial,
paid, pricing or memory refusal. No source check, assertion or bound is disabled. GP 0.8.0 and the
existing PVM memory/exit contracts remain authoritative; compiler and specification pins are fixed.

## Publication, limits and counters

Published children belong to one exclusive arena. Successful appends, including RET, advance both
`codeBytes` and arena usage by the same bytes. The driver computes bounded signed aligned calls
against its planned append offset. The publisher validates the returned offset before replacing
an executable record. Unused appended bytes still consume the existing quota on a mismatch;
previously valid entries remain intact. No child image is rewritten.

The driver uses the ordinary 1,023-slot ceiling, preserving the separate pure region's reserved
1,024th slot and the existing 1 MiB arena. Source/child prerequisites can remain retryable; once
emission begins, oversized/link/publication failures are sticky to bound repeated compiler work.
The new cache is scalar metadata appended after the old JIT fields. Existing ARC ownership and
retirement apply without a new foreign resource. The idle memory-lease payload policy is unchanged.

Public native calls count outer C-to-arena entries. Nested dirty-child calls, bodies and word
groups remain separately visible; native operations include the newly lowered complete prefix.
Cross-source call/operation/code-byte equality is therefore not expected. Fresh processes within
each source role must retain identical activity and footprint. Forced interpretation retains zero
native counters.

## Local correctness evidence

The formatted prototype passes eleven maintained native/refusal/ownership qualification records.
The promoted witness retains all old controls and adds 7,236 full CPU/PC/gas/deficit/paid/attempt/
memory/source comparisons in both native and forced-refusal builds. These include complete 4/5/4
boundary sweeps, an internal folded prefix no-op, sixteen gas values, prepaid entry, a signed read
of newly stored bytes, an unmapped
tail after committed word stores, fresh descriptors, owner transfer and a similar ineligible graph.
The refusal case additionally proves one native prefix/child, four dirty bodies and a word group
completed while zero tail visits committed. Independent literal backend controls cover same-owner
pure-region coexistence, empty descriptors/bitmap, zero work, cleanup, capacity, expected-offset
mismatch and sticky oversized emission refusal.

Eligible graphs additionally select fresh complete and lazy pricing owners before restoring a
warmed default-native stream; full-state parity and zero driver activity are required.

The promoted source additionally retains repaired-master cache ownership and pricing-selection
contracts. The promoted-source qualification and focused Linux evidence are recorded below; the local
prototype measurements retain their separate source identity.

## Local ARM application evidence

The prototype compares frozen runtime `6c39d0f639ecff3bad12686407e92e09ebfc24f4` with two private
module overlays. Apple M1 Max uses pinned Nimony `63fed6cb`, checked ARC and Clang ThinLTO.
Eight canonical-path application images pass four fresh duplicate-image controls. Each source
role has four balanced fresh processes, thirteen complete-state public calls per process, and
CPU medians over samples 3:13. Two PolkaVM interpreted processes supply the raw denominator.

| Workload/backend | Baseline CPU ms | Candidate CPU ms | Change |
|---|---:|---:|---:|
| DOOM init JIT | 114.642 | 114.852 | +0.18% |
| DOOM init interpreter | 239.018 | 242.663 | +1.52% |
| DOOM tick JIT | 16.085 | 14.123 | -12.19% |
| DOOM tick interpreter | 22.745 | 22.941 | +0.86% |
| Minimal JIT | 4.074 | 4.077 | +0.07% |
| Pinky JIT | 63.699 | 63.664 | -0.05% |
| Memset JIT | 2.485 | 2.473 | -0.49% |
| Sieve 10m JIT | 199.560 | 200.435 | +0.44% |

All four JIT tick pairs improve with nonoverlapping ranges. Interpreter init is slower in all
four pairs with nonoverlapping ranges: retain this observed cost. Interpreter tick has three
slower pairs with overlapping ranges. Other JIT ranges overlap; minimal and Pinky are flat,
memset improves in three pairs and sieve is slower in three. No causal layout attribution is
established. Matched raw DOOM tick ratios, ours / PolkaVM interpreted, are **0.326 JIT / 0.529
interpreter**; init is **0.167 / 0.352**. No x86 or full-block throughput claim follows.

The separate initial tick screen showed JIT -11.35% and interpreter +0.05%. Both cohorts remain
separate; all 94 process logs strictly reparse with identical native activity/code within source
roles and zero interpreted counters. One unclocked complete-state DOOM call reduces C-to-arena
entries from **1,228,661 to 845,196** while native guest work rises from **12,430,817 to 13,454,725**.
It adds one publication and 504 bytes, from 200,172 to 200,676 bytes in that cold call. The coverage
change is intentional and does not replace complete CPU/page/source/event validation.

Ignored evidence: `build/pvm-native-memory-chain/`, including source freezes, native/GP controls,
`final-qualification/results.json`, `application-build.json`, both raw cohorts and strict reparse.
Initial tick raw SHA-256:
`53702f61edf9d44e9d8819526839653ea607e22ad7e10157b6046225115e331a`.
Broader raw SHA-256:
`805332859e70ce4fd2e465f2dd2634977ca0f04d8c0da8b94d28f86c9d60a898`.


## Promoted Linux ARM qualification

[Focused ARM run 41337664624](https://github.com/jacogr/ragnarok/actions/runs/41337664624) passes
at runtime/test/controller head `e38fa0ab2c56ea18f565eca2c36b55ea823809e1`, against merged parent
`7cc87ed192c78d0af28b70eef0eea87dc34a20c3`, with interpreted pairing enabled and no broad CI
labels. The automatic [Smoke run 41337592297](https://github.com/jacogr/ragnarok/actions/runs/41337592297)
also passes. Evidence-only documentation updates preserve those qualified runtime identities.

Each application process contains thirteen complete-state public calls; CPU process medians use
samples 3:13. The JIT replay cohort contains six fresh processes per source role. The separate
primary interpreter cohort contains two per role. Keep these cohorts separate.

| Workload / JIT replay | Baseline CPU ms | Candidate CPU ms | Change |
|---|---:|---:|---:|
| DOOM tick | 23.719 | 21.639 | -8.77% |
| DOOM init | 145.724 | 145.126 | -0.41% |
| Minimal | 5.274 | 5.260 | -0.26% |
| Pinky | 81.235 | 81.616 | +0.47% |
| Sieve 10m | 271.312 | 266.856 | -1.64% |

DOOM tick and sieve improve in all six pairs with nonoverlapping ranges. Pinky is slower in all
six pairs with nonoverlapping ranges: retain that cost. Init improves in all six pairs with
source ranges overlapping; minimal improves in four, also with overlap. Primary memset changes
by -0.14% JIT / -0.48% interpreter. Primary interpreted DOOM tick changes from 28.672 to 27.780 ms
(-3.11%, both pairs faster), and init by -0.38%. No cause for interpreted timing changes is
established by this native-only implementation.

Matched **primary** raw DOOM ratios, ours / PolkaVM interpreted, are **0.541 JIT / 0.693
interpreter** for tick and **0.233 / 0.509** for init. These numerators and denominators belong
to the same primary cohort; replay timings are not mixed into raw ratios.

Across the thirteen tick calls, outer native entries change from 15,973,728 to 10,988,287;
native guest operations rise from 161,636,087 to 174,947,995. Publications change from 996 to
997 and code from 223,884 to 224,388 bytes. This intentional added prefix coverage is distinct
from a semantic mismatch. Every native activity/code field is deterministic within its source
role, including all replays; interpreted native counters remain zero.

Independent audits verify all 144 primary/replay process logs, 42 positive and 96 negative
controls, 18 image equalities, 24 fixture identities, all 2,575 application role source hashes
and 519 native hashes. The native gate retains eleven verification records, both pricing-policy
suites and move/copy refusal checks; new backend receipts are 19 native / 1 forced-refusal and
Frame controls are 7,236 in each mode. The 15 affected mocked receipt tests pass as well.

Artifact `13096671553`, `pvm-comparison-arm64-1`, is preserved in ignored
`build/pvm-native-memory-chain/ci-arm/`. Application report SHA-256:
`b1ca3214eab6bd61b802dd59830722d3954c20da0173b18b0a8015462f3ff6dd`.
Native report SHA-256:
`ce730c7eeec79893e533f71ae1c5d0d3e214435accf28350a0a1a94a799e8fca`.
Original ZIP SHA-256:
`2561deea39eefffc01c8964098ea50ef26e1e1304fdc18ef10e71feef3fb71a0`.
No x86 or full-block throughput claim follows.
