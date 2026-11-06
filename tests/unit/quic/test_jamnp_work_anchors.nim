# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_work_anchors_arc_release"}

## Complete captured maps and real sealed parent links qualify contexts without fabricating authorizations or signatures.
import std/[assertions, syncio]
import ../../../src/jamnp-s/[work_submission, work_anchors, work_population]
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/[bounded, header, composite, assurances]
import ../../../src/codec/state/[history, layout, trie, safrole]
import ../../../src/codec/work/[package, digest, report]
import ../../../src/state/[ancestor_context, store]
import ../../../src/state/report/anchors
import ../../support/[jamnp_topology_fixture, arc_evidence]

proc limits(cores = 2): WorkAnchorLimits =
  ## The two-core structural source uses explicit independent decode/header work budgets.
  WorkAnchorLimits(history: HistoryConfig(cores: CoreCount(uint64(cores)), blocks: ElementLimit(8),
    perBlock: ElementLimit(2), totalPackages: ElementLimit(16), peaks: ElementLimit(64),
    maxBytes: ByteLimit(4096)), ancestors: AncestorContextLimits(header: HeaderConfig(
      cores: CoreCount(uint64(cores)), authorValidators: ValidatorCount(6), epochSlots: EpochSlots(12),
      maxBytes: ByteLimit(4096)), headers: ElementLimit(8), maxBytes: ByteLimit(32768)))
proc captured(slot: uint32, parent = unavailableGenesis(), suffix = false,
    cores = 2, active = 6, pending = 6, duration = 12,
    omitPending = false, pendingSuffix = false): BlockSnapshotResult =
  ## Preserve actual sealed ancestry while independently creating complete canonical-shaped recent history.
  let seed = topologyCaptured([topologyRecords(0, 6), topologyRecords(1, active), topologyRecords(2,
      pending)],
    cores = cores, duration = duration, atSlot = slot, parent = parent)
  assert seed.error == GenesisError.None, "anchor seed: " & $seed.error
  var records: seq[HistoryBlock] = @[]
  let peak = HistorySuperPeak([33'u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
  if parent.error == GenesisError.None:
    records.add(HistoryBlock(header: HistoryHeaderHash(array[32, byte](parent.value.blockHash)),
      state: HistoryStateRoot(array[32, byte](parent.value.stateRoot)), superPeak: peak,
      slot: HistorySlot(parent.value.slot)))
  records.add(HistoryBlock(header: HistoryHeaderHash(array[32, byte](seed.value.blockHash)),
    state: HistoryStateRoot(default(array[32, byte])), superPeak: peak, slot: HistorySlot(slot)))
  let recent = historyStateEntry(HistoryState(blocks: records), limits(cores).history)
  assert recent.error == HistoryError.None
  var entries: seq[StateEntry] = @[]
  for index in 0..<seed.value.keyCount:
    # A fresh complete map preserves immutable source creation ceilings; no production state guard is weakened.
    let key = seed.value.keyAt(StateKeyIndex(index))
    let isPending = array[31, byte](key) == array[31, byte](chapterKey(StateChapter(4)))
    if isPending and omitPending: continue # Missing future-state evidence must remain observable.
    var value = seed.value.lookup(key).value.bytes
    if isPending and pendingSuffix: value.add(0) # Prefix-decodable C4 still is not an exact state chapter.
    entries.add(StateEntry(key: key, value: value))
  var chapter = recent.value
  if suffix: chapter.value.add(0)
  entries.add(chapter)
  var wire = newSeq[byte](seed.value.header.headerInfo.value.consumed)
  assert seed.value.header.encodeOwnedHeader(wire).error == HeaderError.None
  captureBlockSnapshot(wire, entries, seed.value.chainParameters)
proc context(source: BlockSnapshot): RefinementContext =
  ## The current head's actual complete posterior root replaces its zero pending C(3) root only during qualification.
  result = RefinementContext(anchor: report.BlockHash(bytes: array[32, byte](source.blockHash)),
    stateRoot: report.StateRoot(bytes: array[32, byte](source.stateRoot)), anchorSlot: AnchorSlot(
        source.slot),
    accumulationRoot: AccumulationRoot(bytes: [33'u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    lookupAnchor: report.BlockHash(bytes: array[32, byte](source.blockHash)),
        lookupSlot: LookupSlot(source.slot),
    lookupStateRoot: LookupStateRoot(bytes: array[32, byte](source.stateRoot)))
proc submission(context: RefinementContext): WorkSubmissionHeader =
  ## A genuine bounded package decoder supplies original header identity; this fixture grants no authorization or credential.
  let package = WorkPackage(context: context, items: @[WorkItem(service: ServiceIndex(1),
    refineGas: Gas(1), accumulateGas: Gas(1))])
  var wire = newSeq[byte](4096)
  let encoded = encodeWorkPackage(package, fullPackageConfig(ByteLimit(4096)), wire)
  assert encoded.error == PackageError.None
  var message = @[0'u8, 0]
  for index in 0..<encoded.value: message.add(wire[index])
  let decoded = decodeWorkSubmission(WorkSubmissionKind.Package, message, [], fullPackageConfig(
      ByteLimit(4096)))
  assert decoded.error == WorkSubmissionError.None
  decoded.value
proc cycle(original: WorkSubmissionHeader, view: ChainView) =
  ## Complete and refused qualifications release the original header/map and bounded temporary ancestry/history owners.
  let outcome = captureWorkAnchors(original, view, StateTime(20), limits())
  assert outcome.error == WorkAnchorError.None
  assert outcome.value.anchorInfo.value.inclusionSlot == StateTime(21)
  assert outcome.value.anchoredWorkMatches(original, view.bestBlock.value.stateSnapshot)
  let population = captureWorkPopulation(outcome.value, original, view, topologyLimits(2))
  assert population.error == WorkPopulationError.None
  assert population.value.accepts(ErasureShards(6))
  let rejected = captureWorkAnchors(original, view, StateTime(19), limits())
  assert rejected.error == WorkAnchorError.InvalidSlot
proc main() =
  ## Current-head roots, older child commitments, mixed tuples, exact source identity and every resource refusal are independent witnesses.
  let first = captured(18)
  let head = captured(20, first)
  assert first.error == GenesisError.None and head.error == GenesisError.None
  let view = genesisView(first).advanceView(head).value
  let declared = context(head.value)
  let original = submission(declared)
  let accepted = captureWorkAnchors(original, view, StateTime(20), limits())
  assert accepted.error == WorkAnchorError.None, "current complete-map lookup root"
  assert not accepted.value.anchoredWorkMatches(submission(declared), head.value.stateSnapshot)
  assert not accepted.value.anchoredWorkMatches(original, first.value.stateSnapshot)
  assert default(AnchoredWorkContext).anchorInfo.error == WorkAnchorError.Uninitialized
  var older = declared
  older.lookupAnchor = report.BlockHash(bytes: array[32, byte](first.value.blockHash))
  older.lookupSlot = LookupSlot(18)
  older.lookupStateRoot = LookupStateRoot(bytes: array[32, byte](first.value.stateRoot))
  assert captureWorkAnchors(submission(older), view, StateTime(20), limits()).error ==
      WorkAnchorError.None
  var bad = older
  bad.lookupStateRoot.bytes[0] = bad.lookupStateRoot.bytes[0] xor 1
  let wrongRoot = captureWorkAnchors(submission(bad), view, StateTime(20), limits())
  assert wrongRoot.error == WorkAnchorError.LookupFailure
  assert wrongRoot.ancestorError == AncestorContextError.WrongLookupState
  bad = older
  bad.lookupSlot = LookupSlot(19)
  assert captureWorkAnchors(submission(bad), view, StateTime(20), limits()).ancestorError ==
      AncestorContextError.WrongLookupSlot
  bad = declared
  bad.stateRoot.bytes[0] = bad.stateRoot.bytes[0] xor 1
  assert captureWorkAnchors(submission(bad), view, StateTime(20), limits()).recentError ==
      ReportAnchorError.InvalidRecentAnchor
  bad = declared
  bad.accumulationRoot.bytes[0] = bad.accumulationRoot.bytes[0] xor 1
  assert captureWorkAnchors(submission(bad), view, StateTime(20), limits()).recentError ==
      ReportAnchorError.InvalidRecentAnchor
  bad = declared
  bad.lookupStateRoot.bytes[0] = bad.lookupStateRoot.bytes[0] xor 1
  assert captureWorkAnchors(submission(bad), view, StateTime(20), limits()).ancestorError ==
      AncestorContextError.WrongLookupState
  var bounded = limits()
  bounded.ancestors.headers = ElementLimit(1)
  assert captureWorkAnchors(submission(older), view, StateTime(20), bounded).error ==
      WorkAnchorError.LimitExceeded
  bounded = limits()
  bounded.history.maxBytes = ByteLimit(1)
  assert captureWorkAnchors(original, view, StateTime(20), bounded).error ==
      WorkAnchorError.LimitExceeded
  let malformed = captured(20, first, suffix = true)
  assert captureWorkAnchors(original, genesisView(malformed), StateTime(20), limits()).error ==
      WorkAnchorError.InvalidSource
  let age = head.value.chainParameters.get(maxLookupAnchorAge)
  assert age < 1000000
  let expired = captureWorkAnchors(original, view, StateTime(uint32(21+age)), limits())
  assert expired.error == WorkAnchorError.RecentFailure
  assert expired.recentError == ReportAnchorError.LookupTooOld
  cycle(original, view)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(original, view)
  let after = getOccupiedMem()
  assert before == after, "work anchor contexts release original source and scratch owners"
  recordArcRelease("jamnp_work_anchors", 1000, before, after)
  echo "JAMNP-S source-bound work anchors passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
main()

proc populationBoundaries() =
  ## Genuine anchor state permits each population only when a following slot lies in its epoch.
  for slot in [12'u32, 13'u32, 23'u32]:
    let head = captured(slot, cores = 3, active = 6, pending = 9)
    assert head.error == GenesisError.None, "population boundary 4"
    let header = submission(context(head.value))
    let view = genesisView(head)
    let qualified = captureWorkAnchors(header, view, StateTime(slot), limits(3))
    assert qualified.error == WorkAnchorError.None, "population boundary 8"
    let captured = captureWorkPopulation(qualified.value, header, view, topologyLimits(3))
    assert captured.error == WorkPopulationError.None, "population boundary 10"
    let window = captured.value
    assert uint32(window.firstSlot) == slot+1 and uint32(window.lastSlot) == slot+11, "population boundary 12"
    assert window.accepts(ErasureShards(6)) == (slot != 23), "population boundary 13"
    assert window.accepts(ErasureShards(9)) == (slot != 12), "population boundary 14"
    assert not window.accepts(ErasureShards(12)), "population boundary 15"
    assert not default(WorkShardWindow).accepts(ErasureShards(6)), "population boundary 16"
    # GP active cores scale with the selected population, independently from configured capacity and current duty.
    assert not window.accepts(ErasureShards(6), CoreIndex(2))
    assert window.accepts(ErasureShards(6), CoreIndex(1)) == (slot != 23)
    assert window.accepts(ErasureShards(9), CoreIndex(2)) == (slot != 12)
    assert not default(WorkShardWindow).accepts(ErasureShards(6), CoreIndex(0))
    let other = submission(context(head.value))
    let wrong = captureWorkPopulation(qualified.value, other, view, topologyLimits(3))
    assert wrong.error == WorkPopulationError.InvalidSource, "population boundary 19"
    let defaults = captureWorkPopulation(default(AnchoredWorkContext), header, view, topologyLimits(3))
    assert defaults.error == WorkPopulationError.InvalidSource, "population boundary 21"
  let edge = captured(high(uint32)-1)
  assert edge.error == GenesisError.None, "population boundary 23"
  let header = submission(context(edge.value))
  let view = genesisView(edge)
  let qualified = captureWorkAnchors(header, view, StateTime(high(uint32)-1), limits())
  assert qualified.error == WorkAnchorError.None, "population boundary 27"
  let overflow = captureWorkPopulation(qualified.value, header, view, topologyLimits(2))
  assert overflow.error == WorkPopulationError.InvalidSlot, "population boundary 29"
  for slot in [12'u32, 23'u32]:
    # A window wholly before the boundary needs no C4; a next-epoch window must refuse its actual absence.
    let missing = captured(slot, omitPending = true)
    assert missing.error == GenesisError.None, "population boundary 33"
    let view = genesisView(missing)
    let header = submission(context(missing.value))
    let qualified = captureWorkAnchors(header, view, StateTime(slot), limits())
    assert qualified.error == WorkAnchorError.None, "population boundary 37"
    let checked = captureWorkPopulation(qualified.value, header, view, topologyLimits(2))
    if slot == 12:
      assert checked.error == WorkPopulationError.None, "population boundary 40"
      assert checked.value.accepts(ErasureShards(6)), "population boundary 41"
    else:
      assert checked.error == WorkPopulationError.StateFailure, "population boundary 43"
      assert checked.stateError == StateStoreError.MissingKey, "population boundary 44"
      assert uint8(checked.chapter) == 4, "population boundary 45"
  let malformed = captured(23, pendingSuffix = true)
  assert malformed.error == GenesisError.None, "population boundary 47"
  let malformedView = genesisView(malformed)
  let malformedHeader = submission(context(malformed.value))
  let malformedContext = captureWorkAnchors(malformedHeader, malformedView, StateTime(23), limits())
  assert malformedContext.error == WorkAnchorError.None, "population boundary 51"
  let refused = captureWorkPopulation(malformedContext.value, malformedHeader, malformedView,
    topologyLimits(2))
  assert refused.error == WorkPopulationError.InvalidState, "population boundary 54"
  assert uint8(refused.chapter) == 4, "population boundary 55"
  var small = topologyLimits(2)
  small.maxBytes = ByteLimit(0)
  let bounded = captureWorkPopulation(malformedContext.value, malformedHeader, malformedView, small)
  assert bounded.error == WorkPopulationError.LimitExceeded, "population boundary 59"
  let farther = captured(19, duration = 10)
  assert farther.error == GenesisError.None, "population boundary 61"
  let fartherView = genesisView(farther)
  let fartherHeader = submission(context(farther.value))
  let fartherContext = captureWorkAnchors(fartherHeader, fartherView, StateTime(19), limits())
  assert fartherContext.error == WorkAnchorError.None, "population boundary 65"
  let unknown = captureWorkPopulation(fartherContext.value, fartherHeader, fartherView,
    topologyLimits(2, 10))
  assert unknown.error == WorkPopulationError.UncertainWindow, "population boundary 68"
populationBoundaries()
