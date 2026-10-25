# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bounded proof request retains one explicitly selected posterior state and detached semantic plan.
## Capturing is host-side admission only; generation and authentication belong outside callbacks.
import std/assertions
import ./[light_head, checkpoint_identity]
import ../chain/[genesis, state_proof]
import ../state/[proof_service, proof_view, trie_proof, store, proof_plan, planned_proof]
import ../codec/[bounded, state_layout, state_trie]

type
  ProofHashLimit* = distinct uint64 ## Conservative admitted hash-call ceiling, separate from bytes and node counts.
  ProofQueryLimits* = object ## Independent full-map, path, batch, retained-view, wire and crypto-work ceilings.
    map*: StateTrieLimits
    proof*: StateProofLimits
    aggregate*: StateProofBatchLimits
    view*: ProofViewLimits
    wireBytes*: ByteLimit
    hashes*: ProofHashLimit
  ProofQueryError* {.pure.} = enum ## Failed/default requests expose no selected graph or partially generated response.
    Uninitialized, None, InvalidSelection, InvalidPlan, LimitExceeded, ProofFailure, ServiceFailure, ViewFailure
  QuerySourceKind {.pure.} = enum ## Complete-map generation and retained partial evidence have distinct private sources.
    Full, Light
  QueryData = ref object ## Immutable acyclic request; worker use requires exclusive access to every selected-state alias.
    plan: StateProofPlan
    serviceCompatibility: bool
    limits: ProofQueryLimits
    hashes: ProofHashLimit
    case source: QuerySourceKind
    of Full: selected: BlockSnapshotResult
    of Light: partial: LightApplicationHead
  ProofQuery* = object ## Root authority comes only from the explicit retained selection, never from response bytes.
    data: nil QueryData
  ProofQueryResult*[T] = object ## Only complete success owns its typed request/response payload.
    case status: ProofQueryError
    of None:
      completed: T
    of ProofFailure:
      proofReason: StateProofError
    of ServiceFailure:
      serviceReason: ServiceProofError
    of ViewFailure:
      viewReason: ProofViewError
    else:
      discard                   # Default and admission refusals have reasons alone.
func error*[T](outcome: ProofQueryResult[T]): ProofQueryError =
  ## Read a reason without authorizing payload access.
  outcome.status
func value*[T](outcome: ProofQueryResult[T]): T {.inline, requires: outcome.status ==
    ProofQueryError.None.} =
  ## Select only successful immutable payloads in checked optimized builds.
  outcome.completed
func proofError*[T](outcome: ProofQueryResult[T]): StateProofError {.requires: outcome.status ==
    ProofQueryError.ProofFailure.} =
  ## Preserve precise generation/authentication failure without exposing a response prefix.
  outcome.proofReason
func serviceError*[T](outcome: ProofQueryResult[T]): ServiceProofError {.requires: outcome.status ==
    ProofQueryError.ServiceFailure.} =
  ## Inspect only an actual semantic-view/encoding refusal.
  outcome.serviceReason
func viewError*[T](outcome: ProofQueryResult[T]): ProofViewError {.requires:
    outcome.status == ProofQueryError.ViewFailure.} =
  ## Generic planned-view failures retain their exact reason without exposing a response prefix.
  outcome.viewReason

func valid*(query: ProofQuery): bool =
  ## Default requests grant neither selected-state access nor work authority.
  query.data != nil
proc blockHash*(query: ProofQuery): BlockHash {.requires: query.data != nil.} =
  ## Retain exact selected block identity independently of transport framing.
  let data = query.data
  assert data != nil
  case data.source
  of QuerySourceKind.Full: data.selected.value.blockHash
  of QuerySourceKind.Light: data.partial.current.value.identity.blockHash # Trusted metadata is independent of partial fact coverage.
proc stateRoot*(query: ProofQuery): StateRoot {.requires: query.data != nil.} =
  ## The selected posterior commitment never substitutes its header's prior-state root.
  let data = query.data
  assert data != nil
  case data.source
  of QuerySourceKind.Full: data.selected.value.stateRoot
  of QuerySourceKind.Light: data.partial.stateRoot # A partial mapping never recomputes the complete JAM state root.
proc estimatedHashes*(query: ProofQuery): ProofHashLimit {.requires: query.data != nil.} =
  ## Expose the conservative admission bound, not a measured backend counter.
  let data = query.data
  assert data != nil
  data.hashes
proc captureProofQueryImpl(selected: BlockSnapshotResult, plan: StateProofPlan,
    limits: ProofQueryLimits, serviceCompatibility: bool): ProofQueryResult[ProofQuery] =
  ## Inspect cached complete-map counts and fixed plan metadata before allocation or hash work.
  if selected.error != GenesisError.None:
    return ProofQueryResult[ProofQuery](status: ProofQueryError.InvalidSelection)
  if not plan.valid:
    return ProofQueryResult[ProofQuery](status: ProofQueryError.InvalidPlan)
  let count = uint64(plan.len)
  if count > uint64(limits.aggregate.items) or count > uint64(limits.view.items):
    return ProofQueryResult[ProofQuery](status: ProofQueryError.LimitExceeded)
  let commitment = selected.value.stateSnapshot.commitment
  let nodes = commitment.nodes
  let entries = uint64(commitment.entries)
  if nodes > uint64(limits.map.nodes) or entries > uint64(limits.map.items):
    return ProofQueryResult[ProofQuery](status: ProofQueryError.LimitExceeded)
  let budget = uint64(limits.hashes)
  if nodes > budget or entries > budget-nodes:
    return ProofQueryResult[ProofQuery](status: ProofQueryError.LimitExceeded)
  var perQuery = nodes+entries
  let verification = min(uint64(limits.proof.nodes), 249'u64)+1
  if verification > budget-perQuery:
    return ProofQueryResult[ProofQuery](status: ProofQueryError.LimitExceeded)
  perQuery += verification
  if count > budget div perQuery:
    return ProofQueryResult[ProofQuery](status: ProofQueryError.LimitExceeded)
  if uint64(limits.wireBytes) < 8 or count > (uint64(limits.wireBytes)-8) div 45:
    return ProofQueryResult[ProofQuery](status: ProofQueryError.LimitExceeded)
  let detached = mergeStateProofPlans(plan, plan, limits.aggregate.items)
  if detached.error != ProofPlanError.None:
    return ProofQueryResult[ProofQuery](status: ProofQueryError.LimitExceeded)
  ProofQueryResult[ProofQuery](status: ProofQueryError.None,
    completed: ProofQuery(data: QueryData(source: QuerySourceKind.Full, selected: selected,
      plan: detached.value,
      limits: limits, hashes: ProofHashLimit(count*perQuery),
          serviceCompatibility: serviceCompatibility)))

proc captureProofQuery*(selected: BlockSnapshotResult, plan: StateProofPlan,
    limits: ProofQueryLimits): ProofQueryResult[ProofQuery] =
  ## Generic global/service requests keep exact planned-view failure reasons.
  captureProofQueryImpl(selected, plan, limits, false)
proc captureProofQuery*(selected: BlockSnapshotResult, plan: ServiceProofPlan,
    limits: ProofQueryLimits): ProofQueryResult[ProofQuery] =
  ## Preserve legacy service-result spelling while using the same detached generic plan owner.
  captureProofQueryImpl(selected, plan.toStateProofPlan, limits, true)

proc captureLightQuery(head: LightApplicationHead, plan: StateProofPlan,
    limits: ProofQueryLimits, serviceCompatibility: bool): ProofQueryResult[ProofQuery] =
  ## Admit fixed metadata and a detached bounded plan; no complete-map source or hashing work is required.
  if not head.valid: return ProofQueryResult[ProofQuery](
      status: ProofQueryError.InvalidSelection) # Defaults grant no root/header authority.
  if not plan.valid: return ProofQueryResult[ProofQuery](
      status: ProofQueryError.InvalidPlan) # A default plan cannot become an empty response.
  let count = uint64(plan.len)
  if count > uint64(limits.aggregate.items) or count > uint64(
      limits.view.items): return ProofQueryResult[ProofQuery](
      status: ProofQueryError.LimitExceeded) # Query retention is independent of source coverage.
  if uint64(limits.wireBytes) < 8 or count > (uint64(
      limits.wireBytes)-8) div 45: return ProofQueryResult[ProofQuery](
      status: ProofQueryError.LimitExceeded) # Prove the minimum canonical response extent before plan copying.
  let detached = mergeStateProofPlans(plan, plan, limits.aggregate.items)
  if detached.error != ProofPlanError.None: return ProofQueryResult[ProofQuery](
      status: ProofQueryError.LimitExceeded) # No partially copied plan escapes.
  ProofQueryResult[ProofQuery](status: ProofQueryError.None,
    completed: ProofQuery(data: QueryData(source: QuerySourceKind.Light, partial: head,
      plan: detached.value, limits: limits, hashes: ProofHashLimit(0),
          serviceCompatibility: serviceCompatibility)))
proc captureProofQuery*(head: LightApplicationHead, plan: StateProofPlan,
    limits: ProofQueryLimits): ProofQueryResult[ProofQuery] =
  ## Project only already verified retained facts under independently trusted current metadata.
  captureLightQuery(head, plan, limits, false)
proc captureProofQuery*(head: LightApplicationHead, plan: ServiceProofPlan,
    limits: ProofQueryLimits): ProofQueryResult[ProofQuery] =
  ## Preserve the established service error spelling while retaining a distinct partial source.
  captureLightQuery(head, plan.toStateProofPlan, limits, true)

type
  ResponseData = ref object ## Detached output shares no canonical snapshot, plan or raw proof graph.
    identity: BlockHash
    root: StateRoot
    wire: seq[byte]
  ProofResponse* = object ## Explicit identities describe the response; callers still select trust independently.
    data: nil ResponseData
func valid*(response: ProofResponse): bool =
  ## A default response never impersonates a successful empty envelope.
  response.data != nil
proc blockHash*(response: ProofResponse): BlockHash {.requires: response.data != nil.} =
  ## Return fixed selected identity after successful response selection.
  let data = response.data
  assert data != nil
  data.identity
proc stateRoot*(response: ProofResponse): StateRoot {.requires: response.data != nil.} =
  ## Preserve the posterior root used for generation and local verification.
  let data = response.data
  assert data != nil
  data.root
func byteLength*(response: ProofResponse): int =
  ## Fixed metadata inspection allocates no wire copy; defaults have no bytes.
  let data = response.data
  if data == nil: 0 else: data.wire.len
proc bytes*(response: ProofResponse, limit: ByteLimit): ProofQueryResult[seq[byte]] =
  ## Apply the consumer's own copy budget before returning detached mutable bytes.
  let data = response.data
  if data == nil:
    return ProofQueryResult[seq[byte]](status: ProofQueryError.Uninitialized)
  if uint64(data.wire.len) > uint64(limit):
    return ProofQueryResult[seq[byte]](status: ProofQueryError.LimitExceeded)
  var copied = newSeq[byte](data.wire.len)
  for i in 0..<copied.len: copied[i] = data.wire[i]
  ProofQueryResult[seq[byte]](status: ProofQueryError.None, completed: copied)
proc viewFailure(data: QueryData, reason: ProofViewError): ProofQueryResult[ProofResponse] =
  ## Generic callers retain view errors; existing service callers keep their established typed alternatives.
  if not data.serviceCompatibility:
    return ProofQueryResult[ProofResponse](status: ProofQueryError.ViewFailure, viewReason: reason)
  let translated = case reason
    of ProofViewError.LimitExceeded, ProofViewError.LengthOverflow: ServiceProofError.LimitExceeded
    of ProofViewError.Uninitialized: ServiceProofError.Uninitialized
    of ProofViewError.MissingWitness: ServiceProofError.MissingWitness
    of ProofViewError.NonCanonical: ServiceProofError.InvalidInput
    else: ServiceProofError.InvalidValue # Authenticated generation never fabricates a service value or response prefix.
  ProofQueryResult[ProofResponse](status: ProofQueryError.ServiceFailure, serviceReason: translated)

proc executeLightQuery(data: QueryData): ProofQueryResult[ProofResponse] {.requires: data.source ==
    QuerySourceKind.Light.} =
  ## Project immutable verified witnesses without complete-map generation or cryptographic work; all requested facts must exist.
  let limits = data.limits
  let projected = projectPlannedProofs(data.partial.proofView, data.plan, limits.view)
  if projected.error != ProofViewError.None: return viewFailure(data,
      projected.error) # Missing witnesses never become authenticated absence.
  let view = projected.value
  var nodes = 0'u64
  var values = 0'u64
  for index in 0..<view.len:
    # Retained immutable witness metadata suffices to recheck every independent aggregate channel before encoding.
    let proof = view.lookupAt(index).value.witness
    let count = uint64(proof.len)
    let size = uint64(proof.suppliedByteLength.value)
    if count > uint64(limits.proof.nodes) or size > uint64(limits.proof.valueBytes) or count >
        uint64(limits.aggregate.nodes)-nodes or size > uint64(
        limits.aggregate.valueBytes)-values: return ProofQueryResult[ProofResponse](
        status: ProofQueryError.ProofFailure,
        proofReason: StateProofError.LimitExceeded) # Previous totals prove subtraction and addition safe.
    nodes += count
    values += size
  let encoded = encodePlannedProofs(view, data.plan, limits.view, limits.proof, limits.wireBytes)
  if encoded.error == ProofViewError.ProofFailure: return ProofQueryResult[ProofResponse](
      status: ProofQueryError.ProofFailure, proofReason: encoded.proofError) # No successful wire prefix escapes.
  if encoded.error != ProofViewError.None: return viewFailure(data,
      encoded.error) # Preserve canonical scope and retention refusal.
  ProofQueryResult[ProofResponse](status: ProofQueryError.None,
    completed: ProofResponse(data: ResponseData(identity: data.partial.current.value.identity.blockHash,
      root: data.partial.stateRoot, wire: encoded.value)))
proc executeProofQuery*(query: ProofQuery): ProofQueryResult[ProofResponse] =
  ## Run bounded complete-map generation/authentication or verified partial projection, then encode outside dispatcher callbacks.
  let data = query.data
  if data == nil:
    return ProofQueryResult[ProofResponse](status: ProofQueryError.Uninitialized)
  if data.source == QuerySourceKind.Light: return executeLightQuery(
      data) # Explicit partial evidence never enters complete-map generation.
  let limits = data.limits
  let generated = generateBlockPlannedProofs(data.selected, data.plan, limits.map,
    limits.proof, limits.aggregate)
  if generated.error != StateProofError.None:
    return ProofQueryResult[ProofResponse](status: ProofQueryError.ProofFailure,
        proofReason: generated.error)
  var queries = newSeq[StateProofQuery](generated.value.len)
  for i in 0..<queries.len:
    # Raw paths are copied as immutable handles only within this exclusively leased worker activation.
    queries[i] = generated.value.queryAt(i).value
  let root = data.selected.value.stateRoot
  let checked = verifyPlannedProofs(data.plan, queries, root, limits.proof, limits.aggregate, limits.view)
  if checked.error == ProofViewError.ProofFailure:
    return ProofQueryResult[ProofResponse](status: ProofQueryError.ProofFailure,
        proofReason: checked.proofError)
  if checked.error != ProofViewError.None:
    return viewFailure(data, checked.error)
  let encoded = encodePlannedProofs(checked.value, data.plan, limits.view, limits.proof,
      limits.wireBytes)
  if encoded.error == ProofViewError.ProofFailure:
    return ProofQueryResult[ProofResponse](status: ProofQueryError.ProofFailure,
        proofReason: encoded.proofError)
  if encoded.error != ProofViewError.None:
    return viewFailure(data, encoded.error)
  ProofQueryResult[ProofResponse](status: ProofQueryError.None,
    completed: ProofResponse(data: ResponseData(identity: data.selected.value.blockHash,
      root: root, wire: encoded.value)))
