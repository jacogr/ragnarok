# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Capture scalar checkpoint context from one selected application head and its exact canonical complete map.
## This metadata is not a consensus certificate or authorization to adopt a recovered chain.

import ./chain
import ../chain/[genesis, provider, parameters]
import ../state/store
import ../codec/state_trie

type
  ApplicationCheckpointSlot* = distinct uint32 ## Captured block time remains distinct from disk generations and slot-file selectors.
  ApplicationCheckpointIdentity* = object ## Fixed-size metadata retains no state, header or history ARC graph.
    initialized: bool
    blockIdentity: BlockHash
    stateCommitment: StateRoot
    timeslot: ApplicationCheckpointSlot
    configuration: Parameters
  ApplicationCheckpointIdentityError* {.pure.} = enum ## Defaults and refused captures expose no partially usable binding.
    Uninitialized, None, MissingHead, StateMismatch
  ApplicationCheckpointIdentityResult* = object ## Only a successful exact-owner capture grants initialized metadata.
    case status: ApplicationCheckpointIdentityError
    of None:
      completed: ApplicationCheckpointIdentity
    else:
      discard # Default or mismatched context carries only its refusal.
func ready*(identity: ApplicationCheckpointIdentity): bool =
  ## Initialization is separate from valid zero-valued roots or timeslots.
  identity.initialized
func error*(outcome: ApplicationCheckpointIdentityResult): ApplicationCheckpointIdentityError =
  ## Inspect refusal without extracting or changing a binding.
  outcome.status
func value*(outcome: ApplicationCheckpointIdentityResult): ApplicationCheckpointIdentity {.inline,
    requires: outcome.status == ApplicationCheckpointIdentityError.None.} =
  ## Failed/default captures cannot expose scalar context for publication.
  outcome.completed
func blockHash*(identity: ApplicationCheckpointIdentity): BlockHash {.inline,
    requires: identity.initialized.} =
  ## The exact sealed-header identity differs from both prior and posterior state roots.
  identity.blockIdentity
func stateRoot*(identity: ApplicationCheckpointIdentity): StateRoot {.inline,
    requires: identity.initialized.} =
  ## This is the selected complete posterior map root, never the header's prior-state field.
  identity.stateCommitment
func slot*(identity: ApplicationCheckpointIdentity): ApplicationCheckpointSlot {.inline,
    requires: identity.initialized.} =
  ## Preserve the selected header/map time without granting disk-generation authority.
  identity.timeslot
func parameters*(identity: ApplicationCheckpointIdentity): Parameters {.inline,
    requires: identity.initialized.} =
  ## Copy the complete immutable scalar tuple, including fields unrelated to Merklization.
  identity.configuration
proc sameApplicationCheckpoint*(left, right: ApplicationCheckpointIdentity): bool =
  ## Root equality alone cannot substitute for exact block, time and complete profile agreement; defaults never match.
  if not left.ready or not right.ready: return false # Zero-filled metadata is not an initialized checkpoint context.
  array[32, byte](left.blockIdentity) == array[32, byte](right.blockIdentity) and
    array[32, byte](left.stateCommitment) == array[32, byte](right.stateCommitment) and
    uint32(left.timeslot) == uint32(right.timeslot) and
    left.configuration.encodeParameters == right.configuration.encodeParameters
proc captureApplicationCheckpointIdentity*(chain: ApplicationChain): ApplicationCheckpointIdentityResult =
  ## Capture from the private canonical pair, proving exact immutable map ownership before retaining only scalars.
  let selected = chain.chainView.bestBlock
  if selected.error != GenesisError.None:
    return ApplicationCheckpointIdentityResult(status: ApplicationCheckpointIdentityError.MissingHead) # Missing context cannot be inferred from a root or empty map.
  let state = chain.stateSnapshot
  if state.error != StateStoreError.None or not sameStateSnapshot(state.value,
      selected.value.stateSnapshot):
    return ApplicationCheckpointIdentityResult(status: ApplicationCheckpointIdentityError.StateMismatch) # Independently reconstructed equal roots do not prove canonical owner agreement.
  let head = selected.value
  ApplicationCheckpointIdentityResult(status: ApplicationCheckpointIdentityError.None,
    completed: ApplicationCheckpointIdentity(initialized: true, blockIdentity: head.blockHash,
      stateCommitment: state.value.commitment.root, timeslot: ApplicationCheckpointSlot(head.slot),
      configuration: head.chainParameters))
