# Bounded Services state-proof queries

## Scope and authority

Current GP pin `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and existing
[service proof interfaces](state-proof-service.md) remain unchanged. Connect
one selected posterior complete state to bounded asynchronous host requests.
Public RPC method/schema assignment belongs to the RPC owner. Storage formats,
light mode, consensus/root discovery, PVM behavior and pin changes are excluded.

## Planned bounded increment

Capture one immutable selected block and detached semantic plan; generate,
verify and encode outside callbacks; preserve explicit block/root identity;
manage one reusable worker and one outstanding request; hold canonical/RPC
exclusion through Queued/Running/Done and cancellation until collection/join;
exercise Services end to end, failures, shutdown, non-copyability and ARC.

## Request admission

`captureProofQuery` accepts only an explicit successful selection and valid plan.
Cached complete-map entry/node counts, query counts, a minimum possible wire
extent and conservative hash work are checked before plan allocation. The work
bound is queries times (complete nodes + entries + min(path ceiling,249) +1):
all full-map node/value generation hashes plus verification path/value hashes.
This is a conservative admission ceiling, not measured CPU time or exact hashing.
Existing full-map/value/node policies additionally bound traversal, sorting and
copies during execution. Subtract/divide guards precede every sum/product.
The plan is detached from the caller's private owner before native submission.
Selected state still shares canonical ARC owners and requires the managed lease.

Completion: `application_proof_query_capture` covers genuine signed selection,
exact posterior identity, exact/short work, count/map/wire policies and defaults.
M1 framing/request namespace adoption is complete; full serialization/STF parity
remains open. Local model checking uses the separately pinned tool in `spec/model-checking.md`.
Deterministic native lifecycle tests retain explicit scope limits.

## Detached execution response

`executeProofQuery` is synchronous bounded worker work, never a dispatcher callback.
It generates from the retained complete selection, verifies exact planned facts
under its posterior root and encodes existing RPV1. Only detached wire plus fixed
block/root identities survive in `ProofResponse`; canonical aliases retire first.
Consumers must supply independent trust and copy policy. Nested generation/proof
and semantic/encoding failures remain typed and expose no prefix.
`application_proof_query_execution` independently receives the response, checks
identity, exact/short output policies, detached copies and generation refusal.

## Reusable native slot

`StateProofWorker` has one condition-driven thread and one slot. Successful
submission moves the caller query; refusal preserves it. A host-only retained
namespace and nonwrapping generation reject foreign/stale tickets. The host
polls scalar phase only. Queued/Running/Done and cancelled work retain capacity
and exclusive selected-state access until matching Done collection or joined
close. Execution temporaries retire before Done publication. Cancellation is
logical discard, never preemption of crypto/FFI. Close joins before dropping
query/result owners; live relocation/copy and unjoined destruction are forbidden.
`application_proof_worker` covers native generation, capacity, exact collection,
foreign/stale tokens, Done cancellation, reuse, restart and active joined close.

## Managed Services lease

`beginStateProof` selects an exact retained block before native submission, detaches the caller's
plan and finishes every temporary canonical ARC activation before the worker can execute.
Admission is private/guarded and preserves capture or worker failure reasons. An existing
preparation/publication/maintenance job, pending adoption or foreign RPC pause refuses admission.

Successful admission pauses RPC chain work and closes canonical reception, mutation and export
preparation gates. Scalar polling, logical cancellation and independent UI ticks remain available.
Cancelled/Done work retains the gate until matching collection or joined stop. Stopping preparation
cannot release a proof lease. Services close joins proofs before canonical/RPC aliases retire.
All external canonical aliases must remain alive and untouched for this exclusive ARC lease.
This is internal host integration; public RPC proof methods remain outside this increment.

`application_proof_services` covers genuine selected-state execution, fixed block/posterior root,
unknown selection, foreign RPC suspension, Busy retention, stale/default tickets, cancellation,
reuse, cross-worker stop isolation, detached output and active joined Services shutdown.

The six-variable `application_proof_services` model maps admission to the scalar exclusion
checks/pause/submission in `beginStateProof`, Running/Done to the native worker's synchronized
phase, collection to `collectStateProof`, joined release to `stopStateProofs`, and canonical
read to the checked `chainView` predicate. `other` abstracts an already admitted preparation
or disk job. `StopOther` maps `stopPreparation`'s proofing guard; cancelled work retains the
RPC token. The capture helper activation has already retired before the atomic admission;
its ARC implementation is checked by native execution and source review, not proven by this model.
The bounded model omits ticket identity, repeated generations, UI/transport bytes and proof
correctness. It must kill canonical-gate removal, foreign-stop resume and cancel-resume mutants,
and reach cancelled Done work that still owns its RPC lease.
