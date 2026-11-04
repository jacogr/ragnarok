# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_work_anchors_arc_release"}

## Complete captured maps and real sealed parent links qualify contexts without fabricating authorizations or signatures.
import std/[assertions, syncio]
import ../../../src/jamnp-s/[work_submission, work_anchors]
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/[bounded, header, composite, assurances]
import ../../../src/codec/state/[history, layout, trie, safrole]
import ../../../src/codec/work/[package, digest, report]
import ../../../src/state/ancestor_context
import ../../../src/state/report/anchors
import ../../support/[jamnp_topology_fixture, arc_evidence]

proc limits(): WorkAnchorLimits =
  ## The two-core structural source uses explicit independent decode/header work budgets.
  WorkAnchorLimits(history: HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8),
    perBlock: ElementLimit(2), totalPackages: ElementLimit(16), peaks: ElementLimit(64),
    maxBytes: ByteLimit(4096)), ancestors: AncestorContextLimits(header: HeaderConfig(
      cores: CoreCount(2), authorValidators: ValidatorCount(6), epochSlots: EpochSlots(12),
      maxBytes: ByteLimit(4096)), headers: ElementLimit(8), maxBytes: ByteLimit(32768)))
proc captured(slot: uint32, parent = unavailableGenesis(), suffix = false): BlockSnapshotResult =
  ## Preserve actual sealed ancestry while independently creating complete canonical-shaped recent history.
  let seed = topologyCaptured([topologyRecords(0, 6), topologyRecords(1, 6), topologyRecords(2, 6)],
    cores = 2, atSlot = slot, parent = parent)
  assert seed.error == GenesisError.None
  var records: seq[HistoryBlock] = @[]
  let peak = HistorySuperPeak([33'u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
  if parent.error == GenesisError.None:
    records.add(HistoryBlock(header: HistoryHeaderHash(array[32, byte](parent.value.blockHash)),
      state: HistoryStateRoot(array[32, byte](parent.value.stateRoot)), superPeak: peak,
      slot: HistorySlot(parent.value.slot)))
  records.add(HistoryBlock(header: HistoryHeaderHash(array[32, byte](seed.value.blockHash)),
    state: HistoryStateRoot(default(array[32, byte])), superPeak: peak, slot: HistorySlot(slot)))
  let recent = historyStateEntry(HistoryState(blocks: records), limits().history)
  assert recent.error == HistoryError.None
  var entries: seq[StateEntry] = @[]
  for index in 0..<seed.value.keyCount:
    # A fresh complete map preserves immutable source creation ceilings; no production state guard is weakened.
    let key = seed.value.keyAt(StateKeyIndex(index))
    entries.add(StateEntry(key: key, value: seed.value.lookup(key).value.bytes))
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
