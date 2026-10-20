# State storage and transitions

[Design overview](../design.md). Detailed feature contracts live in `spec/`; routine increments
update their feature contract rather than appending progress here.

`src/state/` owns the in-memory serialized-state store: atomic write batches publish complete
immutable snapshots and recompute roots through the existing Merklization implementation.
`src/state/checkpoint.nim` encodes and verifies versioned local full-map checkpoints;
`checkpoint_file.nim` bounds synchronous startup reads and publishes complete sibling files
through the bounded `src/lib/atomic_file.nim` byte-publication primitive: POSIX file sync,
atomic replacement and directory sync. See the
[checkpoint contract](../../spec/state-checkpoint.md). These are full-state snapshots,
not light-state databases or authenticated chain-head recovery.

Snapshots can fork private complete-map working stores with inherited resource ceilings; branches share
only immutable prior owners and publish independently.
The standalone [`storage/full_state_trie`](../../src/storage/README.md) provides immutable
incremental full-map revisions with shared subtrees; integration into this store is a later increment.
See [the trie contract](../../spec/full-state-trie.md) and
[the storage contract](../../spec/state-store.md). Native replay verifies seven published pre/post mapping pairs; this is not state-transition
execution.

`src/state/authorization.nim` implements the first bounded non-PVM transition: authorization
pool advancement from validated guarantee projections and post-accumulation queues. Its store
adapter atomically replaces C(1), preserving C(2) and unrelated entries. See
[the transition contract](../../spec/authorization-transition.md); whole-block execution remains open.

`src/state/history.nim` adds parent-state-root correction, accumulation-output Keccak trees,
belt/super-peak advancement and bounded recent-history updates through the C(3) store adapter.
See [the history transition contract](../../spec/history-transition.md) for scheduling and the
clarified hash-token notation; these components do not execute accumulation.

`src/state/entropy.nim` advances the fixed entropy accumulator/history and timeslot, with one
rotation on epoch crossing and atomic C(6)/C(11) publication. See
[the transition contract](../../spec/entropy-transition.md); VRF authentication and the rest of Safrole
remain separate stages.

`src/state/validators.nim` plans epoch roster rotation and complete offender-record nulling from
immutable snapshots. `src/state/validator_state.nim` recomputes the profile-bound pending ring root
and atomically publishes C(4)/C(8)/C(9), preserving schedules and accumulators.
[The contract](../../spec/validator-rotation.md) defines pre-time-advancement ordering; complete Safrole
ticket/schedule/marker execution remains open.

`src/state/ticket_admission.nim` verifies Safrole RingVRF tickets, checks eligibility/order/
disjointness and selects the bounded posterior accumulator. [Its first-slice contract](../../spec/ticket-admission.md)
returns an immutable C(4) candidate. `src/state/ticket_state.nim` atomically publishes it after
checking staged entropy/time inputs. `src/state/sealer_schedule.nim` selects the current schedule
from separate parent/staged C(4), posterior active keys and entropy, covering outside-in tickets
and fallback generation. `src/state/sealer_state.nim` retains the parent snapshot and atomically
publishes only C(4) after checking staged C(4)/C(6)/C(8)/C(11). The
[schedule contract](../../spec/sealer-schedule.md) defines this substep's rollback boundary; header
marker derivation/comparison now lives in `src/state/safrole_markers.nim`. It binds parent
entropy/contest and posterior pending keys to immutable expected header fields. See
[the marker contract](../../spec/safrole-markers.md). `src/state/marker_state.nim` checks decoded
unsigned headers against retained parent and staged snapshots without writes or hashing. Entropy-VRF,
seal authentication now lives in `src/state/safrole_authentication.nim`. It binds the indexed
posterior active author and cyclic schedule entry to both ordinary VRF proofs, retaining the exact
header and verified entropy. See [the authentication contract](../../spec/safrole-authentication.md);
`src/state/authentication_state.nim` supplies parent history/time and posterior schedule/active
keys without requiring the new entropy accumulator to exist. Authenticated output feeds the existing
atomic entropy/time updater. `src/state/safrole_transition.nim` now coordinates validator rotation,
ticket admission, schedules, markers and authenticated entropy on private candidates, then publishes
changed C(4)/C(6)/C(8)/C(9)/C(11) in one atomic batch. See [the stage contract](../../spec/safrole-transition.md).
`src/state/block_admission.nim` now binds a single immutable block to its full parent header, complete
parent-state root and five-family extrinsic commitment, then extracts that block's own tickets for
Safrole. `src/crypto/extrinsic_commitment.nim` implements the special preimage/report hash projections.
See [the admission contract](../../spec/block-admission.md). `src/state/disputes.nim` now validates
verdicts/evidence and plans C(5)/C(10), including exact new-offender markers.
`src/state/block_transition.nim` composes admission, derived disputes offenders and Safrole on a
private map, publishing only on complete success. See [the disputes contract](../../spec/disputes-transition.md)
for pinned STF coverage and two dummy-assignment fixture incompatibilities.
`src/state/availability.nim` now verifies assurances using parent keys, retains newly available
reports, and advances post-disputes C(10) for strict supermajority, timeout and population-size
changes. The block coordinator includes this stage before its final publication; see
[the availability contract](../../spec/availability-transition.md). New guarantee assignment is now integrated below; accumulation,
wall-clock admission and whole-block execution remain open.
`src/state/guarantors.nim` supplies immutable current/previous rotation assignments from posterior
rosters, entropy and offenders. See [the assignment contract](../../spec/guarantor-assignments.md);
`src/state/guarantee_credentials.nim` now verifies the exact report signatures, current-core/shard
constraints and unique reporter keys against those assignments. See
[the credential contract](../../spec/guarantee-credentials.md).
`src/state/report_policy.nim` consumes certified credentials and retains their exact parent map after
checking C(1) authorizer membership, per-report gas and each service's code/minimum gas. See
[the policy contract](../../spec/report-policy.md).
`src/state/report_anchors.nim` checks the complete recent-history tuple and lookup age, then verifies
lookup hashes/slots and child-committed roots on a bounded chain of full sealed headers linked to
caller-supplied trusted parent context. See [the anchor contract](../../spec/report-anchors.md).
`src/state/report_packages.nim` checks package uniqueness against recent/current reports and the
prior pipeline, resolves prerequisites and exact segment-root pairs, and derives existing identities
from parent C(10)/C(14)/C(15). See [the package contract](../../spec/report-packages.md).
`src/state/report_assignments.nim` plans new C(10) assignments only on vacant post-assurance cores,
using candidate time and active population retained in the credential certificate. It preserves
untouched guarantees and registration times; see [the assignment contract](../../spec/report-assignments.md).
`src/state/report_admission.nim` now binds all those checks to one private successful coordinator
result, deriving the actual block/parent, corrected history, posterior credentials and post-assurance
capacity. See [the binding contract](../../spec/report-admission.md).
`src/state/report_transition.nim` now composes that planner with the earlier coordinator on one
private working store and publishes the final C(10) only on complete success. See
[the atomic publication contract](../../spec/report-transition.md). Accumulation history/queue
planning now lives in `src/state/accumulation_queue.nim`: it derives the exact assurance output and
parent C(14)/C(15) from completed report admission, then computes dependency removal and deterministic
ready waves without writes. See [the queue contract](../../spec/accumulation-queue.md). Per-service
operand preparation is next; PVM execution and full block execution remain later work.

`src/state/accumulation_fetch.nim` connects a selected prepared input group to the PVM
fetch boundary. It preserves preparation order and owns bounded encoded bytes without
executing a service or certifying block provenance. See [the adapter contract](../../spec/pvm-fetch-invocation.md).

Reentry preparation and completion share a private immutable certificate graph in
`src/state/accumulation_reentry.nim`. This keeps repeated advance source-authenticated without
exporting raw construction fields or creating a module dependency cycle. The execution import
module remains a narrow compatibility facade; bounded history retains an immediate predecessor
and direct original block provenance. See [the repeated reentry contract](../../spec/accumulation-reentry-cycle.md).

## Full and light node modes

The client will support full and light operation selected by a command-line mode flag. Startup
will choose the corresponding mode-specific database; full and light data/schema requirements
must remain separate. In-memory backends may also differ, sharing only operations with matching
semantics. No database backend or mode flag is implemented by the current storage increment.

`src/state/store.nim` is a complete-map in-memory execution store. Light-node verified roots,
partial state and proofs require a separate appropriate contract; hashing partial data through
this complete-map calculator cannot establish the full state root. Codecs and Merklization
primitives remain shared, with mode selection at the application boundary.

## Accumulation successor boundary

Execution owns stopped continuation/reentry selection and the immutable
`PreparedFinalAccumulation` successor, including selected effects, output/gas
history, complete state and authenticated original block provenance. State's
`prepareAccumulationComposition` consumes that owner and state-only policies;
state owns history/statistics/authorization/consensus composition and exact-parent
final publication. Neither side accepts a detached map as a replacement execution
certificate. See [the shared boundary contract](../../spec/pvm-state-successor.md).
