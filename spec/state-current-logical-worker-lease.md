# Frozen logical owners across actual proof worker leases

An actual slot3 full logical plan and materialized logical owner share the exact canonical snapshot
with the generic proof query sent to the maintained fixed-address single-slot worker. Expected roots
and every temporary selected alias are captured/retired before admission. While leased, host work
is limited to scalar worker controls and tickets; no logical/query/fixture getters, copies, retains,
drops, observer access or canonical work runs. Done, cancellation and stale-ticket collection all
keep the lease. Matching collection or joined close alone permits full plan execution again.

A normal collected response authenticates against the independently retained actual producer root.
1,000 cancelled Done/collection cycles then execute the retained full plan only after Idle. A final
cancelled uncollected job releases by joined close before canonical owners retire. This qualifies
existing library ownership composition; no Services gate, RPC policy, worker state machine or
storage format changes, and no claim of detection of arbitrary external aliases.

Local checked native qualification passed: 1,000 cancellation/collection cycles retained
303,504 live bytes unchanged. A separately admitted cancelled job joined without collection before
canonical access resumed. Pinned format and verification inventory checks passed.
