# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine authored linked ancestors and original computation/state/recent provenance for lookup validation.

import std/assertions
import ../../src/state/computed_lookup as state_computed_lookup
import ../../src/state/computed_recent as state_computed_recent
import ../../src/state/computed_state as state_computed_state
import ../../src/state/computed_links as state_computed_links
import ../../src/state/computed_guarantee as state_computed_guarantee
import ../../src/state/computed_report as state_computed_report
import ../../src/state/block_admission as state_block_admission
import ../../src/state/store as state_store
import ../../src/state/input_refinement as state_input_refinement
import ../../src/state/extrinsic_inputs as state_extrinsic_inputs
import ../../src/state/import_inputs as state_import_inputs
import ../../src/state/import_justification as state_import_justification
import ../../src/state/availability_specifier as state_availability_specifier
import ../../src/state/export_erasure as state_export_erasure
import ../../src/state/bundle_erasure as state_bundle_erasure
import ../../src/state/erasure_layout as state_erasure_layout
import ../../src/state/erasure_words as state_erasure_words
import ../../src/state/auditable_bundle as state_auditable_bundle
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/header as codec_header
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/work_package as codec_work_package
import ../../src/codec/work_report as codec_work_report
import ../../src/codec/composite as codec_composite
import ../../src/codec/state_history as codec_state_history
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/assurances as codec_assurances
import ../../src/chain/parameters as chain_parameters
import ../../src/crypto/primitives as crypto_primitives
import ../../src/crypto/extrinsic_commitment as crypto_extrinsic_commitment
import ./pvm_computed_state
import ./pvm_computed_recent
import ./pvm_computed_lookup_vectors
import ./pvm_input_refinement
import ./pvm_report_results
import ./pvm_refinement_outcome
import ./pvm_computed_report
import ./pvm_export_erasure
import ./pvm_extrinsic_inputs
import ./pvm_import_inputs

type
  ComputedLookupFixture* = object ## Caller-owned chain handles may be replaced without altering any completed source or accepted owner.
    source*: RecentComputedReport
    older*: seq[OwnedHeader]
proc lookupLimits*(): ComputedLookupLimits =
  ## Independent local count/per-header/aggregate policies cover the authored three-header sequence.
  ComputedLookupLimits(headers: ElementLimit(8), headerBytes: ByteLimit(4096), bytes: ByteLimit(32768))
proc lookupHeaderConfig(): HeaderConfig =
  ## Exact original core/epoch profile with a structural six-validator author ceiling.
  HeaderConfig(cores: CoreCount(2), authorValidators: ValidatorCount(6), epochSlots: EpochSlots(12),
      maxBytes: ByteLimit(4096))
proc lookupWire*(owner: OwnedHeader): seq[byte] =
  ## Copy exact full sealed bytes for independent identity checks and isolated test-only mutation.
  result = newSeq[byte](headerInfo(owner).value.consumed)
  assert encodeOwnedHeader(owner, result).error == HeaderError.None
proc lookupOwner(value: Header): OwnedHeader =
  ## Capture one complete canonical header with no signature/consensus verification claim.
  var wire = newSeq[byte](4096)
  let written = encodeHeader(value, lookupHeaderConfig(), wire).value
  decodeHeader(wire.toOpenArray(0, written-1), lookupHeaderConfig()).value.owner
proc authoredHeader(slot: uint32, root, seal: byte, parent: array[32, byte]): OwnedHeader =
  ## Literal root/seal markers distinguish posterior-root direction and sealed-hash identity.
  var signature = default(array[96, byte])
  signature[0] = seal
  lookupOwner(Header(unsigned: UnsignedHeader(slot: HeaderSlot(slot), parent: HeaderParent(parent),
    priorState: PriorStateRoot(recentHash(root))), seal: HeaderSeal(signature)))
proc alteredLookupHeader*(owner: OwnedHeader, offset: int, value: byte): OwnedHeader =
  ## Replace a single test-owned serialized byte and recapture syntactically valid hostile chain input.
  var wire = lookupWire(owner)
  wire[offset] = value
  decodeHeader(wire, lookupHeaderConfig()).value.owner
proc lookupReport(execution: InputRefinement): ComputedReportLinks =
  ## Complete original computation/availability/transcript before any admission or anchor certificate can be constructed.
  let bundle = prepareAuditableBundle(execution, ByteLimit(20000)).value
  let layout = prepareErasureLayout(bundle, ErasureShards(6), ByteLimit(20000)).value
  let encoded = prepareBundleErasure(layout, BundleErasureLimits(bytes: ByteLimit(1000000),
      products: FieldProductLimit(10000000))).value
  let exported = prepareExportErasure(encoded, exportErasureLimits()).value
  let available = prepareAvailabilityCommitment(exported, reportAvailabilityLimits()).value
  let report = prepareComputedReport(available, ByteLimit(100000)).value
  let transcript = prepareComputedGuarantee(report, ByteLimit(100000)).value
  prepareComputedLinks(transcript, [], ElementLimit(0)).value
proc lookupFixture*(mode = 0): ComputedLookupFixture =
  ## Author chain18/19/20, commit C3/C11 before context capture, then execute/admit/check the exact original source.
  let tail = authoredHeader(18, 6, 13, default(array[32, byte]))
  assert array[32, byte](blake2b256(lookupWire(tail)).value) == TailHash, "independent tail sealed hash"
  let lookup = authoredHeader(if mode == 9: 20'u32 else: 19'u32, 7, 12, TailHash)
  let selectedLookupHash = array[32, byte](blake2b256(lookupWire(lookup)).value)
  if mode != 9: assert selectedLookupHash == LookupHash, "independent lookup sealed hash"
  let parent = authoredHeader(20, 8, 11, selectedLookupHash)
  let selectedParentHash = array[32, byte](blake2b256(lookupWire(parent)).value)
  if mode != 9: assert selectedParentHash == ParentHash, "independent parent sealed hash"
  let halt = @[50'u8, 0]
  let guest = reportGuest([refinementImmediate(8, 0), halt])
  var fixture = executionFixture([halt], [guest], external = false)
  var store = forkStateStore(fixture.state).value
  let chapter = historyStateEntry(HistoryState(blocks: @[HistoryBlock(header: HistoryHeaderHash(
      selectedParentHash),
    superPeak: HistorySuperPeak(recentHash(9)), slot: HistorySlot(20))]), recentConfig()).value
  assert store.apply([StateWrite(kind: StateWriteKind.Put, key: chapterKey(StateChapter(11)),
      value: @[20'u8, 0, 0, 0]),
    StateWrite(kind: StateWriteKind.Put, key: chapter.key, value: chapter.value)]).error ==
        StateStoreError.None
  fixture.state = store.snapshot.value
  let root = array[32, byte](fixture.state.commitment.root)
  let info = fixture.package.workPackageInfo.value
  var context = info.context
  context.anchor.bytes = selectedParentHash
  context.anchorSlot = AnchorSlot(20)
  context.stateRoot.bytes = root
  context.accumulationRoot.bytes = recentHash(9)
  context.lookupAnchor.bytes = selectedLookupHash
  context.lookupSlot = LookupSlot(19)
  context.lookupStateRoot.bytes = recentHash(8)
  var age = 2'u32
  case mode
  of 1: age = 1 # One slot below the inclusive age bound.
  of 2: age = 100 # Candidate21 is below the age constant; subtraction must saturate.
  of 3: context.lookupAnchor.bytes[0] = context.lookupAnchor.bytes[0] xor 1 # Wrong hash with correct slot.
  of 4: context.lookupSlot = LookupSlot(20) # Correct hash with wrong slot.
  of 5: context.lookupStateRoot.bytes = recentHash(7) # Own prior root is not the lookup posterior root.
  of 6:
    # Candidate21 cannot supply the newer witness for endpoint parent20 because only ancestors count.
    context.lookupAnchor.bytes = selectedParentHash
    context.lookupSlot = LookupSlot(20)
    context.lookupStateRoot.bytes = root
  of 7:
    # The oldest retained header is legal when its immediate newer retained child commits the claimed state.
    age = 3
    context.lookupAnchor.bytes = TailHash
    context.lookupSlot = LookupSlot(18)
    context.lookupStateRoot.bytes = recentHash(7)
  of 9: context.lookupSlot = LookupSlot(20) # Hash-linked header has the same slot as its parent.
  of 8: context.lookupSlot = LookupSlot(21) # Future slot cannot match any retained older header.
  else: discard # Ordinary exact-age-boundary lookup19 under candidate21 and age2.
  let item = fixture.package.workItemAt(0).value.workItemInfo.value
  let package = WorkPackage(host: info.host, codeHash: info.codeHash, context: context,
    authorization: @[91'u8], configuration: @[81'u8, 82], items: @[WorkItem(service: item.service,
      codeHash: item.codeHash, refineGas: item.refineGas, accumulateGas: item.accumulateGas,
      payload: @[42'u8])])
  var wire = newSeq[byte](4096)
  let packageConfig = fullPackageConfig(ByteLimit(4096))
  let written = encodeWorkPackage(package, packageConfig, wire).value
  fixture.package = decodeWorkPackage(wire.toOpenArray(0, written-1), packageConfig).value.owner
  let external = verifyExtrinsicInputs(fixture.package, @[newSeq[seq[byte]](0)], extrinsicLimits()).value
  fixture.inputs = bindImportInputs(external, @[newSeq[VerifiedImport](0)], [], inputLimits()).value
  var parameters = fixture.parameters.encodeParameters
  parameters[24] = 2
  parameters[25] = 0
  for index in 30..<34: parameters[index] = 0 # E4 epoch tuple field.
  parameters[30] = 12
  for index in 118..<122: parameters[index] = 0 # Tail remains within configured epoch.
  for index in 0..<4: parameters[74+index] = byte((age shr (8*index)) and
      255) # Original E4 maxLookupAnchorAge field.
  fixture.parameters = decodeParameters(parameters).value
  let links = lookupReport(executionRun(fixture, core = 0).value)
  let empty = decodeExtrinsic([0'u8, 0, 0, 0, 0, 0, 0], stateFrame().frame).value.owner
  let ext = extrinsicCommitment(empty, ByteLimit(100000)).value
  let child = lookupOwner(Header(unsigned: UnsignedHeader(parent: HeaderParent(selectedParentHash),
    priorState: PriorStateRoot(root), extrinsics: ext, slot: HeaderSlot(21))))
  var blockWire = lookupWire(child)
  for index in 0..<7: blockWire.add(0) # Full empty extrinsic follows the entire sealed child header.
  let candidate = decodeBlock(blockWire, stateFrame().frame).value.owner
  let admitted = validateBlockCommitments(candidate, parent, fixture.state, stateFrame())
  assert admitted.error == BlockAdmissionError.None, "real linked-parent block/state admission"
  let bound = bindComputedState(links, admitted).value
  let recent = checkComputedRecentAnchor(bound, recentConfig()).value
  ComputedLookupFixture(source: recent, older: @[lookup, tail])
