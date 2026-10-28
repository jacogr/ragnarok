# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine C3-bearing original execution and admitted-state fixtures with independently distinguishable recent records.

import std/assertions
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
import ../../src/codec/state_history as codec_state_history
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/work_package as codec_work_package
import ../../src/codec/work_report as codec_work_report
import ../../src/codec/assurances as codec_assurances
import ../../src/chain/parameters as chain_parameters
import ./pvm_computed_state
import ./pvm_computed_state_vectors
import ./pvm_input_refinement
import ./pvm_report_results
import ./pvm_refinement_outcome
import ./pvm_computed_report
import ./pvm_export_erasure
import ./pvm_extrinsic_inputs
import ./pvm_import_inputs

type
  ComputedRecentFixture* = object ## Caller-owned mutable handles expose original chapter preservation after successful preparation.
    source*: StateBoundComputedReport
    state*: StateStore
    original*: seq[byte]
proc recentConfig*(): HistoryConfig =
  ## Original two-core profile with independent recent-record, pair, peak and complete-value ceilings.
  HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8), perBlock: ElementLimit(2),
    totalPackages: ElementLimit(16), peaks: ElementLimit(64), maxBytes: ByteLimit(100000))
proc recentHash*(first: byte): array[32, byte] =
  ## Literal leading-byte markers distinguish records, state roots and accumulation super-peaks without new hashes.
  result = default(array[32, byte])
  result[0] = first
proc recentReport(execution: InputRefinement): ComputedReportLinks =
  ## Complete the original zero-lookup bundle/availability/report/transcript path before any anchor checking.
  let bundle = prepareAuditableBundle(execution, ByteLimit(20000)).value
  let layout = prepareErasureLayout(bundle, ErasureShards(6), ByteLimit(20000)).value
  let encoded = prepareBundleErasure(layout, BundleErasureLimits(bytes: ByteLimit(1000000),
    products: FieldProductLimit(10000000))).value
  let exported = prepareExportErasure(encoded, exportErasureLimits()).value
  let available = prepareAvailabilityCommitment(exported, reportAvailabilityLimits()).value
  let report = prepareComputedReport(available, ByteLimit(100000)).value
  let transcript = prepareComputedGuarantee(report, ByteLimit(100000)).value
  prepareComputedLinks(transcript, [], ElementLimit(0)).value
proc recentFixture*(mode = 0): ComputedRecentFixture =
  ## Commit C3/C11 before final context capture and execution; each negative mode remains a genuine completed state binding.
  let halt = @[50'u8, 0]
  let guest = reportGuest([refinementImmediate(8, 0), halt])
  var fixture = executionFixture([halt], [guest], external = false)
  var store = forkStateStore(fixture.state).value
  let older = HistoryBlock(header: HistoryHeaderHash(recentHash(1)), state: HistoryStateRoot(
      recentHash(2)),
    superPeak: HistorySuperPeak(recentHash(3)), slot: HistorySlot(18))
  var latest = HistoryBlock(header: HistoryHeaderHash(StateParentHash),
    superPeak: HistorySuperPeak(recentHash(9)), slot: HistorySlot(20))
  if mode == 7: latest.header = HistoryHeaderHash(recentHash(
      99)) # Wrong endpoint cannot receive state correction.
  if mode == 8: latest.slot = HistorySlot(19) # Endpoint chronology must match the admitted parent too.
  if mode == 13: latest.state = HistoryStateRoot(recentHash(
      100)) # Correction replaces any stored latest value, never older records.
  let history = if mode == 10: HistoryState() else: HistoryState(blocks: @[older, latest])
  let entry = historyStateEntry(history, recentConfig()).value
  var bytes = entry.value
  if mode == 11: bytes = @[1'u8] # Truncated nonempty C3 count.
  if mode == 12: bytes.add(0) # A canonical prefix plus a suffix cannot become exact state.
  var writes = @[StateWrite(kind: StateWriteKind.Put, key: chapterKey(StateChapter(11)), value: @[
      20'u8, 0, 0, 0])]
  if mode != 9: writes.add(StateWrite(kind: StateWriteKind.Put, key: entry.key,
      value: bytes)) # Missing is distinct from explicitly empty history.
  assert store.apply(writes).error == StateStoreError.None, "original recent chapter preparation"
  fixture.state = store.snapshot.value
  let root = array[32, byte](fixture.state.commitment.root)
  let info = fixture.package.workPackageInfo.value
  var context = info.context
  context.anchor.bytes = StateParentHash
  context.anchorSlot = AnchorSlot(20)
  context.stateRoot.bytes = root
  context.accumulationRoot.bytes = recentHash(9)
  case mode
  of 1: context.anchor.bytes[0] = context.anchor.bytes[0] xor 1 # Header identity mismatch alone.
  of 2: context.stateRoot.bytes[0] = context.stateRoot.bytes[0] xor 1 # Posterior root mismatch alone.
  of 3: context.accumulationRoot.bytes[0] = 8 # Super-peak mismatch alone.
  of 4: context.anchorSlot = AnchorSlot(19) # Slot mismatch alone.
  of 5: context.anchor.bytes = recentHash(1) # Fields individually occur across two records, never together.
  of 6:
    # An earlier complete tuple retains its original root rather than receiving the newest correction.
    context.anchor.bytes = recentHash(1)
    context.stateRoot.bytes = recentHash(2)
    context.accumulationRoot.bytes = recentHash(3)
    context.anchorSlot = AnchorSlot(18)
  else: discard # The ordinary candidate claims the newest parent's corrected tuple.
  let item = fixture.package.workItemAt(0).value.workItemInfo.value
  let package = WorkPackage(host: info.host, codeHash: info.codeHash, context: context,
    authorization: @[91'u8], configuration: @[81'u8, 82], items: @[WorkItem(service: item.service,
      codeHash: item.codeHash, refineGas: item.refineGas, accumulateGas: item.accumulateGas,
      payload: @[42'u8])])
  var wire = newSeq[byte](4096)
  let config = fullPackageConfig(ByteLimit(4096))
  let written = encodeWorkPackage(package, config, wire).value
  fixture.package = decodeWorkPackage(wire.toOpenArray(0, written-1), config).value.owner
  let external = verifyExtrinsicInputs(fixture.package, @[newSeq[seq[byte]](0)], extrinsicLimits()).value
  fixture.inputs = bindImportInputs(external, @[newSeq[VerifiedImport](0)], [], inputLimits()).value
  var parameters = fixture.parameters.encodeParameters
  parameters[24] = 2
  parameters[25] = 0
  for index in 30..<34: parameters[index] = 0 # Exact E4 epoch tuple field.
  parameters[30] = 12
  for index in 118..<122: parameters[index] = 0 # Tail remains within configured epoch.
  fixture.parameters = decodeParameters(parameters).value
  let links = recentReport(executionRun(fixture, core = 0).value)
  let admitted = stateAdmission(fixture.state)
  assert admitted.error == BlockAdmissionError.None, "real C3-bearing block/state commitment admission"
  ComputedRecentFixture(source: bindComputedState(links, admitted).value, state: store,
      original: bytes)
