# Current PVM disk worker payload

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains unchanged.
This adapter changes no storage format, protocol semantics or worker scheduling policy.

The existing fixed-address `DiskPublicationWorker` now accepts a borrowed
`PreparedCurrentDiskPublication`. An explicit private operation enum selects legacy/current
publication or maintenance. All three use the same one-slot capacity, ticket namespace,
nonwrapping generation, lock/wait predicates, Done retention, collection and joined shutdown.
Every retirement path clears the current-publication pointer. Current publication returns the
existing exact `Completed` disk receipt; maintenance keeps its distinct receipt.

The host must freeze **all** aliases of the disk/publication/canonical graph until collect or
joined close. Only scalar worker phase and ticket operations are available during that lease.
The worker never installs canonical/RPC state. An entered operation always preserves its actual
IO result during shutdown; queued-only shutdown may return `NotExecuted`, never a fabricated
commit or cancellation rollback. Thread addresses remain stable and the composite owner remains
explicitly noncopyable/nonduplicable.

Completion checks use real current maps and files for normal collection, joined Done, immediate
shutdown, Busy/NotReady/Closed, stale publication and old/default tickets, with repeated full
start/commit/join lifetimes. Legacy publication and maintenance consumers and existing ownership
lowering guards qualify the shared dispatch change. Public allocator counters are per-thread;
these thread lifetimes do not claim process-wide ARC equality. Local macOS evidence and Linux CI
remain separate; dispatcher/service wiring is not implied by payload support.

Local macOS validation passed: 306 source modules; genuine current disk-worker, legacy disk-worker
and managed-maintenance native suites; 27 real current start/publication/join cycles across the
three shutdown modes; three exact runtime guards, two private-field rejections and the existing
actual ARC `=dup` lowering rejection; inventory and formatting. Native/runtime/lowering checks
ran serially. The lock/wait/ticket transition functions are unchanged; this layer adds payload
dispatch only. Exact-head Linux CI and complete Services wiring remain separate.
