# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine original exports become builder imports and independently selected canonical availability descriptors.

import std/assertions
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, composite, header, guarantees, report_owned, owned, assurances]
import ../../src/codec/work/[package as work_package, report as work_report]
import ../../src/codec/state/[layout, trie, safrole, history, availability]
import ../../src/state/[store, extrinsic_inputs]
import "../../src/state/import/inputs" as import_inputs
import "../../src/state/import/justification" as import_proof
import "../../src/state/export/commitment" as export_commitment
import "../../src/state/export/erasure" as export_erasure
import ../../src/state/availability/specifier
import ../../src/state/computed/report
import ../../src/pvm/host/fetch
import ../../src/jamnp-s/[work_submission, work_recovery, availability_proof]
import ../../src/state/erasure/words
import ./[jamnp_work_fixture, pvm_computed_report, pvm_input_refinement,
  pvm_import_inputs, pvm_import_justification, jamnp_import_recovery_fixture, jamnp_topology_fixture]

type WorkRecoveryFixture* = object ## Source bytes, canonical state and typed builder inputs keep independent ownership.
  work*: WorkFixture
  available*: AvailabilityCommitment
  snapshot*: BlockSnapshot

proc recoveryPolicy*(): WorkRecoveryPolicy =
  ## Explicit whole-session reservations cover both imports, both trust rounds and all declared packet checks.
  workRecoveryPolicy(WorkRecoveryLimits(catalog: importCatalogLimits(), pair: importRecoveryLimits(),
    transfer: AvailabilityMerkleLimits(bytes: ByteLimit(1000000), hashes: ElementLimit(1000),
        hashBytes: ByteLimit(1000000)),
    items: ElementLimit(2), requests: ElementLimit(64), dials: ElementLimit(16),
        hashes: ElementLimit(1000000), peersPerPoll: ElementLimit(6),
    bytes: ByteLimit(16000000), hashBytes: ByteLimit(1000000000), products: FieldProductLimit(
        1000000000),
    replyBytes: ByteLimit(8192), timeoutMs: 1000))

proc workRecoveryFixture*(local, peer: StateEdKey, invalidRoot = false): WorkRecoveryFixture =
  ## Actual authorization/refinement and erasure coding supply every imported byte; no fabricated proof or success bit enters the fixture.
  result = default(WorkRecoveryFixture)
  result.available = computedAvailabilityAtCore(3, 0)
  let specifier = result.available.availabilityInfo.value.specifier
  var root = specifier.segmentRoot
  if invalidRoot: root.bytes[0] = root.bytes[0] xor 1 # A structurally reported invalid commitment must fail even after authenticating every erasure piece.
  result.work = workFixture()
  let old = result.work.input.package
  let described = old.workPackageInfo.value
  var package = WorkPackage(host: described.host, codeHash: described.codeHash,
    context: described.context,
    authorization: newSeq[byte](described.authorizationBytes), configuration: newSeq[byte](
        described.configurationBytes))
  assert old.copyPackageBlob(PackageBlob.Authorization, package.authorization).error ==
      PackageError.None
  assert old.copyPackageBlob(PackageBlob.Configuration, package.configuration).error ==
      PackageError.None
  var extrinsics: seq[seq[seq[byte]]] = @[]
  var proofs: seq[seq[VerifiedImport]] = @[]
  let originalExtrinsics = result.work.input.inputs.importInputsExtrinsics.value
  let commitment = result.available.availabilitySource.value.exportErasureCommitment.value
  result.work.segments = @[]
  result.work.proofs = @[]
  for item in 0..<described.items:
    # Copy all original manifests and payloads, replacing only the intended independent import source identities.
    let original = old.workItemAt(item).value
    let info = original.workItemInfo.value
    var copied = WorkItem(service: info.service, codeHash: info.codeHash, refineGas: info.refineGas,
      accumulateGas: info.accumulateGas, exports: info.exports, payload: newSeq[byte](
          info.payloadBytes))
    assert original.copyItemPayload(copied.payload).error == PackageError.None
    var row: seq[seq[byte]] = @[]
    for index in 0..<info.extrinsics:
      copied.extrinsics.add(original.extrinsicAt(index).value)
      row.add(originalExtrinsics.extrinsicInput(FetchItemIndex(item), ExtrinsicInputIndex(index)).value)
    extrinsics.add(row)
    var imported: seq[VerifiedImport] = @[]
    for index in 0..<info.imports:
      let reference = original.importAt(index).value
      if reference.kind == ImportKind.Root: copied.imports.add(rootImport(root, reference.index))
      else: copied.imports.add(packageImport(specifier.packageHash, reference.index))
      let selected = ExportSegmentIndex(uint16(reference.index))
      let segment = commitment.commitmentSegment(selected).value
      let path = commitment.commitmentPath(selected).value
      let verified = verifyImportSegment(specifier.segmentRoot, reference.index, segment, path,
          importLimits()).value
      imported.add(verified)
      for octet in array[4104, byte](segment): result.work.segments.add(octet)
      for octet in verified.verifiedImportProof.value: result.work.proofs.add(octet)
    package.items.add(copied)
    proofs.add(imported)
  var wire = newSeq[byte](204800)
  let config = fullPackageConfig(ByteLimit(204800))
  let encoded = encodeWorkPackage(package, config, wire)
  assert encoded.error == PackageError.None
  result.work.package = newSeq[byte](encoded.value)
  for index in 0..<encoded.value: result.work.package[index] = wire[index]
  result.work.input.package = decodeWorkPackage(result.work.package, config).value.owner
  if not invalidRoot:
    # Keep the positive typed fixture coherent after all original package commitments have been replaced.
    let verified = verifyExtrinsicInputs(result.work.input.package, extrinsics,
        result.work.limits.extrinsics).value
    result.work.input.inputs = bindImportInputs(verified, proofs, [SegmentLookup(
      packageHash: specifier.packageHash,
      segmentRoot: root)], result.work.limits.imports).value
  result.work.first = @[0'u8, 0, 1]
  for octet in specifier.packageHash.bytes: result.work.first.add(octet)
  for octet in root.bytes: result.work.first.add(octet)
  let recent = historyStateEntry(HistoryState(blocks: @[HistoryBlock(slot: HistorySlot(20),
      packages: @[
    ReportedPackage(package: specifier.packageHash, segment: root)])]),
        result.work.limits.history).value
  var state = forkStateStore(result.work.input.state).value
  assert state.apply([StateWrite(kind: StateWriteKind.Put, key: recent.key,
      value: recent.value)]).error == StateStoreError.None
  result.work.input.state = state.snapshot.value
  let base = result.work.workSnapshot(local, peer)
  var validators = topologyRecords(0, 6)
  for index in 0..<validators.len: validators[index].ed25519 = peer
  validators[1].ed25519 = local # The independent existing zero-entropy duty fixture keeps the local guarantor on core0 at slot20.
  let rosterPolicy = ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
      maxBytes: ByteLimit(10000))
  let active = validatorEntry(ValidatorChapter.Active, validators, rosterPolicy).value
  let previous = validatorEntry(ValidatorChapter.Previous, validators, rosterPolicy).value
  var reportBytes = prepareComputedReport(result.available, ByteLimit(
      20000)).value.computedReportBytes.value
  if invalidRoot:
    # Literal fixed header widths: package32, bundle4, erasure32, shards2, then segment root32.
    reportBytes[70] = reportBytes[70] xor 1
  let report = decodeOwnedReport(reportBytes, 2).value
  var guarantee = Guarantee(report: report, slot: GuaranteeSlot(20), credentialCount: 2)
  guarantee.credentials[1].validator = GuarantorIndex(2)
  let assignment = availabilityStateEntry([presentAssignment(guarantee, AssignmentSlot(20)),
      absentAssignment()],
    AvailabilityConfig(guarantee: GuaranteeConfig(cores: CoreCount(2), validators: ValidatorCount(
        6), maxBytes: ByteLimit(10000)),
      maxPresent: ElementLimit(2), maxBytes: ByteLimit(10000))).value
  var entries: seq[StateEntry] = @[]
  for index in 0..<base.keyCount:
    let key = base.keyAt(StateKeyIndex(index))
    let octets = array[31, byte](key)
    if octets == array[31, byte](active.key): continue
    if octets == array[31, byte](previous.key): continue
    entries.add(StateEntry(key: key, value: base.lookup(key).value.bytes))
  entries.add(active)
  entries.add(previous)
  entries.add(assignment)
  var header = newSeq[byte](base.header.headerInfo.value.consumed)
  assert base.header.encodeOwnedHeader(header).error == HeaderError.None
  let captured = captureBlockSnapshot(header, entries, result.work.input.parameters)
  assert captured.error == GenesisError.None, "canonical work recovery fixture"
  result.snapshot = captured.value

proc recoveryHeader*(fixture: WorkRecoveryFixture): WorkSubmissionHeader =
  ## Independent CE133 framing binds the final original package before actual authorizer execution.
  var first = @[0'u8, 0]
  for octet in fixture.work.package: first.add(octet)
  decodeWorkSubmission(WorkSubmissionKind.Package, first, [], fullPackageConfig(ByteLimit(204800))).value

proc recoveryFrame*(payload: openArray[byte]): seq[byte] =
  ## Literal E4 framing independently checks the production request/reply boundaries.
  result = @[]
  for index in 0..<4: result.add(byte((uint32(payload.len) shr (index*8)) and 255))
  for octet in payload: result.add(octet)

proc recoveryWire*(fixture: WorkRecoveryFixture): seq[byte] =
  ## Builder input contains the original package and exact committed extrinsic bytes only.
  var header = @[0'u8, 0]
  for octet in fixture.work.package: header.add(octet)
  result = @[133'u8]
  for octet in recoveryFrame(header): result.add(octet)
  for octet in recoveryFrame(fixture.work.extrinsics): result.add(octet)

proc shardRequestWire*(fixture: WorkRecoveryFixture, item, shard: int, proven: bool): seq[byte] =
  ## Independent singleton group requests exactly one export and its distinct combined proof-page row.
  let specifier = fixture.available.availabilityInfo.value.specifier
  var payload: seq[byte] = @[]
  for octet in specifier.erasureRoot.bytes: payload.add(octet)
  payload.add(byte(shard))
  payload.add(0)
  payload.add(2)
  payload.add(byte(item))
  payload.add(0)
  payload.add(byte(uint16(specifier.segmentCount)))
  payload.add(0)
  result = @[if proven: 140'u8 else: 139'u8]
  for octet in recoveryFrame(payload): result.add(octet)

proc shardReplyWire*(fixture: WorkRecoveryFixture, item, shard: int, proven: bool): seq[byte] =
  ## Genuine original transfer proofs, not test-issued verification flags, supply both response pieces.
  let source = fixture.available.availabilitySource.value
  let specifier = fixture.available.availabilityInfo.value.specifier
  var segments: seq[byte] = @[]
  for row in [item, int(uint16(specifier.segmentCount))]:
    for octet in source.exportErasureChunk(ErasureShardIndex(shard), ExportErasureIndex(
        row)).value: segments.add(octet)
  result = recoveryFrame(segments)
  if proven:
    for row in [item, int(uint16(specifier.segmentCount))]:
      let request = AvailabilityRequest(kind: AvailabilityTransferKind.Segment,
        root: specifier.erasureRoot,
        shard: ErasureShardIndex(shard), row: ExportErasureIndex(row))
      let proof = prepareAvailabilityTransfer(fixture.available, request, recoveryPolicy().limits.transfer).value
      for octet in recoveryFrame(proof.justification): result.add(octet)
