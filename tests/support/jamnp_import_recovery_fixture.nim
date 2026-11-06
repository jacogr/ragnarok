# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine erasure sources plus structural selected-chain registration snapshots isolate catalog and recovery provenance.
import std/assertions
import ../../src/chain/[genesis, provider, import_catalog]
import ../../src/codec/[bounded, header, guarantees, report_owned, owned, assurances]
import ../../src/codec/state/[safrole, availability, layout, trie]
from ../../src/state/erasure/words import FieldProductLimit
import ../../src/state/store
import ../../src/state/computed/report
import ../../src/state/availability/specifier
import ../../src/jamnp-s/import_recovery
import ./[jamnp_topology_fixture, pvm_import_justification]

proc importCatalogLimits*(): ImportCatalogLimits =
  ## Explicit local metadata and retention ceilings cover current/previous rosters across the selected bounded chain.
  ImportCatalogLimits(blocks: ElementLimit(8), reports: ElementLimit(16), keys: ElementLimit(20000),
    chapterBytes: ByteLimit(1000000), readBytes: ByteLimit(8000000), retentionEpochs: ElementLimit(672))
proc importRecoveryLimits*(): ImportRecoveryLimits =
  ## Independent aggregate arithmetic/hash/payload caps admit parity recovery and the complete two-level page witness.
  ImportRecoveryLimits(bytes: ByteLimit(2000000), products: FieldProductLimit(20000000),
    hashes: ElementLimit(100), hashBytes: ByteLimit(20000), proof: importLimits())
proc registrationSnapshot*(source: AvailabilityCommitment, slot = 20'u32,
    parent = unavailableGenesis(), active = 6, previous = 9, registered = 20'u32,
    badSuffix = false, highCredentials = true, generation = 1): BlockSnapshotResult =
  ## A report is structurally retained on the selected chain; its original execution/erasure provenance comes from the genuine source.
  let cores = if active > 9 or previous > 9: 341 else: 3
  let base = topologyCaptured([topologyRecords(generation-1, min(previous, 9)), topologyRecords(
      generation, min(active, 9)),
    topologyRecords(generation+1, min(active, 9))], cores = cores, atSlot = slot,
        parent = parent).value
  let bytes = prepareComputedReport(source, ByteLimit(20000)).value.computedReportBytes.value
  let report = decodeOwnedReport(bytes, uint64(cores)).value
  let core = int(uint64(report.ownedReportInfo.value.core))
  var guarantee = Guarantee(report: report, slot: GuaranteeSlot(registered), credentialCount: 2)
  guarantee.credentials[0].validator = GuarantorIndex(if highCredentials: max(active,
      previous)-2 else: 0)
  guarantee.credentials[1].validator = GuarantorIndex(if highCredentials: max(active,
      previous)-1 else: 1)
  var assignments = newSeq[AvailabilityAssignment](cores)
  assignments[core] = presentAssignment(guarantee, AssignmentSlot(registered))
  let config = AvailabilityConfig(guarantee: GuaranteeConfig(cores: CoreCount(cores),
    validators: ValidatorCount(max(active, previous)), maxBytes: ByteLimit(1000000)),
    maxPresent: ElementLimit(341), maxBytes: ByteLimit(1000000))
  let chapter = availabilityStateEntry(assignments, config).value
  var wire = chapter.value
  if badSuffix: wire.add(0) # A malformed final chapter must refuse even after an earlier valid registration source.
  let rosterPolicy = ValidatorStateConfig(cores: CoreCount(cores), validators: ElementLimit(1023),
      maxBytes: ByteLimit(1000000))
  let current = validatorEntry(ValidatorChapter.Active, topologyRecords(generation, active),
      rosterPolicy).value
  let prior = validatorEntry(ValidatorChapter.Previous, topologyRecords(generation-1, previous),
      rosterPolicy).value
  var entries: seq[StateEntry] = @[]
  for index in 0..<base.keyCount:
    # The topology snapshot has exact creation ceilings; capture a new complete map rather than extending a zero-spare-capacity fork.
    let key = base.keyAt(StateKeyIndex(index))
    let octets = array[31, byte](key)
    if octets == array[31, byte](current.key): continue # Replace the full active roster with the requested population.
    if octets == array[31, byte](prior.key): continue # Previous credentials retain their independent full population.
    entries.add(StateEntry(key: key, value: base.lookup(key).value.bytes))
  entries.add(current)
  entries.add(prior)
  entries.add(StateEntry(key: chapter.key, value: wire))
  var header = newSeq[byte](base.header.headerInfo.value.consumed)
  assert base.header.encodeOwnedHeader(header).error == HeaderError.None, "registration header encoding"
  captureBlockSnapshot(header, entries, base.chainParameters)
proc catalogSource*(availability: AvailabilityCommitment): ReportedImport =
  ## Only a selected-chain capture, never a caller-built descriptor, can supply the recovery capability under test.
  let count = int(uint16(availability.availabilityInfo.value.specifier.erasureShards))
  let saved = registrationSnapshot(availability, active = count, previous = count)
  assert saved.error == GenesisError.None
  let catalog = captureImportCatalog(genesisView(saved), importCatalogLimits())
  assert catalog.error == ImportCatalogError.None, "catalog fixture " & $catalog.error
  let selected = catalog.value.catalogImport(availability.availabilityInfo.value.specifier.segmentRoot)
  assert selected.error == ImportCatalogError.None
  selected.value
