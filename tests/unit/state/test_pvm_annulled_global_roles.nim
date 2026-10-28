# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_annulled_global_roles_arc_release"}

## Genuine parallel role hosts prove R, annulment, original authority and bounded immutable C(12) selection.
import std/assertions
import std/syncio
import ../../../src/state/accumulation_global_roles as state_accumulation_global_roles
import ../../../src/state/accumulation_annulment as state_accumulation_annulment
import ../../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../../src/state/accumulation_outcome as state_accumulation_outcome
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_privileges as codec_state_privileges
import ../../../src/codec/state_authorization as codec_state_authorization
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/chain/parameters as chain_parameters
import ../../../src/pvm/machine as pvm_machine
import ../../support/state_accumulation_batch_context
import ../../support/state_accumulation_annulment_context
import ../../support/pvm_accumulation_context
import ../../support/pvm_accumulation_program
import ../../support/testing_arc_evidence

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc put(bytes: var seq[byte], value: uint64, width: int) =
  ## Encode independent E4/E8 oracle fields without the production privilege serializer.
  for offset in 0..<width:
    bytes.add(byte((value shr (8*offset)) and 255)) # Explicit fixed widths bound every shift.
proc profile(): Parameters =
  ## Tiny deposits isolate global choices; assign still reads its exact eighty-hash queue.
  var wire = encodeParameters(pvmParameters())
  for index in 0..<24: wire[index] = 0 # Three complete deposit words.
  wire[24] = 2
  wire[25] = 0
  wire[82] = 80
  wire[83] = 0
  decodeParameters(wire).value
proc selfWrite(code: var seq[seq[byte]]) =
  ## A real no-op upgrade marks the invoking account for conflict detection.
  for instruction in @[registerImmediate(7, high(uint64)), registerImmediate(8, 65536),
      registerImmediate(9, 0), registerImmediate(10, 0), @[10'u8, 21]]:
    code.add(instruction) # Only actual executed host facts contribute membership.
proc foreignWrite(code: var seq[seq[byte]], target, owner: uint64) =
  ## Matching prior supervision authorizes a real foreign membership mutation.
  for instruction in @[registerImmediate(7, target), registerImmediate(8, owner), @[10'u8, 29]]:
    code.add(instruction) # Restoring an equal supervisor still records membership.
proc managerProgram(changed, cancelManager, cancelOwner: bool, pairs: int): seq[byte] =
  ## Manager handoffs and allowance values are independent of the original assigner's update.
  var payload: seq[byte] = @[]
  payload.put(if changed: 88'u64 else: 99'u64, 4)
  payload.put(89, 4)
  if pairs > 0:
    payload.put(42, 4)
    payload.put(0, 8) # Present zero gas is not an absent allowance.
  if pairs > 1:
    payload.put(uint64(high(uint32)), 4)
    payload.put(high(uint64), 8) # Preserve full unsigned allowance/service domains.
  var code = @[registerImmediate(7, 99), registerImmediate(8, 196608),
    registerImmediate(9, uint64(high(uint32))-1), registerImmediate(10, 17),
    registerImmediate(11, 196616), registerImmediate(12, uint64(pairs)), @[10'u8, 16]]
  if cancelManager: code.selfWrite() # Selected self membership makes this producer conflict eligible.
  if cancelOwner: code.foreignWrite(99, 42) # The original supervisor marks the junior.
  code.add(@[50'u8, 0])
  guestEnvelope(code, writable = payload)
proc ownerProgram(cancelManager, cancelOwner: bool): seq[byte] =
  ## Original owner changes core zero and staging; its successor never becomes this round's source.
  var payload = newSeq[byte](96)
  for index in 64..<96: payload[index] = byte(index) # Observable queue slot two.
  var code = @[registerImmediate(7, 0), registerImmediate(8, 196608), registerImmediate(9, 77),
    @[10'u8, 17], registerImmediate(7, 196608), registerImmediate(8, 6), @[10'u8, 18]]
  if cancelOwner: code.selfWrite() # Cancel all global effects from this genuine owner together.
  if cancelManager: code.foreignWrite(42, 99) # Reciprocal prior supervision tests original outcome decisions.
  code.add(@[50'u8, 0])
  guestEnvelope(code, writable = payload)
proc seedSupervisor(fixture: var BatchFixture, service, supervisor: uint32) =
  ## Amend the complete authored prior before either real execution captures it.
  let key = chapterServiceKey(StateChapter(255), ServiceIndex(service))
  var metadata = decodeServiceMetadata(fixture.state.snapshot.value.lookup(key).value.bytes,
    ByteLimit(ServiceMetadataBytes)).value.metadata
  metadata.supervisor = ServiceIndex(supervisor)
  let entry = serviceMetadataEntry(ServiceIndex(service), metadata, ByteLimit(
      ServiceMetadataBytes)).value
  assert fixture.state.apply([StateWrite(key: key, kind: StateWriteKind.Put,
    value: entry.value)]).error == StateStoreError.None, "seed genuine prior authority"
proc policy(): AccumulationGlobalRoleLimits =
  ## Chain dimensions and independent work/component/aggregate ceilings are explicit.
  AccumulationGlobalRoleLimits(privileges: PrivilegeConfig(cores: CoreCount(2),
    maxAlways: ElementLimit(2), maxBytes: ByteLimit(128)), outcomes: ElementLimit(2),
    checks: ElementLimit(256), totalBytes: ByteLimit(512))
proc selected(changed, cancelManager, cancelOwner: bool, pairs: int,
    reverse = false): PreparedAccumulationAnnulment =
  ## Only real common-input normalized executions can construct the conflict certificate.
  var fixture = batchFixture(incoming = false,
    firstEnvelope = managerProgram(changed, cancelManager, cancelOwner, pairs),
    secondEnvelope = ownerProgram(cancelManager, cancelOwner), manager = 42,
    assigners = @[ServiceIndex(99), ServiceIndex(99)], delegator = 99, allowanceLimit = 2)
  fixture.seedSupervisor(42, if cancelManager: 99'u32 else: 42'u32)
  fixture.seedSupervisor(99, if cancelOwner: 42'u32 else: 99'u32)
  let a = batchExecution(fixture, 0, parameters = profile(), copyLimit = MemoryByteLimit(4096),
    allowanceLimit = 2, modifiedAccounts = ElementLimit(8))
  let b = batchExecution(fixture, 1, parameters = profile(), copyLimit = MemoryByteLimit(4096),
    allowanceLimit = 2, modifiedAccounts = ElementLimit(8))
  assert a.error == AccumulationDispatchError.None, $a.error
  assert b.error == AccumulationDispatchError.None, $b.error
  let first = normalizeAccumulationOutcome(a).value
  let second = normalizeAccumulationOutcome(b).value
  assert first.outcomeContext.value.effectInfo.value.hasPrivileges, "bless actually executed"
  assert second.outcomeContext.value.effectInfo.value.hasAssignments, "assign actually executed"
  assert second.outcomeContext.value.effectInfo.value.hasStaging, "designate actually executed"
  let originals = if reverse: @[second, first] else: @[first, second]
  prepareAccumulationAnnulment(fixture.inputs, fixture.state.snapshot.value, originals,
    annulmentPolicy()).value
proc check(changed, canceledManager, canceledOwner: bool, pairs: int, reverse = false) =
  ## Independent literal bytes prove the exact R alternatives and complete cancellation projection.
  let source = selected(changed, canceledManager, canceledOwner, pairs, reverse)
  assert source.annulmentInfo.value.annulled == int(canceledManager)+int(canceledOwner)
  failHash(1)
  let plan = prepareAccumulationGlobalRoles(source, policy()).value
  let facts = plan.globalRolesInfo.value
  var expected: seq[byte] = @[]
  expected.put(if canceledManager: 42'u64 else: 99'u64, 4)
  expected.put(if not canceledManager and changed: 88'u64 elif canceledOwner: 99'u64 else: 77'u64, 4)
  expected.put(if canceledManager: 99'u64 else: 89'u64, 4)
  expected.put(if canceledManager: 99'u64 else: uint64(high(uint32))-1, 4)
  expected.put(if canceledManager: 0'u64 else: 17'u64, 4)
  let activePairs = if canceledManager: 0 else: pairs
  expected.add(byte(activePairs))
  if activePairs > 0:
    expected.put(42, 4)
    expected.put(0, 8) # Exact zero-valued entry stays present.
  if activePairs > 1:
    expected.put(uint64(high(uint32)), 4)
    expected.put(high(uint64), 8) # Exact MAX-u64 survives canonical capture.
  assert plan.globalRolesEntry.value.value == expected, "literal independent C(12) oracle"
  assert facts.encodedBytes == expected.len and facts.totalBytes == uint64(21+expected.len)
  assert facts.outcomes == 2 and facts.cores == 2 and facts.always == activePairs
  assert plan.globalRolesSource.value.annulmentInfo.value.annulled == int(canceledManager)+int(canceledOwner)
  if canceledManager:
    assert plan.globalManagerOutcome.error == AccumulationGlobalRoleError.NoOutcome
  else:
    assert uint32(plan.globalManagerOutcome.value.outcomeInfo.value.service) == 42, "original manager stays source after handoff to99"
  let queue = plan.globalAssignerOutcomeAt(PrivilegeCoreIndex(0))
  let staging = plan.globalDelegatorOutcome
  if canceledOwner:
    assert queue.error == AccumulationGlobalRoleError.NoOutcome
    assert staging.error == AccumulationGlobalRoleError.NoOutcome
  else:
    assert uint32(queue.value.outcomeInfo.value.service) == 99, "original assigner supplies queue even after manager handoff"
    let row = queue.value.outcomeContext.value.effectQueues.value
    let marker = row.authorizerAt(AuthorizationCoreIndex(0), AuthorizationIndex(2)).value
    assert marker.bytes[0] == 64, "actual original-owner queue mutation retained"
    let roster = staging.value.outcomeContext.value.effectStaging.value
    assert roster.validatorCount.value == 6, "actual original-delegator roster retained"
    let record = roster.validatorAt(StateValidatorIndex(0)).value
    let bls = array[144, byte](record.bls)
    assert bls[0] == 64, "original delegator supplied actual opaque staging bytes"
  assert plan.globalRegistrarOutcome.error == AccumulationGlobalRoleError.NoOutcome
  let invalidIndex = plan.globalAssignerOutcomeAt(PrivilegeCoreIndex(high(uint64)))
  assert invalidIndex.error == AccumulationGlobalRoleError.InvalidIndex
  var copy = plan.globalRolesEntry.value
  copy.value[0] = 0
  assert plan.globalRolesEntry.value.value == expected, "fresh independent wire buffers"
  var short = policy()
  short.checks = ElementLimit(facts.checks)
  assert prepareAccumulationGlobalRoles(source, short).error == AccumulationGlobalRoleError.None
  short.checks = ElementLimit(facts.checks-1)
  assert prepareAccumulationGlobalRoles(source, short).error ==
      AccumulationGlobalRoleError.LimitExceeded
  short = policy()
  short.outcomes = ElementLimit(1)
  assert prepareAccumulationGlobalRoles(source, short).error ==
      AccumulationGlobalRoleError.LimitExceeded
  short = policy()
  short.totalBytes = ByteLimit(facts.totalBytes-1)
  assert prepareAccumulationGlobalRoles(source, short).error ==
      AccumulationGlobalRoleError.LimitExceeded
  if activePairs > 0:
    short = policy()
    short.privileges.maxAlways = ElementLimit(activePairs-1)
    assert prepareAccumulationGlobalRoles(source, short).error ==
        AccumulationGlobalRoleError.LimitExceeded
    short = policy()
    short.privileges.maxBytes = ByteLimit(expected.len-1)
    assert prepareAccumulationGlobalRoles(source, short).error ==
        AccumulationGlobalRoleError.LimitExceeded
  if canceledManager:
    short = policy()
    short.privileges.maxAlways = ElementLimit(0)
    assert prepareAccumulationGlobalRoles(source, short).error == AccumulationGlobalRoleError.None, "canceled original dictionary consumes no selected copy allowance"
  assert hashCalls() == 0, "selection, queries and refusals never hash state"
  failHash(0)
for changed in [false, true]:
  for canceledManager in [false, true]:
    for canceledOwner in [false, true]:
      for pairs in 0..<3:
        check(changed, canceledManager, canceledOwner,
            pairs) # Cover all manager/owner R and cancellation alternatives.
check(true, false, false, 2, reverse = true)
check(false, true, true, 2, reverse = true)
let invalid = prepareAccumulationGlobalRoles(default(PreparedAccumulationAnnulment), policy())
assert invalid.error == AccumulationGlobalRoleError.InvalidSource
let absent = default(PreparedAccumulationGlobalRoles)
assert absent.globalRolesInfo.error == AccumulationGlobalRoleError.Uninitialized
assert absent.globalRolesPrivileges.error == AccumulationGlobalRoleError.Uninitialized
let fixture = batchFixture(incoming = false)
let identity = prepareAccumulationAnnulment(fixture.inputs, fixture.state.snapshot.value, [],
  default(AccumulationAnnulmentLimits)).value
let unchanged = prepareAccumulationGlobalRoles(identity, policy()).value
assert unchanged.globalRolesInfo.value.outcomes == 0 and unchanged.globalRolesInfo.value.always == 0
assert unchanged.globalManagerOutcome.error == AccumulationGlobalRoleError.NoOutcome
var wrongProfile = policy()
wrongProfile.privileges.cores = CoreCount(0)
assert prepareAccumulationGlobalRoles(identity, wrongProfile).error ==
    AccumulationGlobalRoleError.InvalidConfig
# Missing and malformed complete chapters are distinct from an initialized empty producer set.
for malformed in [false, true]:
  var changed = fixture.state
  let key = chapterKey(StateChapter(12))
  let mutation = if malformed: StateWrite(key: key, kind: StateWriteKind.Put, value: @[0'u8])
    else: StateWrite(key: key, kind: StateWriteKind.Delete)
  assert changed.apply([mutation]).error == StateStoreError.None, "author an actual invalid complete prior"
  let emptySource = prepareAccumulationAnnulment(fixture.inputs, changed.snapshot.value, [],
    default(AccumulationAnnulmentLimits)).value
  let refused = prepareAccumulationGlobalRoles(emptySource, policy())
  let expectedError = if malformed: AccumulationGlobalRoleError.MalformedState
    else: AccumulationGlobalRoleError.InvalidState
  assert refused.error == expectedError, "missing/malformed C(12) never becomes identity defaults"
let source = selected(true, false, false, 2)
let before = getOccupiedMem()
for iteration in 0..<1000:
  let local = prepareAccumulationGlobalRoles(source, policy()).value
  assert local.globalRolesInfo.value.always == 2
  assert local.globalRolesEntry.value.value.len ==
      45 # Fresh snapshots, entry buffers and source owners release together.
let after = getOccupiedMem()
assert before == after, "global selection ARC ownership releases"
recordArcRelease("pvm_annulled_global_roles", 1000, before, after)
echo "PVM annulled global roles passed"
echo "ARC_RELEASE cycles=1000 unchanged"
