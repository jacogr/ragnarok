# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Commit original guest code before signing, then compute against the exact admitted parent map.

import ./pvm_computed_storage_program
import std/assertions
import ../../src/state/computed_profile as state_computed_profile
import ../../src/state/computed_lookup as state_computed_lookup
import ../../src/state/computed_recent as state_computed_recent
import ../../src/state/computed_state as state_computed_state
import ../../src/state/computed_links as state_computed_links
import ../../src/state/computed_guarantee as state_computed_guarantee
import ../../src/state/computed_report as state_computed_report
import ../../src/state/block_admission as state_block_admission
import ../../src/state/block_transition as state_block_transition
import ../../src/state/store as state_store
import ../../src/state/input_refinement as state_input_refinement
import ../../src/state/availability_specifier as state_availability_specifier
import ../../src/state/export_erasure as state_export_erasure
import ../../src/state/bundle_erasure as state_bundle_erasure
import ../../src/state/erasure_layout as state_erasure_layout
import ../../src/state/erasure_words as state_erasure_words
import ../../src/state/auditable_bundle as state_auditable_bundle
import ../../src/state/extrinsic_inputs as state_extrinsic_inputs
import ../../src/state/import_inputs as state_import_inputs
import ../../src/state/import_justification as state_import_justification
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/parameters as chain_parameters
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/header as codec_header
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/work_package as codec_work_package
import ../../src/codec/work_report as codec_work_report
import ../../src/codec/composite as codec_composite
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/state_workqueues as codec_state_workqueues
import ../../src/crypto/primitives as crypto_primitives
import ./pvm_input_refinement
import ./pvm_report_results
import ./pvm_refinement_outcome
import ./pvm_computed_report
import ./pvm_export_erasure
import ./pvm_extrinsic_inputs
import ./pvm_import_inputs
import ./pvm_computed_lookup
import ./pvm_computed_recent
import ./state_report_context
import ./state_report_admission_context

type
  ComputedTransitionFixture* = object ## Caller-owned genuine signed inputs preserve original execution and posterior identities.
    source*: ConfiguredComputedReport
    context*: Context
    execution*: InputFixture
    base*: OwnedReport
    options*: SignedBlockFixtureConfig
proc transitionLinks(execution: InputRefinement): ComputedReportLinks =
  ## Complete the actual original computation/availability/transcript path without supplying observations separately.
  let bundle = prepareAuditableBundle(execution, ByteLimit(20000)).value
  let layout = prepareErasureLayout(bundle, ErasureShards(6), ByteLimit(20000)).value
  let encoded = prepareBundleErasure(layout, BundleErasureLimits(bytes: ByteLimit(1000000),
      products: FieldProductLimit(10000000))).value
  let exported = prepareExportErasure(encoded, exportErasureLimits()).value
  let available = prepareAvailabilityCommitment(exported, reportAvailabilityLimits()).value
  let report = prepareComputedReport(available, ByteLimit(100000)).value
  let transcript = prepareComputedGuarantee(report, ByteLimit(100000)).value
  prepareComputedLinks(transcript, [], ElementLimit(0)).value
proc transitionSource*(context: Context, original: InputFixture,
    candidate: OwnedBlock): ConfiguredComputedReport =
  ## Recapture original package context for this real parent/lookup chain before re-execution and every source binding.
  var fixture = original
  fixture.state = context.original.snapshot.value
  let info = fixture.package.workPackageInfo.value
  let item = fixture.package.workItemAt(0).value.workItemInfo.value
  var claim = info.context
  claim.anchor.bytes = array[32, byte](blake2b256(lookupWire(context.parent)).value)
  claim.anchorSlot = AnchorSlot(1)
  claim.stateRoot.bytes = array[32, byte](fixture.state.commitment.root)
  claim.accumulationRoot.bytes = default(array[32, byte])
  claim.lookupAnchor.bytes = array[32, byte](blake2b256(lookupWire(context.older[0])).value)
  claim.lookupSlot = LookupSlot(0)
  claim.lookupStateRoot.bytes = default(array[32, byte])
  let package = WorkPackage(host: info.host, codeHash: info.codeHash, context: claim,
    authorization: @[91'u8], configuration: @[81'u8, 82], items: @[WorkItem(service: item.service,
      codeHash: item.codeHash, refineGas: item.refineGas, accumulateGas: item.accumulateGas,
      payload: @[42'u8])])
  var wire = newSeq[byte](4096)
  let cfg = fullPackageConfig(ByteLimit(4096))
  let written = encodeWorkPackage(package, cfg, wire).value
  fixture.package = decodeWorkPackage(wire.toOpenArray(0, written-1), cfg).value.owner
  let external = verifyExtrinsicInputs(fixture.package, @[newSeq[seq[byte]](0)], extrinsicLimits()).value
  fixture.inputs = bindImportInputs(external, @[newSeq[VerifiedImport](0)], [], inputLimits()).value
  let links = transitionLinks(executionRun(fixture, core = 0).value)
  let admitted = validateBlockCommitments(candidate, context.parent, fixture.state, frame())
  assert admitted.error == BlockAdmissionError.None, "genuine exact original commitment admission"
  let bound = bindComputedState(links, admitted).value
  let recent = checkComputedRecentAnchor(bound, recentConfig()).value
  let lookup = checkComputedLookupAnchor(recent, context.older, lookupLimits()).value
  let configured = captureBlockSnapshot(lookupWire(context.parent), fixture.state,
      fixture.parameters)
  assert configured.error == GenesisError.None, "genuine configured signed parent"
  bindComputedProfile(lookup, configured).value
proc transitionFixture*(epoch = false, withReady = false,
    withExecution = false, invalidEntry = false, storage = ComputedStorageMode.Disabled): ComputedTransitionFixture =
  ## Preserve real signing and original map ownership; no fake keys or forged successful transition result.
  let halt = @[50'u8, 0]
  var instructions = @[refinementImmediate(8, 0), halt]
  if withExecution and not invalidEntry:
    # Five pinned opcode1 fallthrough blocks place the shared zero-output body at accumulation entry5.
    instructions = @[@[1'u8], @[1'u8], @[1'u8], @[1'u8], @[1'u8], refinementImmediate(8, 0), halt]
  if storage != ComputedStorageMode.Disabled:
    instructions = computedStorageInstructions(storage) # Separate original entries prevent refinement from invoking an accumulation-only host.
  let guest = reportGuest(instructions)
  var fixture = executionFixture([halt], [guest], external = false)
  if storage != ComputedStorageMode.Disabled:
    fixture = computedStorageBudget(fixture, storage) # Historical ready and current reports share the actual declared gas, not a later patched observation.
  let templateLinks = transitionLinks(executionRun(fixture, core = 0).value)
  let templateReport = templateLinks.computedLinkSource.value.computedGuaranteeReport.value
  let base = decodeOwnedReport(templateReport.computedReportBytes.value, 2).value
  let duplicates = entriesFor([reportFor(base, 0, [10'u64])])
  var options = signedBlockFixtureConfig()
  options.reports = 0
  if withReady:
    # Historical ready work is part of the actual original committed parent, before any current computation/signing.
    options.ready = @[ReadyItem(report: base, dependencies: @[])]
  options.targetSlot = if epoch: 12'u32 else: 2'u32
  options.shiftPending = epoch
  var histories = 0
  for index in 0..<fixture.state.commitment.entries:
    # Retain complete original code/preimage/account entries, excluding metadata already authored for the same guest.
    let key = fixture.state.keyAt(StateEntryIndex(index)).value
    var duplicate = false
    for entry in duplicates:
      if array[31, byte](entry.key) == array[31, byte](key): duplicate = true
    if not duplicate:
      var bytes = fixture.state.lookup(key).value.bytes
      if bytes == @[1'u8, 10, 0, 0, 0]:
        bytes = @[1'u8, 0, 0, 0, 0] # Original historical code becomes available at lookup0 before any signing or execution.
        inc histories
      options.extra.add(StateEntry(key: key, value: bytes))
  assert histories == 2, "both original historical code requests"
  var params = fixture.parameters.encodeParameters
  if storage != ComputedStorageMode.Disabled:
    for field, amount in [2'u64, 1'u64, 10'u64]:
      for index in 0..<8: params[field*8+index] = byte((amount shr (8*index)) and
          255) # Exact original E8 item/octet/base deposit schedule, before configured capture.
  params[24] = 2
  params[25] = 0
  for index in 30..<34: params[index] = 0 # Original epoch domain is twelve slots.
  params[30] = 12
  params[72] = 3
  params[73] = 0 # Exact ticket ceiling supplied to the genuine transition.
  for index in 118..<122: params[index] = 0 # Original epoch tail matches the genuine Safrole fixture.
  params[118] = 10
  fixture.parameters = decodeParameters(params).value
  let context = authored(base, options)
  let source = transitionSource(context, fixture, context.candidate)
  ComputedTransitionFixture(source: source, context: context, execution: fixture, base: base,
      options: options)
