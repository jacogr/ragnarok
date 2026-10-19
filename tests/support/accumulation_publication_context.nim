# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent metadata octets, processed-package framing and full-map roots verify coordinated atomic accumulation publication.

import std/assertions
import ../../src/state/[accumulation_publication, accumulation_accounts, accumulation_history,
  block_activity, service_activity, accumulation_statistics, accumulation_finalization,
  accumulation_outputs, accumulation_execution, accumulation_round, accumulation_queue, store]
import ../../src/codec/[bounded, composite, owned, report_owned, state_workqueues, state_layout, state_trie]
import ./report_context

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc publicationPolicy*(): AccumulationPublicationConfig =
  ## Final batch caps are independent of metadata inspection and processed history traversal.
  AccumulationPublicationConfig(accounts: AccumulationAccountConfig(services: ElementLimit(2),
      metadataBytes: ByteLimit(178)),
    history: AccumulationHistoryConfig(reports: ElementLimit(4), queues: WorkQueueConfig(
      cores: CoreCount(2), epochSlots: EpochSlots(12), perSlot: ElementLimit(4),
          totalItems: ElementLimit(4),
      maxBytes: ByteLimit(140))), writes: ElementLimit(4), writeBytes: ByteLimit(4096))
proc sameWrite(left, right: StateWrite) =
  ## Compare complete fixed keys, mutation kind and independent payload bytes.
  assert array[31, byte](left.key) == array[31, byte](right.key)
  assert left.kind == right.kind and left.value == right.value

proc checkAccumulationPublication*(activity: PreparedBlockActivity, original: openArray[StateEntry],
    empty = false): PublishedAccumulation =
  ## Source activity, history and timestamps must share one batch and retain rollback and exact stage identity.
  let statistics = activity.blockActivitySource.value.serviceActivitySource.value
  let finalized = statistics.statisticsSource.value
  let prior = finalized.finalAccumulationState.value
  let initial = finalized.finalAccumulationOutputs.value.outputsSource.value
  let reports = initial.executionRound.value.roundBlockQueue.value.accumulationProjection.value
  var expected: seq[StateWrite] = @[]
  if not empty:
    for service in [42'u32, 99'u32]:
      let key = chapterServiceKey(StateChapter(255), ServiceIndex(service))
      var bytes = prior.lookup(key).value.bytes
      assert bytes.len == 89
      for index in 81..84: bytes[index] = (if index ==
          81: 2'u8 else: 0'u8) # Literal child-slot E4 patch, all other metadata preserved.
      expected.add(StateWrite(key: key, kind: StateWriteKind.Put, value: bytes))
  let entry = activity.blockActivityEntry.value
  expected.add(StateWrite(key: entry.key, kind: StateWriteKind.Put, value: entry.value))
  if not empty:
    var ring = newSeq[byte](11)
    ring.add(4'u8)
    for index in 0..<4:
      let hash = reports.accumulationAt(AccumulationIndex(uint64(
          index))).value.ownedReportInfo.value.header.packageHash
      assert hash.bytes[0] == byte(64+index)
      for octet in hash.bytes: ring.add(octet) # Independent literal row framing around exact original processed identities.
    expected.add(StateWrite(key: chapterKey(StateChapter(15)), kind: StateWriteKind.Put, value: ring))
  var byteCount = 0'u64
  for write in expected: byteCount += uint64(write.value.len) # Authored tiny fixtures prove this reference sum fits uint64.
  failHash(3)
  let plan = prepareAccumulationPublication(activity, publicationPolicy()).value
  let info = plan.accumulationPublicationInfo.value
  assert info.writes == (if empty: 1 else: 4) and info.writeBytes == byteCount
  assert info.accounts.services == (if empty: 0 else: 2) and info.accounts.updates == (
      if empty: 0 else: 2)
  assert uint32(info.accounts.slot) == 2
  assert info.history.processedReports == (if empty: 0 else: 4)
  assert info.history.newPackages == (if empty: 0 else: 4) and info.history.slots == 12
  assert info.activity.services == (if empty: 0 else: 3) # Provision-only service 77 is not part of timestamp traversal.
  for index, wanted in expected:
    sameWrite(plan.accumulationPublicationWrite(PublicationWriteIndex(uint64(index))).value, wanted)
  var copied = plan.accumulationPublicationWrite(PublicationWriteIndex(0)).value
  copied.value[0] = copied.value[0] xor 255
  sameWrite(plan.accumulationPublicationWrite(PublicationWriteIndex(0)).value, expected[0])
  var observation = plan.accumulationPublicationInfo.value
  observation.writes = 999
  assert plan.accumulationPublicationInfo.value.writes == expected.len
  assert sameStateSnapshot(plan.accumulationPublicationPrior.value, prior)
  assert plan.accumulationPublicationWrite(PublicationWriteIndex(high(uint64))).error ==
      AccumulationPublicationError.InvalidIndex
  var exact = publicationPolicy()
  exact.writes = ElementLimit(uint64(expected.len))
  exact.writeBytes = ByteLimit(byteCount)
  assert prepareAccumulationPublication(activity, exact).error == AccumulationPublicationError.None
  var short = exact
  short.writes = ElementLimit(uint64(expected.len-1))
  assert prepareAccumulationPublication(activity, short).error ==
      AccumulationPublicationError.LimitExceeded
  short = exact
  short.writeBytes = ByteLimit(byteCount-1)
  assert prepareAccumulationPublication(activity, short).error ==
      AccumulationPublicationError.LimitExceeded
  short = exact
  short.history.queues.epochSlots = EpochSlots(11)
  assert prepareAccumulationPublication(activity, short).error ==
      AccumulationPublicationError.InvalidConfig
  short = exact
  short.history.queues.maxBytes = ByteLimit(11)
  assert prepareAccumulationPublication(activity, short).error ==
      AccumulationPublicationError.LimitExceeded
  if not empty:
    short = exact
    short.accounts.services = ElementLimit(1)
    assert prepareAccumulationPublication(activity, short).error ==
        AccumulationPublicationError.LimitExceeded
    short = exact
    short.accounts.metadataBytes = ByteLimit(177)
    let accountFailure = prepareAccumulationPublication(activity, short)
    assert accountFailure.error == AccumulationPublicationError.AccountFailure and
        accountFailure.accountError == AccumulationAccountError.LimitExceeded
    short = exact
    short.history.reports = ElementLimit(3)
    assert prepareAccumulationPublication(activity, short).error ==
        AccumulationPublicationError.LimitExceeded
    short = exact
    short.history.queues.maxBytes = ByteLimit(139)
    let historyFailure = prepareAccumulationPublication(activity, short)
    assert historyFailure.error == AccumulationPublicationError.HistoryCodecFailure and
        historyFailure.historyCodecError == WorkQueueError.LimitExceeded
  var wide = exact
  wide.writes = ElementLimit(high(uint64))
  wide.writeBytes = ByteLimit(high(uint64))
  wide.accounts.services = ElementLimit(high(uint64))
  wide.accounts.metadataBytes = ByteLimit(high(uint64))
  wide.history.reports = ElementLimit(high(uint64))
  wide.history.queues.perSlot = ElementLimit(high(uint64))
  wide.history.queues.totalItems = ElementLimit(high(uint64))
  wide.history.queues.maxBytes = ByteLimit(high(uint64))
  assert prepareAccumulationPublication(activity, wide).value.accumulationPublicationInfo.value.writes == expected.len
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareAccumulationPublication(activity, publicationPolicy()).value
    assert local.accumulationPublicationInfo.value.writes == expected.len
  assert before == getOccupiedMem() # Pure projections, source handles and retained batch bytes release each cycle.
  assert hashCalls() == 0
  failHash(0)
  var priorEntries: seq[StateEntry] = @[]
  for record in original: priorEntries.add(StateEntry(key: record.key, value: prior.lookup(
      record.key).value.bytes))
  let log = chapterKey(StateChapter(16))
  priorEntries.add(StateEntry(key: log, value: prior.lookup(log).value.bytes))
  assert priorEntries.len == prior.commitment.entries # Enumerate the complete known fixture map, including finalized C(16).
  var equalMap = newStateStore(priorEntries, report_context.limits()).value
  assert array[32, byte](equalMap.snapshot.value.commitment.root) == array[32, byte](
      prior.commitment.root)
  var foreign = forkStateStore(prior).value
  discard foreign.apply([StateWrite(key: chapterKey(StateChapter(250)), kind: StateWriteKind.Put,
      value: @[1'u8])]).value
  let foreignPrior = foreign.snapshot.value
  var missing = default(StateStore)
  failHash(3)
  assert advanceAccumulation(equalMap, plan).error == AccumulationPublicationError.ForeignState
  assert advanceAccumulation(foreign, plan).error == AccumulationPublicationError.ForeignState
  assert advanceAccumulation(missing, plan).error == AccumulationPublicationError.InvalidState
  assert sameStateSnapshot(foreign.snapshot.value, foreignPrior)
  assert hashCalls() == 0 # Snapshot identity refusals happen before Merklization, even for equal roots/bytes.
  failHash(0)
  for successful in [0, 2]:
    var caller = forkStateStore(prior).value
    hashAfter(cint(successful))
    let refused = advanceAccumulation(caller, plan)
    assert refused.error == AccumulationPublicationError.StateFailure and refused.stateError ==
        StateStoreError.BackendFailure
    failHash(0)
    assert sameStateSnapshot(caller.snapshot.value,
        prior) # One failed combined batch cannot publish any earlier timestamp/chapter.
  hashAfter(2)
  let refused = publishAccumulation(plan)
  assert refused.error == AccumulationPublicationError.StateFailure and refused.stateError ==
      StateStoreError.BackendFailure
  failHash(0)
  var wanted = priorEntries
  for index in 0..<wanted.len:
    for write in expected:
      if array[31, byte](wanted[index].key) == array[31, byte](write.key):
        wanted[index].value = write.value # Complete independent map replacement, without the production batch/update path.
  let root = stateTrieRoot(wanted, report_context.limits().trie).value
  let published = publishAccumulation(plan).value
  let posterior = published.publishedAccumulationState.value
  assert array[32, byte](posterior.commitment.root) == array[32, byte](root.root)
  for record in wanted: assert posterior.lookup(record.key).value.bytes ==
      record.value # Every expected changed/unrelated key is preserved exactly.
  assert posterior.lookup(log).value.bytes == prior.lookup(log).value.bytes
  assert posterior.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(77))).error ==
      StateStoreError.MissingKey
  var caller = forkStateStore(prior).value
  let advanced = advanceAccumulation(caller, plan).value
  assert sameStateSnapshot(caller.snapshot.value, advanced.publishedAccumulationState.value)
  assert array[32, byte](caller.snapshot.value.commitment.root) == array[32, byte](root.root)
  let changed = caller.snapshot.value
  failHash(3)
  assert advanceAccumulation(caller, plan).error == AccumulationPublicationError.ForeignState
  assert sameStateSnapshot(caller.snapshot.value, changed) and hashCalls() ==
      0 # Stale replay cannot shift history or increment metrics twice.
  failHash(0)
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = publishAccumulation(plan).value
    assert local.publishedAccumulationState.value.commitment.entries == prior.commitment.entries
    var target = forkStateStore(prior).value
    discard advanceAccumulation(target, plan).value # Each fresh caller commits one complete batch, then releases its immutable map.
  assert occupied == getOccupiedMem()
  assert sameStateSnapshot(finalized.finalAccumulationState.value, prior)
  let missingActivity = default(PreparedBlockActivity)
  let rejected = prepareAccumulationPublication(missingActivity, publicationPolicy())
  assert rejected.error == AccumulationPublicationError.InvalidSource
  assert publishAccumulation(default(PreparedAccumulationPublication)).error ==
      AccumulationPublicationError.InvalidSource
  published
