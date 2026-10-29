# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal whole-C(13) bytes and independent complete-map roots verify source-derived assembly and rollback.

import std/assertions
import "../../src/state/block/activity" as block_activity
import ../../src/state/core/activity as core_activity
import ../../src/state/validator/activity as validator_activity
import ../../src/state/service/activity as service_activity
import ../../src/state/accumulation/[statistics as accumulation_statistics,
    finalization as accumulation_finalization, outputs as accumulation_outputs,
    execution as accumulation_execution, round as accumulation_round, queue as accumulation_queue]
import ../../src/state/report/admission as report_admission
import ../../src/state/guarantee_credentials
import "../../src/state/block/transition" as block_transition
import "../../src/state/block/admission" as block_admission
import ../../src/state/store
import ../../src/codec/[bounded, composite, owned, report_owned]
import ../../src/codec/work/[report as work_report, digest as work_digest]
import ../../src/codec/state/[statistics as state_statistics, safrole as state_safrole,
    layout as state_layout, trie as state_trie]
import ../../src/codec/[header, tickets]
import ./report_context

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc blockPolicy*(): BlockActivityConfig =
  ## Explicit producer budgets precede independent complete encoded-output limits.
  BlockActivityConfig(core: CoreActivityConfig(cores: ElementLimit(2), incoming: ElementLimit(2),
    available: ElementLimit(2), digests: ElementLimit(2), assurances: ElementLimit(6),
    assuranceBits: ElementLimit(12), assuranceBytes: ByteLimit(4096)),
    validators: ValidatorActivityConfig(validators: ElementLimit(6), services: ElementLimit(1),
      tickets: ElementLimit(2), preimages: ElementLimit(3), assurances: ElementLimit(6),
      reporters: ElementLimit(6), reporterWork: ElementLimit(36), rosterBytes: ByteLimit(4096),
      statisticsBytes: ByteLimit(4096), preimageFrameBytes: ByteLimit(19), preimageBytes: ByteLimit(3),
      assuranceBytes: ByteLimit(4096)), services: ElementLimit(3), maxBytes: ByteLimit(4096))
proc blockPrior*(): StateEntry =
  ## Stale per-block core/service data must disappear while zero epoch counters receive only this block's credits.
  var state = ActivityState(cores: newSeq[CoreActivity](2), services: @[ServiceStatisticsEntry(
      service: ServiceIndex(777))])
  for epoch in low(StatisticsEpoch)..high(StatisticsEpoch):
    state.validators[epoch] = newSeq[ValidatorActivity](6)
  state.cores[0].gas = ActivityGas(99)
  state.cores[0].counters[CoreMeasure.Popularity] = ActivityNatural(88)
  state.services[0].statistics.counters[ServiceMeasure.ProvisionCount] = ActivityNatural(77)
  activityStateEntry(state, ActivityConfig(cores: CoreCount(2), current: ValidatorCount(6),
      previous: ValidatorCount(6),
    maxServices: ElementLimit(1), maxBytes: ByteLimit(4096))).value
proc blockTemplate*(base: OwnedReport): OwnedReport =
  ## Fix independent incoming metrics; genuine signing later overrides identity/code fields and maximal refinement gas.
  let raw = reportBytes(base)
  var report = decodeReportBorrowed(raw, 2).value
  report.header.bundleLength = BundleLength(7)
  report.header.segmentCount = SegmentCount(64)
  report.digestCount = 1
  report.digests[0].refine = RefineLoad(gasUsed: Gas(11), imports: ImportCount(13),
    extrinsicCount: work_digest.ExtrinsicCount(17), extrinsicSize: work_digest.ExtrinsicBytes(19),
        exports: ExportCount(23))
  var bytes = newSeq[byte](raw.len+1024)
  let encoded = encodeReportBorrowed(report, raw, 2, bytes)
  assert encoded.error == CompositeError.None
  decodeOwnedReport(bytes.toOpenArray(0, encoded.written-1), 2).value
proc putE4(output: var seq[byte], value: uint32) =
  ## Independently emit fixed validator counters and service IDs without using the production codec.
  for index in 0..<4: output.add(byte((value shr (index*8)) and 255))
proc maximum(output: var seq[byte]) =
  ## Literal canonical maximal uint64 natural is the discriminator ff and eight ff payload octets.
  for index in 0..<9: output.add(255'u8)
proc expectedWire(admission: AdmittedReports, empty: bool): seq[byte] =
  ## Every non-maximal natural in these authored cases fits one octet; neither encoder nor metric producer supplies expected fields.
  let staged = admission.reportBlockStage.value
  let author = uint16(staged.value.admitted.admittedHeader.headerInfo.value.unsigned.author)
  let raw = staged.value.snapshot.lookup(chapterKey(StateChapter(8))).value.bytes
  let active = decodeStateValidators(raw, ValidatorStateConfig(cores: CoreCount(2),
      validators: ElementLimit(6), maxBytes: ByteLimit(4096))).value.value
  let reporters = admission.reportCredentials.value
  result = @[6'u8]
  for index in 0..<6:
    var reporting = 0'u32
    let key = array[32, byte](active.validatorAt(StateValidatorIndex(uint64(index))).value.ed25519)
    for ordinal in 0..<reporters.verifiedReporterCount.value:
      if key == array[32, byte](reporters.verifiedReporterAt(ordinal).value):
        reporting = 1
        break # Independent key membership selects one increment, not a credential count.
    let authored = uint16(index) == author
    for counter in [uint32(if authored: 1 else: 0), 0'u32, uint32(if authored and
        not empty: 3 else: 0),
      uint32(if authored and not empty: 3 else: 0), reporting, 0'u32]: putE4(result, counter)
  result.add(6'u8)
  for index in 0..<144: result.add(0'u8) # Previous six zero E4 tuples stay unchanged within the epoch.
  if empty:
    for index in 0..<16: result.add(0'u8) # Every fresh field of both unused core rows is zero.
    result.add(0'u8) # No old service dictionary entry survives an inactive block.
  else:
    for value in [0'u8, 0, 13, 17, 19, 23, 7]: result.add(
        value) # Incoming refinement and bundle usage on core zero only.
    maximum(result)
    for index in 0..<8: result.add(0'u8) # Unused core one is a complete zero tuple.
    result.add(3'u8)
    putE4(result, 42)
    for value in [2'u8, 2, 1]: result.add(value) # Two provisions, two bytes and one incoming refinement.
    maximum(result)
    for value in [13'u8, 17, 19, 23, 4, 0, 66]: result.add(
        value) # Four processed work-items and actual PVM consumption.
    putE4(result, 77)
    for value in [1'u8, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]: result.add(value) # Provision-only service.
    putE4(result, 99)
    for value in [0'u8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 66]: result.add(
        value) # Accumulation-only service with two work-items.

proc checkBlockActivity*(source: PreparedServiceActivity, original: openArray[StateEntry],
    empty = false): PublishedBlockActivity =
  ## Compose actual finalization with original block provenance, then verify byte-exact assembly, atomic publication and owner release.
  let finalized = source.serviceActivitySource.value.statisticsSource.value
  let prior = finalized.finalAccumulationState.value
  let initial = finalized.finalAccumulationOutputs.value.outputsSource.value
  let admission = initial.executionRound.value.roundBlockQueue.value.accumulationAdmission.value
  let expected = expectedWire(admission, empty)
  failHash(3)
  let plan = prepareBlockActivity(source, blockPolicy()).value
  let info = plan.blockActivityInfo.value
  assert info.validators == [6, 6] and info.cores == 2 and info.services == (if empty: 0 else: 3)
  let entry = plan.blockActivityEntry.value
  assert array[31, byte](entry.key) == array[31, byte](chapterKey(StateChapter(13)))
  assert entry.value == expected
  let decoded = decodeActivityState(entry.value, plan.blockActivityProfile.value).value
  assert decoded.consumed == expected.len and decoded.snapshot.activityInfo.value.services == info.services
  var copied = plan.blockActivityEntry.value
  copied.value[0] = 0
  assert plan.blockActivityEntry.value.value == expected # Independent entry bytes cannot alter publication input.
  var observed = plan.blockActivityInfo.value
  observed.services = 999
  assert plan.blockActivityInfo.value.services == info.services
  var profile = plan.blockActivityProfile.value
  profile.current = ValidatorCount(9)
  assert uint64(plan.blockActivityProfile.value.current) == 6
  var exact = blockPolicy()
  exact.maxBytes = ByteLimit(uint64(expected.len))
  exact.services = ElementLimit(uint64(info.services))
  assert prepareBlockActivity(source, exact).value.blockActivityEntry.value.value == expected
  var short = exact
  short.maxBytes = ByteLimit(uint64(expected.len-1))
  let refusal = prepareBlockActivity(source, short)
  assert refusal.error == BlockActivityError.CodecFailure and refusal.codecError ==
      ActivityError.LimitExceeded
  if not empty:
    short = exact
    short.services = ElementLimit(2)
    assert prepareBlockActivity(source, short).error == BlockActivityError.LimitExceeded
  short = exact
  short.core.cores = ElementLimit(1)
  let coreFailure = prepareBlockActivity(source, short)
  assert coreFailure.error == BlockActivityError.CoreFailure and coreFailure.coreError ==
      CoreActivityError.LimitExceeded
  short = exact
  short.validators.statisticsBytes = ByteLimit(0)
  let validatorFailure = prepareBlockActivity(source, short)
  assert validatorFailure.error == BlockActivityError.ValidatorFailure and
      validatorFailure.validatorError == ValidatorActivityError.LimitExceeded
  var wide = exact
  wide.services = ElementLimit(high(uint64))
  wide.maxBytes = ByteLimit(high(uint64))
  assert prepareBlockActivity(source, wide).value.blockActivityEntry.value.value == expected
  assert sameStateSnapshot(plan.blockActivitySource.value.serviceActivitySource.value.statisticsSource.value.finalAccumulationState.value, prior)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareBlockActivity(source, blockPolicy()).value
    assert local.blockActivityInfo.value.services == info.services
  assert before == getOccupiedMem() # Component owners, fixed rows and encoded entry storage retire without retained growth.
  assert hashCalls() == 0
  failHash(0)
  for successful in [0, 2]:
    hashAfter(cint(successful))
    let failed = publishBlockActivity(plan)
    assert failed.error == BlockActivityError.StateFailure and failed.stateError ==
        StateStoreError.BackendFailure
    failHash(0)
    assert sameStateSnapshot(finalized.finalAccumulationState.value,
        prior) # Early and late root refusals preserve the exact source.
  let published = publishBlockActivity(plan).value
  let posterior = published.publishedActivityState.value
  assert posterior.lookup(entry.key).value.bytes == expected
  var entries: seq[StateEntry] = @[]
  for record in original:
    let old = prior.lookup(record.key).value.bytes
    let wanted = if array[31, byte](record.key) == array[31, byte](entry.key): expected else: old
    entries.add(StateEntry(key: record.key, value: wanted))
    if array[31, byte](record.key) != array[31, byte](entry.key):
      assert posterior.lookup(record.key).value.bytes ==
          old # Every original unrelated value, including service effects, is preserved.
  let log = chapterKey(StateChapter(16))
  entries.add(StateEntry(key: log, value: prior.lookup(log).value.bytes))
  assert entries.len == prior.commitment.entries # Authored guests create no hidden keys beyond the final output log.
  let root = stateTrieRoot(entries, report_context.limits().trie).value
  assert array[32, byte](posterior.commitment.root) == array[32, byte](root.root)
  assert posterior.lookup(log).value.bytes == prior.lookup(log).value.bytes
  assert sameStateSnapshot(finalized.finalAccumulationState.value, prior)
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = publishBlockActivity(plan).value
    assert local.publishedActivityState.value.lookup(entry.key).value.byteLength == expected.len
  assert occupied == getOccupiedMem() # Complete private maps and retained source graphs retire each publication cycle.
  assert published.publishedActivitySource.value.blockActivityEntry.value.value == expected
  assert prepareBlockActivity(default(PreparedServiceActivity), blockPolicy()).error ==
      BlockActivityError.InvalidSource
  assert publishBlockActivity(default(PreparedBlockActivity)).error ==
      BlockActivityError.InvalidSource
  published
