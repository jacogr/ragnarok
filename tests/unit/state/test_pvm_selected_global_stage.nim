# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_selected_global_stage_arc_release"}

## Signed bless/assign/designate hosts preserve original payload authority across handoff and annulment.
import std/[assertions, envvars, syncio]
import ../../../src/codec/[bounded, composite, report_owned, state_layout, state_authorization,
  state_privileges, state_safrole, c2_records]
import ../../../src/pvm/[machine, step, gas]
import ../../../src/state/[accumulation_global_stage, accumulation_global_roles,
  accumulation_provision_stage, accumulation_provisions, accumulation_account_stage,
  accumulation_block_guests, accumulation_guest_runner, store]
import ../../support/[accumulation_execution_context, accumulation_current_guests_context,
  pvm_accumulation_program, pvm_accumulation_provision, arc_evidence]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc policy(): AccumulationGlobalStageLimits =
  ## Fixed two-core queues and six-validator rosters have independent original/output byte and work caps.
  AccumulationGlobalStageLimits(roles: AccumulationGlobalRoleLimits(
    privileges: PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(2),
        maxBytes: ByteLimit(1000)),
    outcomes: ElementLimit(2), checks: ElementLimit(256), totalBytes: ByteLimit(2000)),
    queues: AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(160),
        maxBytes: ByteLimit(5120)),
    staging: ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
        maxBytes: ByteLimit(2017)),
    totalBytes: ByteLimit(20000))
proc code(instructions: seq[seq[byte]], payload: seq[byte]): seq[byte] =
  ## Complete service framing preserves actual PVM guest code and independently authored payloads.
  result = @[0'u8]
  for octet in guestEnvelope(instructions, writable = payload): result.add(
      octet) # Exact canonical service metadata prefix.
proc fixture(base: OwnedReport, cancel = false): ExecutionFixture =
  ## Original manager42 hands roles away; original owner99 still supplies both global payloads unless N annuls it.
  var options = executionFixtureConfig()
  options.manager = 42
  options.assigner = 99
  options.delegator = 99
  options.secondSupervisor = 42
  var manager = @[registerImmediate(7, 99), registerImmediate(8, 196608), registerImmediate(9, 88),
    registerImmediate(10, 17), registerImmediate(11, 0), registerImmediate(12, 0), @[10'u8, 16]]
  if cancel:
    manager.add(registerImmediate(7, 99))
    manager.add(registerImmediate(8, 42))
    manager.add(@[10'u8, 29]) # Genuine prior supervisor membership conflicts with the junior's self modification.
  manager.add(@[50'u8, 0])
  options.firstProgram = code(manager, @[88'u8, 0, 0, 0, 89, 0, 0, 0])
  var payload = newSeq[byte](96)
  for index in 64..<96: payload[index] = byte(index) # Distinct ordered queue hash and roster opaque bytes.
  var owner = @[registerImmediate(7, 0), registerImmediate(8, 196608), registerImmediate(9, 77), @[
      10'u8, 17],
    registerImmediate(7, 196608), registerImmediate(8, 6), @[10'u8, 18]]
  if cancel:
    for instruction in @[registerImmediate(7, high(uint64)), registerImmediate(8, 65536),
      registerImmediate(9, 0), registerImmediate(10, 0), @[10'u8, 21]]:
      owner.add(instruction) # Actual self upgrade makes N cancel original global effects.
  owner.add(@[50'u8, 0])
  options.secondProgram = code(owner, payload)
  executionFixture(base, options)
proc provisions(fixture: ExecutionFixture): PreparedAccumulationProvisionStage =
  ## Ready guests capture strict facts before complete selected accounts and original provision fulfillment.
  var limits = currentGuestLimits()
  limits.steps = ExecutionStepLimit(200)
  limits.calls = HostCallLimit(32)
  limits.copyBytes = MemoryByteLimit(4096)
  limits.modifiedAccounts = ElementLimit(8)
  limits.accountWriteFacts = ElementLimit(8)
  let guests = runBlockAccumulationGuests(fixture.round, currentGuestParameters(), limits)
  assert guests.error == BlockGuestError.None, $guests.error
  let accounts = prepareAccumulationAccountStage(guests.value, currentAccountStageLimits()).value
  prepareAccumulationProvisionStage(accounts, AccumulationProvisionUnionLimits(
      contexts: ElementLimit(2),
    values: PreimageLimits(items: ElementLimit(0), perBlob: ByteLimit(0), totalBlobBytes: ByteLimit(
        0)), encodedBytes: ByteLimit(8))).value
proc main() {.raises.} =
  ## Native fixture generation retains actual report/admission cryptography before any guest or global selection.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve exact prepared report bytes.
  let base = decodeOwnedReport(wire, 2).value
  let authored = fixture(base)
  let source = provisions(authored)
  let before = source.provisionStageSnapshot.value
  let prepared = prepareAccumulationGlobalStage(source, policy())
  assert prepared.error == AccumulationGlobalStageError.None, $prepared.error
  let stage = prepared.value
  let info = stage.globalStageInfo.value
  assert info.cores == 2 and info.validators == 6
  let roles = stage.globalStageRoles.value.globalRolesPrivileges.value
  assert uint32(roles.privilegeInfo.value.manager) == 99
  assert uint32(roles.privilegeInfo.value.delegator) == 88
  assert uint32(roles.privilegeAssignerAt(PrivilegeCoreIndex(0)).value) == 88, "manager override wins R"
  let snapshot = stage.globalStageSnapshot.value
  let queues = decodeAuthorization(AuthorizationKind.Queues, snapshot.lookup(chapterKey(
      StateChapter(2))).value.bytes, policy().queues).value.snapshot
  let marker = queues.authorizerAt(AuthorizationCoreIndex(0), AuthorizationIndex(2)).value.bytes
  for index in 0..<32: assert marker[index] == byte(
      index+64) # Original99 supplies payload despite posterior assigner88.
  let roster = snapshot.lookup(chapterKey(StateChapter(7))).value.bytes
  assert roster[65] == 64 and roster[96] == 95, "original99 supplies staging despite posterior delegator88"
  let canceledFixture = fixture(base, cancel = true)
  let canceled = provisions(canceledFixture)
  let canceledStage = prepareAccumulationGlobalStage(canceled, policy()).value
  for chapter in [2'u8, 7'u8]:
    let key = chapterKey(StateChapter(chapter))
    assert canceledStage.globalStageSnapshot.value.lookup(key).value.bytes ==
        canceledFixture.state.snapshot.value.lookup(key).value.bytes, "annulled original owner leaves prior payload"
  assert uint32(canceledStage.globalStageRoles.value.globalRolesPrivileges.value.privilegeInfo.value.delegator) == 88
  var limits = policy()
  limits.totalBytes = ByteLimit(0)
  assert prepareAccumulationGlobalStage(source, limits).error ==
      AccumulationGlobalStageError.LimitExceeded
  limits = policy()
  limits.queues.cores = CoreCount(3)
  assert prepareAccumulationGlobalStage(source, limits).error ==
      AccumulationGlobalStageError.InvalidConfig
  limits = policy()
  limits.queues.maxBytes = ByteLimit(5119)
  let queueFailure = prepareAccumulationGlobalStage(source, limits)
  assert queueFailure.error == AccumulationGlobalStageError.QueueFailure
  assert queueFailure.queueFailure == AuthorizationError.LimitExceeded
  limits = policy()
  limits.staging.maxBytes = ByteLimit(2016)
  let stagingFailure = prepareAccumulationGlobalStage(source, limits)
  assert stagingFailure.error == AccumulationGlobalStageError.StagingFailure
  assert stagingFailure.stagingFailure == StateComponentError.LimitExceeded
  failHash(1)
  let backend = prepareAccumulationGlobalStage(source, policy())
  assert backend.error == AccumulationGlobalStageError.StoreFailure
  assert backend.storeFailure == StateStoreError.BackendFailure
  failHash(0)
  assert sameStateSnapshot(source.provisionStageSnapshot.value, before), "late global hash refusal never publishes a prefix"
  let refused = prepareAccumulationGlobalStage(default(PreparedAccumulationProvisionStage), policy())
  assert refused.error == AccumulationGlobalStageError.InvalidSource
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareAccumulationGlobalStage(source, policy()).value
    assert local.globalStageInfo.value.cores == 2 # Complete canonical payloads and private Merkle forks release together.
  let after = getOccupiedMem()
  assert occupied == after, "global phase owners release"
  recordArcRelease("pvm_selected_global_stage", 1000, occupied, after)
  echo "PVM selected global stage passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Admission, guest or native setup failures cannot become an empty successful phase.
except:
  quit(2)
