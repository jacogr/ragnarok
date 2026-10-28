# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict runtime result-extraction probes for resolved accumulation services and bound provenance.
## Dynamic modes require the selected-success diagnostic for defaults, refusals and unavailable code.

import std/cmdline
import ../../src/state/accumulation_service as state_accumulation_service
import ../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../src/state/accumulation_operands as state_accumulation_operands
import ../../src/state/accumulation_queue as state_accumulation_queue
import ../../src/state/accumulation_round as state_accumulation_round
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/codec/state_privileges as codec_state_privileges
import ../../src/codec/state_workqueues as codec_state_workqueues
import ../../src/codec/header as codec_header
import ../../src/codec/state_trie as codec_state_trie

## Build an actual existing account with absent code; this successful context must refuse code extraction.
proc unavailable(): PreparedAccumulationService =
  let queue = planAccumulationQueues([], [0'u8], [0'u8], HeaderSlot(0),
    AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(2), epochSlots: EpochSlots(1),
      maxBytes: ByteLimit(1000)))).value
  let operands = prepareAccumulationOperands(queue, AccumulationReportPrefix(0), default(
      AccumulationOperandConfig)).value
  let inputs = prepareAccumulationInputs(operands, [], [AlwaysAccumulate()],
    AccumulationInputConfig(allowances: ElementLimit(1), services: ElementLimit(1))).value
  let entry = serviceMetadataEntry(ServiceIndex(0), ServiceMetadata(), ByteLimit(
      ServiceMetadataBytes)).value
  let state = newStateStore([entry], StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(1),
    perValue: ByteLimit(ServiceMetadataBytes), totalValueBytes: ByteLimit(ServiceMetadataBytes),
        nodes: TrieNodeLimit(1)))).value.snapshot.value
  prepareAccumulationService(inputs, InvocationServiceIndex(0), state, HeaderSlot(0),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(100), preimageBytes: ByteLimit(100))).value

# Dynamic choices preserve runtime result-contract failures rather than constant-invalid compilation.
let owner = if paramStr(1) == "unavailable": unavailable()
else: default(PreparedAccumulationService) # No usable account or code.
let outcome = if paramStr(1) == "refused":
  prepareAccumulationService(default(PreparedAccumulationInputs), InvocationServiceIndex(0),
    default(StateStoreSnapshot), HeaderSlot(0), default(AccumulationServiceConfig))
else: default(AccumulationServiceResult[PreparedAccumulationService]) # Defaults carry no success value.
let bound = default(BlockAccumulationService)
case paramStr(1)
of "info": discard owner.serviceInfo.value # No fabricated metadata.
of "prior": discard owner.servicePriorState.value # No substituted pre-credit source.
of "state": discard owner.serviceState.value # No substituted parent.
of "input": discard owner.serviceInputAt(InvocationInputIndex(0)).value # No default input.
of "code", "unavailable": discard owner.serviceCode.value # Missing code cannot fabricate a valid empty blob.
of "round": discard bound.serviceBlockRound.value # No forged round certificate.
of "projection": discard bound.serviceProjection.value # No fabricated resolved context.
else: discard outcome.value # Actual/default failures require selected success too.
