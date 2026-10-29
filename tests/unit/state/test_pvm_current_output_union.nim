# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_output_union_arc_release"}

## Terminal output union preserves full pair identity across real current entries and excludes original annulled yields.
import std/[assertions, envvars, syncio]
import ../../../src/codec/[bounded, report_owned]
import ../../../src/codec/state/outputs as state_outputs
import ../../../src/state/accumulation/current/[outputs as accumulation_current_outputs,
    driver as accumulation_current_driver]
import ../../../src/state/history
import ../../support/[accumulation_current_outputs_context, accumulation_current_statistics_context, arc_evidence]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc main() {.raises.} =
  ## Original signed input remains the authority for each actual terminal fixture.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve exact report transport.
  let base = decodeOwnedReport(wire, 2).value
  let duplicate = currentOutputCompletion(base, false)
  var policy = currentOutputLimits()
  policy.log.items = ElementLimit(2)
  policy.log.maxBytes = ByteLimit(73)
  failHash(3)
  let prepared = prepareCurrentAccumulationOutputs(duplicate, policy)
  assert prepared.error == CurrentAccumulationOutputsError.None, $prepared.error
  assert hashCalls() == 0, "output capture neither hashes nor writes state"
  let outputs = prepared.value
  let info = outputs.currentOutputsInfo.value
  assert info.entries == 2 and info.visits == 3 and info.outputs == 2 and info.encodedBytes == 73
  let first = outputs.currentOutputAt(OutputLogIndex(0)).value
  let second = outputs.currentOutputAt(OutputLogIndex(1)).value
  assert uint32(first.service) == 42 and uint32(second.service) == 99
  assert array[32, byte](first.commitment) == array[32, byte](second.commitment), "equal hashes from different services remain separate pairs"
  var copied = first
  copied.service = ServiceIndex(77)
  assert uint32(outputs.currentOutputAt(OutputLogIndex(0)).value.service) == 42
  let encoded = outputs.currentOutputsEntry.value
  assert encoded.value.len == 73 and encoded.value[0] == 2 and encoded.value[1] == 42 and
      encoded.value[37] == 99
  var detached = encoded
  detached.value[1] = 77
  assert outputs.currentOutputsEntry.value.value[1] == 42, "fresh C16 encoding owns independent bytes"
  let failed = outputs.currentOutputsRoot
  assert failed.error == CurrentAccumulationOutputsError.HistoryFailure
  assert failed.historyFailure == HistoryTransitionError.BackendFailure
  failHash(0)
  let expected = accumulationRoot([first, second], policy.log).value
  assert array[32, byte](outputs.currentOutputsRoot.value) == array[32, byte](expected), "root consumes the complete canonical pair sequence"
  assert outputs.currentOutputsSource.value.completedSequenceInfo.value.entries == 2
  let varied = currentOutputCompletion(base, true)
  let different = prepareCurrentAccumulationOutputs(varied, currentOutputLimits()).value
  assert different.currentOutputsInfo.value.outputs == 3
  let a = different.currentOutputAt(OutputLogIndex(0)).value
  let b = different.currentOutputAt(OutputLogIndex(1)).value
  assert uint32(a.service) == 42 and uint32(b.service) == 42
  assert array[32, byte](a.commitment) != array[32, byte](b.commitment), "same service keeps its distinct selected commitments"
  assert array[32, byte](a.commitment) == default(array[32, byte]), "present zero commitment remains a real selected pair"
  for scenario in [CurrentStatisticsScenario.ZeroParticipants, CurrentStatisticsScenario.Annulled]:
    let empty = currentStatisticsCompletion(base, scenario)
    var zeroPolicy = currentOutputLimits()
    zeroPolicy.log.items = ElementLimit(0)
    zeroPolicy.log.maxBytes = ByteLimit(1)
    failHash(3)
    let zero = prepareCurrentAccumulationOutputs(empty, zeroPolicy).value
    assert zero.currentOutputsInfo.value.outputs == 0, "absent or annulled original yield contributes no pair"
    assert array[32, byte](zero.currentOutputsRoot.value) == default(array[32, byte])
    assert zero.currentOutputsEntry.value.value == @[0'u8]
    failHash(0)
  for mode in 0..<4:
    var limit = policy
    case mode
    of 0: limit.entries = ElementLimit(1) # No truncated terminal traversal.
    of 1: limit.outcomes = ElementLimit(2) # Duplicates still consume original inspection work.
    of 2: limit.log.items = ElementLimit(1) # Unique capacity cannot replace services by equal hash.
    else: limit.log.maxBytes = ByteLimit(72) # Complete count-prefixed extent includes its last hash octet.
    assert prepareCurrentAccumulationOutputs(duplicate, limit).error ==
        CurrentAccumulationOutputsError.LimitExceeded
  assert outputs.currentOutputAt(OutputLogIndex(high(uint64))).error ==
      CurrentAccumulationOutputsError.InvalidIndex
  let invalid = prepareCurrentAccumulationOutputs(default(CompletedCurrentAccumulationSequence), policy)
  assert invalid.error == CurrentAccumulationOutputsError.InvalidSource
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareCurrentAccumulationOutputs(duplicate, policy).value
    assert local.currentOutputsInfo.value.outputs == 2 # Fixed pair buffers and terminal source release together.
  let after = getOccupiedMem()
  assert occupied == after, "current output union releases"
  recordArcRelease("pvm_current_output_union", 1000, occupied, after)
  echo "PVM current output union passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Unexpected admission/native/ownership failures must fail the suite.
except:
  quit(2)
