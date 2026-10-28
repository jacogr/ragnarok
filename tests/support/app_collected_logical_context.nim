# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit host adapter limits and bounded native lifecycle helpers for genuine current receipts.
import std/assertions
import std/monotimes
import std/times
import ./state_current_identity_context
import ./state_current_namespace_refresh_context
import ./state_accumulation_current_candidate_context
import ../../src/app/current_logical as app_current_logical
import ../../src/app/preparation_worker as app_preparation_worker
import ../../src/app/current_block_input as app_current_block_input
import ../../src/app/candidate as app_candidate
import ../../src/app/chain as app_chain
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/header as codec_header
import ../../src/state/accumulation_current_update as state_accumulation_current_update
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
