# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_import_recovery_arc_release"}

## Selected original rosters, paired parity reconstruction and hostile proof pages exercise source-bound CE139/140 recovery.
import std/[assertions, syncio, rawthreads]
import ../../../src/chain/[genesis, provider, import_catalog]
import ../../../src/jamnp-s/import_recovery
import ../../../src/state/availability/specifier
import ../../../src/state/erasure/[layout, words]
import "../../../src/state/export/erasure" as export_erasure
import "../../../src/state/import/justification" as import_proof
import ../../../src/codec/[bounded, natural]
import ../../../src/codec/state/[safrole, layout as state_layout]
from ../../../src/codec/work/package import ImportIndex
from ../../../src/codec/work/report import SegmentRoot
import ../../../src/state/store
import ../../support/[pvm_computed_report, jamnp_import_recovery_fixture, jamnp_topology_fixture, arc_evidence]

type ChunkPair = object ## Caller-owned raw row buffers carry no verification or report authority.
  segment, page: seq[byte]
proc chunks(source: AvailabilityCommitment, index: int,
    indices: openArray[ErasureShardIndex]): ChunkPair =
  ## Genuine original erasure rows contain both the requested export and its distinct combined proof-page row.
  let exports = source.availabilitySource.value
  let info = exports.exportErasureInfo.value
  result = default(ChunkPair)
  for shard in indices:
    for octet in exports.exportErasureChunk(shard, ExportErasureIndex(
        index)).value: result.segment.add(octet)
    for octet in exports.exportErasureChunk(shard, ExportErasureIndex(uint64(uint16(
        info.exports))+uint64(index div 64))).value:
      result.page.add(octet)
proc checkSource(source: AvailabilityCommitment, index: int, indices: openArray[
    ErasureShardIndex]) =
  ## Pair recovery must reproduce a genuine normalized original export and authenticate its independently retained root.
  let data = chunks(source, index, indices)
  let recovered = recoverImport(catalogSource(source), ImportIndex(uint16(index)), data.segment,
    data.page, indices, importRecoveryLimits())
  assert recovered.error == ImportRecoveryError.None, "recover import " & $recovered.error
  assert recovered.value.verifiedImportInfo.value.root.bytes ==
      source.availabilityInfo.value.specifier.segmentRoot.bytes
  assert uint16(recovered.value.verifiedImportInfo.value.index) == uint16(index), "recovered original ordinal"
proc catalogChecks(source: AvailabilityCommitment) =
  ## Retained registration snapshots bind old assurers across a real population/credential-domain change.
  let first = registrationSnapshot(source)
  assert first.error == GenesisError.None, "registration snapshot"
  let child = registrationSnapshot(source, slot = 21, parent = first, active = 9, previous = 6,
      generation = 2)
  assert child.error == GenesisError.None, "new epoch child snapshot"
  let view = genesisView(first).advanceView(child).value
  let captured = captureImportCatalog(view, importCatalogLimits())
  assert captured.error == ImportCatalogError.None, "original roster capture " & $captured.error
  let spec = source.availabilityInfo.value.specifier
  let selected = captured.value.catalogPackageImport(spec.packageHash, spec.segmentRoot).value
  assert selected.reportedImportInfo.value.registered == 20, "original registration slot"
  for index in 0..<6:
    # Core1 rotates the original six-member threshold assignment by three, independently of the new nine-member head roster.
    let assurer = selected.importAssurer(StateValidatorIndex(index)).value
    assert array[32, byte](assurer.identity) == array[32, byte](topologyKey(60+index)), "original assurer identity"
    assert uint64(assurer.shard) == uint64((3+index) mod 6), "pinned core shard rotation"
  assert selected.importAssurer(StateValidatorIndex(6)).error == ImportCatalogError.InvalidIndex, "exclusive original roster index"
  assert captureImportCatalog(genesisView(child), importCatalogLimits()).value.catalogImport(
      spec.segmentRoot).error == ImportCatalogError.Missing
  var wrongPackage = spec.packageHash
  wrongPackage.bytes[0] = wrongPackage.bytes[0] xor 1
  assert captured.value.catalogPackageImport(wrongPackage, spec.segmentRoot).error ==
      ImportCatalogError.Missing
  let wrongPopulation = registrationSnapshot(source, active = 9, previous = 6)
  assert captureImportCatalog(genesisView(wrongPopulation), importCatalogLimits()).error ==
      ImportCatalogError.InvalidSource
  var cap = importCatalogLimits()
  cap.blocks = ElementLimit(1)
  assert captureImportCatalog(view, cap).error == ImportCatalogError.LimitExceeded, "retained block ceiling"
  cap = importCatalogLimits()
  cap.keys = ElementLimit(29)
  assert captureImportCatalog(view, cap).error == ImportCatalogError.LimitExceeded, "aggregate roster key ceiling"
  cap.keys = ElementLimit(30)
  cap.reports = ElementLimit(2)
  assert captureImportCatalog(view, cap).error == ImportCatalogError.None, "exact aggregate report/key caps"
  cap.reports = ElementLimit(1)
  assert captureImportCatalog(view, cap).error == ImportCatalogError.LimitExceeded, "aggregate decoded report cap"
  cap = importCatalogLimits()
  var bytes = 0'u64
  for index in 0..<view.retainedCount:
    let state = view.retainedBlockAt(RetainedBlockIndex(index)).value.stateSnapshot
    for chapter in [StateChapter(10), StateChapter(8), StateChapter(9)]:
      bytes += uint64(state.lookup(chapterKey(chapter)).value.byteLength)
  cap.readBytes = ByteLimit(bytes)
  assert captureImportCatalog(view, cap).error == ImportCatalogError.None, "exact complete chapter bytes"
  cap.readBytes = ByteLimit(bytes-1)
  assert captureImportCatalog(view, cap).error == ImportCatalogError.LimitExceeded, "aggregate chapter byte ceiling"
  let malformed = registrationSnapshot(source, slot = 21, parent = first, badSuffix = true)
  assert malformed.error == GenesisError.None, "malformed late snapshot capture"
  assert captureImportCatalog(genesisView(first).advanceView(malformed).value,
    importCatalogLimits()).error == ImportCatalogError.InvalidSource
  let expired = registrationSnapshot(source, slot = 8084, parent = first)
  let old = genesisView(first).advanceView(expired).value
  assert captureImportCatalog(old, importCatalogLimits()).value.catalogImport(
      spec.segmentRoot).error == ImportCatalogError.Missing
  cap = importCatalogLimits()
  cap.retentionEpochs = ElementLimit(673)
  assert captureImportCatalog(old, cap).value.catalogImport(spec.segmentRoot).error ==
      ImportCatalogError.None
  cap.retentionEpochs = ElementLimit(671)
  assert captureImportCatalog(old, cap).error == ImportCatalogError.InvalidPolicy, "minimum retention policy"
type StackContext = object ## The host freezes every selected graph and raw buffer alias until the exact bounded thread joins.
  view: ChainView
  data: ChunkPair
  indices: seq[ErasureShardIndex]
  root: SegmentRoot
  passed: bool
proc boundedRecovery(context: pointer) =
  ## Maximum-population catalog capture and paired parity reconstruction must fit the real managed-worker stack ceiling.
  let selected = cast[ptr StackContext](context)
  let catalog = captureImportCatalog(selected.view, importCatalogLimits())
  assert catalog.error == ImportCatalogError.None, "bounded stack catalog"
  let source = catalog.value.catalogImport(selected.root)
  assert source.error == ImportCatalogError.None, "bounded stack source"
  let recovered = recoverImport(source.value, ImportIndex(0), selected.data.segment,
    selected.data.page, selected.indices, importRecoveryLimits())
  assert recovered.error == ImportRecoveryError.None, "bounded stack recovery"
  selected.passed = true
proc checkStack(source: AvailabilityCommitment, indices: seq[ErasureShardIndex]) {.raises.} =
  ## No host-side ARC operation or observation of the shared context overlaps its private CPU borrow.
  let saved = registrationSnapshot(source, active = 1023, previous = 1023)
  assert saved.error == GenesisError.None
  var context = StackContext(view: genesisView(saved), data: chunks(source, 0, indices),
    indices: indices, root: source.availabilityInfo.value.specifier.segmentRoot, passed: false)
  var thread = default(RawThread)
  thread.create(boundedRecovery, addr context, stackSize = 524288)
  thread.join()
  assert context.passed, "bounded recovery stack joined"
proc cycle(source: ReportedImport, data: ChunkPair, indices: seq[ErasureShardIndex]) =
  ## Complete verified imports and late corrupted proof pages release every reconstructed buffer and selected source alias.
  assert recoverImport(source, ImportIndex(0), data.segment, data.page, indices,
      importRecoveryLimits()).error == ImportRecoveryError.None
  var changed = data.page
  changed[0] = changed[0] xor 1
  let failed = recoverImport(source, ImportIndex(0), data.segment, changed, indices,
      importRecoveryLimits())
  assert failed.error != ImportRecoveryError.None

let original = computedAvailabilityAtCore(3, 1)
catalogChecks(original)
for values in [[0'u64, 1, 2], [3'u64, 4, 5], [5'u64, 0, 4], [2'u64, 1, 0]]:
  let indices = @[ErasureShardIndex(values[0]), ErasureShardIndex(values[1]), ErasureShardIndex(
      values[2])]
  for index in 0..<3: checkSource(original, index, indices)
let boundary = computedAvailabilityAtCore(65, 1)
let indices = @[ErasureShardIndex(3), ErasureShardIndex(4), ErasureShardIndex(5)]
for index in [0, 63, 64]: checkSource(boundary, index, indices)
let large = computedAvailabilityAtCore(1, 1, 1023)
var many = newSeq[ErasureShardIndex](342)
for index in 0..<many.len: many[index] = ErasureShardIndex(681+index)
checkSource(large, 0, many)
try:
  checkStack(large, many)
except:
  quit 2 # Failure to create/join the exact bounded worker cannot substitute for the completed recovery witness.

let selected = catalogSource(original)
let data = chunks(original, 0, indices)
assert recoverImport(default(ReportedImport), ImportIndex(0), data.segment, data.page, indices,
  importRecoveryLimits()).error == ImportRecoveryError.InvalidSource
assert recoverImport(selected, ImportIndex(3), data.segment, data.page, indices,
  importRecoveryLimits()).error == ImportRecoveryError.InvalidIndex
assert recoverImport(selected, ImportIndex(0), data.segment.toOpenArray(0, data.segment.high-1), data.page,
  indices, importRecoveryLimits()).error == ImportRecoveryError.InvalidPayload
let duplicate = @[ErasureShardIndex(3), ErasureShardIndex(3), ErasureShardIndex(5)]
assert recoverImport(selected, ImportIndex(0), data.segment, data.page, duplicate,
  importRecoveryLimits()).recoveryError == ErasureWordError.InvalidIndex
var cap = importRecoveryLimits()
cap.hashes = ElementLimit(6)
assert recoverImport(selected, ImportIndex(0), data.segment, data.page, indices, cap).error ==
    ImportRecoveryError.LimitExceeded
cap.hashes = ElementLimit(7)
cap.hashBytes = ByteLimit(8555)
assert recoverImport(selected, ImportIndex(0), data.segment, data.page, indices, cap).error ==
    ImportRecoveryError.LimitExceeded
cap.hashBytes = ByteLimit(8556)
assert recoverImport(selected, ImportIndex(0), data.segment, data.page, indices, cap).error ==
    ImportRecoveryError.None
cap = importRecoveryLimits()
cap.products = FieldProductLimit(0)
assert recoverImport(selected, ImportIndex(0), data.segment, data.page, indices,
    cap).recoveryError == ErasureWordError.LimitExceeded
cap = importRecoveryLimits()
cap.bytes = ByteLimit(0)
assert recoverImport(selected, ImportIndex(0), data.segment, data.page, indices, cap).error ==
    ImportRecoveryError.LimitExceeded
cap = importRecoveryLimits()
cap.proof.siblings = ElementLimit(0)
assert recoverImport(selected, ImportIndex(0), data.segment, data.page, indices, cap).error ==
    ImportRecoveryError.LimitExceeded
cycle(selected, data, indices)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(selected, data, indices)
let after = getOccupiedMem()
assert before == after, "import recovery ARC release"
recordArcRelease("jamnp_import_recovery", 1000, before, after)
echo "JAMNP-S source-bound import recovery passed"
echo "ARC_RELEASE cycles=1000 unchanged"
