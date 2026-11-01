# Native arithmetic-prefix and read spans

## Architecture and semantic boundary

ARM compilation can now compose a genuine arithmetic prefix with following direct or indirect
loads in one standalone transactional read image. The old compiler stopped its pure leaf at
the first read and considered memory fragments separately. The new cold helper uses the existing
`ArmReadSpan`, arithmetic/read emitters, register-bank bookkeeping and complete checked fallback.
It introduces no opcode evaluator, native ABI, Frame field, retained invocation pointer or
ownership hook. x86 lowering is unchanged. GP 0.8.0 remains authoritative.

The helper is considered only when the existing pure scan reaches a direct or indirect read.
It scans at most 64 physical stream nodes and requires at least four operations including a
read. Synthetic headers, source terminals, stores, hosts and unsupported operations end the
span. Folded no-ops retain their source pricing and attempt coordinates despite emitting no
physical node. Every read has its existing individual address/descriptor/extent guards; no new
shared window proof or pointer cache is introduced.

Native register changes remain speculative until every read succeeds. A guard refusal branches
past all guest-register stores, returning the unchanged input to the saved checked source worker.
That worker replays the whole original prefix, exposing the precise completed state and fault
PC. Partial attempt reservations retain their temporary source barrier and use the original
workers; paid interior entries remain addressable. Existing headers still own gas and source
attempt reservation. Branches, host effects and writes are never crossed speculatively.

The published image must fit the existing 1,024-word leaf limit including RET. A nonmutating preflight
checks ordinary publication slots and exact remaining one-MiB arena bytes, including the final
RET. The arena appends exactly four bytes per word without padding. Larger-image refusal leaves
the existing smaller pure publisher available in the same visit. The generic publisher can
also overwrite a refused `code=1` record with a successful smaller same-offset publication;
this is an existing capability, not a new bug fix. No resource ceiling is raised.

## Focused correctness evidence

The final witness adds **945 independent Step comparisons per build**: 662 prefix/read cases,
177 folded-source/64-node boundary cases and 106 cross-block charge cases. It covers write-only
slot R12, a derived address base aliased with its read destination, signed direct and indirect
loads, a missing second page, successful fragmented RO/RW reads, gas/attempt boundaries and paid
interior PCs. R0 increments exactly once on checked replay, catching premature native publication
that a constant-writing prefix could conceal. Literal signed results independently check the
full register value.

Available-native controls require two actual five-operation activations and four late-load
refusals, with exact native call/operation deltas. Four separate literal backend controls inspect
all thirteen unchanged registers immediately after native refusal, before checked replay can
hide a bad publication. A folded no-op immediately before a read preserves exact source attempt
boundaries; a 65th executable node runs separately after a 64-node native image. A jump into a
separately charged read block cannot bypass its gas or expose a read result early.

An oversized speculative read image still executes its original four-operation pure leaf.
A separate literal fills the arena so only that smaller image fits, confirms larger publication
refusal, then publishes and executes the pure image at the same offset. These tests exercise
real executable-memory capacity and source execution. They do not require a future optimizer
to retain today's admission choices.

All full plain/native/forced-refusal witnesses pass on frozen source. The controller requires
exactly one complete receipt for every frame/source/charge/activation/refusal/rollback/size/
capacity group. Valid Python transcripts and independent missing/truncated/duplicate negatives
for all three modes are included with the runtime change.

## Local ARM application evidence, 2026-11-01 UTC

Canonical baseline runtime is `5edcbfabbadc1bc9a732b6fe948443933b2a1796`, whose final spec-only
head `72ae09aa5425d19571a7f51be4d6c0c5561c772b` was squash merged as master
`b5898e247337a30d6c2cc7311e07c725c9cafc31`. Those parent forms have identical runtime, tests and
controllers. Apple M1 Max uses pinned checked Nimony `63fed6cb`, ARC and Clang ThinLTO, with
bounds checks enabled.

Eight fresh application builds on the same canonical source paths pass four duplicate-image
controls. Four balanced fresh processes per source/backend each execute thirteen complete-state
public calls. Process values are CPU medians of samples 3:13; table values take the median across
four processes. Two matched PolkaVM interpreted reference processes supply each raw denominator.
Lifecycle restoration remains inside collection. Complete CPU/pages/source/events are validated
for every call.

| Workload/backend | Baseline CPU ms | Candidate CPU ms | Change |
|---|---:|---:|---:|
| DOOM init JIT | 112.770 | 112.913 | +0.13% |
| DOOM tick JIT | 13.803 | 13.704 | -0.71% |
| Minimal JIT | 4.071 | 4.071 | 0.00% |
| Pinky JIT | 63.012 | 60.376 | -4.18% |
| Memset JIT | 2.496 | 2.483 | -0.51% |
| Sieve 10m JIT | 196.408 | 187.380 | -4.60% |
| DOOM init interpreter | 239.365 | 242.077 | +1.13% |
| DOOM tick interpreter | 22.380 | 22.473 | +0.42% |
| Minimal interpreter | 4.540 | 4.503 | -0.81% |
| Pinky interpreter | 79.209 | 79.291 | +0.10% |
| Memset interpreter | 3.704 | 3.699 | -0.11% |
| Sieve 10m interpreter | 327.976 | 327.840 | -0.04% |

Pinky and Sieve JIT improve in all four pairs with nonoverlapping ranges. JIT tick improves in
three of four pairs but overlaps because of a candidate outlier; memset improves in all four
but overlaps. JIT init has three slower pairs and overlapping ranges; Minimal is flat with mixed
pairs. Interpreter init is all four slower with overlap, retaining an observed cost. Interpreter
tick, Pinky, Minimal and memset have mixed pairs/overlap; interpreter Sieve improves in all four
but overlaps. No general interpreter benefit is attributed to the native compiler change.

The separate initial 36-process DOOM gate shows JIT tick -0.75%, all four faster/nonoverlapping,
but JIT init +0.71%, all four slower/nonoverlapping. Interpreter init is +1.42%, all four slower/
nonoverlapping; tick is +0.25%, three slower with overlap. The initial and broader cohorts remain
separate. Init costs and the weaker broader tick distribution are not replaced with the stronger
initial tick result.

Matched broader raw ratios, ours / PolkaVM interpreted, are **0.317 JIT / 0.519 interpreter** for
DOOM tick and **0.164 / 0.352** for init. These are local application measurements, not portable
or full-block throughput claims.

## Linux ARM qualification, 2026-11-01 UTC

[Focused ARM run 41361031150](https://github.com/jacogr/ragnarok/actions/runs/41361031150)
passes on exact runtime head `0d64aee296d5078aa64707207f924e70d71509b3`, compared with
master `b5898e247337a30d6c2cc7311e07c725c9cafc31`. It uses the explicit checked-interpreter
pair, thirteen-call protocol and pinned toolchain above. Smoke also passes. No broad CI suite
was dispatched.

The five JIT rows below use **six balanced process replays per source**. Each process value is
the CPU median of samples 3:13; the table takes the median across six processes. The DOOM and
Minimal ranges overlap despite every paired candidate being faster. Pinky and Sieve have
nonoverlapping ranges in all six comparisons.

| JIT workload | Baseline CPU ms | Candidate CPU ms | Change | Paired result |
|---|---:|---:|---:|---|
| DOOM init | 142.816 | 141.000 | -1.27% | 6/6 faster; overlapping ranges |
| DOOM tick | 20.795 | 20.677 | -0.57% | 6/6 faster; overlapping ranges |
| Minimal | 5.327 | 5.272 | -1.03% | 6/6 faster; overlapping ranges |
| Pinky | 80.978 | 78.541 | -3.01% | 6/6 faster; nonoverlapping ranges |
| Sieve 10m | 277.267 | 253.327 | -8.63% | 6/6 faster; nonoverlapping ranges |

The **two primary process comparisons** additionally show JIT memset -0.76% and Sieve 100k
-4.17%, both pairs faster with nonoverlapping ranges. Primary JIT Minimal is -0.52% with mixed
pairs/overlap; its six-replay result above is a separate cohort. Primary JIT DOOM tick is -0.73%
and init -1.05%, both pairs faster/nonoverlapping. These stronger primary DOOM distributions
do not replace the overlapping six-replay ranges.

The checked interpreter uses **two primary process comparisons**, not six JIT replays:

| Interpreter workload | Baseline CPU ms | Candidate CPU ms | Change | Paired result |
|---|---:|---:|---:|---|
| DOOM init | 317.433 | 317.006 | -0.13% | 2/2 faster; overlapping ranges |
| DOOM tick | 27.628 | 27.942 | +1.14% | 2/2 slower; nonoverlapping ranges |
| Minimal | 5.553 | 5.485 | -1.22% | 2/2 faster; nonoverlapping ranges |
| Pinky | 86.195 | 85.424 | -0.90% | 2/2 faster; nonoverlapping ranges |
| Memset | 3.448 | 3.417 | -0.90% | 2/2 faster; nonoverlapping ranges |
| Sieve 100k | 3.096 | 3.066 | -0.96% | 2/2 faster; nonoverlapping ranges |
| Sieve 10m | 324.178 | 320.278 | -1.20% | 2/2 faster; nonoverlapping ranges |

**Interpreted DOOM tick's +1.14% is an observed cost**, in addition to the local init costs and
larger native images. The compiler change adds no new interpreter execution path; these
measurements establish neither the cause of its interpreter changes nor a general interpreter
benefit. The JIT DOOM tick result is a small improvement, while the larger Pinky/Sieve gains
are more consistent. Local and Linux directions and cohort sizes remain separately visible.

Matched **primary-only** raw ratios, ours / PolkaVM interpreted, are **0.517 JIT / 0.698
interpreter** for DOOM tick and **0.226 / 0.505** for init. Numerators and reference denominators
come from the same primary cohort; the six-replay JIT medians are not divided by a primary
reference. These do not establish x86 or full-block throughput.

The author audit strictly reparses all 144 primary/replay transcripts, checks 42 positive and
96 negative controls, the exact replay schedule, 18 fresh-image equalities, 2,575 role-source
hashes, 519 native-source hashes and all 32 fixture identity files. The latter contain the
24 official workload pins plus other fixture identities. All eleven native/refusal/ownership
records, both policy suites, move/copy controls and all eight new witness receipts pass.
Within-role work and code are deterministic across primary/replay processes; interpreter
native counters remain zero. Fourteen paired cross-source native records deliberately change
and are retained rather than asserted equal. Their warmed counters match the local ARM table
below, including all footprint growth.

Official artifact `13105379065` (`pvm-comparison-arm64-1`), ZIP SHA-256:
`465a8af50b79b7353d25308044f184f0b0f07f2784312a82981c457df3326a4f`.
Application report SHA-256:
`8f880a36b60ea183e6c487bb6be37684d677e3fe72c2c149be9b56695067460b`.
Native report SHA-256:
`a923bc7804c8a4335b86ef6c200268efe89b86306f319171fee2403abb39ee9e`.

## Coverage, transitions and footprint

Native work intentionally changes. The following counters are final prepared-owner diagnostics
after thirteen public calls, deterministic across fresh processes within each source role.

| Workload | Native calls change | Lowered operations change | Native code bytes, baseline to candidate |
|---|---:|---:|---:|
| DOOM tick | -3.68% | +0.11% | 225,268 to 253,416 (+12.50%) |
| DOOM init | -0.90% | +0.11% | 176,900 to 230,056 (+30.05%) |
| Minimal | unchanged | +26 total | 2,592 to 2,836 (+9.41%) |
| Pinky | -1.80% | +4.39% | 221,088 to 248,584 (+12.44%) |
| Memset | +52 total | +483 total | 9,416 to 12,056 (+28.04%) |
| Sieve 100k | +0.0903% | +10.48% | 455,184 to 458,540 (+0.74%) |
| Sieve 10m | +0.0074% | +10.06% | 457,300 to 460,644 (+0.73%) |

Warm DOOM tick publications rise from 997 to 1,013; init remains at 1,024 including the reserved
region slot. One separate unclocked cold DOOM tick has 923 to 953 publications and 201,556 to
230,676 code bytes (+14.45%). That initial owner state is distinct from the thirteen-call warmed
owner state. Both complete unclocked phases pass all CPU/page/source/event checks.

The benefits combine wider lowering and changed transition counts; Sieve's gain is not a bridge
reduction claim. Code footprint grows, and no RSS claim is made. All existing image/arena/slot
limits stay fixed. The broader regions trade that footprint and the measured init/interpreter
costs for fewer DOOM/Pinky entries, more lowered work and the observed workload gains.

## Qualification boundary and retained evidence

The exact final formatted promoted source passes all eleven maintained native/refusal/ownership
records, both runtime-policy suites, pricing ownership and the plain full witness. All eighteen
controller tests pass, rejecting incomplete execution evidence independently in all three modes.
The exact runtime head passes the focused Linux ARM replay and explicit interpreter pair above;
the final evidence-only update changes this spec alone. No broad CI labels are requested.
x86 is unchanged and no x86 speed claim is established.

Ignored evidence: `build/pvm-prefix-read-span/`, including source/image identities, all canonical
builds, `results-v1.json`, `results-v2.json`, focused-witness freezes, both raw cohorts,
`local-reparse.json`, `cohort-audit.json`, full validation and unclocked native activity. Official Linux artifacts and independent author
audits are retained in `ci-arm/`, `ci-arm-audit.json` and `remaining-audit.json`.
Initial raw SHA-256:
`7e68048db2c986425686fb1868f4dbf778fe44845820c9ff1d28e0a52293e4d6`.
Broader raw SHA-256:
`1657711519c9e75e3fffd03bbf02fcd4169e8f61eedb2919e1f47aad0e87aa66`.
Formatted runtime SHA-256:
`13e312df9c86a0c6c7997f76d56a7f6d0d4b58da52fc5fb3489a2bd7e374a204`.
Final focused witness SHA-256:
`d8f7badfadfec7fa34d2f9e85fc5560a88a79d6a708eadaedf3e2aeb9b6d95be`.
