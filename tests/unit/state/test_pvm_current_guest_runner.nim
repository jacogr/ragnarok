# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_guest_runner_arc_release"}

## Actual current guests connect creation, skipped credit and absent identity to complete provider and selected-state proofs.
import std/[assertions, syncio]
import ../../../src/state/[accumulation_guest_runner, accumulation_coverage, accumulation_annulment,
  accumulation_account_selection, accumulation_creation_union, accumulation_selected_writes,
  accumulation_annulled_outputs, accumulation_global_roles, accumulation_inputs,
  accumulation_service,
  accumulation_invocation, accumulation_context, accumulation_machine, accumulation_dispatch,
  accumulation_outcome, accumulation_skip, accumulation_absent, store]
import ../../../src/codec/[bounded, composite, header, state_accounts, state_privileges,
  state_outputs,
  state_safrole, state_layout, c2_records]
import ../../../src/chain/parameters
import ../../../src/pvm/[initialize, program, machine, step, gas, host_fetch]
import ../../support/[accumulation_batch_context, accumulation_annulment_context,
  pvm_accumulation_context, pvm_accumulation_program, pvm_accumulation_provision, arc_evidence]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc profile(): Parameters =
  ## The explicit caller profile matches the original two-core/eighty-queue context and zero fixture deposits.
  var wire = encodeParameters(pvmParameters())
  for index in 0..<24: wire[index] = 0 # Independent complete deposit words.
  wire[24] = 2
  wire[25] = 0
  wire[82] = 80
  wire[83] = 0
  for index in 110..<114: wire[index] = 0 # Full current E4 memo extent.
  wire[110] = 128
  decodeParameters(wire).value
proc policy(): AccumulationGuestLimits =
  ## Local runtime/proof ceilings are independent of protocol prices and code eligibility in Parameters.
  AccumulationGuestLimits(services: ElementLimit(3), preimageBytes: ByteLimit(1024),
      probes: ServiceProbeLimit(1),
    initialization: InitializationLimits(envelope: InitializationByteLimit(512),
        program: ProgramByteLimit(256),
      jumps: JumpCountLimit(0), pages: PageLimit(5)), contexts: pvmContextConfig(),
    fetch: FetchAccumulationLimits(items: ElementLimit(2), bytes: ByteLimit(512),
        operand: OperandLimits(maxBytes: ByteLimit(512))),
    copyBytes: MemoryByteLimit(128), steps: ExecutionStepLimit(200), calls: HostCallLimit(32),
        cycles: GasCycleLimit(10000),
    provisions: provisionPolicy(items = 2, perBlob = 1, total = 2), transfers: ElementLimit(2),
    accountWriteKeys: ElementLimit(4), createdAccounts: ElementLimit(2),
        deletedAccounts: ElementLimit(2),
    modifiedAccounts: ElementLimit(8), accountWriteFacts: ElementLimit(8),
    annulment: AccumulationAnnulmentLimits(outcomes: ElementLimit(3), modified: ElementLimit(24),
        checks: ElementLimit(256)),
    coverage: AccumulationCoverageLimits(services: ElementLimit(3), executed: ElementLimit(3),
        skipped: ElementLimit(3),
      absent: ElementLimit(3), checks: ElementLimit(256), gas: Gas(300000)))
proc mixedInputs(source: PreparedAccumulationInputs, executing = true): PreparedAccumulationInputs =
  ## The absent input has maximal offered gas; actual consumption still counts only real execution.
  var allowances: seq[AlwaysAccumulate] = @[]
  if executing: allowances.add(AlwaysAccumulate(service: ServiceIndex(42), gas: PrivilegeGas(
      100000))) # One real ready guest.
  allowances.add(AlwaysAccumulate(service: ServiceIndex(77), gas: PrivilegeGas(100000)))
  allowances.add(AlwaysAccumulate(service: ServiceIndex(123), gas: PrivilegeGas(high(uint64))))
  prepareAccumulationInputs(source.invocationOperands.value,
    [DeferredTransfer(source: ServiceIndex(7), destination: ServiceIndex(77),
        amount: TransferBalance(5), destinationSupervisor: true)],
    allowances, AccumulationInputConfig(inputs: ElementLimit(1), allowances: ElementLimit(3),
        services: ElementLimit(3))).value
proc fixture(): BatchFixture =
  ## Genuine new allocates from the common prior while77 lacks code and123 lacks its account.
  var payload = newSeq[byte](60)
  payload[32] = 1 # Exact packed request length; all funding/minimum-gas fields are zero.
  let code = guestEnvelope([registerImmediate(7, high(uint64)), registerImmediate(8, high(uint64)),
    registerImmediate(9, 0), registerImmediate(10, 196608), @[10'u8, 20], @[50'u8, 0]],
        writable = payload)
  let target = serviceMetadataEntry(ServiceIndex(77), ServiceMetadata(balance: AccountBalance(10)),
      ByteLimit(ServiceMetadataBytes)).value
  result = batchFixture(incoming = false, firstEnvelope = code, extra = @[target])
  result.inputs = mixedInputs(result.inputs)
proc run(source: BatchFixture, limits = policy()): AccumulationGuestResult =
  ## The pure runner receives explicit immutable source/profile choices; no block or completed publication owner is forged.
  runAccumulationGuests(source.inputs, source.state.snapshot.value, HeaderSlot(128), default(
      StateEntropyWord), profile(), limits)
let source = fixture()
let prior = source.state.snapshot.value
let completed = run(source)
assert completed.error == AccumulationGuestError.None, $completed.error
let coverage = completed.value
let info = coverage.coverageInfo.value
assert info.services == 3 and info.executed == 1 and info.skipped == 1 and info.absent == 1, "current guest check: info.services == 3 and info.executed == 1 and info.skipped == 1 and info.absent == 1"
assert uint64(info.gasUsed) > 3855, "actual new host and instruction prices are consumed"
assert coverage.coverageRowAt(AccumulationCoverageIndex(0)).value.kind ==
    AccumulationCoverageKind.Executed, "current guest check: coverage.coverageRowAt(AccumulationCoverageIndex(0)).value.kind =="
assert coverage.coverageRowAt(AccumulationCoverageIndex(1)).value.kind ==
    AccumulationCoverageKind.CodeUnavailable, "current guest check: coverage.coverageRowAt(AccumulationCoverageIndex(1)).value.kind =="
assert coverage.coverageRowAt(AccumulationCoverageIndex(2)).value.kind ==
    AccumulationCoverageKind.Absent, "current guest check: coverage.coverageRowAt(AccumulationCoverageIndex(2)).value.kind =="
assert sameStateSnapshot(coverage.coverageAbsentAt(AccumulationCoverageIndex(
    2)).value.absentState.value, prior), "current guest check: sameStateSnapshot(coverage.coverageAbsentAt(AccumulationCoverageIndex("
assert sameStateSnapshot(source.state.snapshot.value, prior), "successful guest work never mutates the caller"
# The returned genuine proofs feed every new selected-state layer without executing guests again.
let original = coverage.coverageAnnulment.value
let skipped = coverage.coverageSkippedAt(AccumulationCoverageIndex(1)).value
failHash(1)
let m = prepareAccumulationAccountSelection(original, [ServiceIndex(42), ServiceIndex(77)],
  AccumulationAccountSelectionLimits(accounts: ElementLimit(2), outcomes: ElementLimit(1),
      skipped: ElementLimit(1), checks: ElementLimit(256)), [skipped]).value
let n = prepareAccumulationCreationUnion(original, AccumulationCreationLimits(
    outcomes: ElementLimit(1), creations: ElementLimit(1),
  accounts: ElementLimit(1), checks: ElementLimit(128))).value
assert n.creationUnionInfo.value.accounts == 1, "current guest check: n.creationUnionInfo.value.accounts == 1"
assert uint64(m.selectedAccountMetadataAt(AccumulationAccountSelectionIndex(
    1)).value.supervisorBalance) == 5, "actual protected skipped credit feeds M"
let writes = prepareSelectedAccountWrites(m, n, SelectedAccountWriteLimits(accounts: ElementLimit(
    3), facts: ElementLimit(6),
  writes: ElementLimit(4), checks: ElementLimit(256), valueBytes: ByteLimit(316))).value
assert writes.selectedWritesInfo.value.writes == 4 and writes.selectedWritesInfo.value.valueBytes == 316,
  "actual parent, credited skip, child metadata and code-request descriptors"
let outputs = prepareAnnulmentOutputs(original, AnnulmentOutputLimits(outcomes: ElementLimit(1),
  log: OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(1)))).value
assert outputs.annulmentOutputsInfo.value.outputs == 0, "current guest check: outputs.annulmentOutputsInfo.value.outputs == 0"
let roles = prepareAccumulationGlobalRoles(original, AccumulationGlobalRoleLimits(
    outcomes: ElementLimit(1), checks: ElementLimit(64),
  totalBytes: ByteLimit(42), privileges: PrivilegeConfig(cores: CoreCount(2),
      maxAlways: ElementLimit(0), maxBytes: ByteLimit(21)))).value
assert roles.globalRolesEntry.value.value == prior.lookup(chapterKey(StateChapter(12))).value.bytes, "current guest check: roles.globalRolesEntry.value.value == prior.lookup(chapterKey(StateChapter(12))).value.bytes"
assert hashCalls() == 0, "all downstream selections reuse genuine execution proofs without hashing or replaying guests"
failHash(0)
# Every typed failure keeps source state unchanged and cannot expose an earlier successful provider.
for mode in 0..<8:
  var short = policy()
  case mode
  of 0: short.services = ElementLimit(2) # Total resolution work refuses before any guest.
  of 1: short.modifiedAccounts = ElementLimit(0) # Current original modified sets cannot be disabled for ready code.
  of 2: short.preimageBytes = ByteLimit(0) # Local ready-code capture is distinct from protocol unavailable code.
  of 3: short.contexts.totalBytes = ByteLimit(0) # Context capture refuses before machine execution.
  of 4: short.initialization.envelope = InitializationByteLimit(
      0) # Actual ready machine setup retains its own reason.
  of 5: short.steps = ExecutionStepLimit(0) # Runtime quotas never become fake successful panic/skip results.
  of 6: short.annulment.modified = ElementLimit(0) # A successful actual new still needs its original membership proof ceiling.
  else: short.coverage.gas = Gas(0) # Original consumed gas must fit complete coverage even after private guest work.
  let refused = run(source, short)
  case mode
  of 0: assert refused.error == AccumulationGuestError.LimitExceeded,
      "current guest check: refused.error == AccumulationGuestError.LimitExceeded mode=" & $mode &
      " error=" & $refused.error
  of 1: assert refused.error == AccumulationGuestError.ModifiedAccountsDisabled,
      "current guest check: refused.error == AccumulationGuestError.ModifiedAccountsDisabled mode=" &
      $mode & " error=" & $refused.error
  of 2:
    assert refused.error == AccumulationGuestError.ServiceFailure,
        "current guest check: refused.error == AccumulationGuestError.ServiceFailure mode=" &
        $mode & " error=" & $refused.error
    assert refused.serviceFailure == AccumulationServiceError.LimitExceeded,
        "current guest check: refused.serviceFailure == AccumulationServiceError.LimitExceeded mode=" &
        $mode & " error=" & $refused.error
  of 3:
    assert refused.error == AccumulationGuestError.ContextFailure,
        "current guest check: refused.error == AccumulationGuestError.ContextFailure mode=" &
        $mode & " error=" & $refused.error
    assert refused.contextFailure == AccumulationContextError.LimitExceeded,
        "current guest check: refused.contextFailure == AccumulationContextError.LimitExceeded mode=" &
        $mode & " error=" & $refused.error
  of 4:
    assert refused.error == AccumulationGuestError.MachineFailure,
        "current guest check: refused.error == AccumulationGuestError.MachineFailure mode=" &
        $mode & " error=" & $refused.error
    assert refused.machineFailure == AccumulationMachineError.LimitExceeded,
        "current guest check: refused.machineFailure == AccumulationMachineError.LimitExceeded mode=" &
        $mode & " error=" & $refused.error
  of 5:
    assert refused.error == AccumulationGuestError.DispatchFailure,
        "current guest check: refused.error == AccumulationGuestError.DispatchFailure mode=" &
        $mode & " error=" & $refused.error
    assert refused.dispatchFailure.error == AccumulationDispatchError.ExecutionFailure, "retain actual engine failure"
    assert refused.dispatchFailure.executionError == StepError.StepLimitExceeded, "retain the exact step scheduling refusal"

  of 6:
    assert refused.error == AccumulationGuestError.AnnulmentFailure,
        "current guest check: refused.error == AccumulationGuestError.AnnulmentFailure mode=" &
        $mode & " error=" & $refused.error
    assert refused.annulmentFailure == AccumulationAnnulmentError.LimitExceeded,
        "current guest check: refused.annulmentFailure == AccumulationAnnulmentError.LimitExceeded mode=" &
        $mode & " error=" & $refused.error
  else:
    assert refused.error == AccumulationGuestError.CoverageFailure,
        "current guest check: refused.error == AccumulationGuestError.CoverageFailure mode=" &
        $mode & " error=" & $refused.error
    assert refused.coverageFailure == AccumulationCoverageError.GasExceeded,
        "current guest check: refused.coverageFailure == AccumulationCoverageError.GasExceeded mode=" &
        $mode & " error=" & $refused.error
  assert sameStateSnapshot(source.state.snapshot.value, prior), "refusal publishes no earlier successful guest state"
assert runAccumulationGuests(default(PreparedAccumulationInputs), prior, HeaderSlot(0), default(
    StateEntropyWord), profile(), policy()).error == AccumulationGuestError.InvalidInputs, "current guest check: runAccumulationGuests(default(PreparedAccumulationInputs), prior, HeaderSlot(0), default("
assert runAccumulationGuests(source.inputs, default(StateStoreSnapshot), HeaderSlot(0), default(
    StateEntropyWord), profile(), policy()).error == AccumulationGuestError.InvalidState, "current guest check: runAccumulationGuests(source.inputs, default(StateStoreSnapshot), HeaderSlot(0), default("
assert runAccumulationGuests(source.inputs, prior, HeaderSlot(0), default(StateEntropyWord),
    default(Parameters), policy()).error == AccumulationGuestError.InvalidParameters, "current guest check: runAccumulationGuests(source.inputs, prior, HeaderSlot(0), default(StateEntropyWord),"
var wrongProfile = policy()
wrongProfile.contexts.queues.cores = CoreCount(3)
assert run(source, wrongProfile).error == AccumulationGuestError.InvalidParameters, "current guest check: run(source, wrongProfile).error == AccumulationGuestError.InvalidParameters"
failHash(1)
let backend = run(source)
assert backend.error == AccumulationGuestError.ServiceFailure and backend.serviceFailure ==
    AccumulationServiceError.BackendFailure, "current guest check: backend.error == AccumulationGuestError.ServiceFailure and backend.serviceFailure =="
failHash(0)
var malformed = source
assert malformed.state.apply([StateWrite(key: chapterServiceKey(StateChapter(255), ServiceIndex(
    77)), kind: StateWriteKind.Put,
  value: @[0'u8])]).error == StateStoreError.None, "current guest check: malformed.state.apply([StateWrite(key: chapterServiceKey(StateChapter(255), ServiceIndex("
let malformedPrior = malformed.state.snapshot.value
let laterFailure = run(malformed)
assert laterFailure.error == AccumulationGuestError.ServiceFailure and
    laterFailure.serviceFailure == AccumulationServiceError.MalformedAccount,
  "a later malformed account does not release the already successful creator as complete coverage"
assert sameStateSnapshot(malformedPrior, malformed.state.snapshot.value), "current guest check: sameStateSnapshot(malformedPrior, malformed.state.snapshot.value)"
# Present ready code with malformed VM structure is a machine failure, not an unavailable-code completion.
let invalidProgram = batchFixture(incoming = false, firstEnvelope = pvmEnvelope(@[0'u8]))
let invalid = run(invalidProgram)
assert invalid.error == AccumulationGuestError.MachineFailure and invalid.machineFailure ==
    AccumulationMachineError.InvalidProgram, "current guest check: invalid.error == AccumulationGuestError.MachineFailure and invalid.machineFailure =="
# Optional downstream capture gates remain explicit even though current guest execution itself is successful.
var noCreation = policy()
noCreation.createdAccounts = ElementLimit(0)
let locallyCreated = run(source, noCreation)
assert locallyCreated.error == AccumulationGuestError.None, "current guest check: locallyCreated.error == AccumulationGuestError.None"
let incomplete = prepareAccumulationCreationUnion(locallyCreated.value.coverageAnnulment.value,
  AccumulationCreationLimits(outcomes: ElementLimit(1), creations: ElementLimit(1),
      accounts: ElementLimit(1), checks: ElementLimit(128)))
assert incomplete.error == AccumulationCreationError.IncompleteFacts, "current guest check: incomplete.error == AccumulationCreationError.IncompleteFacts"
# Neither no-execution alternative depends on guest/machine/context copy budgets or enabled modification tracing.
var uninvoked = source
uninvoked.inputs = mixedInputs(source.inputs, executing = false)
var zero = policy()
zero.modifiedAccounts = ElementLimit(0)
zero.preimageBytes = ByteLimit(0)
zero.initialization = default(InitializationLimits)
zero.contexts.totalBytes = ByteLimit(0)
zero.steps = ExecutionStepLimit(0)
zero.calls = HostCallLimit(0)
zero.coverage.gas = Gas(0)
let noGuest = run(uninvoked, zero)
assert noGuest.error == AccumulationGuestError.None, "current guest check: noGuest.error == AccumulationGuestError.None"
assert noGuest.value.coverageInfo.value.executed == 0 and
    noGuest.value.coverageInfo.value.skipped == 1 and
  noGuest.value.coverageInfo.value.absent == 1 and uint64(
      noGuest.value.coverageInfo.value.gasUsed) == 0, "current guest check: noGuest.value.coverageInfo.value.executed == 0 and"
# Actual supervision conflict retains original gas/provisions while clearing the junior's selected account/yield contribution.
let conflict = annulmentFixture(emit = false)
let selected = run(conflict).value
assert selected.coverageAnnulment.value.annulmentInfo.value.annulled == 1, "current guest check: selected.coverageAnnulment.value.annulmentInfo.value.annulled == 1"
let left = selected.coverageOriginalAt(AccumulationCoverageIndex(0)).value.outcomeInfo.value
let right = selected.coverageOriginalAt(AccumulationCoverageIndex(1)).value.outcomeInfo.value
assert uint64(selected.coverageInfo.value.gasUsed) == uint64(left.gasUsed)+uint64(right.gasUsed) and
    uint64(right.gasUsed) > 0, "current guest check: uint64(selected.coverageInfo.value.gasUsed) == uint64(left.gasUsed)+uint64(right.gasUsed) and"
# Initialized empty inputs still require valid explicit parameters/profile and produce initialized zero coverage.
let emptyInputs = prepareAccumulationInputs(source.inputs.invocationOperands.value, [], [], default(
    AccumulationInputConfig)).value
var emptyLimits = zero
emptyLimits.services = ElementLimit(0)
emptyLimits.annulment = default(AccumulationAnnulmentLimits)
emptyLimits.coverage = default(AccumulationCoverageLimits)
let empty = runAccumulationGuests(emptyInputs, prior, HeaderSlot(0), default(StateEntropyWord),
    profile(), emptyLimits)
assert empty.error == AccumulationGuestError.None and empty.value.coverageInfo.value.services == 0, "current guest check: empty.error == AccumulationGuestError.None and empty.value.coverageInfo.value.services == 0"
let before = getOccupiedMem()
for iteration in 0..<1000:
  let local = run(source)
  assert local.error == AccumulationGuestError.None and local.value.coverageInfo.value.services ==
      3, "current guest check: local.error == AccumulationGuestError.None and local.value.coverageInfo.value.services ==" # Actual guests, private credited maps and all retained source domains release together.
let after = getOccupiedMem()
assert before == after, "current guest runner owners release"
recordArcRelease("pvm_current_guest_runner", 1000, before, after)
echo "PVM current guest runner passed"
echo "ARC_RELEASE cycles=1000 unchanged"
