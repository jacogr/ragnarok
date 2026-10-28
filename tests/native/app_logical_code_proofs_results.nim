# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine original logical code dependencies produce four-key managed proofs; authenticated time and actual-length history drive the existing typed historical reader.
import std/assertions
import std/syncio
import std/envvars
import std/cmdline
import std/monotimes
import std/times
import std/posix/posix
import ../support/app_collected_native_context
import ../support/app_collected_logical_services_context
import ../support/app_managed_supplied_context
import ../support/state_current_logical_proof_context
import ../support/state_supplied_services_context
import ../support/state_current_namespace_refresh_context
import ../support/app_collected_mutation_context
import ../support/state_current_namespace_context
import ../support/state_current_namespace_transition_context
import ../support/state_current_namespace_execution_context
import ../support/state_accumulation_execution_context
import ../support/pvm_accumulation_program
import ../../src/app/logical_code_proof as app_logical_code_proof
import ../../src/state/proof_service as state_proof_service
import ../../src/state/trie_proof as state_trie_proof
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/app/logical_code as app_logical_code
import ../../src/app/full_logical_proof as app_full_logical_proof
import ../../src/app/logical_proof as app_logical_proof
import ../../src/app/proof_query as app_proof_query
import ../../src/app/services as app_services
import ../../src/app/current_block_input as app_current_block_input
import ../../src/app/proof_worker as app_proof_worker
import ../../src/state/code_availability as state_code_availability
import ../../src/state/current_logical as state_current_logical
import ../../src/state/current_state as state_current_state
import ../../src/state/current_globals as state_current_globals
import ../../src/state/current_profile as state_current_profile
import ../../src/state/proof_plan as state_proof_plan
import ../../src/state/planned_proof as state_planned_proof
import ../../src/state/proof_view as state_proof_view
import ../../src/state/proof_state_import as state_proof_state_import
import ../../src/state/store as state_store
import ../../src/state/global_snapshot as state_global_snapshot
import ../../src/state/manifest as state_manifest
import ../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../src/state/supplied_services as state_supplied_services
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/state_requests as codec_state_requests
import ../../src/chain/provider as chain_provider
import ../../src/chain/genesis as chain_genesis
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
  let empty = default(LogicalCodeProofResult[LogicalCodeProof])
  if mode == "value":
    discard empty.value
    return
  if mode == "reason":
    discard empty.queryFailure
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  if mode == "code":
    discard empty.codeFailure
    return
  if mode == "preimage":
    discard empty.preimageError
    return
  if mode == "key":
    discard empty.requestError
    return
  if mode == "plan":
    discard empty.planError
    return
  let fixture = collectedNativeFixture()
  var owner = default(Services)
  var input = default(CurrentBlockInput)
  var path = "application-logical-code-proof-chain.json"
  discard startLogicalServices(owner, fixture.fixture, path)
  defer:
    owner.close()
    discard posix.unlink(path.toCString())
  let head = array[32, byte](owner.chainView.bestBlock.value.blockHash)
  let logical = collectManagedSupplied(owner, input, fixture.fixture)
  let source = logical.currentLogicalContext.value.state
  let root = source.commitment.root
  let codeLimits = CodeAvailabilityLimits(services: ElementLimit(2), visits: ElementLimit(128),
      descriptors: ByteLimit(65536), perCode: ByteLimit(65536), totalCodeBytes: ByteLimit(131072))
  let table = auditLogicalCodeAvailability(logical, codeLimits).value.logicalCodeTable
  let limits = LogicalCodeProofLimits(code: codeLimits, keys: ElementLimit(4), bytes: ByteLimit(310))
  let queryLimits = LogicalProofLimits(blocks: ElementLimit(16), viewBytes: ByteLimit(33554432),
      query: logicalProofLimits())
  fail(1)
  var short = limits
  short.keys = ElementLimit(3)
  assert owner.planLogicalCodeProof(logical, ServiceIndex(0), short).error ==
      LogicalCodeProofError.LimitExceeded and calls() == 0
  short = limits
  short.bytes = ByteLimit(309)
  assert planLogicalCodeProof(logical, ServiceIndex(0), short).error ==
      LogicalCodeProofError.LimitExceeded and calls() == 0
  short = limits
  short.code.visits = ElementLimit(0)
  assert planLogicalCodeProof(logical, ServiceIndex(0), short).codeFailure.codeFailure.error ==
      CodeAvailabilityError.LimitExceeded and calls() == 0
  assert planLogicalCodeProof(default(CurrentLogicalState), ServiceIndex(0),
      limits).codeFailure.error == LogicalCodeError.InvalidLogical
  assert planLogicalCodeProof(logical, ServiceIndex(0), limits).codeFailure.codeFailure.error ==
      CodeAvailabilityError.BackendFailure
  assert default(LogicalCodeProof).logicalCodeProofInfo.error == LogicalCodeProofError.InvalidPlan
  assert default(LogicalCodeProof).logicalCodeProofSource.error == LogicalCodeProofError.InvalidPlan
  assert default(LogicalCodeProof).logicalCodeProofKeys.error == LogicalCodeProofError.InvalidPlan
  assert captureLogicalCodeProofQuery(default(LogicalCodeProof), queryLimits).error ==
      LogicalCodeProofError.InvalidPlan
  fail(0)
  assert planLogicalCodeProof(logical, ServiceIndex(high(uint32)), limits).error ==
      LogicalCodeProofError.NoService
  var available = 0
  var absent = 0
  for i in 0..<table.codeAvailabilityInfo.value.services:
    # Each selector derives identity and actual stored length from the original account; no caller guess can request a different history.
    let code = table.serviceCodeAt(i).value
    let plan = owner.planLogicalCodeProof(logical, code.service, limits).value
    let info = plan.logicalCodeProofInfo.value
    assert info.code.service == code.service and info.code.bytes == code.bytes and
        info.code.state == code.state
    assert uint32(info.slot) == logical.currentLogicalContext.value.slot
    assert info.keys == (if code.state == ServiceCodeState.Absent: 3 else: 4)
    fail(1)
    var noHashes = queryLimits
    noHashes.query.hashes = ProofHashLimit(0)
    assert captureLogicalCodeProofQuery(plan, noHashes).queryFailure.error ==
        LogicalProofError.QueryFailure
    let query = captureLogicalCodeProofQuery(plan, queryLimits).value
    assert calls() == 0
    fail(0)
    let direct = executeProofQuery(query).value
    let keptSource = plan.logicalCodeProofSource.value
    let keys = plan.logicalCodeProofKeys.value
    let ticket = owner.beginLogicalProof(keptSource, keys, queryLimits).value
    owner.waitProof()
    assert owner.stateProofActive
    assert owner.collectStateProof(default(ProofWorkerTicket)).kind ==
        ProofWorkerCompletionKind.Uninitialized and owner.stateProofActive
    let completion = owner.collectStateProof(ticket)
    assert completion.kind == ProofWorkerCompletionKind.Completed and not owner.stateProofActive
    let wire = completion.value.value.bytes(queryLimits.query.wireBytes).value
    assert wire == direct.bytes(queryLimits.query.wireBytes).value
    let view = decodePlannedProofs(wire, keys, root, queryLimits.query.view,
        queryLimits.query.proof, queryLimits.query.aggregate, queryLimits.query.wireBytes).value
    assert view.len == info.keys
    let time = view.readProofTime.value
    assert uint32(time) == uint32(info.slot)
    let read = view.readProofCode(code.service, RequestSlot(uint32(time)), ByteLimit(65536))
    if code.state == ServiceCodeState.Available:
      inc available
      assert read.error == ServiceProofError.None and read.value.bytes == table.copyServiceCode(i,
          ByteLimit(65536)).value
      assert read.value.byteLength == int(info.code.bytes)
      assert view.readProofCode(code.service, RequestSlot(uint32(time)), ByteLimit(uint64(
          read.value.byteLength)-1)).error == ServiceProofError.LimitExceeded
    else:
      inc absent
      assert read.error == ServiceProofError.AbsentValue # Existing absent/unavailable semantics are preserved; no fabricated empty code success.
    assert decodePlannedProofs(wire, keys, default(StateRoot), queryLimits.query.view,
        queryLimits.query.proof, queryLimits.query.aggregate, queryLimits.query.wireBytes).error !=
        ProofViewError.None
  assert available > 0 and available+absent == table.codeAvailabilityInfo.value.services
  # A genuine second current execution upgrades metadata to an identity with no stored code preimage; no completed map or result is patched.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  var missingHash = newSeq[byte](32)
  for j in 0..<missingHash.len: missingHash[j] = 231 # Fixed independently selected unavailable code identity enters guest writable memory before execution.
  let upgrades = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
      registerImmediate(9, 123), registerImmediate(10, 456), @[10'u8, 21], @[50'u8, 0]]
  options.secondProgram = @[0'u8]
  for octet in guestEnvelope(upgrades, missingHash): options.secondProgram.add(
      octet) # Actual upgrade changes metadata after original code loading; no state patch supplies the posterior.

  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let missingOrigin = namespaceTransitionFixture(nativeBase(), options)
  let missingFixture = collectMutation(missingOrigin, missingOrigin.services, chapterKey(
      StateChapter(11)))
  let missingLogical = qualifyMutation(missingFixture)
  let missingPlan = planLogicalCodeProof(missingLogical, ServiceIndex(99), limits).value
  let missingInfo = missingPlan.logicalCodeProofInfo.value
  assert missingInfo.code.state == ServiceCodeState.Absent and missingInfo.keys == 3
  let missingRoot = missingLogical.currentLogicalContext.value.state.commitment.root
  let missingQuery = captureLogicalCodeProofQuery(missingPlan, queryLimits).value
  let missingWire = executeProofQuery(missingQuery).value.bytes(queryLimits.query.wireBytes).value
  let missingKeys = missingPlan.logicalCodeProofKeys.value
  let missingView = decodePlannedProofs(missingWire, missingKeys, missingRoot,
      queryLimits.query.view, queryLimits.query.proof, queryLimits.query.aggregate,
      queryLimits.query.wireBytes).value
  let missingTime = missingView.readProofTime.value
  assert uint32(missingTime) == uint32(missingInfo.slot)
  assert missingView.readProofCode(ServiceIndex(99), RequestSlot(uint32(missingTime)), ByteLimit(
      0)).error == ServiceProofError.AbsentValue

  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == head
  owner.close() # Actual join precedes retirement of retained source and selector aliases.
  echo "application-logical-code-proofs: ok"
try:
  main()
except:
  quit(2) # Ordinary fixture/transport failures cannot satisfy strict result-access contracts.
