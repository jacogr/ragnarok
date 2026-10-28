# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_outcome_coverage_arc_release"}

## Genuine mixed providers prove exact canonical coverage, original canceled gas and distinct immutable proof domains.
import std/assertions
import std/syncio
import ../../../src/state/accumulation_coverage as state_accumulation_coverage
import ../../../src/state/accumulation_annulment as state_accumulation_annulment
import ../../../src/state/accumulation_outcome as state_accumulation_outcome
import ../../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_service as state_accumulation_service
import ../../../src/state/accumulation_skip as state_accumulation_skip
import ../../../src/state/accumulation_absent as state_accumulation_absent
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/header as codec_header
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_privileges as codec_state_privileges
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/c2_records as codec_c2_records
import ../../../src/chain/parameters as chain_parameters
import ../../../src/pvm/machine as pvm_machine
import ../../support/state_accumulation_batch_context
import ../../support/state_accumulation_annulment_context
import ../../support/pvm_accumulation_context
import ../../support/pvm_accumulation_program
import ../../support/testing_arc_evidence
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc mixedInputs(): PreparedAccumulationInputs =
  ## Offered budgets may sum beyond u64 even though actual consumed gas remains small and representable.
  prepareAccumulationInputs(batchInputSet(false).invocationOperands.value,
    [DeferredTransfer(source: ServiceIndex(7), destination: ServiceIndex(77),
        amount: TransferBalance(5),
      destinationSupervisor: true)],
    [AlwaysAccumulate(service: ServiceIndex(42), gas: PrivilegeGas(100000)),
     AlwaysAccumulate(service: ServiceIndex(77), gas: PrivilegeGas(100000)),
     AlwaysAccumulate(service: ServiceIndex(123), gas: PrivilegeGas(high(uint64)))],
    AccumulationInputConfig(inputs: ElementLimit(1), allowances: ElementLimit(3),
        services: ElementLimit(3))).value
proc skip(fixture: BatchFixture, slot = HeaderSlot(128)): SkippedAccumulation =
  ## Real missing code for existing77 retains its initial protected credit and original source owners.
  let resolved = prepareAccumulationService(fixture.inputs, InvocationServiceIndex(1),
    fixture.state.snapshot.value, slot, AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512),
      preimageBytes: ByteLimit(1024))).value
  assert resolved.serviceInfo.value.code == AccumulationCodeStatus.Missing
  finishUninvokedAccumulation(resolved).value
proc absence(fixture: BatchFixture, slot = HeaderSlot(128)): AbsentAccumulation =
  ## Missing metadata for123 proves identity before any code resolution or credit.
  finishAbsentAccumulation(fixture.inputs, InvocationServiceIndex(2), fixture.state.snapshot.value, slot).value
proc policy(): AccumulationCoverageLimits =
  ## Family caps and actual gas are independent of the complete canonical row limit.
  AccumulationCoverageLimits(services: ElementLimit(3), executed: ElementLimit(2),
    skipped: ElementLimit(2), absent: ElementLimit(2), checks: ElementLimit(128), gas: Gas(200000))
let target = serviceMetadataEntry(ServiceIndex(77), ServiceMetadata(balance: AccountBalance(10)),
  ByteLimit(ServiceMetadataBytes)).value
var fixture = batchFixture(incoming = false, firstEnvelope = guestEnvelope([@[50'u8, 0]]),
    extra = @[target])
fixture.inputs = mixedInputs()
var wire = encodeParameters(pvmParameters())
for index in 0..<24: wire[index] = 0 # The real execution uses the same complete tiny profile without unrelated deposits.
let execution = batchExecution(fixture, 0, parameters = decodeParameters(wire).value,
    modifiedAccounts = ElementLimit(8))
assert execution.error == AccumulationDispatchError.None
let original = normalizeAccumulationOutcome(execution).value
let source = prepareAccumulationAnnulment(fixture.inputs, fixture.state.snapshot.value, [original],
    annulmentPolicy()).value
let skipped = skip(fixture)
let absent = absence(fixture)
let actual = uint64(original.outcomeInfo.value.gasUsed)
assert actual > 0, "real guest termination consumes actual gas"
failHash(1)
let plan = prepareAccumulationCoverage(source, [skipped], [absent], HeaderSlot(128), policy()).value
let info = plan.coverageInfo.value
assert info.services == 3 and info.executed == 1 and info.skipped == 1 and info.absent == 1
assert uint64(info.gasUsed) == actual and uint32(info.slot) == 128, "sum actual consumption, not overflowing offered budgets"
assert sameAccumulationAnnulment(plan.coverageAnnulment.value, source)
let kinds = [AccumulationCoverageKind.Executed, AccumulationCoverageKind.CodeUnavailable,
    AccumulationCoverageKind.Absent]
let services = [42'u32, 77'u32, 123'u32]
for index in 0..<3:
  let ordinal = AccumulationCoverageIndex(uint64(index))
  let row = plan.coverageRowAt(ordinal).value
  assert row.kind == kinds[index] and uint32(row.service) == services[index], "canonical input order"
  assert uint64(row.gasUsed) == (if index == 0: actual else: 0'u64)
  if index == 0:
    assert uint32(plan.coverageOriginalAt(ordinal).value.outcomeInfo.value.service) == 42
    assert plan.coverageSkippedAt(ordinal).error == AccumulationCoverageError.KindMismatch
    assert plan.coverageAbsentAt(ordinal).error == AccumulationCoverageError.KindMismatch
  elif index == 1:
    assert uint32(plan.coverageSkippedAt(ordinal).value.skipInfo.value.service) == 77
    assert plan.coverageOriginalAt(ordinal).error == AccumulationCoverageError.KindMismatch
    assert plan.coverageAbsentAt(ordinal).error == AccumulationCoverageError.KindMismatch
  else:
    assert uint32(plan.coverageAbsentAt(ordinal).value.absentInfo.value.service) == 123
    assert plan.coverageOriginalAt(ordinal).error == AccumulationCoverageError.KindMismatch
    assert plan.coverageSkippedAt(ordinal).error == AccumulationCoverageError.KindMismatch
var copied = plan.coverageRowAt(AccumulationCoverageIndex(0)).value
copied.kind = AccumulationCoverageKind.Absent
assert plan.coverageRowAt(AccumulationCoverageIndex(0)).value.kind ==
    AccumulationCoverageKind.Executed
let highIndex = plan.coverageRowAt(AccumulationCoverageIndex(high(uint64)))
assert highIndex.error == AccumulationCoverageError.InvalidIndex
var exact = policy()
exact.services = ElementLimit(3)
exact.executed = ElementLimit(1)
exact.skipped = ElementLimit(1)
exact.absent = ElementLimit(1)
exact.checks = ElementLimit(info.checks)
exact.gas = Gas(actual)
assert prepareAccumulationCoverage(source, [skipped], [absent], HeaderSlot(128), exact).error ==
    AccumulationCoverageError.None
for kind in 0..<6:
  var short = exact
  case kind
  of 0: short.services = ElementLimit(2) # Final canonical rows are independently bounded.
  of 1: short.executed = ElementLimit(0) # Actual original provider traversal is not a selected-state count.
  of 2: short.skipped = ElementLimit(0) # Code-unavailable providers retain their own ceiling.
  of 3: short.absent = ElementLimit(0) # Missing-account providers are not code skips.
  of 4: short.checks = ElementLimit(info.checks-1) # Complete final inspection consumes exact work.
  else: short.gas = Gas(actual-1) # Actual consumption cannot exceed its explicit round budget.
  let refused = prepareAccumulationCoverage(source, [skipped], [absent], HeaderSlot(128), short)
  assert refused.error == (if kind == 5: AccumulationCoverageError.GasExceeded else: AccumulationCoverageError.LimitExceeded)
assert prepareAccumulationCoverage(source, [skipped], [], HeaderSlot(128), policy()).error ==
    AccumulationCoverageError.CoverageMismatch
assert prepareAccumulationCoverage(source, [default(SkippedAccumulation)], [absent], HeaderSlot(
    128), policy()).error == AccumulationCoverageError.InvalidProvider
assert prepareAccumulationCoverage(source, [skipped], [default(AbsentAccumulation)], HeaderSlot(
    128), policy()).error == AccumulationCoverageError.InvalidProvider
assert prepareAccumulationCoverage(source, [skipped], [absent], HeaderSlot(129), policy()).error ==
    AccumulationCoverageError.SlotMismatch
assert hashCalls() == 0, "coverage preparation, source checks, refusals and extraction hash nothing"
failHash(0)
assert prepareAccumulationCoverage(source, [skip(fixture, HeaderSlot(129))], [absent], HeaderSlot(
    128), policy()).error == AccumulationCoverageError.SlotMismatch
assert prepareAccumulationCoverage(source, [skipped], [absence(fixture, HeaderSlot(129))],
    HeaderSlot(128), policy()).error == AccumulationCoverageError.SlotMismatch
var foreignInputs = fixture
foreignInputs.inputs = mixedInputs()
assert prepareAccumulationCoverage(source, [skipped], [absence(foreignInputs)], HeaderSlot(128),
    policy()).error == AccumulationCoverageError.SourceMismatch,
  "equal input contents cannot substitute another owner"
var foreignState = fixture
assert foreignState.state.apply([StateWrite(key: chapterKey(StateChapter(250)),
    kind: StateWriteKind.Put,
  value: @[3'u8])]).error == StateStoreError.None
let foreignRefusal = prepareAccumulationCoverage(source, [skip(foreignState)], [absent], HeaderSlot(
    128), policy())
assert foreignRefusal.error == AccumulationCoverageError.SourceMismatch

let noOriginals = prepareAccumulationAnnulment(fixture.inputs, fixture.state.snapshot.value, [],
    default(AccumulationAnnulmentLimits)).value
assert prepareAccumulationCoverage(noOriginals, [skipped], [absent, absent], HeaderSlot(128),
    policy()).error == AccumulationCoverageError.DuplicateService,
  "repeated absence cannot cover a missing executed input"
assert prepareAccumulationCoverage(source, [skipped, skipped], [], HeaderSlot(128), policy(
  )).error == AccumulationCoverageError.DuplicateService,
  "repeated unavailable-code proof cannot cover an absent input"
# Original consumed gas remains charged even when N clears the producer's selected state, transfers and yield.
let canceledFixture = annulmentFixture(emit = false)
let a = annulmentOriginal(canceledFixture, 0)
let b = annulmentOriginal(canceledFixture, 1)
let consumed = uint64(a.outcomeInfo.value.gasUsed)+uint64(b.outcomeInfo.value.gasUsed)
assert uint64(b.outcomeInfo.value.gasUsed) > 0
for reverse in [false, true]:
  let originals = if reverse: @[b, a] else: @[a, b]
  let canceled = prepareAccumulationAnnulment(canceledFixture.inputs,
      canceledFixture.state.snapshot.value, originals, annulmentPolicy()).value
  assert canceled.annulmentInfo.value.annulled == 1
  let covered = prepareAccumulationCoverage(canceled, [], [], HeaderSlot(128), policy()).value
  assert covered.coverageInfo.value.executed == 2 and uint64(covered.coverageInfo.value.gasUsed) ==
      consumed,
    "annulment never refunds original consumed gas or removes executed input coverage"
  assert uint32(covered.coverageRowAt(AccumulationCoverageIndex(0)).value.service) == 42
  assert uint32(covered.coverageOriginalAt(AccumulationCoverageIndex(
      1)).value.outcomeInfo.value.service) == 99
# Initialized empty coverage has no fabricated row and is distinct from default source/owner refusal.
let emptyInputs = prepareAccumulationInputs(fixture.inputs.invocationOperands.value, [], [],
    default(AccumulationInputConfig)).value
let emptySource = prepareAccumulationAnnulment(emptyInputs, fixture.state.snapshot.value, [],
    default(AccumulationAnnulmentLimits)).value
let empty = prepareAccumulationCoverage(emptySource, [], [], HeaderSlot(0), default(
    AccumulationCoverageLimits)).value
assert empty.coverageInfo.value.services == 0 and uint64(empty.coverageInfo.value.gasUsed) == 0
assert empty.coverageRowAt(AccumulationCoverageIndex(0)).error ==
    AccumulationCoverageError.InvalidIndex
assert prepareAccumulationCoverage(default(PreparedAccumulationAnnulment), [], [], HeaderSlot(0),
    policy()).error == AccumulationCoverageError.InvalidSource
assert default(PreparedAccumulationCoverage).coverageInfo.error ==
    AccumulationCoverageError.Uninitialized
let before = getOccupiedMem()
for iteration in 0..<1000:
  let local = prepareAccumulationCoverage(source, [skipped], [absent], HeaderSlot(128), exact).value
  assert local.coverageInfo.value.services == 3
  discard local.coverageOriginalAt(AccumulationCoverageIndex(0)).value
  discard local.coverageSkippedAt(AccumulationCoverageIndex(1)).value
  discard local.coverageAbsentAt(AccumulationCoverageIndex(
      2)).value # All retained source domains release with immutable rows.
let after = getOccupiedMem()
assert before == after, "complete provider coverage owners release"
recordArcRelease("pvm_outcome_coverage", 1000, before, after)
echo "PVM outcome coverage passed"
echo "ARC_RELEASE cycles=1000 unchanged"
