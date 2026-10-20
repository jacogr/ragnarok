# Managed Services preparation lease

Scope: connect the existing bounded preparation worker to a stable Services owner with an
explicit host-side exclusion boundary. Protocol rules, specification/dependency/compiler pins,
plain ARC and exact-parent adoption authority remain unchanged.

A successful submission pauses RPC chain work before the worker can run, and blocks Services
canonical getters, reception, preparation and publication APIs by checked preconditions. Scalar
progress, cancellation, UI ticks and unrelated QUIC work remain available. RPC ticks perform no
request/context work while paused; publication refuses and close/destruction require release.
A private retained RPC token prevents foreign/default/stale tokens from resuming another lease.
RPC sockets/queues remain intact and resume afterward; existing wall-clock deadlines still apply.
This increment pauses RPC service rather than claiming concurrent snapshot access is safe.

One host thread serializes all controls. Existing external aliases of the captured canonical/input
graph must remain untouched and alive until successful collection or joined close. Services and
input addresses remain stable. Cancellation and Done retain the gate until explicit collection.
Collection returns the genuine pipeline result; host enqueue/adoption remains explicit and deferred.
Close joins the worker before RPC or canonical owners retire. Once a worker has been started,
Services requires explicit close before destruction, including after collection. Failed submission
restores RPC availability and grants no input lease. Admission requires started complete canonical
state, idle adoption and no existing RPC suspension; default/legacy Services cannot prepare.

Completion checks: real signed child preparation through Services with RPC off/on, guarded canonical
access and RPC lifecycle/publication during a lease, UI/scalar ticks, exact-parent host adoption,
failed admission rollback, cancellation, stale collection, reuse and joined close. Preserve existing
Services/RPC behavior when idle and composite ownership lowering rejections.

Next: wire the managed lease into the download dispatcher with network progress and timeout/load
evidence. Full state serialization/JAM parity and persistent full/light stores remain open. M1
framing is complete, independently of complete state serialization.

## Local verification

On 2026-10-20, macOS arm64, pinned Nimony with checked ARC/Clang/LTO:

- `make unit SUITE=application_preparation_lease` passes genuine signed preparation and
  deferred host adoption with RPC disabled/enabled, exact parent identity, failed-admission
  rollback, token isolation, stale collection, cancellation/reuse and joined shutdown.
  A live UI response progresses during the lease; a pending real WebSocket upgrade stays
  paused and resumes afterward, followed by a successful client-information query.
- Existing `application_services` and `rpc` native suites pass; the production `make build`,
  application help/version, formatting and changed documentation links pass.
- Four private-field compiler checks, both Services/Server copy-lowering rejections, eleven
  strict runtime access/lifecycle guard failures and the positive joined-close control pass.
- Native harness (56), verification (35) and inventory harness (11) Python checks pass.
  Inventory discovers 234 native suites, 165 failure families and 2046 data-driven probes.

Evidence remains under `build/preparation-lease-*`. These are local lifecycle/exclusion checks;
canonical Linux CI, sustained network/load behavior and concurrent RPC snapshot serving remain
separate work. No remote CI was requested. Existing external aliases still obey the exclusive
borrow contract; this managed boundary does not discover or synchronize arbitrary caller aliases.
