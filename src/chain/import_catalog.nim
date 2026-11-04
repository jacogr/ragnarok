# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Source-bound availability descriptors retain the original registration roster for bounded import recovery.
## Capture only selected-chain C(10) registration snapshots; absent history never authorizes a guessed assurer set.
import ./[provider, genesis]
import ../codec/[bounded, guarantees, report_owned, owned, assurances, natural]
import ../codec/work/report as work_report
import ../codec/state/[layout, safrole, availability]
import ../state/store
import ../state/availability/specifier
import ../state/erasure/[layout as erasure_layout, words]

type
  ImportCatalogError* {.pure.} = enum ## Failed/default captures and lookups expose no partial catalog or substitute metadata.
    Uninitialized, None, InvalidSource, InvalidPolicy, LimitExceeded, Missing, InvalidIndex
  ImportCatalogLimits* = object ## Every selected snapshot, copied chapter, decoded report and roster key has an explicit aggregate ceiling.
    blocks*, reports*, keys*, retentionEpochs*: ElementLimit
    chapterBytes*, readBytes*: ByteLimit
  ImportCatalogResult*[T] = object ## Only complete selected success carries a source-bearing owner or detached metadata.
    case status: ImportCatalogError
    of None: completed: T
    else: discard # A reason alone cannot act as a report or roster certificate.
  ReportedImportInfo* = object ## Fixed copied report facts retain their original registration block and expiry context.
    specifier*: AvailabilitySpecifier
    core*: CoreIndex
    registered*: uint32
  ImportAssurer* = object ## Detached original roster identity and assigned shard never imply a current connection or current validator role.
    identity*: StateEdKey
    shard*: ErasureShardIndex
  ImportRecord = ref object ## One canonical report and original roster form immutable acyclic recovery provenance.
    info: ReportedImportInfo
    roster: ValidatorStateSnapshot
  ReportedImport* = object ## Only the selected-chain catalog can construct a report/roster capability for recovery.
    data: nil ImportRecord
  CatalogData = ref object ## Bounded immutable rows retain no mutable ChainView container or network-selected report.
    head: genesis.BlockHash
    rows: seq[ImportRecord]
  ImportCatalog* = object ## Defaults supply no independently trusted availability descriptor.
    data: nil CatalogData
func error*[T](outcome: ImportCatalogResult[T]): ImportCatalogError =
  ## Inspect a failure without permitting discriminator mutation.
  outcome.status
func value*[T](outcome: ImportCatalogResult[T]): T {.requires: outcome.status ==
    ImportCatalogError.None.} =
  ## Extract only a completely selected catalog, source or detached value.
  outcome.completed
func failure[T](reason: ImportCatalogError): ImportCatalogResult[T] {.requires: reason !=
    ImportCatalogError.None.} =
  ## Refusal retains no accepted prefix or inferred default source.
  ImportCatalogResult[T](status: reason)
proc reportedImportInfo*(source: ReportedImport): ImportCatalogResult[ReportedImportInfo] =
  ## Copy fixed report facts only while the caller owns canonical graph access.
  let data = source.data
  if data == nil: return failure[ReportedImportInfo](ImportCatalogError.Uninitialized)
  ImportCatalogResult[ReportedImportInfo](status: ImportCatalogError.None, completed: data.info)
proc importAssurer*(source: ReportedImport, index: StateValidatorIndex): ImportCatalogResult[
    ImportAssurer] =
  ## Apply pinned NP i=(cR+v) mod V to the original registration roster, even after that set retires.
  let data = source.data
  if data == nil: return failure[ImportAssurer](ImportCatalogError.Uninitialized)
  let count = uint64(uint16(data.info.specifier.erasureShards))
  if uint64(index) >= count: return failure[ImportAssurer](ImportCatalogError.InvalidIndex)
  let geometry = erasureGeometry(BundleLength(4104), data.info.specifier.erasureShards)
  if geometry.error != ErasureLayoutError.None: return failure[ImportAssurer](
      ImportCatalogError.InvalidSource)
  let ordinal = (uint64(data.info.core)*geometry.value.originalShards+uint64(index)) mod count
  let validator = data.roster.validatorAt(index)
  if validator.error != StateComponentError.None: return failure[ImportAssurer](
      ImportCatalogError.InvalidSource)
  ImportCatalogResult[ImportAssurer](status: ImportCatalogError.None,
    completed: ImportAssurer(identity: validator.value.ed25519, shard: ErasureShardIndex(ordinal)))
proc findImport(catalog: ImportCatalog, root: SegmentRoot, packageBound: bool,
    package: PackageHash): ImportCatalogResult[ReportedImport] =
  ## Deterministically choose an independently canonical source; identical exported content can legitimately have multiple source reports.
  let data = catalog.data
  if data == nil: return failure[ReportedImport](ImportCatalogError.Uninitialized)
  for index in 0..<data.rows.len:
    let row = data.rows[index]
    # Package references require that exact package identity, while direct roots may use any canonical report of the same content.
    if row.info.specifier.segmentRoot.bytes != root.bytes: continue
    if packageBound and row.info.specifier.packageHash.bytes != package.bytes: continue
    return ImportCatalogResult[ReportedImport](status: ImportCatalogError.None,
        completed: ReportedImport(data: row))
  failure[ReportedImport](ImportCatalogError.Missing)
proc catalogImport*(catalog: ImportCatalog, root: SegmentRoot): ImportCatalogResult[
    ReportedImport] =
  ## Direct-root references select the oldest retained non-expired original registration source with that exact export root.
  findImport(catalog, root, false, default(PackageHash))
proc catalogPackageImport*(catalog: ImportCatalog, package: PackageHash,
    root: SegmentRoot): ImportCatalogResult[ReportedImport] =
  ## Package-relative references cannot substitute another package that happens to export identical bytes.
  findImport(catalog, root, true, package)
proc catalogHead*(catalog: ImportCatalog): ImportCatalogResult[genesis.BlockHash] =
  ## Copy the selected-chain head identity without exporting its retained map or child owners.
  let data = catalog.data
  if data == nil: return failure[genesis.BlockHash](ImportCatalogError.Uninitialized)
  ImportCatalogResult[genesis.BlockHash](status: ImportCatalogError.None, completed: data.head)
proc captureImportCatalog*(view: ChainView, limits: ImportCatalogLimits): ImportCatalogResult[
    ImportCatalog] =
  ## Preflight all selected chapter bytes before any decoder allocation; read only complete registration-block snapshots.
  template fail(reason: ImportCatalogError) =
    return failure[ImportCatalog](reason)
  let head = view.bestBlock
  if head.error != GenesisError.None: fail(ImportCatalogError.InvalidSource)
  if uint64(limits.blocks) == 0 or uint64(limits.chapterBytes) == 0 or uint64(limits.readBytes) == 0:
    fail(ImportCatalogError.InvalidPolicy)
  if uint64(limits.retentionEpochs) < 672 or uint64(limits.retentionEpochs) > uint64(high(uint32)):
    fail(ImportCatalogError.InvalidPolicy)
  if uint64(view.retainedCount) > uint64(limits.blocks): fail(ImportCatalogError.LimitExceeded)
  var total = 0'u64
  for index in 0..<view.retainedCount:
    # Missing C(10) contributes no source; every present assignment chapter requires its exact active roster chapter.
    let selected = view.retainedBlockAt(RetainedBlockIndex(index)).value
    let state = selected.stateSnapshot
    let assignments = state.lookup(chapterKey(StateChapter(10)))
    if assignments.error == StateStoreError.MissingKey: continue
    if assignments.error != StateStoreError.None: fail(ImportCatalogError.InvalidSource)
    for chapter in [StateChapter(10), StateChapter(8), StateChapter(9)]:
      let entry = state.lookup(chapterKey(chapter))
      if entry.error != StateStoreError.None: fail(ImportCatalogError.InvalidSource)
      let length = uint64(entry.value.byteLength)
      if length > uint64(limits.chapterBytes): fail(ImportCatalogError.LimitExceeded)
      if length > uint64(limits.readBytes)-total: fail(ImportCatalogError.LimitExceeded)
      total += length
  var keys = 0'u64
  var reports = 0'u64
  for index in 0..<view.retainedCount:
    # Raw chapter copies were globally charged above; now charge every decoded roster/report before allocating any owner.
    let selected = view.retainedBlockAt(RetainedBlockIndex(index)).value
    let state = selected.stateSnapshot
    let assignments = state.lookup(chapterKey(StateChapter(10)))
    if assignments.error == StateStoreError.MissingKey: continue
    if assignments.error != StateStoreError.None: fail(ImportCatalogError.InvalidSource)
    var credentialCount = 0'u64
    for chapter in [StateChapter(8), StateChapter(9)]:
      # Previous-rotation credentials may exceed the current assurer population; validate both exact roster counts before C(10).
      let roster = state.lookup(chapterKey(chapter))
      if roster.error != StateStoreError.None: fail(ImportCatalogError.InvalidSource)
      let rosterWire = roster.value.bytes
      let population = decode(rosterWire)
      if not population.ok: fail(ImportCatalogError.InvalidSource)
      let count = uint64(population.value)
      if count > uint64(limits.keys)-keys: fail(ImportCatalogError.LimitExceeded)
      keys += count
      credentialCount = max(credentialCount, count)
      let profile = ValidatorStateConfig(cores: selected.cores, validators: ElementLimit(count),
          maxBytes: limits.chapterBytes)
      let size = stateValidatorPrefixSize(rosterWire, profile)
      if size.error == StateComponentError.LimitExceeded: fail(ImportCatalogError.LimitExceeded)
      if size.error != StateComponentError.None: fail(ImportCatalogError.InvalidSource)
      if size.value != rosterWire.len: fail(ImportCatalogError.InvalidSource)
    let wire = assignments.value.bytes
    let inspected = inspectAvailabilityState(wire, AvailabilityConfig(guarantee: GuaranteeConfig(
      cores: selected.cores, validators: ValidatorCount(credentialCount),
          maxBytes: limits.chapterBytes),
      maxPresent: ElementLimit(uint64(limits.reports)-reports), maxBytes: limits.chapterBytes))
    if inspected.error == AvailabilityError.LimitExceeded: fail(ImportCatalogError.LimitExceeded)
    if inspected.error != AvailabilityError.None: fail(ImportCatalogError.InvalidSource)
    if inspected.value.consumed != wire.len: fail(ImportCatalogError.InvalidSource)
    reports += uint64(inspected.value.present)
  var rows: seq[ImportRecord] = @[]
  for index in 0..<view.retainedCount:
    # The private view is immutable throughout this call; the prior pass charged all variable chapter copies.
    let selected = view.retainedBlockAt(RetainedBlockIndex(index)).value
    let state = selected.stateSnapshot
    let assignments = state.lookup(chapterKey(StateChapter(10)))
    if assignments.error == StateStoreError.MissingKey: continue
    if assignments.error != StateStoreError.None: fail(ImportCatalogError.InvalidSource)
    let roster = state.lookup(chapterKey(StateChapter(8)))
    if roster.error != StateStoreError.None: fail(ImportCatalogError.InvalidSource)
    let rosterWire = roster.value.bytes
    let populationPrefix = decode(rosterWire)
    if not populationPrefix.ok: fail(ImportCatalogError.InvalidSource)
    let count = uint64(populationPrefix.value)
    let validators = decodeStateValidators(rosterWire, ValidatorStateConfig(cores: selected.cores,
      validators: ElementLimit(count), maxBytes: limits.chapterBytes))
    if validators.error == StateComponentError.LimitExceeded: fail(ImportCatalogError.LimitExceeded)
    if validators.error != StateComponentError.None: fail(ImportCatalogError.InvalidSource)
    if validators.value.consumed != rosterWire.len: fail(ImportCatalogError.InvalidSource)
    let population = validators.value.value.validatorCount.value
    if uint64(population) != count: fail(ImportCatalogError.InvalidSource)
    let previous = state.lookup(chapterKey(StateChapter(9)))
    if previous.error != StateStoreError.None: fail(ImportCatalogError.InvalidSource)
    let previousPrefix = decode(previous.value.bytes)
    if not previousPrefix.ok: fail(ImportCatalogError.InvalidSource)
    let credentialCount = max(count, uint64(previousPrefix.value))
    let wire = assignments.value.bytes
    let decoded = decodeAvailabilityState(wire, AvailabilityConfig(guarantee: GuaranteeConfig(
      cores: selected.cores, validators: ValidatorCount(credentialCount),
          maxBytes: limits.chapterBytes),
      maxPresent: limits.reports,
          maxBytes: limits.chapterBytes))
    if decoded.error == AvailabilityError.LimitExceeded: fail(ImportCatalogError.LimitExceeded)
    if decoded.error != AvailabilityError.None: fail(ImportCatalogError.InvalidSource)
    if decoded.value.consumed != wire.len: fail(ImportCatalogError.InvalidSource)
    for core in 0..<int(uint64(selected.cores)):
      # A later copy of an assignment cannot relabel its original assurer epoch; only its registration block supplies the roster.
      let assignment = decoded.value.snapshot.availabilityAt(AssignmentCoreIndex(core)).value
      if not assignment.present: continue
      if uint32(assignment.registered) != selected.slot: continue
      let report = assignment.guarantee.report.ownedReportInfo
      if report.error != OwnershipError.None: fail(ImportCatalogError.InvalidSource)
      let facts = report.value
      if uint64(facts.core) != uint64(core) or uint16(facts.header.erasureShards) != uint16(population):
        fail(ImportCatalogError.InvalidSource)
      if uint32(facts.header.bundleLength) == 0 or uint32(facts.header.bundleLength) > 13904950:
        fail(ImportCatalogError.InvalidSource)
      if selected.slot > head.value.slot: fail(ImportCatalogError.InvalidSource)
      let geometry = erasureGeometry(facts.header.bundleLength, facts.header.erasureShards)
      if geometry.error != ErasureLayoutError.None: fail(ImportCatalogError.InvalidSource)
      if uint16(facts.header.segmentCount) > 3072: fail(ImportCatalogError.InvalidSource)
      let epoch = uint64(selected.epochSlots)
      if epoch == 0 or epoch > uint64(high(uint32)): fail(ImportCatalogError.InvalidSource)
      let expires = uint64(selected.slot)+uint64(limits.retentionEpochs)*epoch
      if uint64(head.value.slot) >= expires: continue # Explicit local retention meets the GP minimum; both multiplicands are E4-bounded before addition.
      if uint64(rows.len) >= uint64(limits.reports): fail(ImportCatalogError.LimitExceeded)
      let specifier = AvailabilitySpecifier(packageHash: facts.header.packageHash,
        bundleLength: facts.header.bundleLength, erasureRoot: facts.header.erasureRoot,
        erasureShards: facts.header.erasureShards, segmentRoot: facts.header.segmentRoot,
        segmentCount: facts.header.segmentCount)
      rows.add(ImportRecord(info: ReportedImportInfo(specifier: specifier,
        core: facts.core, registered: selected.slot), roster: validators.value.value))
  ImportCatalogResult[ImportCatalog](status: ImportCatalogError.None,
    completed: ImportCatalog(data: CatalogData(head: head.value.blockHash, rows: rows)))
