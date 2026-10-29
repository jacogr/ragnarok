# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Coherent original nine-validator computed chain fixtures retain exact parent maps, headers and complete parameters.

import ./pvm_computed_storage_program
import std/[assertions, syncio]
import ../../src/state/computed/[composition as computed_composition,
    finalization as computed_finalization, execution as computed_execution, round as computed_round]
import ../../src/state/accumulation/[completion as accumulation_completion,
    finalization as accumulation_finalization, consensus as accumulation_consensus]
import ../../src/state/report/admission as report_admission
import "../../src/state/block/transition" as block_transition
import "../../src/state/block/admission" as block_admission
import ../../src/state/store
import ../../src/chain/[genesis, parameters]
import ../../src/codec/[header, bounded]
import ./[pvm_computed_composition, pvm_computed_state_publication]

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
