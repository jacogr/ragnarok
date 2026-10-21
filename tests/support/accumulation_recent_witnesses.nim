# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal C(3) framing and an independent Keccak tree bind original headers and guarantees to completed outputs.

import std/assertions
import ../../src/state/[accumulation_recent, history, accumulation_ready, accumulation_history,
  accumulation_finalization,
  accumulation_outputs, accumulation_execution, accumulation_round, accumulation_queue,
  report_admission, guarantee_credentials, block_transition, block_admission, store]
import ../../src/codec/[assurances, bounded, header, report_owned, state_history, state_outputs,
    state_layout, state_trie]
import ../../src/crypto/primitives
import ./[report_context, pvm_accumulation_context]

proc recentPolicy*(): AccumulationRecentConfig =
  ## Header/log work has independent ceilings from complete parent/output history encoding.
  AccumulationRecentConfig(history: HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8),
      perBlock: ElementLimit(2),
    totalPackages: ElementLimit(16), peaks: ElementLimit(64), maxBytes: ByteLimit(4096)),
    outputs: OutputLogConfig(items: ElementLimit(4), maxBytes: ByteLimit(145)),
        headerBytes: ByteLimit(100000))
proc recentYieldProgram*(): seq[byte] =
  ## Actual guest yields the 32-byte padded bootstrap tuple and halts without a return override.
  result = @[0'u8]
  let raw = @[0'u8, 0, 9, 0, 0, 0, 0, 0, 10, 27, 50, 0, 191, 0]
  for octet in pvmEnvelope(raw): result.add(octet)
proc leaf(service: uint32, count: byte): seq[byte] =
  ## Independently frame E4(service) plus the literal yielded slot/service/count and zero padding.
  result = newSeq[byte](36)
  for shift in 0..<4: result[shift] = byte((service shr (shift*8)) and 255)
  result[4] = 2
  result[5] = byte(service)
  result[6] = count
proc expectedRoot(): array[32, byte] =
  ## Four literal leaves have two 76-byte internal nodes and one 68-byte root; no production tree routine is used.
  var left = @[110'u8, 111, 100, 101]
  for count in [1'u8, 2]:
    for octet in leaf(42, count): left.add(octet)
  var right = @[110'u8, 111, 100, 101]
  for count in [0'u8, 1]:
    for octet in leaf(99, count): right.add(octet)
  let a = array[32, byte](keccak256(left).value)
  let b = array[32, byte](keccak256(right).value)
  var root = @[110'u8, 111, 100, 101]
  for octet in a: root.add(octet)
  for octet in b: root.add(octet)
  array[32, byte](keccak256(root).value)
proc appendBlock(bytes: var seq[byte], header, peak, state: array[32, byte], slot: uint32,
    packages: seq[ReportedPackage]) =
  ## Literal field order is header, super-peak, state, E4 slot and a one-octet package count in these tiny fixtures.
  for octet in header: bytes.add(octet)
  for octet in peak: bytes.add(octet)
  for octet in state: bytes.add(octet)
  for shift in 0..<4: bytes.add(byte((slot shr (shift*8)) and 255))
  assert packages.len < 128
  bytes.add(byte(packages.len))
  for pair in packages:
    for octet in pair.package.bytes: bytes.add(octet)
    for octet in pair.segment.bytes: bytes.add(octet)

proc checkRecentHistory*(source: PreparedAccumulationReady,
    yielded = false): PreparedAccumulationRecent =
  ## Original guaranteed packages/header and finalized output log remain distinct from processed reports and posterior state roots.
  let prior = source.accumulationReadyState.value
  let finalized = source.accumulationReadySource.value.accumulationHistorySource.value
  let outputs = finalized.finalAccumulationOutputs.value
  let admission = finalized.finalAccumulationAdmission.value
  let binding = admission.reportBlockStage.value.value.admitted
  let header = binding.admittedHeader
  let facts = header.headerInfo.value
  var wire = newSeq[byte](facts.consumed)
  assert header.encodeOwnedHeader(wire).error == HeaderError.None
  let expectedHeader = array[32, byte](blake2b256(wire).value)
  let unsignedHash = array[32, byte](blake2b256(wire.toOpenArray(0,
      facts.unsigned.consumed-1)).value)
  assert expectedHeader != unsignedHash # The sealed-header witness distinguishes complete serialization from the unsigned prefix.
  let parentState = array[32, byte](facts.unsigned.priorState)
  assert parentState == array[32, byte](binding.admittedState.commitment.root)
  assert parentState != array[32, byte](prior.commitment.root) # Parent correction cannot use the resulting post-ready root.
  let credentials = admission.reportCredentials.value
  let count = credentials.verifiedGuaranteeCount.value
  assert count <= 1
  var packages: seq[ReportedPackage] = @[]
  if count == 1:
    let report = credentials.verifiedGuaranteeAt(0).value.report.ownedReportInfo.value.header
    packages.add(ReportedPackage(package: report.packageHash, segment: report.segmentRoot))
  let originalHistory = decodeHistoryState(binding.admittedState.lookup(chapterKey(StateChapter(
      3))).value.bytes, recentPolicy().history).value.snapshot
  assert originalHistory.historyInfo.value.blocks == 1 and
      originalHistory.historyInfo.value.peaks == 0
  let parent = originalHistory.historyBlockAt(HistoryBlockIndex(0)).value
  assert parent.packages == 0 and array[32, byte](parent.state) != parentState
  let root = if yielded: expectedRoot() else: default(array[32, byte])
  if yielded:
    var log = @[4'u8]
    for count in [1'u8, 2]:
      for octet in leaf(42, count): log.add(octet)
    for count in [0'u8, 1]:
      for octet in leaf(99, count): log.add(octet)
    assert outputs.outputsEntry.value.value == log # Expected Keccak leaves are the actual finalized four-pair C(16), not a loose caller array.
  var expected = @[2'u8]
  appendBlock(expected, array[32, byte](parent.header), array[32, byte](parent.superPeak),
      parentState, uint32(parent.slot), @[])
  appendBlock(expected, expectedHeader, root, default(array[32, byte]), uint32(facts.unsigned.slot), packages)
  expected.add(1'u8)
  expected.add(1'u8)
  for octet in root: expected.add(octet) # Empty old belt becomes one present peak, including the all-zero empty-output root.
  let prepared = prepareAccumulationRecent(source, recentPolicy())
  let plan = prepared.value
  assert plan.accumulationRecentEntry.value.value == expected
  let snapshot = plan.accumulationRecentHistory.value
  assert array[32, byte](snapshot.historyBlockAt(HistoryBlockIndex(0)).value.state) == parentState
  let last = snapshot.historyBlockAt(HistoryBlockIndex(1)).value
  assert array[32, byte](last.state) == default(array[32, byte]) and last.packages == count
  assert array[32, byte](last.header) == expectedHeader and array[32, byte](last.superPeak) == root
  assert snapshot.historyPeakAt(HistoryPeakIndex(0)).value.present
  plan
