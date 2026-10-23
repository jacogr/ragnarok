# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine native proof pages are independently authenticated, merged without absence inference, and restored only after complete expected-root equality.
import std/[assertions, syncio, envvars, cmdline, monotimes, times]
import std/posix/posix
import ../support/[collected_native_context, collected_logical_services_context,
    managed_supplied_context, current_logical_proof_context, supplied_services_context, current_namespace_refresh_context]
import ../../src/app/paged_logical_proof
import ../../src/state/trie_proof
import ../../src/app/[logical_code, full_logical_proof, logical_proof, proof_query, services,
    current_block_input, proof_worker]
import ../../src/state/[code_availability, current_logical, current_state, current_globals,
    current_profile, proof_plan, planned_proof, proof_view, proof_state_import, store,
    global_snapshot, manifest,
    supplied_logical_inventory, supplied_services]
import ../../src/codec/[bounded, state_layout, state_trie, state_requests]
import ../../src/chain/[provider, genesis]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Selector/query admission remains hash-free after genuine execution and qualification finish.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe whole-selector refusal before any new primitive work.
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Scalar monotonic polling cannot observe or retire leased canonical graphs.
proc waitProof(owner: var Services) =
  ## Actual Done remains leased until exact matching collection.
  let started = getMonoTime()
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    discard pauseMicros(1000)
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(LogicalProofPageResult[LogicalProofPages])
  if mode == "value":
    discard empty.value
    return
  if mode == "reason":
    discard empty.queryFailure
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  if mode == "full":
    discard empty.fullFailure
    return
  if mode == "plan":
    discard empty.planError
    return
  let fixture = collectedNativeFixture()
  var owner = default(Services)
  var input = default(CurrentBlockInput)
  var path = "application-paged-logical-proof-chain.json"
  discard startLogicalServices(owner, fixture.fixture, path)
  defer:
    owner.close()
    discard posix.unlink(path.toCString())
  let head = array[32, byte](owner.chainView.bestBlock.value.blockHash)
  let logical = collectManagedSupplied(owner, input, fixture.fixture)
  let source = logical.currentLogicalContext.value.state
  let root = source.commitment.root
  let selectorLimits = FullLogicalProofLimits(keys: ElementLimit(128), bytes: ByteLimit(16384))
  let pageLimits = LogicalProofPageLimits(keys: ElementLimit(7), bytes: ByteLimit(
      527)) # Seven input/output keys plus three merge-sort keys, each 31 bytes.
  fail(1)
  let pages = owner.planLogicalProofPages(logical, selectorLimits, pageLimits).value
  let info = pages.logicalProofPagesInfo.value
  assert info.keys == source.commitment.entries and info.pageKeys == 7 and info.pages == (
      info.keys+6) div 7
  assert info.pages > 1 and calls() == 0
  assert array[32, byte](info.root) == array[32, byte](root)
  var short = pageLimits
  short.bytes = ByteLimit(526)
  assert planLogicalProofPages(logical, selectorLimits, short).error ==
      LogicalProofPageError.LimitExceeded
  short.keys = ElementLimit(0)
  assert planLogicalProofPages(logical, selectorLimits, short).error ==
      LogicalProofPageError.LimitExceeded
  assert planLogicalProofPages(default(CurrentLogicalState), selectorLimits,
      pageLimits).fullFailure.error == FullLogicalProofError.InvalidLogical
  assert planLogicalProofPages(logical, FullLogicalProofLimits(keys: ElementLimit(0)),
      pageLimits).fullFailure.error == FullLogicalProofError.LimitExceeded
  assert default(LogicalProofPages).logicalProofPagesInfo.error == LogicalProofPageError.InvalidPlan
  assert default(LogicalProofPages).logicalProofPageAt(LogicalProofPageIndex(0)).error ==
      LogicalProofPageError.InvalidPlan
  assert pages.logicalProofPageAt(LogicalProofPageIndex(high(uint64))).error ==
      LogicalProofPageError.InvalidIndex
  assert pages.logicalProofPageAt(LogicalProofPageIndex(uint64(info.pages))).error ==
      LogicalProofPageError.InvalidIndex
  assert default(LogicalProofPage).logicalProofPageInfo.error == LogicalProofPageError.InvalidPlan
  assert default(LogicalProofPage).logicalProofPageSource.error == LogicalProofPageError.InvalidPlan
  assert default(LogicalProofPage).logicalProofPageKeys.error == LogicalProofPageError.InvalidPlan
  assert captureLogicalProofPageQuery(default(LogicalProofPage), default(
      LogicalProofLimits)).error == LogicalProofPageError.InvalidPlan
  let saturated = planLogicalProofPages(logical, selectorLimits, LogicalProofPageLimits(
      keys: ElementLimit(high(uint64)), bytes: ByteLimit(high(uint64)))).value
  assert saturated.logicalProofPagesInfo.value.pages == 1
  assert saturated.logicalProofPageAt(LogicalProofPageIndex(
      0)).value.logicalProofPageInfo.value.keys == info.keys
  var limits = LogicalProofLimits(blocks: ElementLimit(16), viewBytes: ByteLimit(33554432),
      query: logicalProofLimits())
  limits.query.aggregate.items = ElementLimit(7)
  limits.query.view.items = ElementLimit(7)
  assert captureFullLogicalProofQuery(planFullLogicalProof(logical, selectorLimits).value,
      limits).error == FullLogicalProofError.QueryFailure
  var merged = default(ProofView)
  let mergeLimits = ProofViewLimits(items: ElementLimit(128), valueBytes: ByteLimit(1048576))
  let importLimits = ProofStateImportLimits(lookups: ElementLimit(128), copyBytes: ByteLimit(
      1048576), store: genesisStoreLimits())
  var seen = 0
  for ordinal in 0..<info.pages:
    # Reverse-order transfer proves deterministic key ranges need no mutable receiver cursor or trusted arrival ordering.
    let index = info.pages-1-ordinal
    let page = pages.logicalProofPageAt(LogicalProofPageIndex(uint64(index))).value
    let current = page.logicalProofPageInfo.value
    assert current.offset == index*7 and current.keys == min(7, info.keys-current.offset)
    assert current.totalKeys == info.keys and current.pages == info.pages and calls() == 0
    var noHashes = limits
    noHashes.query.hashes = ProofHashLimit(0)
    assert captureLogicalProofPageQuery(page, noHashes).queryFailure.error ==
        LogicalProofError.QueryFailure
    let query = captureLogicalProofPageQuery(page, limits).value
    assert calls() == 0
    fail(0)
    let direct = executeProofQuery(query).value
    let keptSource = page.logicalProofPageSource.value
    let keys = page.logicalProofPageKeys.value
    let ticket = owner.beginLogicalProof(keptSource, keys, limits).value
    owner.waitProof()
    assert owner.stateProofActive
    assert owner.collectStateProof(default(ProofWorkerTicket)).kind ==
        ProofWorkerCompletionKind.Uninitialized and owner.stateProofActive
    let completion = owner.collectStateProof(ticket)
    assert completion.kind == ProofWorkerCompletionKind.Completed and not owner.stateProofActive
    let wire = completion.value.value.bytes(limits.query.wireBytes).value
    assert wire == direct.bytes(limits.query.wireBytes).value
    let view = decodePlannedProofs(wire, keys, root, limits.query.view, limits.query.proof,
        limits.query.aggregate, limits.query.wireBytes).value
    assert view.len == current.keys
    let first = pages.logicalProofPageAt(LogicalProofPageIndex(
        0)).value.logicalProofPageKeys.value.keyAt(0).value
    if index != 0:
      assert view.lookup(first).error == ProofViewError.MissingWitness # An omitted page grants no absence fact.
    if ordinal == 0:
      merged = view
      assert importProofState(merged, root, importLimits).error == ProofStateImportError.Incomplete
    else:
      merged = mergeProofViews(merged, view, mergeLimits).value # Independently verified common-root immutable evidence can be combined in any order.
    assert mergeProofViews(merged, view, mergeLimits).value.len ==
        merged.len # Repeated delivery cannot add fabricated keys or replace facts.
    seen += current.keys
    if ordinal+1 < info.pages:
      assert importProofState(merged, root, importLimits).error == ProofStateImportError.Incomplete
    fail(1) # Re-arm only after native matching collection and independent authentication have finished.
  assert seen == info.keys and merged.len == info.keys
  fail(0)
  let view = merged
  let restored = importProofState(view, root, ProofStateImportLimits(lookups: ElementLimit(128),
      copyBytes: ByteLimit(1048576), store: genesisStoreLimits())).value.snapshot.value
  assert not sameStateSnapshot(restored, source) and restored.commitment.entries ==
      source.commitment.entries
  for i in 0..<source.commitment.entries:
    let key = source.keyAt(StateEntryIndex(i)).value
    assert restored.lookup(key).value.bytes == source.lookup(
        key).value.bytes # Every exact serialized value survives existing wire verification and checked completeness reconstruction.
  let declarations = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  let policy = namespaceLogicalLimits()
  let profile = logical.currentLogicalSource.value.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedStateProfile.value
  let globals = validateGlobalState(restored, profile, policy.globals).value
  let complete = validateStateManifest(globals, declarations,
      policy.logical.inventory.manifest).value
  let qualified = captureSuppliedLogicalInventory(complete, declarations, policy.logical).value
  assert not sameStateSnapshot(qualified.suppliedInventory.value.inventorySource.value.manifestSource.value, source)
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) ==
      head # Complete proof export/import grants no canonical adoption.
  let codeLimits = CodeAvailabilityLimits(services: ElementLimit(2), visits: ElementLimit(128),
      descriptors: ByteLimit(65536), perCode: ByteLimit(65536), totalCodeBytes: ByteLimit(131072))
  let originalCodes = auditLogicalCodeAvailability(logical, codeLimits).value.logicalCodeTable
  let importedCodes = auditCodeAvailability(qualified.suppliedInventory.value, RequestSlot(
      logical.currentLogicalContext.value.slot), codeLimits).value
  assert originalCodes.codeAvailabilityInfo.value.available ==
      importedCodes.codeAvailabilityInfo.value.available
  for i in 0..<originalCodes.codeAvailabilityInfo.value.services:
    let originalCode = originalCodes.serviceCodeAt(i).value
    let importedIndex = importedCodes.findServiceCode(originalCode.service).value
    assert importedCodes.serviceCodeAt(importedIndex).value.state == originalCode.state
    if originalCode.state == ServiceCodeState.Available:
      assert importedCodes.copyServiceCode(importedIndex, ByteLimit(65536)).value ==
          originalCodes.copyServiceCode(i, ByteLimit(
          65536)).value # Independent complete owners preserve code content and selected-slot availability.
  owner.close() # Joined shutdown releases managed borrowing before retained plans and reconstructed maps retire.
  assert importProofState(merged, root, importLimits).error == ProofStateImportError.None
  echo "application-paged-logical-proofs: ok"
try:
  main()
except:
  quit(2) # Ordinary failures cannot impersonate contract/privacy rejection.
