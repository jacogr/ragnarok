# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine original-current complete proofs survive native collection and produce independently owned complete snapshots that requalify under explicit original schemas/declarations.
import std/[assertions, syncio, envvars, cmdline, monotimes, times]
import std/posix/posix
import ../support/[collected_native_context, collected_logical_services_context,
    managed_supplied_context, current_logical_proof_context, supplied_services_context, current_namespace_refresh_context]
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
  let empty = default(FullLogicalProofResult[FullLogicalProofPlan])
  if mode == "value":
    discard empty.value
    return
  if mode == "reason":
    discard empty.queryFailure
    return
  if mode == "plan":
    discard empty.planError
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  let fixture = collectedNativeFixture()
  var owner = default(Services)
  var input = default(CurrentBlockInput)
  var path = "application-full-logical-proof-chain.json"
  discard startLogicalServices(owner, fixture.fixture, path)
  defer:
    owner.close()
    discard posix.unlink(path.toCString())
  let head = array[32, byte](owner.chainView.bestBlock.value.blockHash)
  let logical = collectManagedSupplied(owner, input, fixture.fixture)
  let source = logical.currentLogicalContext.value.state
  let root = source.commitment.root
  let selectorLimits = FullLogicalProofLimits(keys: ElementLimit(128), bytes: ByteLimit(16384))
  fail(1)
  let prepared = owner.planFullLogicalProof(logical, selectorLimits).value
  let info = prepared.fullLogicalProofInfo.value
  assert info.keys == source.commitment.entries and calls() == 0
  assert array[32, byte](info.root) == array[32, byte](root)
  var exact = selectorLimits
  exact.keys = ElementLimit(uint64(info.keys))
  exact.bytes = ByteLimit(info.bytes)
  assert planFullLogicalProof(logical, exact).error == FullLogicalProofError.None and calls() == 0
  exact.bytes = ByteLimit(info.bytes-1)
  assert planFullLogicalProof(logical, exact).error == FullLogicalProofError.LimitExceeded and
      calls() == 0
  exact.bytes = ByteLimit(info.bytes)
  exact.keys = ElementLimit(uint64(info.keys)-1)
  assert planFullLogicalProof(logical, exact).error == FullLogicalProofError.LimitExceeded and
      calls() == 0
  assert planFullLogicalProof(logical, FullLogicalProofLimits(keys: ElementLimit(high(uint64)),
      bytes: ByteLimit(high(uint64)))).error == FullLogicalProofError.None and calls() == 0
  assert planFullLogicalProof(default(CurrentLogicalState), selectorLimits).error ==
      FullLogicalProofError.InvalidLogical
  assert default(FullLogicalProofPlan).fullLogicalProofKeys.error ==
      FullLogicalProofError.InvalidPlan
  assert default(FullLogicalProofPlan).fullLogicalProofInfo.error ==
      FullLogicalProofError.InvalidPlan
  assert default(FullLogicalProofPlan).fullLogicalProofSource.error ==
      FullLogicalProofError.InvalidPlan
  assert captureFullLogicalProofQuery(default(FullLogicalProofPlan), default(
      LogicalProofLimits)).error == FullLogicalProofError.InvalidPlan
  var limits = LogicalProofLimits(blocks: ElementLimit(16), viewBytes: ByteLimit(33554432),
      query: logicalProofLimits())
  limits.query.aggregate.items = ElementLimit(128)
  limits.query.aggregate.nodes = ElementLimit(31872)
  limits.query.view.items = ElementLimit(128)
  var short = limits
  short.blocks = ElementLimit(0)
  assert captureFullLogicalProofQuery(prepared, short).queryFailure.error ==
      LogicalProofError.LimitExceeded
  var noHashBudget = limits
  noHashBudget.query.hashes = ProofHashLimit(0)
  let queryRefused = captureFullLogicalProofQuery(prepared, noHashBudget)
  assert queryRefused.queryFailure.error == LogicalProofError.QueryFailure
  assert queryRefused.queryFailure.queryFailure.error == ProofQueryError.LimitExceeded and calls() == 0
  assert captureFullLogicalProofQuery(prepared, limits).error == FullLogicalProofError.None and
      calls() == 0
  fail(0)
  let direct = executeProofQuery(captureFullLogicalProofQuery(prepared, limits).value).value
  let keptSource = prepared.fullLogicalProofSource.value
  let keys = prepared.fullLogicalProofKeys.value
  let ticket = owner.beginLogicalProof(keptSource, keys, limits).value
  owner.waitProof()
  assert owner.stateProofActive
  assert owner.collectStateProof(default(ProofWorkerTicket)).kind ==
      ProofWorkerCompletionKind.Uninitialized
  assert owner.stateProofActive
  let completed = owner.collectStateProof(ticket)
  assert completed.kind == ProofWorkerCompletionKind.Completed and not owner.stateProofActive
  let response = completed.value.value
  assert response.bytes(limits.query.wireBytes).value == direct.bytes(limits.query.wireBytes).value
  let wire = response.bytes(limits.query.wireBytes).value
  let view = decodePlannedProofs(wire, keys, root, limits.query.view, limits.query.proof,
      limits.query.aggregate, limits.query.wireBytes).value
  assert view.len == source.commitment.entries
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
  let cancelled = owner.beginLogicalProof(keptSource, keys, limits).value
  owner.waitProof()
  assert owner.cancelStateProof(cancelled) and owner.stateProofActive
  assert owner.collectStateProof(ticket).kind == ProofWorkerCompletionKind.Uninitialized and
      owner.stateProofActive
  assert owner.collectStateProof(cancelled).kind == ProofWorkerCompletionKind.Cancelled
  discard owner.beginLogicalProof(keptSource, keys, limits).value
  owner.close() # Joined shutdown retires native borrowing before source/query/selector aliases can be observed again.
  let outside = decodePlannedProofs(wire, keys, root, limits.query.view, limits.query.proof,
      limits.query.aggregate, limits.query.wireBytes).value
  assert importProofState(outside, root, ProofStateImportLimits(lookups: ElementLimit(128),
      copyBytes: ByteLimit(1048576), store: genesisStoreLimits())).error ==
      ProofStateImportError.None
  echo "application-full-logical-proofs: ok"
try:
  main()
except:
  quit(2) # Ordinary preparation/proof/import failures cannot impersonate strict extraction rejection.
