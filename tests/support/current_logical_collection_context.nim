# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Test-owned real Services preparation/collection and independently bounded State logical refresh for actual host consumers.
import std/[assertions, monotimes, times]
import std/posix/posix
import ./[current_identity_context, current_namespace_refresh_context]
import ../../src/app/[services, preparation_worker, current_block_input, candidate]
import ../../src/rpc/server
import ../../src/codec/[bounded, block_codec]
import ../../src/state/[accumulation_current_update, current_identities, current_request_keys,
    current_refresh_plan, current_logical_refresh, current_logical]
proc collectLogicalChild*(owner: var Services, input: var CurrentBlockInput, child: OwnedBlock,
    policies: CurrentCandidateLimits): PreparedCurrentChainUpdate {.raises.} =
  ## Encode and bind on the open host gate; the exact native lease stays exclusive until matching collection, including Done/stale observations.
  var wire = newSeq[byte](child.blockInfo.value.consumed)
  assert child.encodeOwnedBlock(wire).error == FrameError.None
  let received = owner.beginBlockInput(input, ByteLimit(uint64(wire.len)), [],
      CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(wire.len)),
          ancestorBytes: ByteLimit(10000), ancestors: ElementLimit(4)), policies)
  assert received.error == CurrentBlockInputError.None
  assert input.append(received.value, wire, true) == CurrentBlockInputError.None
  let ticket = owner.beginPreparation(input, received.value)
  assert ticket.error == PreparationError.None
  let started = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    owner.tick(0)
    var delay = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(delay, remaining) # No retained graph owner is accessed, copied or retired during native borrowing.
  assert owner.preparationActive and owner.rpc.chainPaused
  assert owner.collectPreparation(default(PreparationTicket)).kind ==
      PreparationCompletionKind.Uninitialized
  assert owner.preparationActive and owner.preparationPhase == PreparationPhase.Done
  let completed = owner.collectPreparation(ticket.value)
  assert completed.kind == PreparationCompletionKind.CurrentCompleted
  assert completed.currentValue.error == CurrentBlockInputError.None
  assert not owner.preparationActive and not owner.rpc.chainPaused
  assert owner.preparationAvailable and owner.stateProofAvailable
  completed.currentValue.value
proc refreshCollectedIdentities*(source: PreservedCurrentIdentities): CurrentLogicalState =
  ## Every actual opaque predecessor is checked under explicit independent namespace policies before extraction; no enqueue or installation occurs here.
  let keys = captureCurrentRequestKeys(source, namespaceRequestLimits)
  assert keys.error == CurrentRequestKeyError.None
  let reconstruction = planCurrentRefresh(keys.value, namespaceRefreshLimits)
  assert reconstruction.error == CurrentRefreshPlanError.None
  let plan = planCurrentLogicalRefresh(reconstruction.value, namespaceLogicalLimits())
  assert plan.error == LogicalRefreshPlanError.None
  let logical = executeCurrentLogicalRefresh(plan.value)
  assert logical.error == LogicalRefreshError.None
  logical.value
