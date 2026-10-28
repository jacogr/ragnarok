# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Coherent original nine-validator computed chain fixtures retain exact parent maps, headers and complete parameters.

import ./pvm_computed_storage_program
import std/assertions
import std/syncio
import ../../src/state/computed_composition as state_computed_composition
import ../../src/state/computed_finalization as state_computed_finalization
import ../../src/state/computed_execution as state_computed_execution
import ../../src/state/computed_round as state_computed_round
import ../../src/state/accumulation_completion as state_accumulation_completion
import ../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../src/state/report_admission as state_report_admission
import ../../src/state/block_transition as state_block_transition
import ../../src/state/block_admission as state_block_admission
import ../../src/state/store as state_store
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/parameters as chain_parameters
import ../../src/codec/header as codec_header
import ../../src/codec/bounded as codec_bounded
import ./pvm_computed_composition
import ./pvm_computed_state_publication

proc chainHeaderBytes*(header: OwnedHeader): seq[byte] =
  ## Re-encode the actual owner-bound sealed header without modifying its signed bytes.
  result = newSeq[byte](header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header, result).error == HeaderError.None
proc chainFixture*(coherent = true, storage = ComputedStorageMode.Disabled): ComposedComputedState =
  ## Author actual original nine-active keys/statistics/shards before signing; existing bounded defaults remain separately testable.
  let final = compositionFixture(withChain = coherent, storage = storage)
  var limits = computedCompositionLimits()
  limits.validators.projection.rows = ElementLimit(18)
  let composed = composeComputedState(final, limits)
  if composed.error != ComputedCompositionError.None:
    echo "coherent composition ", composed.error
    if composed.error == ComputedCompositionError.CompositionFailure: echo "phase ",
        composed.compositionFailure.error
  assert composed.error == ComputedCompositionError.None
  composed.value
proc chainFixtureParameters*(source: ComposedComputedState): Parameters =
  ## Derive complete original chain settings through actual computed round provenance.
  source.computedCompositionSource.value.computedFinalizationSource.value.computedExecutionSource.value.computedRoundParameters.value
proc chainFixtureParent*(source: ComposedComputedState, settings: Parameters): BlockSnapshotResult =
  ## Capture the real admitted parent header with its exact original map and explicitly selected parameters.
  let final = source.computedCompositionSource.value.computedFinalizationPlan.value
  let binding = final.finalAccumulationAdmission.value.reportBlockStage.value.value.admitted
  captureBlockSnapshot(chainHeaderBytes(binding.admittedParent), source.statePublicationParent, settings)
