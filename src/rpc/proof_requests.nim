# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Connection-local bounded proof selectors, independent of canonical state and native worker lifetime.
## Immutable namespace identities prevent stale or foreign completions from consuming a replacement slot.
import ../state/proof_plan
import ../codec/[bounded, state_layout]
from ../chain/genesis import BlockHash
export proof_plan, BlockHash, StateKey

const MaxRpcProofKeys* = 16 ## One immutable request retains at most sixteen exact serialized selectors.
type
  ProofNamespace = ref object ## Retained host-only identity prevents connection-reset ABA without wrapping counters.
    marker: uint8
  RpcProofRequest* = object ## A selector is neither a selected snapshot nor proof/root authority.
    owner: nil ProofNamespace
    identity: uint32
    selected: BlockHash
    selectors: StateProofPlan
  RpcProofState* = object ## One queued/taken slot and one nonwrapping ID sequence belong to this connection.
    owner: nil ProofNamespace
    last: uint32
    current: RpcProofRequest
    taken: bool
  RpcProofError* {.pure.} = enum ## Failed admissions grant neither an ID nor retained selectors.
    Uninitialized, None, Busy, InvalidSelectors, Exhausted
  RpcProofAdmission* = object ## Only complete capture returns an immutable request identity.
    case status: RpcProofError
    of None: completed: RpcProofRequest
    else: discard             # Defaults and failures contain no partially admitted selectors.
func error*(outcome: RpcProofAdmission): RpcProofError =
  ## Read admission status before selecting its payload.
  outcome.status
func value*(outcome: RpcProofAdmission): RpcProofRequest {.requires: outcome.status ==
    RpcProofError.None.} =
  ## Return only an admitted immutable request.
  outcome.completed
func valid*(request: RpcProofRequest): bool =
  ## Default requests grant no completion or selection authority.
  request.owner != nil and request.identity != 0
func id*(request: RpcProofRequest): uint32 {.requires: request.valid.} =
  ## Public wire identity is scoped to the originating connection.
  request.identity
func blockHash*(request: RpcProofRequest): BlockHash {.requires: request.valid.} =
  ## The host resolves this exact hash after RPC request contexts have retired.
  request.selected
func plan*(request: RpcProofRequest): StateProofPlan {.requires: request.valid.} =
  ## Capture supplied fixed keys only; no canonical graph is retained.
  request.selectors
func active*(state: RpcProofState): bool =
  ## A taken request continues to occupy capacity until cancellation or exact completion.
  state.current.valid
proc enqueue*(state: var RpcProofState, selected: BlockHash,
    keys: openArray[StateKey]): RpcProofAdmission =
  ## Validate and detach selectors before reserving a nonzero ID; refusal preserves existing state.
  if state.active: return RpcProofAdmission(status: RpcProofError.Busy)
  if keys.len == 0 or keys.len > MaxRpcProofKeys:
    return RpcProofAdmission(status: RpcProofError.InvalidSelectors)
  let captured = captureStateProofPlan(keys, ElementLimit(MaxRpcProofKeys))
  if captured.error != ProofPlanError.None:
    return RpcProofAdmission(status: RpcProofError.InvalidSelectors) # Duplicates cannot silently widen/coalesce caller intent.
  if state.last == high(uint32): return RpcProofAdmission(status: RpcProofError.Exhausted)
  if state.owner == nil: state.owner = ProofNamespace(
      marker: 1) # Allocate a namespace only for successful admission.
  inc state.last
  state.current = RpcProofRequest(owner: state.owner, identity: state.last,
    selected: selected, selectors: captured.value)
  state.taken = false
  RpcProofAdmission(status: RpcProofError.None, completed: state.current)
proc take*(state: var RpcProofState): RpcProofRequest =
  ## Host dispatch claims the selector once without releasing the connection slot.
  if not state.active or state.taken: return default(RpcProofRequest)
  state.taken = true
  state.current
proc cancel*(state: var RpcProofState, id: uint32): bool =
  ## Logical cancellation never joins or mutates the worker; the host separately retires its lease.
  if not state.active or state.current.identity != id: return false
  state.current = default(RpcProofRequest)
  state.taken = false
  true
func matches*(state: RpcProofState, request: RpcProofRequest): bool =
  ## Namespace and monotonic ID jointly reject foreign, stale, cancelled and connection-reset replies.
  state.active and request.valid and state.taken and state.owner == request.owner and
    state.current.identity == request.identity
proc finish*(state: var RpcProofState, request: RpcProofRequest): bool =
  ## Completion consumes only the exact claimed request; cancelled work cannot resurrect it.
  if not state.matches(request): return false
  state.current = default(RpcProofRequest)
  state.taken = false
  true
