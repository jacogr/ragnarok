# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_recent_arc_release"}

## Signed stopped accumulation binds complete sealed headers, guarantee packages and selected outputs to private C(3).

import std/[assertions, envvars, syncio]
import ../../../src/state/accumulation/[recent as accumulation_recent, ready as accumulation_ready,
    history as accumulation_history, finalization as accumulation_finalization,
    outputs as accumulation_outputs, reentry as accumulation_reentry,
    continuation as accumulation_continuation, execution as accumulation_execution,
    inputs as accumulation_inputs, dispatch as accumulation_dispatch, round as accumulation_round,
    queue as accumulation_queue]
import ../../../src/state/report/admission as report_admission
import "../../../src/state/block/transition" as block_transition
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/[history, store]
import ../../../src/codec/[bounded, header, block_codec, composite, report_owned, owned]
import ../../../src/codec/work/report as work_report
import ../../../src/codec/state/[history as state_history, outputs as state_outputs,
    workqueues as state_workqueues, layout as state_layout, trie as state_trie]
import ../../../src/crypto/primitives
import ../../support/[accumulation_reentry_context, accumulation_execution_context,
  pvm_accumulation_program, pvm_accumulation_context, pvm_accumulation_provision,
  report_context, arc_evidence]

# Fault injection begins only after real signed certificates have been constructed.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

# All inherited queue work is finite; this slice adds independent header, output and C(3) bounds.
proc queuePolicy(): AccumulationReadyConfig =
  AccumulationReadyConfig(items: ElementLimit(100), dependencies: ElementLimit(100),
    queues: WorkQueueConfig(epochSlots: EpochSlots(12), cores: CoreCount(2),
      perSlot: ElementLimit(20), totalItems: ElementLimit(40), perDependencies: ElementLimit(20),
      totalDependencies: ElementLimit(100), reportBytes: ByteLimit(4096), maxBytes: ByteLimit(65536)))

proc policy(): AccumulationRecentConfig =
  ## Header/pair work and history input/output storage have separate policies.
  AccumulationRecentConfig(headerBytes: ByteLimit(4096),
    outputs: OutputLogConfig(items: ElementLimit(4), maxBytes: ByteLimit(145)),
    history: HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8), perBlock: ElementLimit(2),
      totalPackages: ElementLimit(16), peaks: ElementLimit(10), maxBytes: ByteLimit(4096)))

# Actual source-derived guest execution supplies every completed round; idle entries have no guests.
proc completed(source: PreparedAccumulationReentry,
    provided = false): CompletedAccumulationReentry =
  var runs: seq[AccumulationDispatchResult] = @[]
  for index in 0..<source.reentryInputs.value.invocationServiceCount.value:
    runs.add(reentryGuest(source, uint64(index), provided = provided and index == 0))
  completeAccumulationReentry(source, runs, [], executionLimits()).value

# The fixed four-report fixture needs one dispatched reentry, followed by its genuine terminal entry.
proc finished(fixture: ReentryFixture, provided = false): PreparedFinalAccumulation =
  let limits = AccumulationOutputHistoryLimits(rounds: ElementLimit(4), executions: ElementLimit(6),
    log: OutputLogConfig(items: ElementLimit(4), maxBytes: ByteLimit(145)))
  if not fixture.source.reentryInfo.value.dispatch:
    return prepareFinalAccumulation(fixture.source.reentrySource.value,
        limits).value # Earliest genuine stopped certificate.
  let policy = executionRoundConfig()
  let next = AccumulationReentryConfig(selection: AccumulationContinuationLimits(
    executions: ElementLimit(2), reports: ElementLimit(4), digests: ElementLimit(8)),
    operands: policy.operands, inputs: policy.inputs)
  let terminal = prepareAccumulationReentry(completed(fixture.source, provided), next,
    AccumulationReentryDepthLimit(2)).value
  assert not terminal.reentryInfo.value.dispatch
  prepareFinalAccumulation(completed(terminal), limits).value

# Return the real compact bootstrap tuple, or a fixed readable address, from the initialized CPU.
proc returnProgram(address = 0'u64): seq[byte] =
  var instructions: seq[seq[byte]] = @[]
  if address != 0:
    instructions.add(registerImmediate(7, address)) # Fixed-page mode supplies equal or zero commitments.
  instructions.add(registerImmediate(8, 32))
  instructions.add(@[50'u8, 0])
  var code = @[0'u8, 0, 0, 0, 0]
  var starts = @[0, 1, 2, 3, 4]
  for instruction in instructions:
    starts.add(code.len)
    for octet in instruction: code.add(octet) # Argument data is never marked as an instruction.
  var raw = @[0'u8, 0, byte(code.len)]
  for octet in code: raw.add(octet)
  var mask = newSeq[byte]((code.len+7) div 8)
  for index in starts:
    mask[index div 8] = mask[index div 8] or byte(1 shl (index mod 8))
  for octet in mask: raw.add(octet)
  result = @[0'u8]
  for octet in pvmEnvelope(raw): result.add(octet)

# Independent fixed leaves encode E4 service and raw argument bytes without using the production codec.
proc leaf(service: uint32, count: byte): seq[byte] =
  result = @[]
  for shift in 0..<4: result.add(byte((service shr (shift*8)) and 255))
  result.add(2)
  result.add(byte(service))
  result.add(count)
  for index in 3..<32: result.add(0) # All three compact arguments fit one byte in this fixture.

# Build an independent binary node transcript for exactly two raw leaves or two hashed children.
proc node(left, right: seq[byte]): seq[byte] =
  var bytes = @[110'u8, 111, 100, 101]
  for octet in left: bytes.add(octet)
  for octet in right: bytes.add(octet)
  result = @[]
  for octet in array[32, byte](keccak256(bytes).value): result.add(octet)

# Form the exact ready predecessor through the established finalized-history and ready constructors.
proc predecessor(fixture: ReentryFixture, provided = false): PreparedAccumulationReady =
  let finalized = finished(fixture, provided)
  let accumulated = prepareAccumulationHistory(finalized,
    AccumulationHistoryConfig(reports: ElementLimit(4), queues: queuePolicy().queues)).value
  prepareAccumulationReady(accumulated, queuePolicy()).value

# Literal T framing puts super-peak before state root, using sealed block bytes and authored package identities.
proc expectedEntry(fixture: ReentryFixture, base: OwnedReport, guarantees: int,
    root: array[32, byte]): seq[byte] =
  let binding = fixture.initial.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted
  let fields = binding.admittedHeader.headerInfo.value
  var wire = newSeq[byte](binding.admittedBlock.blockInfo.value.consumed)
  assert encodeOwnedBlock(binding.admittedBlock, wire).error == FrameError.None
  let identity = array[32, byte](blake2b256(wire.toOpenArray(0, fields.consumed-1)).value)
  assert identity != array[32, byte](blake2b256(wire.toOpenArray(0,
      fields.unsigned.consumed-1)).value)
  result = @[2'u8] # Exactly parent and current records, without an epoch or chapter discriminator.
  for hash in [array[32, byte](fields.unsigned.parent), default(array[32, byte]),
      array[32, byte](fixture.initial.state.snapshot.value.commitment.root)]:
    for octet in hash: result.add(octet) # Parent receives its actual posterior root, not its own prior-state field.
  for octet in [1'u8, 0, 0, 0, 0]: result.add(octet) # Parent E4 slot and empty package dictionary.
  for hash in [identity, root, default(array[32, byte])]:
    for octet in hash: result.add(octet) # Current record deliberately retains a zero state-root placeholder.
  for octet in [2'u8, 0, 0, 0, byte(guarantees)]: result.add(octet)
  let segment = base.ownedReportInfo.value.header.segmentRoot.bytes
  for index in 0..<guarantees:
    result.add(byte(10+index))
    for octet in 1..<32: result.add(0) # Authored new guarantee identities are 10 and 11, distinct from accumulated 64..67.
    for octet in segment: result.add(octet)
  result.add(1'u8)
  result.add(1'u8) # A present zero peak remains distinct from no peak or an absent peak.
  for octet in root: result.add(octet)

proc main() {.raises.} =
  ## Preserve source identity, literal encoding and independent full-map roots for genuine signed accumulation.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  let fixture = reentryFixture(base, incomingReports = 2)
  let source = predecessor(fixture)
  let prior = source.accumulationReadyState.value
  let key = chapterKey(StateChapter(3))
  let old = prior.lookup(key).value.bytes
  let expected = expectedEntry(fixture, base, 2, default(array[32, byte]))
  assert expected.len == 365
  let cfg = policy()
  let plan = prepareAccumulationRecent(source, cfg).value
  assert plan.accumulationRecentEntry.value.value == expected, "canonical C(3) wire witness"
  assert array[32, byte](plan.accumulationRecentRoot.value) == default(array[32, byte])
  let recent = plan.accumulationRecentHistory.value
  assert recent.historyInfo.value.blocks == 2 and recent.historyInfo.value.peaks == 1
  assert recent.historyPeakAt(HistoryPeakIndex(0)).value.present
  assert array[32, byte](recent.historyPeakAt(HistoryPeakIndex(0)).value.hash) == default(array[32, byte])
  assert recent.historyPackageAt(HistoryBlockIndex(1), HistoryPackageIndex(0)).value.package.bytes[0] == 10
  assert recent.historyPackageAt(HistoryBlockIndex(1), HistoryPackageIndex(1)).value.package.bytes[0] == 11
  let candidate = plan.accumulationRecentState.value
  assert candidate.lookup(key).value.bytes == expected
  assert prior.lookup(key).value.bytes == old
  assert sameStateSnapshot(plan.accumulationRecentSource.value.accumulationReadyState.value, prior)
  var expectedMap: seq[StateEntry] = @[]
  for entry in fixture.initial.entries:
    let chapter = array[31, byte](entry.key)
    let bytes = if chapter == array[31, byte](key): expected else: prior.lookup(
        entry.key).value.bytes
    expectedMap.add(StateEntry(key: entry.key, value: bytes))
    if chapter != array[31, byte](key):
      assert candidate.lookup(entry.key).value.bytes ==
          bytes # Preserve all earlier chapters, including C(14)/C(15).
  expectedMap.add(StateEntry(key: chapterKey(StateChapter(16)), value: prior.lookup(chapterKey(
      StateChapter(16))).value.bytes))
  let independent = newStateStore(expectedMap, report_context.limits()).value.snapshot.value
  assert array[32, byte](independent.commitment.root) == array[32, byte](candidate.commitment.root)
  var copied = plan.accumulationRecentEntry.value
  copied.value[0] = 0
  assert plan.accumulationRecentEntry.value.value == expected
  # The recent dictionary is independent of how many old queued reports execution could afford.
  for partial in [reentryFixture(base, stopped = true, incomingReports = 2), reentryFixture(base,
      empty = true, incomingReports = 2)]:
    let bound = predecessor(partial)
    let result = prepareAccumulationRecent(bound, cfg).value
    assert result.accumulationRecentEntry.value.value == expectedEntry(partial, base, 2, default(
        array[32, byte]))
    assert result.accumulationRecentHistory.value.historyBlockAt(HistoryBlockIndex(
        1)).value.packages == 2
  let noReports = predecessor(reentryFixture(base))
  assert prepareAccumulationRecent(noReports, cfg).value.accumulationRecentHistory.value.historyBlockAt(
      HistoryBlockIndex(1)).value.packages == 0
  let supplied = predecessor(reentryFixture(base, provided = true, incomingReports = 2),
      provided = true)
  let request = provisionRequest(42, @[73'u8])
  assert prepareAccumulationRecent(supplied, cfg).value.accumulationRecentState.value.lookup(
      request.key).value.bytes == @[1'u8, 2, 0, 0, 0]
  # Four real multi-round selected pairs form the independent balanced raw-node tree already defined by GP.
  let program = returnProgram()
  let yieldedFixture = reentryFixture(base, firstGas = 100000, secondGas = 100000,
    firstProgram = program, secondProgram = program, incomingReports = 2)
  let yielded = predecessor(yieldedFixture)
  let expectedRootBytes = node(node(leaf(42, 1), leaf(42, 2)), node(leaf(99, 0), leaf(99, 1)))
  var expectedRoot = default(array[32, byte])
  for index in 0..<32: expectedRoot[index] = expectedRootBytes[index]
  let withOutputs = prepareAccumulationRecent(yielded, cfg).value
  assert array[32, byte](withOutputs.accumulationRecentRoot.value) == expectedRoot
  assert withOutputs.accumulationRecentEntry.value.value == expectedEntry(yieldedFixture, base, 2, expectedRoot)
  assert withOutputs.accumulationRecentState.value.lookup(chapterKey(StateChapter(
      16))).value.bytes == yielded.accumulationReadyState.value.lookup(chapterKey(StateChapter(
      16))).value.bytes
  failHash(2)
  let refusedRoot = prepareAccumulationRecent(yielded, cfg)
  assert refusedRoot.error == AccumulationRecentError.OutputFailure
  assert refusedRoot.outputError == HistoryTransitionError.BackendFailure
  failHash(0)
  assert prepareAccumulationRecent(yielded, cfg).value.accumulationRecentEntry.value.value ==
      withOutputs.accumulationRecentEntry.value.value
  # Prior belt ownership matters: carry consumes an old present peak, while bagging retains later peaks.
  var oldHash = default(array[32, byte])
  oldHash[0] = 71
  let carried = predecessor(reentryFixture(base, historyPeaks = @[presentHistoryPeak(
      HistoryPeakHash(oldHash))]))
  let bagged = predecessor(reentryFixture(base, historyPeaks = @[absentHistoryPeak(),
      presentHistoryPeak(HistoryPeakHash(oldHash))]))
  let carriedPlan = prepareAccumulationRecent(carried, cfg).value
  var carryTranscript = newSeq[byte](64)
  for index in 0..<32: carryTranscript[index] = oldHash[index]
  let carryHash = array[32, byte](keccak256(carryTranscript).value)
  let carriedHistory = carriedPlan.accumulationRecentHistory.value
  assert not carriedHistory.historyPeakAt(HistoryPeakIndex(0)).value.present
  assert array[32, byte](carriedHistory.historyPeakAt(HistoryPeakIndex(1)).value.hash) == carryHash
  assert array[32, byte](carriedHistory.historyBlockAt(HistoryBlockIndex(1)).value.superPeak) == carryHash
  var bagTranscript = @[112'u8, 101, 97, 107]
  for index in 0..<32: bagTranscript.add(0)
  for octet in oldHash: bagTranscript.add(octet)
  let bagHash = array[32, byte](keccak256(bagTranscript).value)
  assert array[32, byte](prepareAccumulationRecent(bagged,
      cfg).value.accumulationRecentHistory.value.historyBlockAt(HistoryBlockIndex(
      1)).value.superPeak) == bagHash
  for bound in [carried, bagged]:
    failHash(2)
    let refused = prepareAccumulationRecent(bound, cfg)
    assert refused.error == AccumulationRecentError.HistoryFailure
    assert refused.historyError == HistoryTransitionError.BackendFailure
    failHash(0)
    assert prepareAccumulationRecent(bound, cfg).error == AccumulationRecentError.None
  # Independent exact and short header/log/history limits refuse before cryptographic work where preflight permits.
  let header = fixture.initial.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedHeader.headerInfo.value
  var exact = cfg
  exact.headerBytes = ByteLimit(header.consumed)
  exact.outputs = OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(1))
  exact.history.maxBytes = ByteLimit(uint64(expected.len))
  assert prepareAccumulationRecent(source, exact).value.accumulationRecentEntry.value.value == expected
  for kind in 0..<6:
    var short = cfg
    case kind
    of 0: short.headerBytes = ByteLimit(header.consumed-1)
    of 1: short.outputs.maxBytes = ByteLimit(0)
    of 2: short.history.perBlock = ElementLimit(1)
    of 3: short.history.totalPackages = ElementLimit(1)
    of 4: short.history.maxBytes = ByteLimit(1)
    else: short.outputs.items = ElementLimit(3)
    failHash(3)
    let refused = prepareAccumulationRecent(if kind == 5: yielded else: source, short)
    assert refused.error == AccumulationRecentError.LimitExceeded
    assert hashCalls() == 0
    failHash(0)
  var short = cfg
  short.history.blocks = ElementLimit(0)
  assert prepareAccumulationRecent(source, short).codecError == HistoryError.LimitExceeded
  short = cfg
  short.history.blocks = ElementLimit(1)
  assert prepareAccumulationRecent(source, short).historyError ==
      HistoryTransitionError.LimitExceeded
  short = cfg
  short.history.maxBytes = ByteLimit(uint64(expected.len-1))
  assert prepareAccumulationRecent(source, short).historyError ==
      HistoryTransitionError.LimitExceeded
  var wide = cfg
  wide.headerBytes = ByteLimit(high(uint64))
  wide.outputs = OutputLogConfig(items: ElementLimit(high(uint64)), maxBytes: ByteLimit(high(uint64)))
  wide.history.maxBytes = ByteLimit(high(uint64))
  wide.history.totalPackages = ElementLimit(high(uint64))
  wide.history.peaks = ElementLimit(high(uint64))
  assert prepareAccumulationRecent(source, wide).value.accumulationRecentEntry.value.value == expected
  var mismatched = cfg
  mismatched.history.cores = CoreCount(3)
  failHash(3)
  assert prepareAccumulationRecent(source, mismatched).error ==
      AccumulationRecentError.InvalidConfig
  assert prepareAccumulationRecent(default(PreparedAccumulationReady), cfg).error ==
      AccumulationRecentError.InvalidSource
  assert hashCalls() == 0
  failHash(0)
  let empty = default(PreparedAccumulationRecent)
  assert empty.accumulationRecentSource.error == AccumulationRecentError.Uninitialized
  assert empty.accumulationRecentHistory.error == AccumulationRecentError.Uninitialized
  assert empty.accumulationRecentRoot.error == AccumulationRecentError.Uninitialized
  assert empty.accumulationRecentEntry.error == AccumulationRecentError.Uninitialized
  assert empty.accumulationRecentState.error == AccumulationRecentError.Uninitialized
  var detached: PreparedAccumulationRecent
  block:
    let local = predecessor(reentryFixture(base, incomingReports = 2))
    detached = prepareAccumulationRecent(local, cfg).value
  assert detached.accumulationRecentHistory.value.historyInfo.value.blocks == 2
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    failHash(1)
    assert prepareAccumulationRecent(source, cfg).error == AccumulationRecentError.BackendFailure
    failAfter(1) # Header hashing succeeds; the following private trie publication refuses.
    let refused = prepareAccumulationRecent(source, cfg)
    assert refused.error == AccumulationRecentError.StateFailure
    assert refused.stateError == StateStoreError.BackendFailure
    failHash(0)
    let current = prepareAccumulationRecent(source, cfg).value
    assert current.accumulationRecentEntry.value.value == expected
    assert array[32, byte](current.accumulationRecentState.value.commitment.root) == array[32,
        byte](candidate.commitment.root)
    assert prior.lookup(key).value.bytes == old
  let after = getOccupiedMem()
  assert before == after, "recent candidate ARC release"
  recordArcRelease("accumulation_recent", 1000, before, after)
  echo "Accumulation recent history passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fallible fixture I/O remains a strict native test failure.
except:
  quit(2)
