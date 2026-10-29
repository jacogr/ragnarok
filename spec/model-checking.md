# Bounded state-machine verification

`tlanif` is a separate upstream tool, not a Nimony distribution component. `make model-tools`
builds the exact source revision and SHA-256 archive in `spec/model-tools.json`; `make setup`
includes this prerequisite. Outputs and logs remain under `build/model-tools` and `build/ci`.

The checker is built with Nim from the existing pinned formatter archive, solely as a verification
tool. NIF reader libraries come from the existing pinned Nimony release archive. Both archives
are checksum-verified before extraction, dependency sources remain pristine, and production
compiler pins and PATH stay unchanged. Linux x86-64 and macOS ARM64 use the existing host pins.

Run `build/model-tools/bin/tlanif --help` for upstream options. A source/build identity and binary
checksum validate retained output; changed inputs rebuild instead of trusting an old executable.
`make clean` removes the installation. No global installation or Nimble dependency is required.

Each model-local declaration requires exactly one unmodified passing `base`, at least one
nonzero `Mut` counterexample with role `mutant`, and exactly one unmutated `Witness`
counterexample with role `witness`. Default switches must select unmutated safety.
`make check-inventory` validates these contracts before provisioning the checker, so removing
negative cases or relabeling a witness as a mutant cannot silently weaken CI.

Models check bounded abstractions of documented implementation transitions. A passing safety
check alone is insufficient: each model must also kill an intentional guard-removal mutant and
reach its interesting state through a counterexample witness. Parser errors, state-limit exhaustion
and tool failures are never successful counterexamples. This complements native ownership,
cancellation and shutdown tests; it does not establish unbounded correctness or full JAM parity.

Upstream: <https://github.com/Araq/tlanif>, revision
`59e1e5c99b2e1ba3ba5502010f6a9293cc501e08` (MIT; retained in extracted source).

## Preparation worker lease

`tests/models/application_preparation_worker.nif` models the actual capacity-one
`src/app/preparation_worker.nim` lifecycle with six variables and one accepted job. The single
host serializes submit/cancel/collect/close; one worker executes outside the lock. Tickets are
assumed valid here: native foreign/stale ticket tests remain separate. Start/restart, generation
exhaustion, payload correctness, scheduling fairness and eventual completion are outside this model.

The atomic action mapping is:

| Model action | Implementation region |
| --- | --- |
| Submit | `submit`: lock, Idle/admission checks, borrow, Queued, signal, unlock |
| Dispatch | `run`: wait predicate/stop check, Running, cancellation snapshot, unlock |
| Execute | `execute` activation, including retirement of all temporary ARC aliases |
| Publish | `run`: reacquire lock, publish Done |
| Cancel | `cancel`: matching ticket, mark only, unlock |
| Collect | `collect`: matching Done only, transfer/drop outcome, clear borrows, Idle |
| RequestClose | `close`: set stopping and broadcast under the lock |
| Exit | `run`: observe stopping at the wait/dispatch boundary and return |
| JoinedClose | `close`: join returned, clear owners and slot, deinitialize synchronization |

The invariant requires the exclusive graph lease throughout execution/activation retirement and
for every occupied slot until joined shutdown. Cancellation preserves capacity and the lease;
collection cannot release either before Done; shutdown cannot release either before joining.
Spurious wakeups stutter because the predicate is rechecked under the same lock. An executing
worker can retire and publish after a close request, then observes stop and exits before join.

`make check-models` discovers each model's adjacent case declaration, checks safety, kills all
three deliberate guard-removal mutants and produces a witness reaching cancelled, still-running
work with shutdown requested. Each case must agree exactly between sequential and four-worker
exploration after memo/progress diagnostics are removed. Parser errors, timeout and state caps
fail the gate. Logs, replayable variants, source/checker hashes and fresh results are retained in
`build/tests/models/`. `make check` includes this gate. CI runs it in the separate **Model verification** job on
master pushes and existing unit/full requests, independently of source compilation. Its own job
summary lists base, mutant and witness verdicts; artifacts retain logs, replayable model variants
and results for seven days. `make summary-models` renders the same report locally. Native `application_preparation_worker` tests cover actual reuse, foreign/stale tickets,
cancellation and joined shutdown; the model is complementary evidence, not a native test substitute.

The new `src/app/proof/worker.nim` uses the same lock/condition/phase/stop transitions. Its
`submit` moves an admitted immutable query into the slot instead of borrowing input pointers;
`collect` and joined `close` retire that owner. The same six-variable model checks its lease
retention and join ordering. Query move semantics, exact proof outcomes and ticket identity
remain covered by the native `application_proof_worker` suite and compiler ownership probe.

## Disk publication and host installation

`application_disk_worker.nif` checks one admitted publication/maintenance against
`src/app/disk/worker.nim` (`submit`, `run`, `collect`, `close`). Locked dispatch,
unlocked I/O, activation retirement, locked Done publication, stop observation and joined
retirement are distinct transitions. Success and uncertain failure are abstract receipt tags;
queued shutdown returns NotExecuted. The graph lease must survive until collection/join,
and an actual returned I/O receipt must survive shutdown unchanged. Mutants release before
join, drop the joined receipt or fabricate queued success. The witness retains an uncertain
receipt through joined close. This does not model disk contents, process crashes or recovery.

`application_disk_installation.nif` separately maps `Services.tick`,
`stopDiskPublication` and `finishCurrentDiskPublication`. It checks that observing Done does
not authorize installation before collection/join, only an exact confirmed publication may
install, and RPC remains paused through installation/refusal. Uncertain outcomes fault the
backend without installation. Mutants install before retirement, accept uncertain I/O, or
resume RPC before the host finishes. The witness reaches joined uncertain refusal with RPC
resumed and no installation. Exact receipt/context validation, canonical/RPC history and
operation-specific maintenance payloads remain native checks; the model treats their
confirmation result as an abstract success/refusal input. Host completion steps are serialized.

## Checkpoint dispatch, retry and shutdown journal

`application_checkpoint_lifecycle.nif` maps `ApplicationCheckpointWorker.stage`,
`stageVerification`, `begin`, `cancel`, `run`, `collect` and `close`. Staged work owns
capacity but has not dispatched; Running may enter I/O; Executing must retire before Done.
Unlike preparation cancellation, checkpoint cancellation is staged-only. Completed Publish
and Verify receipts preserve both operation kind and actual success/failure through collection
or joined close. Mutants cancel after dispatch, erase joined completion or report verification
as publication. The witness reaches a failed verification retained through joined close. The
state checkpoint worker shares the dispatch/cancellation/join pattern, but its extra operations
and retry semantics are not inferred from the application worker. Native file error/crash tests
cover actual filesystem behavior; the model assumes the synchronous operation returns.

`state_checkpoint_retry.nif` focuses on `CheckpointWorker.retry`, `begin`, `peek`,
`matches` and `collect`, assuming a valid Advance request, ready expected head and available
generation. Only an exact StaleHead refusal permits the sole retained buffer to be restaged;
success and uncertain I/O require collection/reconciliation. Retry grants fresh ticket authority
and still requires explicit dispatch. Mutants retry uncertainty, retry success or let an old
ticket collect the retried slot. The witness reaches explicit retry followed by successful
collection. Generation tags represent two distinct nonwrapping admissions, not uint64 exhaustion;
wrong-owner tickets, other request kinds and real head validation remain native checks.

`application_checkpoint_session.nif` checks the host-only journal around worker close.
`ApplicationCheckpointSession.close` retains operation completion independently of retirement
refusal; repeated close and observation preserve the journal. `start` refuses unacknowledged
shutdown state and `takeShutdown` explicitly releases the gate. Mutants erase repeated-close
evidence, restart before acknowledgement or forget retirement-only errors. The witness retains
both a completed operation and a retirement error. Worker shutdown outcomes are abstract inputs
here, including Interrupted; the model does not manufacture a process-failure execution path.

## Authority across service admissions and worker reuse

`application_service_lease_authority.nif` distinguishes preparation, proof and disk owners,
plus two distinct retained `RpcChainLease` tokens. It maps scalar admission/pause, submission
success/refusal, native completion and matching retirement in `Services`, and exact-token
`Server.pauseChain`/`resumeChain`. Foreign stop calls, a stale token from a retired attempt,
nested pause and failed admission must not release, replace or leak the active token. Each
has a killed mutant. The witness reaches a second proof job at Done while its new token is
still held. Joined worker retirement is an abstraction already checked by the lifecycle models;
the token model does not certify join ordering, disk installation or query payloads. The
pre-submit host activation is serialized: no foreign host API interleaves pause and submission.

`application_worker_reuse.nif` checks two preparation/proof submissions, with optional idle
close/restart between them. Generations remain distinct across restart and startup allocates
a fresh identity. A retained old generation in the same namespace and an equal-generation
ticket from a foreign owner are inert. Those two equality classes also cover old namespaces
after restart; actual ref lifetimes remain native evidence. The model additionally checks
that cancellation of the first job cannot contaminate the next admission. Mutants remove
generation checking, remove owner checking or retain the previous cancellation flag. The
witness reaches an uncancelled second Done job after restart. Active close/join and temporary
ARC aliases remain in the preparation lifecycle model; exact uint64 exhaustion remains native.

## Two-worker proof offload pool

`quic_offload_pool.nif` maps the enabled `src/quic/offload.nim` implementation's
`worker`, `submitPool`, `cancelPool`, `collectPool` and `stopPool`. It keeps the real two
workers and four-slot limit. One distinguished job retains phase and cancellation identity;
interchangeable other slots are counted as queued, worker-owned Running or uncollected Done.
Slot ordering and payloads are abstracted because the checked properties concern ownership
and occupancy. Each locked claim, unlocked synchronous verification, locked completion,
cancellation, stop observation and join is a separate transition.

The invariant bounds total occupancy, forbids two workers from claiming the distinguished
job, and prevents cancellation/shutdown from freeing its Running slot before native return.
Both workers must exit before joined retirement. Mutants duplicate a Running claim, reuse a
cancelled Running slot, free that slot during stop or omit Done from admission accounting.
The witness first saturates the real capacity and then reaches shutdown with both workers
still owning jobs, retaining the cancelled distinguished slot. Native/E2E checks retain crypto
correctness, immutable bytes, setup failures, explicit held-gate behavior and generation IDs.
The base explores 274 states under the unchanged 10,000-state cap; all four mutants are killed.
