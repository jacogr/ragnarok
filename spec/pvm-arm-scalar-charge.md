# Scalar ARM region source-charge matching

## Scope and invariant

Independent draft layer in stack1786. The accepted region wrapper spends substantial
measured work on metadata/context boundaries. This isolated trial matches original
header/price/span values directly against each cached scalar record while gathering
the same guarded-return header list. It removes temporary span/price arrays and their
second comparison loop; it does not hoist checks across calls or assume immutable prices.

Every active and inactive record remains checked, including the two-block region's
third sentinel/zero lane. Header bounds, source-owner leases, pricing mode, paid state,
barrier, root identity, gas/source ordering, checked memory, publication and native
emission/accounting are unchanged. All source header reads still happen before a
mismatch selects the original fallback. No capacity, admission or hotness change.
The original complete-array matcher remains as the independent test oracle.

## Qualification and decision

The native witness adds111 checks for unpublished owners and genuine two/three-block
records, both rotations and all exercised price widths. Each header/span/price field,
including inactive sentinels, is independently changed and must agree with the old
complete matcher. Existing full register/gas/source-prefix/paid-state/host/memory
checks and native/refused ownership controls remain.

All native builds/execution/timing stay on CI. Keep only qualified useful same-runner
paired benefit without material regressions, otherwise restore only the runtime
helper/wrapper delta while retaining useful tests and measured rejection evidence.
Constructor/cold/reused public calls, retained-frame lifecycle and reference restoration
remain separate. Paired ARM explicit-marker profiles retain exact source/image/native
activity, thirteen checked calls and all calibration controls. Qualification pending.
