# Current candidate preparation worker payload

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains authoritative.
No protocol semantics, pins, storage formats or thread scheduling policies change here.

The reusable fixed-address `PreparationWorker` accepts either legacy `BlockInput` or genuine
`CurrentBlockInput`. A private operation selects one borrowed payload; one capacity, ticket
namespace, nonwrapping generation, condition variable and lock protect both. Busy admission
precedes input graph reads. Current execution calls only the current receiver's pipeline and
returns `CurrentCompleted`, whose guarded `currentValue` preserves the selected typed raw-input
result. Legacy `Completed` retains its existing accessor. Defaults and cancellation expose neither.

All input, original/canonical history and retained ARC aliases remain untouched until collection
or joined close, including during cancellation and Done. Cancellation never ends the lease or
interrupts guest execution; a collected cancelled job discards every outcome. Shutdown joins before
clearing pointers and results, and installs no state. Every retirement path clears the current
pointer as well as the legacy pointer. Composite ownership continues to reject copies and actual
ARC duplication; worker addresses stay fixed from start through close. The worker never publishes
canonical/RPC heads or performs disk IO. Services and network selection remain later integration.

The payload dispatch adds no lock-free window or shared lifecycle transition. Review found no new
plausible scheduling hypothesis needing a model; do not treat this as formal interleaving coverage.
Native witnesses cover actual signed current execution and independent complete root equality,
malformed/stale IDs, Busy/NotReady/Closed, current/legacy reuse, foreign/restarted tickets,
completed cancellation, queued/running shutdown, repeated native lifetimes and two-lease ancestor
resumption. Runtime/private-result and existing composite ownership probes retain exact diagnostics.
Thread allocator counters are per-thread; no process-wide ARC equality is claimed. Local macOS
validation and exact-head Linux CI are separate, as are full JAM/ThinVRF/production Services parity.

Local macOS ARC/Clang validation passed: current and legacy native preparation-worker suites;
six source-owned compiler/privacy/actual ARC duplication checks, four runtime guards and two
nonfailing joined-worker controls; four affected worker/Services/download semantic checks;
inventory and changed-source pinned formatter idempotence. Linked checks ran serially.
Linux CI has not been requested. Existing unchanged 314-module baseline remains separately recorded.
