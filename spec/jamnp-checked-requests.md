# Managed checked outbound requests

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE128/129/143,
and the trusted-root validation contract in [read validation](jamnp-read-validation.md).
No specification, dependency or toolchain pin changes.

`ApplicationNode.requestChecked` owns one acquisition-to-verification operation. Its opaque ticket
retains a host-specific namespace and nonwrapping serial; reopening a host creates a fresh namespace.
Default, foreign and collected tickets cannot cancel or collect another operation. Admission
validates the fixed request and reply ceiling before reserving the existing node client frame.
One checked operation occupies host capacity through terminal collection; raw outbound requests
retain their separate existing interface and shared native per-peer/global quotas.

The lifecycle exposes scalar Receiving, Waiting, Verifying and Done phases. TLS framing must finish
before the host captures one detached wire buffer. At most8MiB of logical response bytes can wait
for the shared Services worker; shorter explicit limits apply throughout acquisition and verification.
Native buffers, transient copies, allocator capacity and checked caller-owned results are separate
from that retained logical buffer bound. Source capture occurs only when the canonical gate opens,
so pruning while a foreign job holds the gate can cause an explicit NoSource admission failure.
No peer-supplied root, header or announcement supplies independent trust.

A foreign Services job may delay verification while networking continues. Host polling collects
only its exact worker generation. Ready inbound responses and buffered checked replies alternate
at worker admission; physical stream order cannot permanently favor one class. Verification uses
the existing single bounded CPU worker and exact canonical/RPC lease. No native callback touches
canonical state and no extra worker thread is created.

Cancellation before worker admission removes the native open intent or discards detached bytes.
After admission it marks the operation cancelled, retaining the worker ticket, capacity and lease
through Queued, Running and Done until exact collection or joined shutdown. A120s total deadline
also bounds receiving, detached waiting and admitted verification; an executing bounded job is joined
or collected rather than unsafely preempted. Terminal uncollected results retain the single bounded
host slot. Explicit cancellation can discard such a result. Closing an admitted operation joins
only after successful exact-ticket cancellation; closing buffered work leaves foreign leases intact.
An external joined worker stop followed by a replacement foreign job yields Interrupted without
retiring the replacement job, even when that job is already Done.

`takeChecked` returns Pending without a payload until terminal collection. Completed carries the
whole guarded `ReadVerificationResult`, including genuine semantic/proof failures. NetworkFailure
and AdmissionFailure expose only their actual collection/source-capture reasons. Cancellation,
timeout, interruption and default results carry no checked response prefix. Immutable collected
proof evidence can outlive explicit host/worker shutdown. Checked block success still requires
ordinary GP execution and consensus admission before canonical adoption; verified partial state
never becomes a complete full-state mapping.

Verification:

- `jamnp_checked_requests`: actual TLS CE129 acquisition and trusted-root verification; corrupt
  values, malformed framing and unavailable trusted sources; reply-byte admission bounds;
  foreign/default/stale/reopen ticket isolation; buffered and worker-Done cancellation;
  deliberate foreign Done lease retention; inbound/checked admission fairness; external joined
  stop followed by a replacement foreign Done job; owned joined shutdown, buffered shutdown and
  detached deadline expiry;1000 queued cancellation generations with balanced ARC memory.
- `jamnp_application_node`: existing real TLS inbound routing, raw outbound requests, worker/RPC
  lease management, finality gates, clock handling and close/restart regression coverage.
- Actual compiler lowering rejects implicit `ApplicationNode` duplication after its owner fields
  change. Formatter checks and application build cover the integrated public surface.

Ordinary executable activation, canonical GP execution/adoption integration and the remaining
protocol families stay open. This lifecycle is a usable managed host API, not a complete syncing
or validator runtime.
