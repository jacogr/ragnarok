# Managed Services preparation lease

Scope: connect the existing bounded preparation worker to a stable Services owner with an
explicit host-side exclusion boundary. Protocol rules, specification/dependency/compiler pins,
plain ARC and exact-parent adoption authority remain unchanged.

[Services preparation](../src/app/services.nim) owns host exclusion and the RPC pause.
The [worker](../src/app/preparation_worker.nim) owns the stable input borrow and exact
retirement. The [RPC listener](../src/rpc/server.nim) owns its pause token and socket queues.

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
