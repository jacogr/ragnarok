# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared genuine signed two-guest block and complete application seed; explicit policies preserve existing stage contracts.

import std/[assertions, strutils]
import ../../src/app/[chain, candidate]
import ../../src/chain/[genesis, provider, parameters]
import ../../src/lib/json_writer
import ../../src/codec/[block_codec, header, bounded, report_owned, state_layout]
import ../../src/state/[store, accumulation_finalization, accumulation_validators,
  accumulation_statistics, accumulation_times, accumulation_activity, report_admission, block_admission]
import ./[accumulation_activity_context, accumulation_execution_context,
  accumulation_runner_context, accumulation_completion_context]
import ./report_admission_context as report_fixture

type SeedFixture* = object ## Test text comes from a genuine signed original parent; its original certificate remains a separate owner.
  text*: string
  source*: PreparedFinalAccumulation

proc hex(value: openArray[byte]): string =
  ## Emit canonical lowercase hexadecimal independently of the production configuration decoder.
  result = ""
  for octet in value: result.add(toHex(int(octet), 2).toLowerAscii())

proc policy*(writes = 1000'u64, bytes = 1000000'u64): StateStoreLimits =
  ## Writable mutation ceilings are caller decisions; fixed trie capture ceilings retain the legacy limits.
  result = genesisStoreLimits()
  result.writes = ElementLimit(writes)
  result.writeValueBytes = ByteLimit(bytes)

proc fixture*(base: OwnedReport, guarantees = 0): SeedFixture =
  ## Capture all original entries of a signed two-guest block, including code and opaque/service chapters.
  ## Optional genuine guarantees require their matching lookup headers when preparing this child.
  let authored = activityFixture(base, executed = true, guarantees = guarantees)
  let source = authored.source.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value
  let parent = source.finalAccumulationParent.value
  let bound = source.finalAccumulationAdmission.value.reportBlockStage.value.value.admitted
  var wire = newSeq[byte](bound.admittedParent.headerInfo.value.consumed)
  assert encodeOwnedHeader(bound.admittedParent, wire).error == HeaderError.None
  var state = JsonObject()
  for index in 0..<parent.commitment.entries:
    let key = parent.keyAt(StateEntryIndex(index)).value
    let value = parent.lookup(key).value.bytes
    state.add(hex(array[31, byte](key)), json(hex(value)))
  let text = $jsonObject([("protocol_parameters", json(hex(runnerParameters().encodeParameters))),
    ("genesis_header", json(hex(wire))), ("genesis_state", json(state))])
  SeedFixture(text: text, source: source)

proc candidateBlock*(context: SeedFixture): OwnedBlock =
  ## Retain the genuine signed child; its separately retained original parent never replaces the selected application head.
  context.source.finalAccumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock

proc preparationLimits*(): ApplicationCandidateLimits =
  ## Independent explicit stage/gas policies match the existing manual execution oracle.
  ApplicationCandidateLimits(reporting: report_fixture.transitionConfig(),
      queue: executionQueueConfig(),
    round: executionRoundConfig(), execution: runnerLimits(), driver: completionDriverLimits(),
    finalization: completionLimits().finalization)

proc initialized*(context: SeedFixture): ApplicationChain =
  ## A decoded complete seed gets caller-selected writable limits and exact independent identity.
  initApplicationChain(context.text, policy()).value
