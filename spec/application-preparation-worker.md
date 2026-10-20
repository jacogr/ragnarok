# Exclusive application preparation worker

Scope: one reusable native worker and one outstanding raw-block preparation, including an
uncollected result. Protocol behavior, the pinned specification, compiler, plain ARC memory
manager and dependencies remain unchanged. The worker calls the existing exact-input preparation
pipeline and returns its opaque finalized certificate; it never publishes canonical state.

One host thread serializes control calls. The stable host owns the worker, input and chain until
explicit collection or joined close.
Submission grants an exclusive lease over the entire captured ARC graph: the host must neither
access nor copy nor destroy any alias (including Services/RPC snapshots) until that lease ends.
A mutex protects scalar lifecycle state and publication; it does not make shared ARC references
safe. This low-level component is deliberately not wired into the download dispatcher yet.

A retained host-only identity and generation bind each ticket to its exact worker lifetime. Busy/default/
stale tickets cannot replace a job. Cancellation marks work unwanted without preempting execution
or ending the lease. Completion is published only after preparation locals have been destroyed;
collection moves the result on the host and releases the slot. Close wakes, joins and retires
all worker access before releasing any retained result. Addresses cannot move between start/close.

Completion checks: genuine signed child preparation and adoption on the host; exact selected-parent
identity; idle/readiness/backpressure, stale/cross-owner tickets, cancellation, repeated reuse and
joined shutdown; composite copy lowering rejection, private ticket/result fields and guarded result
extraction. Local checked ARC release builds must exercise the actual native thread.

Remaining work: safe ownership isolation for concurrent Services/RPC dispatcher integration,
production load evidence, persistent full/light stores and complete JAM state serialization/parity.
M1 framing is complete; it does not establish complete state serialization.

## Local verification

On 2026-10-20, macOS arm64, pinned Nimony and checked ARC/Clang/LTO:

- `make unit SUITE=application_preparation_worker` passes genuine signed execution, exact
  parent identity and actual host adoption; typed decode/stale-input failures, foreign/stale
  tickets, Done backpressure, early and completed cancellation, restart and explicit join.
  One reusable thread handles 100 further failed inputs; 25 additional lifecycle cycles cancel
  signed input and join before borrowed owners retire. These are lifecycle checks, not a claim
  of concurrent canonical/RPC safety or a production throughput/memory measurement.
- Three private-field compiler checks, composite ownership lowering rejection, three strict
  runtime extraction/destruction failures and their positive joined-close control pass.
- Native harness (56), verification (35) and inventory harness (11) Python checks pass;
  inventory discovery and formatting pass. Logs remain under `build/preparation-worker-*`.

Canonical Linux CI and production dispatcher/load testing remain separate evidence. No remote
CI was requested. The next bounded increment must establish safe Services/RPC ownership isolation
before this worker can be connected to the live download dispatcher.
