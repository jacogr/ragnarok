# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_selected_provision_stage_arc_release"}

## Signed new/provide and real annulled producers fulfill original provisions over complete selected accounts.
import std/[assertions, envvars, syncio]
import ../../../src/codec/[bounded, composite, report_owned]
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    service_values as state_service_values]
import ../../../src/crypto/primitives
import ../../../src/pvm/[machine, step, gas]
import ../../../src/state/accumulation/provision/stage as accumulation_provision_stage
import ../../../src/state/accumulation/provisions as accumulation_provisions
import ../../../src/state/accumulation/account/stage as accumulation_account_stage
import "../../../src/state/accumulation/block/guests" as accumulation_block_guests
import ../../../src/state/accumulation/[guest_runner as accumulation_guest_runner,
    coverage as accumulation_coverage, annulment as accumulation_annulment,
    creation_union as accumulation_creation_union]
import ../../../src/state/store
import ../../support/[accumulation_execution_context, accumulation_runner_context,
  accumulation_current_guests_context, pvm_accumulation_program, pvm_accumulation_provision, arc_evidence]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc policy(): AccumulationProvisionUnionLimits =
  ## Two original producers and one actual byte remain separate traversal, blob and frame ceilings.
  AccumulationProvisionUnionLimits(contexts: ElementLimit(2),
    values: PreimageLimits(items: ElementLimit(2), perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(2)),
    encodedBytes: ByteLimit(128))
proc serviceCode(code: seq[byte]): seq[byte] =
  ## Keep service preimage framing independent from actual guest instruction assembly.
  result = @[0'u8]
  for octet in code: result.add(octet) # Exact canonical metadata prefix before the authored envelope.
proc creationCode(): seq[byte] =
  ## Actual new returns the child in r7; provide uses that real result to target its freshly created request.
  let hash = array[32, byte](blake2b256([73'u8]).value)
  var payload = newSeq[byte](60)
  for index in 0..<32: payload[index] = hash[index] # New code hash matches the independently supplied read-only byte.
  payload[32] = 1
  serviceCode(guestEnvelope([registerImmediate(7, high(uint64)), registerImmediate(8, high(uint64)),
    registerImmediate(9, 0), registerImmediate(10, 196608), @[10'u8, 20],
    registerImmediate(8, 65536), registerImmediate(9, 1), @[10'u8, 28], @[50'u8, 0]],
        writable = payload))
proc accounts(fixture: ExecutionFixture): PreparedAccumulationAccountStage =
  ## Production guest dispatch captures strict facts before complete private M/n application.
  var limits = currentGuestLimits()
  limits.steps = ExecutionStepLimit(200)
  limits.calls = HostCallLimit(32)
  limits.copyBytes = MemoryByteLimit(128)
  limits.modifiedAccounts = ElementLimit(8)
  limits.accountWriteFacts = ElementLimit(8)
  limits.provisions = provisionPolicy(items = 2, perBlob = 1, total = 2)
  let guests = runBlockAccumulationGuests(fixture.round, currentGuestParameters(), limits)
  assert guests.error == BlockGuestError.None, $guests.error
  let stage = prepareAccumulationAccountStage(guests.value, currentAccountStageLimits())
  assert stage.error == AccumulationAccountStageError.None, $stage.error
  stage.value
proc main() {.raises.} =
  ## Static reports pass maintained signature/admission fixtures; all terminal effects originate in actual guest opcodes.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Exact binary transport preserves fixture provenance.
  let base = decodeOwnedReport(wire, 2).value
  var options = executionFixtureConfig()
  options.firstProgram = creationCode()
  let fixture = executionFixture(base, options)
  let source = accounts(fixture)
  let child = source.accountStageCreation.value.createdAccountAt(AccumulationCreationIndex(
      0)).value.service
  let hash = ServicePreimageHash(array[32, byte](blake2b256([73'u8]).value))
  let key = servicePreimageKey(child, hash, ByteLimit(32)).value
  let before = source.accountStageSnapshot.value
  assert before.lookup(key).error == StateStoreError.MissingKey
  let prepared = prepareAccumulationProvisionStage(source, policy())
  assert prepared.error == AccumulationProvisionStageError.None, $prepared.error
  let stage = prepared.value
  assert stage.provisionStagePlan.value.provisionPlanInfo.value.items == 1
  assert stage.provisionStageSnapshot.value.lookup(key).value.bytes == @[73'u8]
  assert source.accountStageSnapshot.value.lookup(key).error == StateStoreError.MissingKey
  assert sameStateSnapshot(fixture.state.snapshot.value,
    source.accountStageGuests.value.guestCoverage.value.coverageAnnulment.value.annulmentPrior.value)
  var conflict = executionFixtureConfig()
  conflict.secondSupervisor = 42
  conflict.firstProgram = serviceCode(guestEnvelope([registerImmediate(7, 99), registerImmediate(8,
      42), @[10'u8, 29], @[50'u8, 0]]))
  conflict.secondProgram = serviceCode(guestEnvelope([registerImmediate(7, 42), registerImmediate(8,
      65536), registerImmediate(9, 1), @[10'u8, 28], @[10'u8, 19],
    registerImmediate(7, high(uint64)), registerImmediate(8, 65536), registerImmediate(9, 0),
        registerImmediate(10, 0), @[10'u8, 21], @[50'u8, 0]]))
  conflict.signed.extra = @[provisionRequest(42, @[73'u8])]
  let canceledFixture = executionFixture(base, conflict)
  let canceled = accounts(canceledFixture)
  let original = canceled.accountStageGuests.value.guestCoverage.value.coverageAnnulment.value
  assert original.annulmentInfo.value.annulled == 1
  let retained = prepareAccumulationProvisionStage(canceled, policy()).value
  assert retained.provisionStagePlan.value.provisionPlanInfo.value.items == 1
  let parentKey = servicePreimageKey(ServiceIndex(42), hash, ByteLimit(32)).value
  assert retained.provisionStageSnapshot.value.lookup(parentKey).value.bytes == @[73'u8], "N retains original provision contributions"
  var limits = policy()
  limits.contexts = ElementLimit(1)
  assert prepareAccumulationProvisionStage(source, limits).error ==
      AccumulationProvisionStageError.LimitExceeded
  limits = policy()
  limits.values.items = ElementLimit(0)
  let exhausted = prepareAccumulationProvisionStage(source, limits)
  assert exhausted.error == AccumulationProvisionStageError.ProvisionFailure
  assert exhausted.provisionFailure == AccumulationProvisionError.LimitExceeded
  failHash(1)
  let backend = prepareAccumulationProvisionStage(source, policy())
  assert backend.error == AccumulationProvisionStageError.ProvisionFailure
  assert backend.provisionFailure == AccumulationProvisionError.BackendFailure
  failHash(0)
  assert sameStateSnapshot(source.accountStageSnapshot.value, before), "hash refusal preserves the selected account phase"
  let quiet = accounts(executionFixture(base))
  let empty = prepareAccumulationProvisionStage(quiet, policy()).value
  assert empty.provisionStagePlan.value.provisionPlanInfo.value.items == 0
  assert sameStateSnapshot(empty.provisionStageSnapshot.value, quiet.accountStageSnapshot.value)
  let refused = prepareAccumulationProvisionStage(default(PreparedAccumulationAccountStage), policy())
  assert refused.error == AccumulationProvisionStageError.InvalidSource
  assert default(PreparedAccumulationProvisionStage).provisionStageSnapshot.error ==
      AccumulationProvisionStageError.Uninitialized
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareAccumulationProvisionStage(source, policy()).value
    assert local.provisionStageSnapshot.value.lookup(key).value.bytes == @[
        73'u8] # Owned unions and private inherited stores release after actual fulfillment.
  let after = getOccupiedMem()
  assert occupied == after, "provision phase owners release"
  recordArcRelease("pvm_selected_provision_stage", 1000, occupied, after)
  echo "PVM selected provision stage passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Missing fixtures and admission/backend exceptions must fail the native suite.
except:
  quit(2)
