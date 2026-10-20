# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine computed reports execute from the exact complete parent map later admitted with sealed block commitments.

import std/assertions
import ../../src/state/[store, block_admission, computed_links, computed_report, computed_guarantee,
  availability_specifier, export_erasure, bundle_erasure, erasure_layout, erasure_words,
  auditable_bundle, input_refinement]
import ../../src/codec/[bounded, state_trie, state_layout, state_safrole, header, block_codec,
  composite, work_report, assurances, tickets]
import ../../src/chain/parameters
import ../../src/crypto/[primitives, extrinsic_commitment]
import ./[pvm_input_refinement, pvm_report_results, pvm_refinement_outcome, pvm_computed_report,
  pvm_export_erasure, pvm_computed_state_vectors]

type
  ComputedStateFixture* = object ## Mutable fixture handles permit caller replacement after original immutable owners have completed.
    source*: ComputedReportLinks
    state*: StateStore
    admission*: BlockAdmissionResult
proc stateFrame*(): BlockAdmissionConfig =
  ## Small explicit structural domains and independent resource limits cover only the authored commitment boundary.
  BlockAdmissionConfig(frame: FrameConfig(cores: CoreCount(2), validators: ValidatorCount(6),
    epochSlots: EpochSlots(12), ticketLimit: TicketLimit(3), maxBytes: ByteLimit(100000),
    preimages: PreimageLimits(items: ElementLimit(100), perBlob: ByteLimit(100000),
      totalBlobBytes: ByteLimit(100000))), maxParentHeaderBytes: ByteLimit(100000))
proc stateHeader(value: Header): seq[byte] =
  ## Capture every canonical full-header byte, including the opaque unverified seal.
  result = newSeq[byte](4096)
  let config = HeaderConfig(cores: CoreCount(2), authorValidators: ValidatorCount(6),
    epochSlots: EpochSlots(12), maxBytes: ByteLimit(4096))
  let written = encodeHeader(value, config, result).value
  result.setLen(written)
proc stateAdmission*(state: StateStoreSnapshot, wrongRoot = false): BlockAdmissionResult =
  ## Construct and actually validate a sealed-child parent/state/extrinsic commitment binding; no consensus signature claim.
  var parent = Header(unsigned: UnsignedHeader(slot: HeaderSlot(20)))
  var parentSeal = default(array[96, byte])
  parentSeal[0] = 17
  parent.seal = HeaderSeal(parentSeal)
  let parentWire = stateHeader(parent)
  assert parentWire.len == 297, "literal full parent extent"
  let hashed = blake2b256(parentWire).value
  assert array[32, byte](hashed) == StateParentHash, "independent literal full sealed parent hash"
  let cfg = stateFrame()
  let headerConfig = HeaderConfig(cores: cfg.frame.cores, authorValidators: cfg.frame.validators,
    epochSlots: cfg.frame.epochSlots, maxBytes: cfg.maxParentHeaderBytes)
  let parentOwner = decodeHeader(parentWire, headerConfig).value.owner
  let empty = decodeExtrinsic([0'u8, 0, 0, 0, 0, 0, 0], cfg.frame).value.owner
  let ext = extrinsicCommitment(empty, cfg.frame.maxBytes).value
  var root = array[32, byte](state.commitment.root)
  if wrongRoot: root[0] = root[0] xor 1 # A genuinely refused admission is distinct from a fabricated success.
  let child = Header(unsigned: UnsignedHeader(parent: HeaderParent(array[32, byte](hashed)),
    priorState: PriorStateRoot(root), extrinsics: ext, slot: HeaderSlot(21)))
  var wire = stateHeader(child)
  # Append the complete empty extrinsic in normative family order after the entire sealed header.
  for index in 0..<7: wire.add(0)
  let candidate = decodeBlock(wire, cfg.frame).value.owner
  validateBlockCommitments(candidate, parentOwner, state, cfg)
proc stateReport(execution: InputRefinement): ComputedReportLinks =
  ## Complete the original zero-lookup computation and source-bound transcript before state binding is possible.
  let bundle = prepareAuditableBundle(execution, ByteLimit(20000)).value
  let layout = prepareErasureLayout(bundle, ErasureShards(6), ByteLimit(20000)).value
  let encoded = prepareBundleErasure(layout, BundleErasureLimits(bytes: ByteLimit(1000000),
    products: FieldProductLimit(10000000))).value
  let exported = prepareExportErasure(encoded, exportErasureLimits()).value
  let available = prepareAvailabilityCommitment(exported, reportAvailabilityLimits()).value
  let report = prepareComputedReport(available, ByteLimit(100000)).value
  let transcript = prepareComputedGuarantee(report, ByteLimit(100000)).value
  prepareComputedLinks(transcript, [], ElementLimit(0)).value
proc stateFixture*(): ComputedStateFixture =
  ## Add exact C11 before execution, preserving all original code/preimage/history mappings in a private complete store.
  let halt = @[50'u8, 0]
  let guest = reportGuest([refinementImmediate(8, 0), halt])
  var fixture = executionFixture([halt], [guest], external = false)
  var store = forkStateStore(fixture.state).value
  let written = store.apply([StateWrite(kind: StateWriteKind.Put,
    key: chapterKey(StateChapter(11)), value: @[20'u8, 0, 0, 0])])
  assert written.error == StateStoreError.None, "original C11 preparation"
  fixture.state = store.snapshot.value
  var params = fixture.parameters.encodeParameters
  params[24] = 2
  params[25] = 0
  for index in 30..<34: params[index] = 0 # Exact E4 epoch tuple field.
  params[30] = 12
  for index in 118..<122: params[index] = 0 # Configured tail is bounded by the shortened epoch.
  fixture.parameters = decodeParameters(params).value
  let source = stateReport(executionRun(fixture, core = 0).value)
  let admitted = stateAdmission(fixture.state)
  assert admitted.error == BlockAdmissionError.None, "real full-state commitment admission"
  ComputedStateFixture(source: source, state: store, admission: admitted)
proc clonedState*(original: StateStoreSnapshot): StateStore =
  ## Rebuild the same complete mappings under a distinct owner to witness equal-root substitution refusal.
  var entries: seq[StateEntry] = @[]
  for index in 0..<original.commitment.entries:
    let key = original.keyAt(StateEntryIndex(index)).value
    entries.add(StateEntry(key: key, value: original.lookup(key).value.bytes))
  let limits = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(1000),
    perValue: ByteLimit(100000), totalValueBytes: ByteLimit(1000000), nodes: TrieNodeLimit(100000)),
    writes: ElementLimit(100), writeValueBytes: ByteLimit(1000000))
  newStateStore(entries, limits).value
proc changeState*(store: var StateStore) =
  ## Publish an unrelated new version only in test-owned storage, preserving every prior snapshot.
  assert store.apply([StateWrite(kind: StateWriteKind.Put, key: chapterKey(StateChapter(199)),
    value: @[1'u8])]).error == StateStoreError.None, "new test version"
