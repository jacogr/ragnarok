# Checked load continuations

## Scope and correctness boundary

Selected scalar memory workers now share one operand/access equation for single and paired
continuations. A successful fast load stays in its selected worker. A failed fast preflight
has changed no CPU, bytes, price or attempt state, and tail-calls a separate complete checked
worker. That worker retains the existing load preflight, current private-byte reads, signed
extension, exact fault/panic/local-error publication and paired successor lookup. Successful
fragmented reads still continue normally. The next handler is read at execution time, preserving
partial-budget barriers and folded source boundaries. Store equations and checks are unchanged.

The cold definition has an explicit `noinline` boundary so the optimizer cannot reintroduce a
resumable slow call into every hot load. Direct calls from existing specialized store workers
remain eligible for inlining. No opcode evaluator is duplicated, and no check is disabled.
There are no new frame fields, retained resources, native instruction words, source operations,
ABI changes, pricing changes or resource-limit changes. GP 0.8.0 and existing PVM contracts remain
authoritative; the pinned checked ARC/Clang ThinLTO profile remains unchanged.

## Generated-code evidence

A local DOOM sample identified memory workers as a material interpreter cost. Disassembly of an
existing paired eight-byte load shows six callee-saved guest-work registers plus FP/LR saved in
an 80-byte stack frame to survive the rare resumable slow call. The candidate emits 28 distinct
cold load continuations and 28 hot-to-cold tail branches. All 28 hot load workers have no resumable
calls; a representative selected load saves only FP/LR in 16 bytes. This is measured code
structure, not an assumption that the compiler follows the source's visual layout.

An initial helper was inlined back into the hot workers. The final definition-level boundary
is verified in the actual application image. No compiler defect is claimed from this experiment.
Full disassembly and structured inspection are retained under ignored
`build/pvm-memory-cold-tail/final-worker-disassembly.*`.

## Local ARM measurements, 2026-11-01

Shipping parent is master `529f9d6bfda20b7189d9840e2e72912089ead0d2`.
The private canonical source baseline `000d58fa1c0c4c825fa53c753d8cd4035c4e0611` has exactly
the same runtime; the intervening squash/docs update changes evidence only. Apple M1 Max uses
pinned checked Nimony `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`, ARC and Clang ThinLTO.

Eight fresh canonical application builds pass four duplicate-image controls. Four balanced
fresh processes per source role each execute thirteen validated prepared public calls. Process
CPU medians use samples 3:13; the table takes the median across processes. Two PolkaVM interpreted
reference processes supply the matched raw denominator. Complete CPU/pages/events and immutable
source checks remain in every public call; restoration work stays inside the collected clocks.

| Workload/backend | Baseline CPU ms | Candidate CPU ms | Change |
|---|---:|---:|---:|
| DOOM init JIT | 115.588 | 114.623 | -0.84% |
| DOOM init interpreter | 241.038 | 239.464 | -0.65% |
| DOOM tick JIT | 15.959 | 15.973 | +0.09% |
| DOOM tick interpreter | 23.869 | 22.418 | -6.08% |
| Minimal JIT | 4.226 | 4.059 | -3.94% |
| Pinky JIT | 63.700 | 63.666 | -0.05% |
| Memset JIT | 2.489 | 2.448 | -1.65% |
| Sieve 10m JIT | 202.991 | 199.469 | -1.74% |

All four interpreter tick, both init, minimal and sieve process pairs improve with nonoverlapping
aggregate ranges. JIT tick and Pinky are flat with mixed pairs and overlapping ranges. Memset
improves in three of four pairs, with overlapping ranges. Matched raw DOOM tick ratios,
ours / PolkaVM interpreted, are **0.368 JIT / 0.517 interpreter**; init is **0.166 / 0.348**.
These are local application measurements, not a portable or full-block throughput claim.

The separate initial 18-process tick gate used a broader all-workers optimizer barrier and
showed interpreter -3.82%, JIT flat. Its source/images/raw logs remain separate; they are not
attributed to the final cold-only boundary. The final 76-process cohort is the shipping local
estimate. Across both cohorts, all 94 logs strictly reparse. Within each cohort, all native
fragments/calls/operations/code bytes/branches/headers agree between source roles, excluding
compilation time. Interpreted native counters remain zero.

## Validation and qualification boundary

The final formatted candidate passes the full native/ownership witness and fresh-image controls.
All eleven maintained native/refusal qualification records pass, including forced storage
refusal, exact partial/paid boundaries, host/fault behavior, region capacity and ARC ownership.
The supported default-backend all-opcode and host/regions Make suites also pass. Focused Linux ARM qualification
must assess the final source and retain any observed costs. No x86 timing claim is established.

Ignored evidence: `build/pvm-memory-cold-tail/`, including exact per-variant source/images,
`build.json`, both raw cohorts, strict `local-reparse.json`, disassembly and qualification logs.
Initial tick raw SHA-256:
`377f91f0977101ce413ae67abc86dd7dad750ac8cd8a555c69017ef242e51a40`.
Final broader raw SHA-256:
`15f77fd50b2e3a525a8155327bb2f5a14343340101aae5d132c7acc499743838`.
Measured and formatted `handler_stream.nim` SHA-256:
`20196ecd0c495c3b3bb6226df4647cfe974aed5e0b77bb43b3724710e66e9bb3`.
