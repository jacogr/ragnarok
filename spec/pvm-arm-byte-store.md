# Transactional ARM pure-prefix byte store

## Scope

Isolated draft experiment above the accepted scalar source matcher. The existing
DOOM profile identifies indirect byte store opcode120 as a substantial remaining
checked-handler cost. Admit at least three pure operations plus one terminal byte
store, total at most64, within a single already reserved source block. Headers,
branches, earlier memory/host/exit operations are never crossed. Other store widths,
read admission and source/gas policies remain unchanged. No timing claim yet.

The existing X4..X16 guest bank retains the speculative prefix. Fresh invocation-owned
72-byte descriptors contain only genuine stack/RW full-byte extents and the dirty
bitmap word extent; code caches retain no pointer. Native effective addresses wrap
modulo32, then conservatively retain the checked worker's protected/top-address slow
path. All writable and dirty-word guards precede every register, byte or dirty-bit
mutation. A refusal returns flatStop, publishes nothing and replays the original
prefix. Success marks the exact page, stores one low byte, publishes dirty registers
and returns the captured source successor. No byte can cross a page boundary.

Pointer scratch uses caller-saved D0 by integer bit transfer only; no FP arithmetic,
X18, callee-saved register or new OS/FFI ABI. Frame creation/remap rebuilds descriptors;
reset/host deltas mutate stable allocations, while immutable source snapshots and
checked publication remain authoritative. The same native cache/page/word ceilings
and source budget/gas checks remain enabled.

## Checks and verdict gate

Direct native literals cover all13x13 value/address aliases, derived prefix values,
both writable roles, protected/top/wrapped/full64 addresses, extent refusal, absent
writable/dirty regions and page/bitmap-word boundaries. Every register, byte and dirty
word is compared on success/refusal. Native refusal controls execute no direct cases.
Integrated independent single-step cases check every prefix budget, paid/unpaid gas,
RO/inaccessible/extra/empty/high-page maps, host publication, cache transfer and memory
replacement. The shared oracle now compares stores against its immutable single-step
memory snapshot and separately proves the original input snapshot remains unchanged.

All native compilation/execution/timing is CI-only. Require complete exact-head
native gates and seven-workload paired public/core/reference cohorts, constructors,
cold/reused scopes, both orders and calibrated profiles. Keep only useful benefit
without material regressions; otherwise restore just this runtime change while
retaining meaningful witnesses/evidence. Simulated misses are not hardware counters.
