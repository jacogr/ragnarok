# ARM region-entry and selection investigation

Independent draft stack1786 above the rejected capacity evidence. Production/runtime sources
remain identical to accepted parent23f8929dabc630e0c8842e9058e0c55ce6c4a5bd. No default,
admission, code emission, checked memory, host, gas, source-budget or ownership change is included.

The previous eight-slot trial regressed sieve despite identical native work/handoff counts. This
investigation compares the accepted current source against explicitly supplied rejected parent
466b85687fae91ed586ad3d2953d326db170333e on one native ARM Linux runner. Normal checked
application clocks and complete reference-state checks precede instrumentation. No profile clock
is a timing and no simulated branch/cache count is a hardware measurement.

Reuse the existing calibrated Callgrind scope and complete return-dump protocol on Linux ARM64.
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
