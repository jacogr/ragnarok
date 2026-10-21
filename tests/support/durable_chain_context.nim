# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine signed execution fixtures supply original parent authority for durable publication tests.
import std/assertions
import ../../src/chain/[genesis, parameters]
import ../../src/codec/[header, report_owned]
import ../../src/state/[accumulation_finalization, accumulation_validators, accumulation_times,
  accumulation_statistics, report_admission, block_transition, block_admission]
import ./accumulation_activity_context

type DurableChainFixture* = object ## Successful source certificates are authored by existing execution fixtures only.
  source*: PreparedFinalAccumulation
  parent*: BlockSnapshotResult
proc durableSettings*(): ParameterResult =
  ## Match the authentic two-core, twelve-slot profile used by the signed source fixture.
  decodeParametersHex("ffffffffffffffff020000000000000003000000000000000200050000000c0000000700000000000000080000000000000009000000000000000a000000000000000b000c000d000e000f000000100011001200130014001500160000001700000018000000190000001a0000001b0000001c0000000a000000")
proc durableFixture*(base: OwnedReport): DurableChainFixture =
  ## Capture the exact admitted parent header with the source's original complete snapshot.
  let authored = activityFixture(base)
  let source = authored.source.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value
  let admitted = source.finalAccumulationAdmission.value.reportBlockStage.value.value.admitted
  let header = admitted.admittedParent
  var wire = newSeq[byte](header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header, wire).error == HeaderError.None
  let parent = captureBlockSnapshot(wire, source.finalAccumulationParent.value, durableSettings().value)
  assert parent.error == GenesisError.None
  DurableChainFixture(source: source, parent: parent)
