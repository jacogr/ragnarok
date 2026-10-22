# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_skipped_credit_selection_arc_release"}

## Genuine unavailable-code certificates preserve liquid/protected/zero credits and common-frame ownership in M selection.
import std/[assertions, syncio]
import ../../../src/state/[accumulation_annulment, accumulation_account_selection,
  accumulation_outcome, accumulation_inputs, accumulation_service, accumulation_skip, store]
import ../../../src/codec/[bounded, header, state_accounts, state_service_values, state_layout,
  state_trie, state_privileges, state_safrole, c2_records]
import ../../support/[accumulation_annulment_context, accumulation_batch_context, arc_evidence]

# Account-source selection must retain precredited maps, never recompute or publish their roots.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc policy(skips = 1'u64): AccumulationAccountSelectionLimits =
  ## Independent producer/skip/account/work ceilings count even unrequested certified participants.
  AccumulationAccountSelectionLimits(outcomes: ElementLimit(2), skipped: ElementLimit(skips),
    accounts: ElementLimit(2), checks: ElementLimit(256))
proc removeCode(source: var BatchFixture, service: uint32) =
  ## Remove an actual code preimage before either execution or code-unavailable preparation captures the common prior.
  let accountKey = chapterServiceKey(StateChapter(255), ServiceIndex(service))
  let account = decodeServiceMetadata(source.state.snapshot.value.lookup(accountKey).value.bytes,
    ByteLimit(ServiceMetadataBytes)).value.metadata
  let key = servicePreimageKey(ServiceIndex(service), ServicePreimageHash(array[32, byte](
      account.codeHash)), ByteLimit(32)).value
  let removed = source.state.apply([StateWrite(key: key, kind: StateWriteKind.Delete)])
  assert removed.error == StateStoreError.None, "remove the actual original code key before source capture"
proc creditFixture(amount = 11'u64, protected = false, supervisor = 99'u32,
    incarnation = 0'u32, nominee = false): BatchFixture =
  ## Author one incoming record for99 and independent always groups before preparing any genuine source.
  result = annulmentFixture(supervisor = supervisor, incarnation = incarnation,
    parentTarget = 42, write = false, emit = false)
  let operands = result.inputs.invocationOperands.value
  result.inputs = prepareAccumulationInputs(operands,
    [DeferredTransfer(source: ServiceIndex(7), destination: ServiceIndex(99),
        amount: TransferBalance(amount),
      destinationSupervisor: protected)],
    [AlwaysAccumulate(service: ServiceIndex(42), gas: PrivilegeGas(100000)),
      AlwaysAccumulate(service: ServiceIndex(99), gas: PrivilegeGas(100000))],
    AccumulationInputConfig(inputs: ElementLimit(1), allowances: ElementLimit(2),
        services: ElementLimit(2))).value
  if nominee:
    let entry = serviceMetadataEntry(ServiceIndex(supervisor), ServiceMetadata(
      supervisor: ServiceIndex(supervisor), created: AccountSlot(incarnation)), ByteLimit(
          ServiceMetadataBytes)).value
    let added = result.state.apply([StateWrite(key: entry.key, kind: StateWriteKind.Put,
        value: entry.value)])
    assert added.error == StateStoreError.None, "seed a matching inactive supervisor before common-source capture"
  removeCode(result, 99)
proc skipped(source: BatchFixture, index = 1'u64, slot = HeaderSlot(128)): SkippedAccumulation =
  ## Only actual code-unavailable preparation creates this certified zero-execution alternative.
  let service = prepareAccumulationService(source.inputs, InvocationServiceIndex(index),
    source.state.snapshot.value, slot,
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))).value
  assert service.serviceInfo.value.code == AccumulationCodeStatus.Missing, "the original code preimage is genuinely absent"
  finishUninvokedAccumulation(service).value
proc executedSource(source: BatchFixture): PreparedAccumulationAnnulment =
  ## One real parent execution and its exact input/map owners leave the second participant to a certified skip.
  prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value,
    [annulmentOriginal(source, 0)], annulmentPolicy()).value
let services = [ServiceIndex(99)]
for protected in [false, true]:
  for amount in [0'u64, 11]:
    let source = creditFixture(amount, protected)
    let original = executedSource(source)
    let missing = skipped(source)
    assert uint64(missing.skipInfo.value.gasUsed) == 0 and not missing.skipInfo.value.hasYield
    failHash(1)
    let plan = prepareAccumulationAccountSelection(original, services, policy(), [missing]).value
    let info = plan.accountSelectionInfo.value
    assert info.skippedSources == 1 and info.skipped == 1 and info.invokers == 0, "count genuine skipped provenance separately from executed invokers"
    let chosen = plan.selectedAccountAt(AccumulationAccountSelectionIndex(0)).value
    assert chosen.origin == AccumulationAccountOrigin.Skipped and chosen.present, "incoming record marks skipped own account even at zero amount"
    let account = plan.selectedAccountMetadataAt(AccumulationAccountSelectionIndex(0)).value
    assert uint64(account.balance) == 20+(if protected: 0'u64 else: amount)
    assert uint64(account.supervisorBalance) == (if protected: amount else: 0'u64)
    let selectedSkip = plan.selectedAccountSkipAt(AccumulationAccountSelectionIndex(0)).value
    assert selectedSkip.skipInfo.value.code == AccumulationCodeStatus.Missing
    assert sameStateSnapshot(plan.selectedAccountSnapshotAt(AccumulationAccountSelectionIndex(
        0)).value,
      missing.skipState.value), "retain exact post-credit skip map instead of prior fallback"
    let noExecution = plan.selectedAccountOutcomeAt(AccumulationAccountSelectionIndex(0))
    assert noExecution.error == AccumulationAccountSelectionError.NoExecution, "skipped credit never fabricates an executed outcome"
    var exact = policy()
    exact.checks = ElementLimit(info.checks)
    let exactResult = prepareAccumulationAccountSelection(original, services, exact, [missing])
    assert exactResult.error == AccumulationAccountSelectionError.None
    exact.checks = ElementLimit(info.checks-1)
    let shortWork = prepareAccumulationAccountSelection(original, services, exact, [missing])
    assert shortWork.error == AccumulationAccountSelectionError.LimitExceeded
    let noSkips = prepareAccumulationAccountSelection(original, services, policy(0), [missing])
    assert noSkips.error == AccumulationAccountSelectionError.LimitExceeded, "zero skip policy grants no non-executing work"
    let duplicate = prepareAccumulationAccountSelection(original, services, policy(2), [missing, missing])
    assert duplicate.error == AccumulationAccountSelectionError.DuplicateService
    let defaultSkip = prepareAccumulationAccountSelection(original, services, policy(), [default(
        SkippedAccumulation)])
    assert defaultSkip.error == AccumulationAccountSelectionError.InvalidSource
    assert hashCalls() == 0, "skipped selection only retains already credited owners"
    failHash(0)
# Missing/stale nominees fall back to self; a matching nonparticipating supervisor also permits credit.
for mode in 0..<3:
  let source = if mode == 0: creditFixture(supervisor = 77)
    elif mode == 1: creditFixture(supervisor = 42, incarnation = 1)
    else: creditFixture(supervisor = 77, nominee = true)
  let plan = prepareAccumulationAccountSelection(executedSource(source), services, policy(), [
      skipped(source)]).value
  assert plan.accountSelectionInfo.value.skipped == 1
  assert uint64(plan.selectedAccountMetadataAt(AccumulationAccountSelectionIndex(
      0)).value.balance) == 31
# The same input group set cannot accumulate junior credit alongside its effective supervisor.
let unsafeSource = creditFixture(supervisor = 42)
let unsafePlan = executedSource(unsafeSource)
let unsafeSkip = skipped(unsafeSource)
let refused = prepareAccumulationAccountSelection(unsafePlan, services, policy(), [unsafeSkip])
assert refused.error == AccumulationAccountSelectionError.UnsafeCreditSchedule, "require fnpartition's supervisor exclusion before preserving skipped junior credit"
let noExecutions = prepareAccumulationAnnulment(unsafeSource.inputs,
    unsafeSource.state.snapshot.value, [], default(AccumulationAnnulmentLimits)).value
let stillUnsafe = prepareAccumulationAccountSelection(noExecutions, services, policy(), [unsafeSkip])
assert stillUnsafe.error == AccumulationAccountSelectionError.UnsafeCreditSchedule, "inspect all active input groups, not only supplied executed outcomes"
# Slot/input/map mismatches refuse without substituting a newly prepared source.
let source = creditFixture()
let raw = executedSource(source)
let missing = skipped(source)
let wrongSlot = skipped(source, slot = HeaderSlot(129))
let badSlot = prepareAccumulationAccountSelection(raw, services, policy(), [wrongSlot])
assert badSlot.error == AccumulationAccountSelectionError.SourceMismatch
let other = creditFixture()
let otherSkip = skipped(other)
let wrongOwner = prepareAccumulationAccountSelection(raw, services, policy(), [otherSkip])
assert wrongOwner.error == AccumulationAccountSelectionError.SourceMismatch, "equal-content fixture cannot replace exact input/prior ownership"
# Genuine raw executed outcomes must share both bootstrap time and allocation entropy.
let frame = annulmentFixture(supervisor = 99)
let frameFirst = annulmentOriginal(frame, 0)
let frameSecond = annulmentOriginal(frame, 1)
let wrongTime = annulmentOriginal(frame, 1, slot = HeaderSlot(129))
let mixedTime = prepareAccumulationAnnulment(frame.inputs, frame.state.snapshot.value, [frameFirst,
    wrongTime], annulmentPolicy())
assert mixedTime.error == AccumulationAnnulmentError.SourceMismatch
var entropyBytes = default(array[32, byte])
entropyBytes[0] = 1
let entropy = StateEntropyWord(entropyBytes)
let wrongSeed = annulmentOriginal(frame, 1, entropy = entropy)
let mixedSeed = prepareAccumulationAnnulment(frame.inputs, frame.state.snapshot.value, [frameFirst,
    wrongSeed], annulmentPolicy())
assert mixedSeed.error == AccumulationAnnulmentError.SourceMismatch
let validFrame = annulmentPrepared(frame, frameFirst, frameSecond)
assert uint32(validFrame.annulmentSlot.value) == 128
assert sameAccumulationInputs(validFrame.annulmentInputs.value, frame.inputs)
let slotZeroOutcome = annulmentOriginal(frame, 0, slot = HeaderSlot(0))
let slotZero = prepareAccumulationAnnulment(frame.inputs, frame.state.snapshot.value, [
    slotZeroOutcome], annulmentPolicy()).value
assert slotZero.annulmentSlot.error == AccumulationAnnulmentError.None and uint32(
    slotZero.annulmentSlot.value) == 0, "real slot zero is not the empty-source sentinel"
let empty = prepareAccumulationAnnulment(frame.inputs, frame.state.snapshot.value, [], default(
    AccumulationAnnulmentLimits)).value
assert empty.annulmentSlot.error == AccumulationAnnulmentError.NoInvocationSlot
assert sameAccumulationInputs(empty.annulmentInputs.value, frame.inputs)
assert default(PreparedAccumulationAnnulment).annulmentInputs.error ==
    AccumulationAnnulmentError.Uninitialized
assert default(PreparedAccumulationAnnulment).annulmentSlot.error ==
    AccumulationAnnulmentError.Uninitialized
# Uncredited skipped child still yields to a deleting supervisor's real selected map.
var deleted = annulmentFixture(eject = true)
removeCode(deleted, 99)
let parent = executedSource(deleted)
let child = skipped(deleted)
let deletion = prepareAccumulationAccountSelection(parent, services, policy(), [child]).value
assert deletion.accountSelectionInfo.value.deleted == 1 and
    deletion.accountSelectionInfo.value.skipped == 0
let deletedMetadata = deletion.selectedAccountMetadataAt(AccumulationAccountSelectionIndex(0))
assert deletedMetadata.error == AccumulationAccountSelectionError.NoAccount
let noSkipped = deletion.selectedAccountSkipAt(AccumulationAccountSelectionIndex(0))
assert noSkipped.error == AccumulationAccountSelectionError.NoSkipped
# A skip-only source binds its real first slot, preserves own credits and rejects a second different time.
var onlySkips = creditFixture()
removeCode(onlySkips, 42)
let onlySkipSource = prepareAccumulationAnnulment(onlySkips.inputs, onlySkips.state.snapshot.value,
    [], default(AccumulationAnnulmentLimits)).value
let skippedFirst = skipped(onlySkips, index = 0)
let skippedSecond = skipped(onlySkips)
let allSkipped = prepareAccumulationAccountSelection(onlySkipSource,
    [ServiceIndex(42), ServiceIndex(99)], policy(2), [skippedFirst, skippedSecond]).value
assert allSkipped.accountSelectionInfo.value.skippedSources == 2
assert uint64(allSkipped.selectedAccountMetadataAt(AccumulationAccountSelectionIndex(
    1)).value.balance) == 31
let laterSkip = skipped(onlySkips, slot = HeaderSlot(129))
let mixedSkipped = prepareAccumulationAccountSelection(onlySkipSource, [], policy(2), [skippedFirst, laterSkip])
assert mixedSkipped.error == AccumulationAccountSelectionError.SourceMismatch
# A skipped supervisor cannot change another logical account; M's prior identity is equivalent there.
var skippedParent = annulmentFixture(supervisor = 42, parentTarget = 42, write = false, emit = false)
removeCode(skippedParent, 42)
let parentSource = prepareAccumulationAnnulment(skippedParent.inputs,
    skippedParent.state.snapshot.value, [], default(AccumulationAnnulmentLimits)).value
let unavailableParent = skipped(skippedParent, index = 0)
let identity = prepareAccumulationAccountSelection(parentSource, services, policy(), [
    unavailableParent]).value
let identityOrigin = identity.selectedAccountAt(AccumulationAccountSelectionIndex(0)).value.origin
assert identityOrigin == AccumulationAccountOrigin.Prior
let noParentExecution = identity.selectedAccountOutcomeAt(AccumulationAccountSelectionIndex(0))
assert noParentExecution.error == AccumulationAccountSelectionError.NoOutcome
# Caller lifetime and repeated release retain only immutable source and credited-state proofs.
var detached = default(PreparedAccumulationAccountSelection)
block released_sources:
  let temporary = creditFixture(protected = true)
  let source = executedSource(temporary)
  detached = prepareAccumulationAccountSelection(source, services, policy(), [skipped(
      temporary)]).value
assert uint64(detached.selectedAccountMetadataAt(AccumulationAccountSelectionIndex(
    0)).value.supervisorBalance) == 11
assert detached.selectedAccountSkipAt(AccumulationAccountSelectionIndex(
    0)).value.skipInfo.value.code == AccumulationCodeStatus.Missing
let before = getOccupiedMem()
for iteration in 0..<1000:
  let retained = prepareAccumulationAccountSelection(raw, services, policy(), [missing]).value
  assert retained.accountSelectionInfo.value.skipped == 1
  assert uint64(retained.selectedAccountMetadataAt(AccumulationAccountSelectionIndex(
      0)).value.balance) == 31
  let framePlan = annulmentPrepared(frame, frameFirst, frameSecond)
  assert uint32(framePlan.annulmentSlot.value) == 128
let after = getOccupiedMem()
assert before == after, "skipped certificates, selected maps and invocation-frame sources release across 1000 cycles"
recordArcRelease("pvm_skipped_credit_selection", 1000, before, after)
echo "PVM skipped credit selection passed"
echo "ARC_RELEASE cycles=1000 unchanged"
