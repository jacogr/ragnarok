# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_times_arc_release"}

## Literal account timestamps and certified S membership preserve complete maps and atomic rollback.

import std/[assertions, envvars, syncio]
import ../../../src/state/[accumulation_times, accumulation_statistics, accumulation_recent,
  accumulation_ready, accumulation_history, accumulation_finalization, accumulation_outputs,
  accumulation_reentry, accumulation_continuation_execution, accumulation_continuation,
  accumulation_execution, accumulation_inputs, accumulation_dispatch, accumulation_service,
  accumulation_skip, store]
import ../../../src/codec/[bounded, owned, report_owned, state_accounts, state_statistics,
  state_outputs, state_workqueues, state_history, state_layout, state_trie]
import ../../support/[accumulation_reentry_context, accumulation_execution_context,
  accumulation_continuation_execution_context, pvm_accumulation_provision, report_context, arc_evidence]

# Disable hashing only after real complete maps and signed certificates exist.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

# Small explicit work and rewrite policies never allocate from their maxima.
proc limits(services = 3'u64, writes = 2'u64, bytes = 210'u64): AccumulationTimesLimits =
  AccumulationTimesLimits(services: ElementLimit(services), writes: ElementLimit(writes),
      bytes: ByteLimit(bytes))

proc config(): AccumulationTimesConfig =
  ## Actual four-round fixture contains six gas rows/work-items and two retained service keys.
  AccumulationTimesConfig(statistics: AccumulationStatisticsLimits(rounds: ElementLimit(4),
    gasRows: ElementLimit(6), reports: ElementLimit(4), digests: ElementLimit(6),
        services: ElementLimit(2)),
    accounts: limits())

# All inherited queue work is finite; this slice adds independent header, output and C(3) bounds.
proc queuePolicy(): AccumulationReadyConfig =
  AccumulationReadyConfig(items: ElementLimit(100), dependencies: ElementLimit(100),
    queues: WorkQueueConfig(epochSlots: EpochSlots(12), cores: CoreCount(2),
      perSlot: ElementLimit(20), totalItems: ElementLimit(40), perDependencies: ElementLimit(20),
      totalDependencies: ElementLimit(100), reportBytes: ByteLimit(4096), maxBytes: ByteLimit(65536)))

proc recentPolicy(): AccumulationRecentConfig =
  ## Header/pair work and history input/output storage have separate policies.
  AccumulationRecentConfig(headerBytes: ByteLimit(4096),
    outputs: OutputLogConfig(items: ElementLimit(4), maxBytes: ByteLimit(145)),
    history: HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8), perBlock: ElementLimit(2),
      totalPackages: ElementLimit(16), peaks: ElementLimit(10), maxBytes: ByteLimit(4096)))

# Complete only real guests or source-derived non-invoking skips.
proc completed(source: PreparedAccumulationReentry,
    provided = false): CompletedAccumulationReentry =
  var runs: seq[AccumulationDispatchResult] = @[]
  var skips: seq[SkippedAccumulation] = @[]
  for index in 0..<source.reentryInputs.value.invocationServiceCount.value:
    let service = prepareReentryAccumulationService(source, InvocationServiceIndex(uint64(index)),
      continuationServiceConfig()).value
    if service.serviceInfo.value.code == AccumulationCodeStatus.Ready:
      runs.add(reentryGuest(source, uint64(index), provided = provided and index ==
          0)) # All gas observations come from actual PVM execution.
    else:
      skips.add(finishUninvokedAccumulation(service).value) # Missing code never invents zero-gas executions.
  completeAccumulationReentry(source, runs, skips, executionLimits()).value

# Finalize only after actual guest rounds have reached an idle entry under a finite fixture depth.
proc finished(fixture: ReentryFixture, provided = false): PreparedFinalAccumulation =
  let limits = AccumulationOutputHistoryLimits(rounds: ElementLimit(6), executions: ElementLimit(10),
    log: OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(1)))
  if not fixture.source.reentryInfo.value.dispatch:
    return prepareFinalAccumulation(fixture.source.reentrySource.value,
        limits).value # Earliest genuine stopped form.
  let policy = executionRoundConfig()
  let config = AccumulationReentryConfig(selection: AccumulationContinuationLimits(
    executions: ElementLimit(2), reports: ElementLimit(4), digests: ElementLimit(8)),
    operands: policy.operands, inputs: policy.inputs)
  var current = fixture.source
  for step in 0..<4:
    let done = completed(current, provided)
    if not current.reentryInfo.value.dispatch:
      return prepareFinalAccumulation(done, limits).value # The exact terminal certificate binds all earlier usage.
    current = prepareAccumulationReentry(done, config, AccumulationReentryDepthLimit(4)).value
  assert false # Authored fixture histories must reach n=0 within their explicit depth budget.
  default(PreparedFinalAccumulation)

# Build the exact predecessor through the already-certified queue/history/recent adapters.
proc predecessor(fixture: ReentryFixture, provided = false): PreparedAccumulationRecent =
  let finalized = finished(fixture, provided)
  let history = prepareAccumulationHistory(finalized,
    AccumulationHistoryConfig(reports: ElementLimit(4), queues: queuePolicy().queues)).value
  let ready = prepareAccumulationReady(history, queuePolicy()).value
  prepareAccumulationRecent(ready, recentPolicy()).value

# Independent byte replacement expresses T's E4 field, without decoding/re-encoding the expected successor.
proc replaced(original: seq[byte], slot: uint32): seq[byte] =
  assert original.len == 105, "fixed metadata witness extent"
  result = newSeq[byte](original.len)
  for index in 0..<original.len: result[index] = original[index]
  for index in 0..<4: result[97+index] = byte((slot shr (index*8)) and 255)

proc pureCases() =
  ## Every nominal fixed field must survive a timestamp update, including full-width balances/footprints/gas.
  var code = default(array[32, byte])
  for index in 0..<32: code[index] = byte(index+11)
  let metadata = ServiceMetadata(codeHash: CodeHash(code), balance: AccountBalance(high(uint64)),
    minimumAccumulationGas: Gas(high(uint64)), minimumTransferGas: Gas(high(uint64)-1),
    storageBytes: AccountStorageBytes(high(uint64)-2), depositOffset: AccountBalance(high(
        uint64)-3),
    storageItems: AccountStorageItems(high(uint32)), created: AccountSlot(high(uint32)-1),
    lastAccumulation: AccountSlot(0x10203040'u32), parent: ServiceIndex(high(uint32)))
  let first = serviceMetadataEntry(ServiceIndex(42), metadata, ByteLimit(
      ServiceMetadataBytes)).value
  var current = metadata
  current.lastAccumulation = AccountSlot(high(uint32))
  let second = serviceMetadataEntry(ServiceIndex(99), current, ByteLimit(
      ServiceMetadataBytes)).value
  let unrelated = StateEntry(key: chapterKey(StateChapter(250)), value: @[9'u8, 4, 2])
  let prior = newStateStore([first, second, unrelated], report_context.limits()).value.snapshot.value
  let emptyMap = newStateStore([], report_context.limits()).value.snapshot.value
  var services = @[ServiceIndex(42), ServiceIndex(99), ServiceIndex(100)]
  let expected = replaced(first.value, high(uint32))
  failHash(3)
  var projected = projectAccumulationTimes(prior, services, AccountSlot(high(uint32)), limits(
      writes = 1, bytes = 105)).value
  assert projected.entries.len == 1, "one changed surviving account"
  assert projected.entries[0].value == expected, "literal four-byte timestamp replacement"
  assert projected.info.services == 3 and projected.info.accounts == 2 and projected.info.absent == 1
  assert projected.info.updated == 1 and uint32(projected.info.slot) == high(uint32)
  assert array[31, byte](projected.entries[0].key) == array[31, byte](first.key)
  services[0] = ServiceIndex(700)
  projected.entries[0].value[0] = 1
  assert prior.lookup(first.key).value.bytes == first.value, "projection never aliases source metadata"
  assert prior.lookup(second.key).value.bytes == second.value
  assert prior.lookup(unrelated.key).value.bytes == unrelated.value
  let nothing = projectAccumulationTimes(emptyMap, [ServiceIndex(100)], AccountSlot(0), limits(
      writes = 0, bytes = 0)).value
  assert nothing.info.accounts == 0 and nothing.info.absent == 1 and nothing.entries.len == 0
  assert projectAccumulationTimes(emptyMap, [], AccountSlot(0), limits(services = 0, writes = 0,
      bytes = 0)).value.entries.len == 0
  let invalidMap = projectAccumulationTimes(default(StateStoreSnapshot), [], AccountSlot(0), limits())
  assert invalidMap.error == AccumulationTimesError.InvalidState
  for keys in [@[ServiceIndex(42), ServiceIndex(42)], @[ServiceIndex(99), ServiceIndex(42)]]:
    assert projectAccumulationTimes(prior, keys, AccountSlot(0), limits()).error ==
        AccumulationTimesError.NonCanonical
  for short in [limits(services = 2), limits(writes = 0), limits(bytes = 104)]:
    assert projectAccumulationTimes(prior, [ServiceIndex(42), ServiceIndex(99), ServiceIndex(100)],
        AccountSlot(high(uint32)), short).error == AccumulationTimesError.LimitExceeded
  let full = limits(services = high(uint64), writes = high(uint64), bytes = high(uint64))
  assert projectAccumulationTimes(prior, [ServiceIndex(42), ServiceIndex(99), ServiceIndex(100)],
      AccountSlot(high(uint32)), full).value.entries[0].value == expected
  assert hashCalls() == 0, "projection and all policy refusals are hash-free"
  failHash(0)
  # Whole stored values must be exactly 105 bytes; a valid prefix is not an account record.
  for size in [0, 104, 106]:
    let entry = StateEntry(key: first.key, value: newSeq[byte](size))
    let malformed = newStateStore([entry], report_context.limits()).value.snapshot.value
    failHash(3)
    let refused = projectAccumulationTimes(malformed, [ServiceIndex(42)], AccountSlot(2), limits())
    assert refused.error == AccumulationTimesError.InvalidState
    assert hashCalls() == 0
    failHash(0)
  for version in [1'u8, 128]:
    var bytes = newSeq[byte](ServiceMetadataBytes)
    bytes[0] = version
    let malformed = newStateStore([StateEntry(key: second.key, value: bytes), first],
        report_context.limits()).value.snapshot.value
    failHash(3)
    let refused = projectAccumulationTimes(malformed, [ServiceIndex(42), ServiceIndex(99)],
        AccountSlot(2), limits())
    assert refused.error == AccumulationTimesError.MetadataFailure
    let expectedReason = if version == 1: ServiceMetadataError.UnsupportedVersion else: ServiceMetadataError.NonCanonical
    assert refused.metadataError == expectedReason
    assert malformed.lookup(first.key).value.bytes == first.value, "late malformed metadata exposes no earlier partial write"
    assert hashCalls() == 0
    failHash(0)
  # Missing accounts and already-current records do not allocate entries or consume rewrite policy.
  let noChange = projectAccumulationTimes(prior, [ServiceIndex(99), ServiceIndex(100)], AccountSlot(
      high(uint32)), limits(writes = 0, bytes = 0)).value
  assert noChange.info.updated == 0 and noChange.entries.len == 0

proc main() {.raises.} =
  ## The bound constructor derives S and time; independent literal map changes verify only lastAccumulation changes.
  pureCases()
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  let extra = serviceMetadataEntry(ServiceIndex(7), ServiceMetadata(balance: AccountBalance(314),
    created: AccountSlot(1), lastAccumulation: AccountSlot(1)), ByteLimit(
        ServiceMetadataBytes)).value
  let fixture = reentryFixture(base, incomingReports = 2, extra = @[extra])
  let source = predecessor(fixture)
  let prior = source.accumulationRecentState.value
  let cfg = config()
  let plan = prepareAccumulationTimes(source, cfg).value
  let info = plan.accumulationTimesInfo.value
  assert info.services == 2 and info.accounts == 2 and info.absent == 0 and info.updated == 2
  assert uint32(info.slot) == 2, "timestamp comes from the authenticated candidate slot"
  let candidate = plan.accumulationTimesState.value
  assert sameStateSnapshot(plan.accumulationTimesSource.value.accumulationRecentState.value, prior)
  let certified = plan.accumulationTimesStatistics.value
  assert certified.statisticsInfo.value.services == 2
  assert uint64(certified.statisticsAt(StatisticsServiceIndex(
      0)).value.statistics.accumulationGas) == 66
  assert uint64(certified.statisticsAt(StatisticsServiceIndex(
      1)).value.statistics.accumulationGas) == 66
  var expectedMap: seq[StateEntry] = @[]
  for entry in fixture.initial.entries:
    let bytes = prior.lookup(entry.key).value.bytes
    let selected = array[31, byte](entry.key) == array[31, byte](chapterServiceKey(StateChapter(
        255), ServiceIndex(42))) or
      array[31, byte](entry.key) == array[31, byte](chapterServiceKey(StateChapter(255),
          ServiceIndex(99)))
    let expected = if selected: replaced(bytes, 2) else: bytes
    expectedMap.add(StateEntry(key: entry.key, value: expected))
    assert candidate.lookup(entry.key).value.bytes == expected, "only selected metadata timestamp bytes change"
  let outputKey = chapterKey(StateChapter(16))
  expectedMap.add(StateEntry(key: outputKey, value: prior.lookup(outputKey).value.bytes))
  let independent = newStateStore(expectedMap, report_context.limits()).value.snapshot.value
  assert array[32, byte](candidate.commitment.root) == array[32, byte](independent.commitment.root), "independent complete-map root"
  for chapter in [3'u8, 14, 15, 16]:
    let key = chapterKey(StateChapter(chapter))
    assert candidate.lookup(key).value.bytes == prior.lookup(key).value.bytes
  assert candidate.lookup(extra.key).value.bytes == extra.value, "unselected accounts retain their old timestamp"
  for index, service in [42'u32, 99]:
    let entry = plan.accumulationTimeEntryAt(AccumulationTimeIndex(uint64(index))).value
    let key = chapterServiceKey(StateChapter(255), ServiceIndex(service))
    assert array[31, byte](entry.key) == array[31, byte](key)
    assert entry.value == replaced(prior.lookup(key).value.bytes, 2)
  var copied = plan.accumulationTimeEntryAt(AccumulationTimeIndex(0)).value
  copied.value[97] = 7
  assert plan.accumulationTimeEntryAt(AccumulationTimeIndex(0)).value.value[97] == 2
  var observed = plan.accumulationTimesInfo.value
  observed.updated = high(int)
  assert plan.accumulationTimesInfo.value.updated == 2
  assert plan.accumulationTimeEntryAt(AccumulationTimeIndex(high(uint64))).error ==
      AccumulationTimesError.InvalidIndex
  # Allowance-only gas qualifies, missing-code work qualifies, and all-zero S does not qualify.
  for fixture in [reentryFixture(base, stopped = true), reentryFixture(base,
      first = ExecutionEnding.Missing)]:
    let bound = predecessor(fixture)
    let selected = prepareAccumulationTimes(bound, cfg).value
    assert selected.accumulationTimesInfo.value.updated == 2
    for service in [42'u32, 99]:
      let key = chapterServiceKey(StateChapter(255), ServiceIndex(service))
      assert selected.accumulationTimesState.value.lookup(key).value.bytes == replaced(
          bound.accumulationRecentState.value.lookup(key).value.bytes, 2)
  let omitted = predecessor(reentryFixture(base, second = ExecutionEnding.Missing, stopped = true))
  let omittedPlan = prepareAccumulationTimes(omitted, cfg).value
  assert omittedPlan.accumulationTimesInfo.value.services == 1 and
      omittedPlan.accumulationTimesInfo.value.updated == 1
  let omittedKey = chapterServiceKey(StateChapter(255), ServiceIndex(99))
  assert omittedPlan.accumulationTimesState.value.lookup(omittedKey).value.bytes ==
      omitted.accumulationRecentState.value.lookup(omittedKey).value.bytes
  let inactive = predecessor(reentryFixture(base, empty = true, incomingReports = 2))
  var zero = cfg
  zero.accounts = limits(services = 0, writes = 0, bytes = 0)
  zero.statistics.services = ElementLimit(0)
  failHash(3)
  let untouched = prepareAccumulationTimes(inactive, zero).value
  assert untouched.accumulationTimesInfo.value.updated == 0
  assert sameStateSnapshot(untouched.accumulationTimesState.value,
      inactive.accumulationRecentState.value)
  assert hashCalls() == 0, "new guarantees alone do not timestamp accounts when S is empty"
  failHash(0)
  let provided = predecessor(reentryFixture(base, provided = true), provided = true)
  let request = provisionRequest(42, @[73'u8])
  assert prepareAccumulationTimes(provided, cfg).value.accumulationTimesState.value.lookup(
      request.key).value.bytes == provided.accumulationRecentState.value.lookup(
      request.key).value.bytes
  for kind in 0..<4:
    var short = cfg
    case kind
    of 0: short.accounts.services = ElementLimit(1)
    of 1: short.accounts.writes = ElementLimit(1)
    of 2: short.accounts.bytes = ByteLimit(209)
    else: short.statistics.rounds = ElementLimit(3)
    failHash(3)
    let refused = prepareAccumulationTimes(source, short)
    if kind == 3:
      assert refused.statisticsError == AccumulationStatisticsError.LimitExceeded
    else:
      assert refused.error == AccumulationTimesError.LimitExceeded
    assert hashCalls() == 0
    failHash(0)
  let empty = default(PreparedAccumulationTimes)
  assert empty.accumulationTimesInfo.error == AccumulationTimesError.Uninitialized
  assert empty.accumulationTimesSource.error == AccumulationTimesError.Uninitialized
  assert empty.accumulationTimesStatistics.error == AccumulationTimesError.Uninitialized
  assert empty.accumulationTimesState.error == AccumulationTimesError.Uninitialized
  assert empty.accumulationTimeEntryAt(AccumulationTimeIndex(0)).error ==
      AccumulationTimesError.Uninitialized
  assert prepareAccumulationTimes(default(PreparedAccumulationRecent), cfg).error ==
      AccumulationTimesError.InvalidSource
  var detached: PreparedAccumulationTimes
  block:
    let local = predecessor(reentryFixture(base))
    detached = prepareAccumulationTimes(local, cfg).value
  assert detached.accumulationTimesInfo.value.updated == 2
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    failHash(1)
    assert prepareAccumulationTimes(source, cfg).stateError == StateStoreError.BackendFailure
    failAfter(1)
    assert prepareAccumulationTimes(source, cfg).stateError == StateStoreError.BackendFailure
    failHash(0)
    let current = prepareAccumulationTimes(source, cfg).value
    assert array[32, byte](current.accumulationTimesState.value.commitment.root) == array[32, byte](
        candidate.commitment.root)
    assert prior.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(42))).value.bytes[97] == 0
  let after = getOccupiedMem()
  assert before == after, "timestamp candidate ARC release"
  recordArcRelease("accumulation_times", 1000, before, after)
  echo "Accumulation account timestamps passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fallible fixture I/O remains a strict native failure.
except:
  quit(2)
