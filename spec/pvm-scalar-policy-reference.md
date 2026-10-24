# Scalar memory across invocation pricing and paid repairs

## Scope and independent authority

Replay the unchanged4050-row scalar-memory corpus through complete invocations as well as public
single stepping. The original independent Python equations, pinned public PolkaVM comparison and
frozen byte identity remain those of [scalar memory access](pvm-memory-access-reference.md).
No runtime, fixture, dependency, Gray Paper interpretation or toolchain pin changes.

The corpus covers all30 scalar opcodes, four widths, signed/unsigned loads, direct and indirect
addresses, raw saturated register nibbles, A/B aliases, high address bits, five boundary positions
and all nine two-page permission pairs. The native adapter retains only GP-PVM-008: absent high
pages precede read-only low pages for crossing stores. The original paper fault remains frozen.

An additional independent Python pipeline-model check prices every literal scalar-plus-trap block
at25 gas and28 cycles. The native suite does not derive its expected price from the production
simulator. Those fixed costs define exact affordability and one-less cycle-policy witnesses.

## Invocation, repair and ownership checks

Every row now runs with initially paid and unpaid gas under dynamic, complete-plan, cold-memo and
warm-memo execution. Successful accesses reach the real trailing trap; faults retain their causing
PC. Every observation checks complete registers, PC, gas, reserved-zero deficit, paid status, every
physical page byte, permissions and the unchanged original source. Warm memo occupancy remains
zero for already paid input and one for an unpaid block; snapshots and affordability are never
reused as pricing facts.

A fault repairs exactly its reported page with the original independently authored bytes. It
resumes at the paid causing instruction under the same pricing policy, without another gas debit.
Each intermediate expected fault and successful state comes from the existing frozen row for the
new permission pair, preserving the same literal program and initial registers. Crossing stores
can therefore expose a second low-page denial after repairing a missing high page. At most two
repairs are permitted. Retained earlier fault snapshots are checked again after all later repairs
and writes, including otherwise inaccessible bytes.

A one-less gas balance stops OutOfGas before touching memory. Separate27-cycle memo and dynamic
policies refuse unpaid execution repeatedly and retain no price; paid inputs require no pricing
and still reach the original outcome. Complete-plan construction at27 cycles refuses before any
execution. All normal policies use the exact28-cycle ceiling. No successful earlier policy can
authorize work or prices in the stricter policy.

## Completion evidence and limits

The selected native scalar-reference suite and Python frozen-corpus/pricing tests pass. The
complete run includes32400 normal invocations,19728 paid retries,16200 gas-shortage cases and
32400 strict-cycle-policy calls, alongside the4050 original single-step witnesses. Source
inventory and pinned formatting retain their maintained entry points. Exact coverage counts and
logs are stored under `build/pvm11/scalar-policy/`; the frozen corpus remains
`70f725c62dc88c1e211009fa32eb936ec057f9b6d72142775cfb3814055865c4`.

This is invocation/pricing/ownership qualification, not a new speedup or another independent
PolkaVM run. It reuses that corpus's original independently cross-checked outcomes and strengthens
the native execution paths that consume them. Local macOS checks do not establish Linux CI or
whole-JAM/STF equivalence. M1 framing remains complete in scope; full state serialization remains
open. Fuzzing remains paused pending Daybreak access.
