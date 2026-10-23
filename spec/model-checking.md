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

The new `src/app/proof_worker.nim` uses the same lock/condition/phase/stop transitions. Its
`submit` moves an admitted immutable query into the slot instead of borrowing input pointers;
`collect` and joined `close` retire that owner. The same six-variable model checks its lease
retention and join ordering. Query move semantics, exact proof outcomes and ticket identity
remain covered by the native `application_proof_worker` suite and compiler ownership probe.
