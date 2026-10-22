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
