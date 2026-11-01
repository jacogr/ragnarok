# ARM checked fallback continuations

## Architecture and correctness

ARM native-enabled plans now use the same fixed four-node checked continuation bound as
explicit interpretation. The prior native guard kept them at two nodes. Native compilation
still owns its exact source facts and keeps the original addressable handlers as fallbacks;
it does not require every second checked handler to return to main dispatch. Existing native
wrappers already return an advanced scalar coordinate when a checked chain reaches a native
entry. No wrapper, native instruction emitter, Frame field, ownership hook or ABI changes.

The bound remains structural: three continuing prefixes reach an original worker, while fused
workers can return earlier. Interior entry shortens the chain. Runtime next-handler lookup
and fused second-operation budget barriers remain intact. A native refusal or partial source
reservation takes those same checked workers. Source prices, attempts, gas, exit PC, memory
permissions, host stops and fallback ordering remain unchanged. GP 0.8.0 and existing PVM
contracts remain authoritative.

This removes a preparation distinction between ARM interpreted and native-enabled checked
execution. It can reduce ordinary dispatch returns around native or refused leaves. It does
not add native guest coverage or reduce measured C-to-arena entry counts. x86-64 native-enabled
plans retain their existing two-node layout until separately measured and qualified.

## Functional evidence

A new 8,194-source block alternates signed direct loads and moves under an explicitly
native-enabled plan. It compares complete state, every register, source attempts and immutable
read-only memory against independent Step execution over 120 paid/gas/budget combinations.
The full result also has an independent literal sign-extension check. In the forced-refusal
build, exact zero native publication/call/operation counters prove genuine checked execution.
Ordinary native builds may use any valid admitted leaf; the test does not freeze an optimizer's
future admission choices.

The existing fused and non-fused long controls remain. The native controller requires exactly
one new 120-case fallback receipt in every mode; positive Python fixtures and independent
missing/truncated/duplicate negatives are included with the runtime change. Full checked
native-enabled forced-refusal execution with sibling-call optimization disabled and LTO off
also exercises the long fallback program. The bound does not rely on tail-call optimization.

## Local ARM application measurements, 2026-11-01

The canonical baseline is the qualified bounded-interpreter runtime
`e0d4b76cad04a0efda20f5324430a58bf8fff5d4`. Its final evidence-only head
`79c257daf456279cd3ee0aca20a23414dddb046d` was squash merged as master
`f3cfe69fe1bd67d6c0cda9a216752505666b7c13`. No runtime/test/controller change occurs between
these parent forms. Apple M1 Max uses pinned checked Nimony `63fed6cb`, ARC and Clang ThinLTO.

The initial private source used four nodes for all profiles. Before promotion, the final ARM-only
source preserved x86's two-node native layout. Four additional fresh canonical builds of that
final source are **byte-identical** to all four measured candidate images (two DOOM, two kernel),
on the same canonical source paths. The measured source and final scoped source identities remain
separate. This establishes application-image equivalence without attributing x86 performance.

Eight original canonical builds pass four duplicate-image controls. Each fresh process executes
thirteen complete-state public calls. A process contributes its CPU median over samples 3:13;
table values take the median across four balanced fresh processes per source/backend. Two matched
PolkaVM interpreted processes supply each raw denominator. Lifecycle restoration remains inside
the collected clocks; complete CPU/pages/source/events are checked for every call.

| Workload/backend | Baseline CPU ms | Candidate CPU ms | Change |
|---|---:|---:|---:|
| DOOM init JIT | 114.527 | 114.014 | -0.45% |
| DOOM tick JIT | 13.875 | 13.802 | -0.53% |
| Minimal JIT | 4.080 | 4.083 | +0.09% |
| Pinky JIT | 63.459 | 63.066 | -0.62% |
| Memset JIT | 2.473 | 2.483 | +0.41% |
| Sieve 10m JIT | 202.350 | 197.003 | -2.64% |
| DOOM init interpreter | 240.854 | 243.180 | +0.97% |
| DOOM tick interpreter | 22.436 | 22.490 | +0.24% |
| Minimal interpreter | 4.533 | 4.494 | -0.85% |
| Pinky interpreter | 79.531 | 79.271 | -0.33% |
| Memset interpreter | 3.695 | 3.703 | +0.24% |
| Sieve 10m interpreter | 328.147 | 328.303 | +0.05% |

All four JIT tick, Pinky and Sieve pairs improve with nonoverlapping aggregate ranges. JIT init
has three faster pairs and overlapping ranges, including a candidate outlier; Minimal and
memset have mixed pairs and overlap. Interpreter Pinky improves in all four pairs but overlaps;
other interpreter cases have mixed pairs and overlapping ranges. The interpreter init/tick and
memset point costs are retained. No interpreter speedup is attributed to the native-enabled
selection change.

The separate initial 36-process DOOM gate showed JIT init -2.07%, all four faster/nonoverlapping,
and tick -0.22%, three faster/overlapping. Its interpreter tick was -2.12%, reversing the broader
point direction; it overlaps and gives no independent interpreter benefit. The stronger initial
init estimate does not persist across both cohorts. Neither cohort is substituted for the other.

Matched broader raw ratios, ours / PolkaVM interpreted, are **0.318 JIT / 0.518 interpreter**
for DOOM tick and **0.165 / 0.352** for init. These are local complete-application measurements,
not a portable or full-block throughput claim.

All 144 local process logs strictly reparse. All six workloads have exactly equal native
fragments/calls/operations/code bytes/branches/headers across source roles, excluding compilation
time; interpreted native counters are zero. This is a checked-dispatch architecture increment,
with no extra guest lowering or native arena growth.

## Qualification and retained evidence

The final formatted promoted source passes all maintained eleven native/refusal/ownership
records, both backend policy suites, pricing ownership, the plain full witness and the native-enabled
no-sibling forced-refusal full witness. Actual register-pair disassembly contains indirect BLR
calls in that no-sibling image. All seventeen controller tests pass. The receipt tests reject incomplete results independently
in all three modes. One focused Linux ARM run with the explicit interpreter pair will qualify
the exact public head; no broad CI labels are requested.

Ignored evidence: `build/pvm-native-continuations/`, including exact per-variant source/images,
`arm-only-results.json` with all four measured-image equalities, `local-reparse.json`,
`cohort-audit.json`, full mode/owner checks and raw process logs. Initial raw SHA-256:
`8bc2917c26a00eb716b2bb57c06bed573a45f46c1cdf060b915f123e8176f374`.
Broader raw SHA-256:
`82c02e3f51568c3d0ac2b18f0629ec271ade727ed7a0141a1931932995482a59`.
Final ARM-only runtime SHA-256:
`919a79146ab108b07a445f40e8b32213f106b031a3c88aa81f7ccae3784ae869`.
