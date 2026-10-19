# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal C(3) framing and independent Keccak tree/full-map expectations bind original headers/guarantees to real completed outputs.

import std/assertions
import ../../src/state/[recent_history, history, ready_reconciliation, accumulation_publication,
  block_activity, service_activity, accumulation_statistics, accumulation_finalization,
  accumulation_outputs, accumulation_execution, accumulation_round, accumulation_queue,
  report_admission, guarantee_credentials, block_transition, block_admission, store]
import ../../src/codec/[assurances, bounded, header, report_owned, state_history, state_outputs,
    state_layout, state_trie]
import ../../src/crypto/primitives
import ./[report_context, pvm_accumulation_context]

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc recentPolicy*(): RecentHistoryConfig =
  ## Header/log work has independent ceilings from complete parent/output history encoding.
  RecentHistoryConfig(history: HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8),
      perBlock: ElementLimit(2),
    totalPackages: ElementLimit(16), peaks: ElementLimit(64), maxBytes: ByteLimit(4096)),
    outputs: OutputLogConfig(items: ElementLimit(4), maxBytes: ByteLimit(145)),
        headerBytes: ByteLimit(100000))
proc recentYieldProgram*(): seq[byte] =
  ## Actual guest yields the 32-byte padded bootstrap tuple and halts without a return override.
  result = @[0'u8]
  let raw = @[0'u8, 0, 9, 0, 0, 0, 0, 0, 10, 26, 50, 0, 191, 0]
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

proc checkRecentHistory*(source: PublishedReadyReconciliation, original: openArray[StateEntry],
    yielded = false): PublishedRecentHistory =
  ## Original guaranteed packages/header and finalized output log remain distinct from processed reports and posterior state roots.
  let prior = source.publishedReadyState.value
  let ready = source.publishedReadySource.value.readyReconciliationSource.value
  let activity = ready.publishedAccumulationSource.value.accumulationPublicationSource.value
  let finalized = activity.blockActivitySource.value.serviceActivitySource.value.statisticsSource.value
  let outputs = finalized.finalAccumulationOutputs.value
  let admission = outputs.outputsSource.value.executionRound.value.roundBlockQueue.value.accumulationAdmission.value
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
  failHash(3)
  for mode in 0..<5:
    var short = recentPolicy()
    case mode
    of 0: short.headerBytes = ByteLimit(uint64(facts.consumed-1)) # Header capture is checked before any hash.
    of 1: short.outputs.maxBytes = ByteLimit(0) # Even empty C(16) framing consumes one byte.
    of 2: short.history.maxBytes = ByteLimit(0) # Original history is bounded before copying/decoding.
    of 3: short.history.cores = CoreCount(3) # No caller-selected chain profile.
    else: short.history.blocks = ElementLimit(0) # Original retained records obey independent codec policy.
    let refused = prepareRecentHistory(source, short)
    if mode == 3: assert refused.error == RecentHistoryError.InvalidConfig
    elif mode == 4: assert refused.error == RecentHistoryError.CodecFailure and
        refused.codecError == HistoryError.LimitExceeded
    else: assert refused.error == RecentHistoryError.LimitExceeded
  assert hashCalls() == 0
  failHash(1)
  let cryptoFailure = prepareRecentHistory(source, recentPolicy())
  assert cryptoFailure.error == RecentHistoryError.CryptoFailure and cryptoFailure.cryptoError ==
      CryptoError.BackendFailure
  failHash(2)
  let keccak = prepareRecentHistory(source, recentPolicy())
  if yielded:
    assert keccak.error == RecentHistoryError.OutputFailure and keccak.outputError ==
        HistoryTransitionError.BackendFailure
  else:
    assert keccak.error == RecentHistoryError.None # Empty output tree and single peak need no Keccak work.
  failHash(0)
  let plan = prepareRecentHistory(source, recentPolicy()).value
  assert plan.recentHistoryEntry.value.value == expected
  let info = plan.recentHistoryInfo.value
  assert info.outputs == (if yielded: 4 else: 0) and info.guarantees == count
  assert info.history.blocks == 2 and info.history.peaks == 1
  assert array[32, byte](info.header) == expectedHeader and array[32, byte](info.accumulation) == root
  let snapshot = plan.recentHistorySnapshot.value
  assert array[32, byte](snapshot.historyBlockAt(HistoryBlockIndex(0)).value.state) == parentState
  let last = snapshot.historyBlockAt(HistoryBlockIndex(1)).value
  assert array[32, byte](last.state) == default(array[32, byte]) and last.packages == count
  assert array[32, byte](last.header) == expectedHeader and array[32, byte](last.superPeak) == root
  assert snapshot.historyPeakAt(HistoryPeakIndex(0)).value.present
  var copied = plan.recentHistoryEntry.value
  copied.value[0] = 0
  assert plan.recentHistoryEntry.value.value == expected
  var observed = plan.recentHistoryInfo.value
  observed.outputs = 999
  assert plan.recentHistoryInfo.value.outputs == info.outputs
  var exact = recentPolicy()
  exact.headerBytes = ByteLimit(uint64(wire.len))
  exact.outputs.items = ElementLimit(uint64(info.outputs))
  exact.outputs.maxBytes = ByteLimit(uint64(outputs.outputsInfo.value.encodedBytes))
  exact.history.maxBytes = ByteLimit(uint64(expected.len))
  assert prepareRecentHistory(source, exact).value.recentHistoryEntry.value.value == expected
  var short = exact
  short.history.maxBytes = ByteLimit(uint64(expected.len-1))
  let refused = prepareRecentHistory(source, short)
  assert refused.error == RecentHistoryError.HistoryFailure and refused.historyError ==
      HistoryTransitionError.LimitExceeded
  short = exact
  short.history.peaks = ElementLimit(0)
  let beltFailure = prepareRecentHistory(source, short)
  assert beltFailure.error == RecentHistoryError.HistoryFailure and beltFailure.historyError ==
      HistoryTransitionError.LimitExceeded
  if yielded:
    short = exact
    short.outputs.items = ElementLimit(3)
    assert prepareRecentHistory(source, short).error == RecentHistoryError.LimitExceeded
  var wide = exact
  wide.headerBytes = ByteLimit(high(uint64))
  wide.outputs.items = ElementLimit(high(uint64))
  wide.outputs.maxBytes = ByteLimit(high(uint64))
  wide.history.maxBytes = ByteLimit(high(uint64))
  wide.history.perBlock = ElementLimit(high(uint64))
  wide.history.totalPackages = ElementLimit(high(uint64))
  wide.history.peaks = ElementLimit(high(uint64))
  assert prepareRecentHistory(source, wide).value.recentHistoryEntry.value.value == expected
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareRecentHistory(source, recentPolicy()).value
    assert local.recentHistoryInfo.value.guarantees == count
  assert before == getOccupiedMem() # Header/output/package/history scratch and source handles retire each cycle, including real hashes.
  var entries: seq[StateEntry] = @[]
  for record in original: entries.add(StateEntry(key: record.key, value: prior.lookup(
      record.key).value.bytes))
  let logKey = chapterKey(StateChapter(16))
  entries.add(StateEntry(key: logKey, value: prior.lookup(logKey).value.bytes))
  assert entries.len == prior.commitment.entries
  var foreign = newStateStore(entries, report_context.limits()).value
  failHash(3)
  assert advanceRecentHistory(foreign, plan).error == RecentHistoryError.ForeignState
  assert hashCalls() == 0
  failHash(0)
  for successful in [0, 2]:
    var caller = forkStateStore(prior).value
    hashAfter(cint(successful))
    let failure = advanceRecentHistory(caller, plan)
    assert failure.error == RecentHistoryError.StateFailure and failure.stateError ==
        StateStoreError.BackendFailure
    failHash(0)
    assert sameStateSnapshot(caller.snapshot.value, prior)
  let key = chapterKey(StateChapter(3))
  for index in 0..<entries.len:
    if array[31, byte](entries[index].key) == array[31, byte](key): entries[index].value = expected
  let wanted = stateTrieRoot(entries, report_context.limits().trie).value
  let published = publishRecentHistory(plan).value
  let posterior = published.publishedRecentState.value
  assert array[32, byte](posterior.commitment.root) == array[32, byte](wanted.root)
  for record in entries: assert posterior.lookup(record.key).value.bytes ==
      record.value # Every coordinated account/C(13)/C(14)/C(15)/C(16) value survives.
  var caller = forkStateStore(prior).value
  let advanced = advanceRecentHistory(caller, plan).value
  assert sameStateSnapshot(caller.snapshot.value, advanced.publishedRecentState.value)
  let after = caller.snapshot.value
  failHash(3)
  assert advanceRecentHistory(caller, plan).error == RecentHistoryError.ForeignState
  assert sameStateSnapshot(caller.snapshot.value, after) and hashCalls() == 0
  failHash(0)
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = publishRecentHistory(plan).value
    assert local.publishedRecentState.value.lookup(key).value.bytes == expected
  assert occupied == getOccupiedMem()
  assert sameStateSnapshot(source.publishedReadyState.value, prior)
  let missing = default(PublishedReadyReconciliation)
  assert prepareRecentHistory(missing, recentPolicy()).error == RecentHistoryError.InvalidSource
  assert publishRecentHistory(default(PreparedRecentHistory)).error ==
      RecentHistoryError.InvalidSource
  published
