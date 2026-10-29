# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit host adapter limits and bounded native lifecycle helpers for genuine current receipts.
import std/[assertions, monotimes, times]
import ./[current_identity_context, current_namespace_refresh_context, accumulation_current_candidate_context]
import ../../src/app/current/logical as current_logical
import ../../src/app/preparation_worker
import "../../src/app/current/block/input" as current_block_input
import ../../src/app/[candidate, chain]
import ../../src/codec/[bounded, block_codec, header]
import ../../src/state/accumulation/current/update as accumulation_current_update
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield between synchronized scalar polls; every external canonical alias remains untouched.
proc collectedLogicalTestLimits*(): CollectedLogicalLimits =
  ## These independently stated ceilings cover two complete service namespaces without inferred budgets.
  CollectedLogicalLimits(identities: currentIdentityTestLimits, requests: namespaceRequestLimits,
    reconstruction: namespaceRefreshLimits, qualification: namespaceLogicalLimits())
proc waitPreparationDone*(worker: var PreparationWorker) =
  ## Done preserves the graph lease; matching collection or joined close must still follow.
  let start = getMonoTime()
  while worker.phase != PreparationPhase.Done:
    assert (getMonoTime()-start).inSeconds < 20
    discard pauseMicros(1000)
proc currentWire*(owner: OwnedBlock): seq[byte] =
  ## Encode the original immutable signed child under its exact already-admitted consumed extent.
  result = newSeq[byte](owner.blockInfo.value.consumed)
  assert owner.encodeOwnedBlock(result).error == FrameError.None
proc receiveCurrent*(input: var CurrentBlockInput, chain: ApplicationChain,
    wire: openArray[byte], ancestors: openArray[OwnedHeader],
    policies: CurrentCandidateLimits): CurrentBlockInputId =
  ## Complete byte reception on the host before the worker can borrow its exact original input/chain graph.
  let admitted = input.begin(chain, ByteLimit(uint64(wire.len)), ancestors,
    CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(wire.len)), ancestors: ElementLimit(4),
      ancestorBytes: ByteLimit(65536)), policies)
  assert admitted.error == CurrentBlockInputError.None
  assert input.append(admitted.value, wire, true) == CurrentBlockInputError.None
  admitted.value
