# ARM region-entry and selection investigation

Independent draft stack1786 above the rejected capacity evidence. Production/runtime sources
remain identical to the current accepted capacity-evidence parent. The original
pre-upgrade parent was23f8929dabc630e0c8842e9058e0c55ce6c4a5bd. No default,
admission, code emission, checked memory, host, gas, source-budget or ownership change is included.

The previous eight-slot trial regressed sieve despite identical native work/handoff counts. This
investigation compares the accepted current source against explicitly supplied rejected parent
466b85687fae91ed586ad3d2953d326db170333e on one native ARM Linux runner. Normal checked
application clocks and complete reference-state checks precede instrumentation. No profile clock
is a timing and no simulated branch/cache count is a hardware measurement.

Use calibrated explicit Callgrind client-request markers in separate diagnostic images on
Linux ARM64. Only the test wrapper is instrumented; normal timing images are unchanged.
Two fresh private-cache builds per role/family must produce equal diagnostic images, and
their runtime source hashes must match the sealed timing cohort.
Manual `jit-arm-profile` selects only the existing native ARM comparison job, native qualification,
full application cohort and six profiles: supplied baseline/current JIT, sieve100k, DOOM init and
gameplay. Every profile retains13 complete checked calls, cold dump1 and reused dump13, exact
image/input/source seals, matching native activity, self costs and call arcs. Selected/absent and
repeated/last-return controls must pass before any attribution. Unsupported instructions, missing
scopes, incomplete dumps or changed native activity fail qualification; never substitute timing
or a different execution path. Existing x86 and ordinary CI selections remain unchanged.

Inspect actual cold publication calls and warm region-entry/call accounting. Determine whether
region entry occurs on the regressed sieve path before attributing its loss to slot validation.
Use observed costs to choose the next bounded optimization. More slots, one-block admission,
new hotness rules and background compilation are outside this diagnostic step.

All native compilation, execution and profiles run on CI. Local checks cover Python parsing,
plan/environment selection, CI dispatch/matrix isolation and source inventory only.
Status: diagnostic implementation ready; exact-head native attribution pending.

## Boundary qualification and compiler reconciliation

Run40736261999 completed its normal cohort but the ARM symbol-return mechanism produced
one dump for thirteen checked calls; its workload attribution is rejected. Explicit-marker
calibration40739701219 passed selected1297, absent0, repeated2594 and last1297 instructions.
Run40740108016 passed native qualification and the normal cohort, then correctly rejected
the first diagnostic output: the baseline was explicitly requesting `jit`, unlike its normal
cohort, and emitted an additional policy receipt. Preserve strict parsing; diagnostic baseline
selection now uses the same empty/default request as its measured role. No workload
attribution from those failed attempts is accepted.

The independent PR-free base now has the exact tree of integrated x86 stack head
`c1a57ec5ac7136fede515d02b7e62d88404ac50e`, including master
`bf82cf784e97e9bef1b2bcb169b5759037caaf97`, October28 Nimony
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4` and explicit arena move resets.
Historical October26 timings retain their original compiler identity. A new diagnostic
baseline must apply only the previously rejected capacity runtime delta to the upgraded
accepted parent, with an exact tree/patch certificate; never compile an incompatible old
owner silently or relabel its historical timings as new-compiler results.

The upgraded rejected-runtime baseline is PR-free commit
`99659fad8dd81ecb49eebce9d765b487c0e9b862`, based on upgraded accepted
`13a3d5c9c39951d987b6c642c88893a608e7f92a`. Its only delta is the original
`14105fe3..466b8568` patch in `arm64_jit.nim` and `handler_stream.nim`
(94 insertions,55 deletions); arena resets remain present. It is diagnostic input,
not a proposal to restore the rejected runtime.
