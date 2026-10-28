# Native paired-shift reduction

## Scope and proof

An isolated equivalent arithmetic rewrite inside already reserved three-block
native regions, for ARM64 and Linux x86-64. The pinned PVM semantics mask64-bit
shift counts modulo64. When opcode151 writes D from S, immediately followed by
opcode152 reading/writing D, with equal effective counts k, their complete result
is `(S << k) >> k = S & (2^(64-k)-1)` under64-bit wrapping arithmetic. For k=0,
the result is an ordinary full-width copy. All other coordinate/count patterns
retain the original two operations; a declined builder must stay untouched.

Native admission still requires the complete source block. Partial source quotas,
paid/gas failures and observable exits use the existing original workers, so the
intermediate left-shift value remains observable at the original boundary. Logical
source spans, prices and operation counters still include both instructions.
No header/host/memory boundary is crossed. No cache/frame/ABI/capacity policy or
upstream/toolchain pin changes. Rejected ARM store runtime is absent.

## Implementation and qualification gate

ARM uses one unsigned bitfield extract; x86 uses a mask with the original register
array contract. Only a genuine adjacent151/152 source pair with the same final
coordinate and matching masked counts qualifies. Helpers validate before mutating
the cold builder. Existing aliasing, source budget, branch, host, memory and owner
checks remain. No runtime condition or additional metadata enters the hot loop.

Direct native literals cover every13x13 source/destination pair, all64 effective
counts, high immediate bits and independent wrapping-shift equations over full64
values. Declined destination/source/count patterns leave code construction and
native execution unchanged. Existing complete-state three-block rotations and
every source/gas/paid prefix still run through the actual production selector.
All native compilation, execution, profiling and timings are CI-only. Require
same-runner both-order constructor/cold/reused comparisons for all seven workloads,
full source/compiler/input/image/reference-state checks and calibrated profiles.
Keep only useful benefit without material regressions; otherwise restore this
isolated arithmetic rewrite and retain useful evidence. No timing claim yet.
