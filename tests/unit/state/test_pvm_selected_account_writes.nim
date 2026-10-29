# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_selected_account_writes_arc_release"}

## Genuine account mutations prove selected physical key/value ownership across M, n, cancellation and skipped credits.
import std/[assertions, syncio]
import ../../../src/state/accumulation/[selected_writes as accumulation_selected_writes,
    annulment as accumulation_annulment]
import ../../../src/state/accumulation/account/selection as accumulation_account_selection
import ../../../src/state/accumulation/[creation_union as accumulation_creation_union,
    dispatch as accumulation_dispatch, outcome as accumulation_outcome,
    effects as accumulation_effects, inputs as accumulation_inputs, service as accumulation_service,
    skip as accumulation_skip, invocation as accumulation_invocation]
import ../../../src/state/store
import ../../../src/codec/[bounded, composite, header]
import ../../../src/codec/state/[accounts as state_accounts, privileges as state_privileges,
    service_values as state_service_values, requests as state_requests, layout as state_layout,
    trie as state_trie]
import ../../../src/codec/c2_records
import ../../../src/chain/parameters
import ../../../src/pvm/machine
import ../../support/[accumulation_batch_context, accumulation_annulment_context,
  pvm_accumulation_context, pvm_accumulation_program, arc_evidence]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc profile(): Parameters =
  ## Zero deposits isolate genuine logical ownership without changing actual host gas or opcode execution.
  var wire = encodeParameters(pvmParameters())
  for index in 0..<24: wire[index] = 0 # Complete deposit words are independently authored.
  decodeParameters(wire).value
proc run(fixture: BatchFixture, index: uint64, facts = 8'u64): AccumulationOutcome =
  ## Enable complete independent creation and physical facts before any actual guest mutation.
  let execution = batchExecution(fixture, index, parameters = profile(),
      copyLimit = MemoryByteLimit(128),
    createdAccounts = ElementLimit(1), deletedAccounts = ElementLimit(1),
    modifiedAccounts = ElementLimit(8), accountWriteFacts = ElementLimit(facts),
        serviceProbes = ServiceProbeLimit(1))
  assert execution.error == AccumulationDispatchError.None, $execution.error
  normalizeAccumulationOutcome(execution).value
proc previous(source: PreparedAccumulationAnnulment, ids: openArray[
    ServiceIndex]): PreparedAccumulationAccountSelection =
  ## This explicit subset is not a claim that all prior accounts or input groups have been covered.
  prepareAccumulationAccountSelection(source, ids, AccumulationAccountSelectionLimits(
    accounts: ElementLimit(2), outcomes: ElementLimit(2), checks: ElementLimit(256))).value
proc added(source: PreparedAccumulationAnnulment): PreparedAccumulationCreationUnion =
  ## Strict enabled membership proves the complete new-account contribution of surviving original outcomes.
  prepareAccumulationCreationUnion(source, AccumulationCreationLimits(outcomes: ElementLimit(2),
    creations: ElementLimit(2), accounts: ElementLimit(2), checks: ElementLimit(128))).value
proc policy(): SelectedAccountWriteLimits =
  ## Account/fact/descriptor/payload/predicate ceilings are independent and explicit.
  SelectedAccountWriteLimits(accounts: ElementLimit(4), facts: ElementLimit(32),
    writes: ElementLimit(8), checks: ElementLimit(256), valueBytes: ByteLimit(1024))
proc paired(fixture: BatchFixture, facts = 8'u64): PreparedAccumulationAnnulment =
  ## Bind normalized actual executions to the exact common input and prior owners.
  prepareAccumulationAnnulment(fixture.inputs, fixture.state.snapshot.value,
    [run(fixture, 0, facts), run(fixture, 1, facts)], annulmentPolicy()).value
proc checkSupervisor(supervisor: uint32) =
  ## Own selected writes win unless the real original supervisor conflict annuls that self mutation.
  let fixture = annulmentFixture(supervisor = supervisor, emit = false)
  let source = paired(fixture)
  let m = previous(source, [ServiceIndex(99)])
  let n = added(source)
  let key = chapterServiceKey(StateChapter(255), ServiceIndex(99))
  var expected = decodeServiceMetadata(fixture.state.snapshot.value.lookup(key).value.bytes,
    ByteLimit(ServiceMetadataBytes)).value.metadata
  if supervisor == 99:
    var hash = default(array[32, byte])
    hash[0] = 73
    expected.codeHash = CodeHash(hash) # Junior's actual upgrade reads this literal read-only page prefix.
  let wire = serviceMetadataEntry(ServiceIndex(99), expected, ByteLimit(
      ServiceMetadataBytes)).value.value
  failHash(1)
  let plan = prepareSelectedAccountWrites(m, n, policy()).value
  assert plan.selectedWritesInfo.value.writes == 1
  let write = plan.selectedWriteAt(AccumulationSelectedWriteIndex(0)).value
  assert array[31, byte](write.key) == array[31, byte](key) and write.kind == StateWriteKind.Put
  assert write.value == wire, "independent expected selected metadata, including canceled raw self-upgrade exclusion"
  assert plan.selectedWritesPriorSource.value.accountSelectionInfo.value.accounts == 1
  assert plan.selectedWritesNewSource.value.creationUnionInfo.value.accounts == 0
  assert hashCalls() == 0, "physical selection and extraction compute no state hashes"
  failHash(0)
checkSupervisor(42)
checkSupervisor(99)
# Real birth contributes exactly parent metadata, child metadata and the child's own empty code request.
var payload = newSeq[byte](60)
payload[32] = 1
let newProgram = guestEnvelope([registerImmediate(7, high(uint64)), registerImmediate(8, high(uint64)),
  registerImmediate(9, 0), registerImmediate(10, 196608), @[10'u8, 20], @[50'u8, 0]],
      writable = payload)
let noop = guestEnvelope([@[50'u8, 0]])
let fixture = batchFixture(incoming = false, firstEnvelope = newProgram, secondEnvelope = noop)
let source = paired(fixture)
let m = previous(source, [ServiceIndex(42), ServiceIndex(99)])
let n = added(source)
let child = n.createdAccountAt(AccumulationCreationIndex(0)).value.service
let childMetadata = ServiceMetadata(storageItems: AccountStorageItems(2),
    storageBytes: AccountStorageBytes(82),
  created: AccountSlot(128), parent: ServiceIndex(42), supervisor: ServiceIndex(42))
let childEntry = serviceMetadataEntry(child, childMetadata, ByteLimit(ServiceMetadataBytes)).value
let request = serviceRequestEntry(child, default(ServicePreimageHash), RequestLength(1),
    requestedHistory(),
  RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(0),
      maxBytes: ByteLimit(1)))).value
let parentKey = chapterServiceKey(StateChapter(255), ServiceIndex(42))
let parentEntry = StateEntry(key: parentKey, value: fixture.state.snapshot.value.lookup(
    parentKey).value.bytes)
let expected = @[parentEntry, childEntry, request]
failHash(1)
let plan = prepareSelectedAccountWrites(m, n, policy()).value
let info = plan.selectedWritesInfo.value
assert info.accounts == 3 and info.facts == 6 and info.writes == 3 and info.valueBytes == 211,
  "filtered facts consume work independently of actual physical output"
for index in 0..<3:
  let write = plan.selectedWriteAt(AccumulationSelectedWriteIndex(uint64(index))).value
  assert write.kind == StateWriteKind.Put
  var matched = false
  for entry in expected:
    if array[31, byte](entry.key) == array[31, byte](write.key):
      assert entry.value == write.value, "literal parent/child/request expected values"
      matched = true # Unrelated complete-map keys must never escape through selected descriptors.
  assert matched
var detached = plan.selectedWriteAt(AccumulationSelectedWriteIndex(0)).value
detached.value[0] = 255
assert plan.selectedWriteAt(AccumulationSelectedWriteIndex(0)).value.value[0] != 255, "returned write bytes are independently owned"
var exact = policy()
exact.accounts = ElementLimit(info.accounts)
exact.facts = ElementLimit(info.facts)
exact.writes = ElementLimit(info.writes)
exact.checks = ElementLimit(info.checks)
exact.valueBytes = ByteLimit(info.valueBytes)
assert prepareSelectedAccountWrites(m, n, exact).error == SelectedAccountWriteError.None
for kind in 0..<5:
  var short = exact
  case kind
  of 0: short.accounts = ElementLimit(info.accounts-1) # Total M+n traversal is separate from descriptors.
  of 1: short.facts = ElementLimit(info.facts-1) # Even filtered account facts consume capacity.
  of 2: short.writes = ElementLimit(info.writes-1) # Every final key requires one descriptor.
  of 3: short.checks = ElementLimit(info.checks-1) # Exact charged predicates remain independently bounded.
  else: short.valueBytes = ByteLimit(info.valueBytes-1) # No final payload is partially copied out on refusal.
  assert prepareSelectedAccountWrites(m, n, short).error == SelectedAccountWriteError.LimitExceeded
let invalidIndex = plan.selectedWriteAt(AccumulationSelectedWriteIndex(high(uint64)))
assert invalidIndex.error == SelectedAccountWriteError.InvalidIndex
assert hashCalls() == 0
failHash(0)
# Equal independently checked certificates cannot be substituted for exact M/n source ownership.
let sameContents = prepareAccumulationAnnulment(source.annulmentInputs.value,
  source.annulmentPrior.value,
  [source.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(0)).value,
   source.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(1)).value], annulmentPolicy()).value
assert sameAccumulationAnnulment(source, source)
assert not sameAccumulationAnnulment(source, sameContents)
assert not sameAccumulationAnnulment(default(PreparedAccumulationAnnulment), default(PreparedAccumulationAnnulment))
assert prepareSelectedAccountWrites(m, added(sameContents), policy()).error ==
    SelectedAccountWriteError.SourceMismatch
let noFacts = paired(fixture, facts = 0)
assert prepareSelectedAccountWrites(previous(noFacts, [ServiceIndex(42)]), added(noFacts), policy()).error ==
  SelectedAccountWriteError.IncompleteFacts, "disabled physical capture cannot impersonate an empty changed-key set"
# An actual eligible ejection contributes only the selected target's metadata deletion, filtering payer metadata.
let target = serviceMetadataEntry(ServiceIndex(77), ServiceMetadata(supervisor: ServiceIndex(42),
  balance: AccountBalance(5)), ByteLimit(ServiceMetadataBytes)).value
let deletion = batchFixture(incoming = false, firstEnvelope = guestEnvelope([registerImmediate(7, 77),
  @[10'u8, 23], @[50'u8, 0]]), secondEnvelope = noop, extra = @[target])
let deletionSource = paired(deletion)
let deletionM = previous(deletionSource, [ServiceIndex(77)])
assert not deletionM.selectedAccountAt(AccumulationAccountSelectionIndex(0)).value.present, "real superior removed the old empty target"
let deleted = prepareSelectedAccountWrites(deletionM, added(deletionSource), policy()).value
assert deleted.selectedWritesInfo.value.writes == 1
let removed = deleted.selectedWriteAt(AccumulationSelectedWriteIndex(0)).value
assert removed.kind == StateWriteKind.Delete and removed.value.len == 0
assert array[31, byte](removed.key) == array[31, byte](target.key), "discard unselected payer balance write"
# Mutual cancellation selects prior identity and needs no raw physical facts from either discarded producer.
let canceledFixture = annulmentFixture(mutual = true, emit = false)
let canceled = paired(canceledFixture, facts = 0)
let canceledM = previous(canceled, [ServiceIndex(99)])
let canceledPlan = prepareSelectedAccountWrites(canceledM, added(canceled), policy()).value
assert canceledPlan.selectedWritesInfo.value.writes == 0
# Genuine unavailable-code certificates carry only their initial liquid/protected credit, including zero records.
for protected in [false, true]:
  for amount in [0'u64, 11'u64]:
    var credit = annulmentFixture(supervisor = 99, write = false, emit = false)
    credit.inputs = prepareAccumulationInputs(credit.inputs.invocationOperands.value,
      [DeferredTransfer(source: ServiceIndex(7), destination: ServiceIndex(99),
        amount: TransferBalance(amount), destinationSupervisor: protected)],
      [AlwaysAccumulate(service: ServiceIndex(99), gas: PrivilegeGas(100000))],
      AccumulationInputConfig(inputs: ElementLimit(1), allowances: ElementLimit(1),
          services: ElementLimit(1))).value
    let key = chapterServiceKey(StateChapter(255), ServiceIndex(99))
    var metadata = decodeServiceMetadata(credit.state.snapshot.value.lookup(key).value.bytes,
      ByteLimit(ServiceMetadataBytes)).value.metadata
    let preimageKey = servicePreimageKey(ServiceIndex(99), ServicePreimageHash(array[32, byte](
        metadata.codeHash)), ByteLimit(32)).value
    assert credit.state.apply([StateWrite(key: preimageKey, kind: StateWriteKind.Delete)]).error ==
        StateStoreError.None
    let resolved = prepareAccumulationService(credit.inputs, InvocationServiceIndex(0),
        credit.state.snapshot.value,
      HeaderSlot(128), AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512),
          preimageBytes: ByteLimit(1024))).value
    let skipped = finishUninvokedAccumulation(resolved).value
    let original = prepareAccumulationAnnulment(credit.inputs, credit.state.snapshot.value, [],
        default(AccumulationAnnulmentLimits)).value
    let selected = prepareAccumulationAccountSelection(original, [ServiceIndex(99)],
      AccumulationAccountSelectionLimits(accounts: ElementLimit(1), checks: ElementLimit(128),
          skipped: ElementLimit(1)), [skipped]).value
    if protected: metadata.supervisorBalance = AccountBalance(
        amount) # Preserve original liquid balance independently.
    else: metadata.balance = AccountBalance(20+amount) # Only the chosen liquid pool receives credit.
    let expected = serviceMetadataEntry(ServiceIndex(99), metadata, ByteLimit(
        ServiceMetadataBytes)).value.value
    let emptyNew = prepareAccumulationCreationUnion(original, default(
        AccumulationCreationLimits)).value
    failHash(1)
    let writes = prepareSelectedAccountWrites(selected, emptyNew, policy()).value
    assert writes.selectedWritesInfo.value.facts == 0 and writes.selectedWritesInfo.value.writes == 1
    assert writes.selectedWriteAt(AccumulationSelectedWriteIndex(0)).value.value == expected, "exact certified skipped liquid/protected/zero credit"
    assert hashCalls() == 0
    failHash(0)
let invalid = prepareSelectedAccountWrites(default(PreparedAccumulationAccountSelection), n, policy())
assert invalid.error == SelectedAccountWriteError.InvalidSource
let absent = default(PreparedSelectedAccountWrites)
assert absent.selectedWritesInfo.error == SelectedAccountWriteError.Uninitialized
assert absent.selectedWritesPriorSource.error == SelectedAccountWriteError.Uninitialized
assert absent.selectedWritesNewSource.error == SelectedAccountWriteError.Uninitialized
# An initialized genuinely empty subset is distinct from a default/refused plan.
let emptySource = prepareAccumulationAnnulment(source.annulmentInputs.value,
  source.annulmentPrior.value,
  [], default(AccumulationAnnulmentLimits)).value
let emptyM = prepareAccumulationAccountSelection(emptySource, [], default(
    AccumulationAccountSelectionLimits)).value
let emptyN = prepareAccumulationCreationUnion(emptySource, default(
    AccumulationCreationLimits)).value
let emptyPlan = prepareSelectedAccountWrites(emptyM, emptyN, default(
    SelectedAccountWriteLimits)).value
assert emptyPlan.selectedWritesInfo.value.accounts == 0 and
    emptyPlan.selectedWritesInfo.value.writes == 0
assert emptyPlan.selectedWriteAt(AccumulationSelectedWriteIndex(0)).error ==
    SelectedAccountWriteError.InvalidIndex
let before = getOccupiedMem()
for iteration in 0..<1000:
  let local = prepareSelectedAccountWrites(m, n, exact).value
  assert local.selectedWritesInfo.value.writes == 3
  discard local.selectedWriteAt(AccumulationSelectedWriteIndex(
      0)).value # Fresh final byte buffers release with both source owners.
let after = getOccupiedMem()
assert before == after, "selected physical descriptors release"
recordArcRelease("pvm_selected_account_writes", 1000, before, after)
echo "PVM selected account writes passed"
echo "ARC_RELEASE cycles=1000 unchanged"
