# Managed canonical network reads

Scope: the host/worker bridge for JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`
CE128/129/143. `Services.beginNetworkRead` admits a fixed read request against its authoritative
complete canonical view and returns an exact worker ticket or a guarded source/worker refusal.
Light-state mode cannot authorize this complete-map backend. Ordinary node stream routing and
UP0 context integration remain subsequent work; this bridge does not itself create a listener.

Network reads share the existing single reusable `StateProofWorker` with RPC proof queries and
light proof ingestion. No worker is created per request, stream or connection. `NetworkReadJob`
is immutable and admitted before transfer. It projects only the rolling window and explicitly
selected finalized anchor, excluding the optional unbounded memory-history index. Admission
caps the window at64 snapshots and copied index accounting at32MiB before detached traversal.
Canonical read generation preserves its independent map/path/reply ceilings.

Staging activations retire every temporary canonical alias before the worker can start. Native
submission first pauses the exact RPC graph lease, then marks Services proofing; refusal resumes
only that lease and drops the staged job. While queued/running/Done, all other selected-state ARC
aliases remain untouched. A disconnected stream cancels its ticket but must still collect Done
or join; cancellation does not release capacity or reopen canonical/RPC access. Existing
`cancelStateProof`, `stateProofPhase`, `collectStateProof` and `stopStateProofs` controls retain this
shared lifetime. ReadCompleted results are typed frozen wire bytes, distinct from RPC proof
responses and verified light ingestion. Native close/join precedes source and response cleanup.
Worker/Services destructor and move hooks cover every new owned field.

Local checks: `application_proof_worker` tests mixed RPC/network jobs, exact ticket namespaces,
capacity through Done,20 read cancellations, frozen responses and joined queued/running work.
`application_proof_services` tests canonical/RPC exclusion, invalid capture rollback, competing
RPC refusal, cancellation, unrelated subsystem cleanup, stale collection, typed read completion
and joined network shutdown before another job. The actual ARC lowering probe continues to reject
StateProofWorker duplication with the exact unavailable-dup diagnostic. No new concurrency
primitive or host-control interleaving is introduced: the existing single-lock phase/ticket
protocol is reused; these deterministic tests directly pin the cancellation/lease invariant.
