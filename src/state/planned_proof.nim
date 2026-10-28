# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact generic plan authentication and existing RPV1 transport under independent root authority.
## No encoded root, service selector or partial map can substitute for caller-selected trust.
import std/assertions
import ./proof_plan as state_proof_plan
import ./proof_view as state_proof_view
import ./trie_proof as state_trie_proof
import ../codec/bounded as codec_bounded
import ../codec/state_layout as codec_state_layout
import ../codec/state_trie as codec_state_trie

type PlannedProofResult*[T] = object ## Private plan-scoped outcomes preserve existing view/proof reasons without public success forgery.
  case status: ProofViewError
  of None: completed: T
  of ProofFailure: proofReason: StateProofError
  else: discard # Refusals never expose a partial verified view or encoded prefix.
func error*[T](outcome: PlannedProofResult[T]): ProofViewError =
  ## Preserve exact view reasons without extracting payloads.
  outcome.status
func value*[T](outcome: PlannedProofResult[T]): T {.inline,
    requires: outcome.status == ProofViewError.None.} =
  ## Complete planned success alone grants payload access.
  outcome.completed
func proofError*[T](outcome: PlannedProofResult[T]): StateProofError {.inline,
    requires: outcome.status == ProofViewError.ProofFailure.} =
  ## Nested authentication/backend failure remains distinct from framing and scope refusal.
  outcome.proofReason
proc fromView[T](outcome: ProofViewResult[T]): PlannedProofResult[T] =
  ## Translate only already guarded owner results, preserving every precise error and success payload.
  case outcome.error
  of ProofViewError.None:
    PlannedProofResult[T](status: ProofViewError.None, completed: outcome.value)
  of ProofViewError.ProofFailure:
    PlannedProofResult[T](status: ProofViewError.ProofFailure, proofReason: outcome.proofError)
  else:
    PlannedProofResult[T](status: outcome.error) # Ordinary refusals own no payload alternative.

proc matchesStateProofPlan*(view: ProofView, plan: StateProofPlan): PlannedProofResult[bool] =
  ## Compare the exact canonical key set, retaining unknown versus proven-absent distinctions.
  if not plan.valid or not view.valid:
    return PlannedProofResult[bool](status: ProofViewError.Uninitialized)
  if plan.len != view.len:
    return PlannedProofResult[bool](status: ProofViewError.None, completed: false)
  for i in 0..<plan.len:
    # Fixed copied identities suffice; neither side exports mutable backing storage.
    if array[31, byte](plan.keyAt(i).value) != array[31, byte](view.lookupAt(i).value.key):
      return PlannedProofResult[bool](status: ProofViewError.None, completed: false)
  PlannedProofResult[bool](status: ProofViewError.None, completed: true)

proc verifyPlannedProofs*(plan: StateProofPlan, queries: openArray[StateProofQuery],
    expectedRoot: StateRoot, perProof: StateProofLimits, aggregate: StateProofBatchLimits,
    viewLimits: ProofViewLimits): PlannedProofResult[ProofView] =
  ## Refuse every omitted/substituted/reordered query before atomic bounded authentication.
  if not plan.valid:
    return PlannedProofResult[ProofView](status: ProofViewError.Uninitialized)
  if queries.len != plan.len:
    return PlannedProofResult[ProofView](status: ProofViewError.NonCanonical)
  for i in 0..<plan.len:
    # An adversarial valid proof for a different key cannot consume this request's crypto work.
    if array[31, byte](plan.keyAt(i).value) != array[31, byte](queries[i].key):
      return PlannedProofResult[ProofView](status: ProofViewError.NonCanonical)
  let effective = StateProofBatchLimits(
    items: ElementLimit(min(uint64(aggregate.items), uint64(viewLimits.items))),
    nodes: aggregate.nodes,
    valueBytes: ByteLimit(min(uint64(aggregate.valueBytes), uint64(viewLimits.valueBytes))))
  let verified = verifyStateProofs(queries, expectedRoot, perProof, effective)
  if verified.error != StateProofError.None:
    return PlannedProofResult[ProofView](status: ProofViewError.ProofFailure,
        proofReason: verified.error)
  fromView(captureProofView(verified.value, expectedRoot, viewLimits))

proc encodePlannedProofs*(view: ProofView, plan: StateProofPlan, limits: ProofViewLimits,
    perProof: StateProofLimits, wireBytes: ByteLimit): PlannedProofResult[seq[byte]] =
  ## Encode only exact requested facts in unchanged canonical RPV1 bytes.
  let matched = matchesStateProofPlan(view, plan)
  if matched.error != ProofViewError.None:
    return PlannedProofResult[seq[byte]](status: matched.error)
  if not matched.value:
    return PlannedProofResult[seq[byte]](status: ProofViewError.NonCanonical)
  fromView(encodeProofView(view, limits, perProof, wireBytes))

proc decodePlannedProofs*(input: openArray[byte], plan: StateProofPlan,
    expectedRoot: StateRoot, limits: ProofViewLimits, perProof: StateProofLimits,
    aggregate: StateProofBatchLimits, wireBytes: ByteLimit): PlannedProofResult[ProofView] =
  ## One shared decoder preflights declared scope, framing and budgets before any authentication.
  let effective = StateProofBatchLimits(
    items: ElementLimit(min(uint64(aggregate.items), uint64(limits.items))),
    nodes: aggregate.nodes,
    valueBytes: ByteLimit(min(uint64(aggregate.valueBytes), uint64(limits.valueBytes))))
  fromView(decodeProofView(input, expectedRoot, limits, perProof, effective, wireBytes, plan))

proc projectPlannedProofs*(source: ProofView, plan: StateProofPlan,
    limits: ProofViewLimits): PlannedProofResult[ProofView] =
  ## Retain exactly the requested existing evidence under the same root; missing facts refuse atomically.
  if not plan.valid or not source.valid:
    return PlannedProofResult[ProofView](status: ProofViewError.Uninitialized)
  if uint64(plan.len) > uint64(limits.items) or plan.len > high(int) div sizeof(StateKey):
    return PlannedProofResult[ProofView](status: ProofViewError.LimitExceeded)
  var keys = newSeq[StateKey](plan.len)
  for i in 0..<plan.len:
    keys[i] = plan.keyAt(i).value # Detach only bounded fixed identities; root authority stays with the source.
  fromView(projectProofView(source, keys, limits))
