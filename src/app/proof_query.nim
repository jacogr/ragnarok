# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bounded proof request retains one explicitly selected posterior state and detached semantic plan.
## Capturing is host-side admission only; generation and authentication belong outside callbacks.
import std/assertions
import ../chain/genesis
import ../state/[proof_service, proof_view, trie_proof, store]
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
    Uninitialized, None, InvalidSelection, InvalidPlan, LimitExceeded, ProofFailure, ServiceFailure
  QueryData = ref object ## Immutable acyclic request; worker use requires exclusive access to all selected-state aliases.
    selected: BlockSnapshotResult
    plan: ServiceProofPlan
    limits: ProofQueryLimits
    hashes: ProofHashLimit
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
func valid*(query: ProofQuery): bool =
  ## Default requests grant neither selected-state access nor work authority.
  query.data != nil
proc blockHash*(query: ProofQuery): BlockHash {.requires: query.data != nil.} =
  ## Retain exact selected block identity independently of transport framing.
  let data = query.data
  assert data != nil
  data.selected.value.blockHash
proc stateRoot*(query: ProofQuery): StateRoot {.requires: query.data != nil.} =
  ## The selected posterior commitment never substitutes its header's prior-state root.
  let data = query.data
  assert data != nil
  data.selected.value.stateRoot
proc estimatedHashes*(query: ProofQuery): ProofHashLimit {.requires: query.data != nil.} =
  ## Expose the conservative admission bound, not a measured backend counter.
  let data = query.data
  assert data != nil
  data.hashes
proc captureProofQuery*(selected: BlockSnapshotResult, plan: ServiceProofPlan,
    limits: ProofQueryLimits): ProofQueryResult[ProofQuery] =
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
  let detached = mergeProofPlans(plan, plan, limits.aggregate.items)
  if detached.error != ServiceProofError.None:
    return ProofQueryResult[ProofQuery](status: ProofQueryError.LimitExceeded)
  ProofQueryResult[ProofQuery](status: ProofQueryError.None,
    completed: ProofQuery(data: QueryData(selected: selected, plan: detached.value,
      limits: limits, hashes: ProofHashLimit(count*perQuery))))
