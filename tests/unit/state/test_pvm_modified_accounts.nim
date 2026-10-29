# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_modified_accounts_arc_release"}

## Genuine host effects retain exact successful modification membership across equal roots and checkpoints.
import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, header]
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    service_values as state_service_values, requests as state_requests, outputs as state_outputs,
    privileges as state_privileges, authorization as state_authorization, safrole as state_safrole,
    trie as state_trie]
import ../../../src/codec/c2_records
import ../../../src/state/accumulation/[dispatch as accumulation_dispatch,
    effects as accumulation_effects, context as accumulation_context,
    invocation as accumulation_invocation, machine as accumulation_machine,
    outcome as accumulation_outcome, inputs as accumulation_inputs]
import ../../../src/state/store
import ../../../src/pvm/[machine, step, gas, host_fetch]
import ../../../src/crypto/primitives
import ../../support/[pvm_accumulation_context, pvm_accumulation_program,
    accumulation_batch_context, arc_evidence]

# Inject backend refusal only after complete genuine source preparation.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Zero deposits isolate membership from independent storage-price arithmetic.
proc parameters(): Parameters =
  var bytes = encodeParameters(pvmParameters())
  for index in 0..<24:
    bytes[index] = 0 # No protocol funding refusal obscures a successful no-op host.
  for index in 0..<4:
    bytes[74+index] = byte((14400'u32 shr (8*index)) and
        255) # Explicit standard retention replaces the maximal generic fixture field.
  decodeParameters(bytes).value

let blob = @[4'u8, 5, 6]
let hash = ServicePreimageHash(array[32, byte](blake2b256(blob).value))
proc junior(service: uint32): StateEntry =
  ## Both juniors are currently supervised by the invoker's actual incarnation.
  serviceMetadataEntry(ServiceIndex(service), ServiceMetadata(balance: AccountBalance(100),
      supervisorBalance: AccountBalance(60), supervisor: ServiceIndex(42),
      supervisorCreated: AccountSlot(43), created: AccountSlot(7),
      storageItems: AccountStorageItems(if service == 99: 2'u32 else: 0'u32),
      storageBytes: AccountStorageBytes(if service == 99: 84'u64 else: 0'u64)), ByteLimit(
          ServiceMetadataBytes)).value
proc source(code: seq[seq[byte]] = @[@[50'u8, 0]], data = newSeq[byte](128),
    history = requestedHistory(), retained = false, slot = HeaderSlot(
        128)): PreparedAccumulationMachine =
  ## Real complete source accounts and a request support every account-mutating host independently.
  let request = serviceRequestEntry(ServiceIndex(99), hash, RequestLength(3), history,
      RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(
          3), maxBytes: ByteLimit(13)))).value
  var entries = @[junior(77), junior(99), request]
  if retained:
    entries.add(servicePreimageEntry(ServiceIndex(99), hash, blob,
        ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(
            3))).value) # Retained bytes belong to the available/unavailable request's real hash.
  guestProgram(code, credit = 100000, account = ServiceMetadata(balance: AccountBalance(1000),
      supervisorBalance: AccountBalance(1000), supervisor: ServiceIndex(42),
          supervisorCreated: AccountSlot(43),
      created: AccountSlot(43)), extra = entries, writable = data,
      manager = 42, assigner = 42, delegator = 42, registrar = 42, writes = 4, spareEntries = 8, slot = slot)
proc pair(prepared: PreparedAccumulationMachine, limit = 8'u64,
    facts = 12'u64): AccumulationEffects =
  ## Tracking capacity is explicit and separate from existing key/membership publication proofs.
  let contexts = prepareAccumulationContexts(prepared.machineBootstrap.value, pvmContextConfig()).value
  prepareAccumulationEffects(contexts, createdAccounts = ElementLimit(2),
      deletedAccounts = ElementLimit(2), modifiedAccounts = ElementLimit(limit),
          accountWriteFacts = ElementLimit(facts)).value
proc run(prepared: PreparedAccumulationMachine, limit = 8'u64,
    facts = 12'u64): AccumulationDispatchResult =
  ## Execute current host IDs with finite capture, output, state and membership ceilings.
  executeAccumulationMachine(prepared, parameters(),
      FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1), operand: OperandLimits(
          maxBytes: ByteLimit(132))),
      MemoryByteLimit(128), ExecutionStepLimit(200), HostCallLimit(20), GasCycleLimit(1000),
          pvmContextConfig(),
      serviceProbes = ServiceProbeLimit(1), transferLimit = ElementLimit(2),
          modifiedAccounts = ElementLimit(limit), accountWriteFacts = ElementLimit(facts))
proc context(effects: AccumulationEffects, dimension = AccumulationDimension.Regular): AccumulationEffectContext =
  ## Selected context retains both state and immutable successful-membership facts.
  effects.effectContext(dimension).value
proc check(owner: AccumulationEffectContext, expected: openArray[uint32]) =
  ## First-touch order is deterministic; membership values are independent nominal copies.
  assert owner.effectModifiedAccountCount.value == expected.len, "exact unique membership size"
  for index, service in expected:
    let found = owner.effectModifiedAccountAt(AccumulationModifiedAccountIndex(uint64(index)))
    assert uint32(found.value) == service and owner.effectAccountModified(ServiceIndex(
        service)).value,
        "every expected service is present at its retained first-touch ordinal"
  assert not owner.effectAccountModified(ServiceIndex(12345)).value, "absent identity is false only with enabled tracking"
  let past = owner.effectModifiedAccountAt(AccumulationModifiedAccountIndex(high(uint64)))
  assert past.error == AccumulationEffectError.InvalidIndex, "full-width ordinal is bounded before native narrowing"
proc root(owner: AccumulationEffectContext): array[32, byte] =
  ## Compare ordinary complete-state commitments without deriving modification membership from equality.
  array[32, byte](owner.effectAccounts.value.commitment.root)

let prepared = source()
let initial = pair(prepared)
check(context(initial), [])
let disabled = pair(prepared, 0)
assert context(disabled).effectModifiedAccountCount.error ==
    AccumulationEffectError.ModifiedAccountsDisabled,
    "disabled tracking is distinct from enabled empty membership"
assert default(AccumulationEffectContext).effectModifiedAccountCount.error ==
    AccumulationEffectError.Uninitialized,
    "default contexts expose no modification facts"
let disabledAt = context(disabled).effectModifiedAccountAt(AccumulationModifiedAccountIndex(0))
assert disabledAt.error == AccumulationEffectError.ModifiedAccountsDisabled, "disabled ordinal extraction grants no service"
let disabledContains = context(disabled).effectAccountModified(ServiceIndex(42))
assert disabledContains.error == AccumulationEffectError.ModifiedAccountsDisabled, "disabled membership grants no fabricated false"

# Every account row contributes exactly its normative target set.
let stored = recordAccumulationStorage(initial, [1'u8], [2'u8], parameters(), ByteLimit(1),
    ServiceIndex(77)).value.effects
check(context(stored), [77'u32])
let absentWrite = recordAccumulationStorage(initial, [9'u8], [], parameters(), ByteLimit(1),
    ServiceIndex(77)).value.effects
check(context(absentWrite), [77'u32])
assert root(context(absentWrite)) == root(context(initial)), "successful absent-key deletion still modifies its target"

let solicited = recordAccumulationSolicit(initial, default(ServicePreimageHash), RequestLength(3),
    parameters(), ServiceIndex(77)).value
check(context(solicited), [77'u32])
let forgotten = recordAccumulationForget(solicited, default(ServicePreimageHash), RequestLength(3),
    parameters(), ServiceIndex(77)).value
check(context(forgotten), [77'u32])
assert root(context(forgotten)) == root(context(initial)), "restored request and metadata bytes retain successful membership"
let upgraded = recordAccumulationUpgrade(initial, default(CodeHash), Gas(0), Gas(0), ServiceIndex(77)).value
check(context(upgraded), [77'u32])
assert root(context(upgraded)) == root(context(initial)), "successful identical upgrade is still a modification"
let supervised = recordAccumulationSupervisor(initial, ServiceIndex(77), ServiceIndex(42)).value
check(context(supervised), [77'u32])
assert root(context(supervised)) == root(context(initial)), "successful identical supervision is still a modification"
let born = recordAccumulationNew(initial, AccumulationNewService(length: RequestLength(3)),
    parameters(), ServiceProbeLimit(1), ServiceIndex(77), AccumulationFundingMode(3)).value
check(context(born.effects), [77'u32])
assert not context(born.effects).effectAccountModified(born.service).value, "new marks the payer, not its separately tracked child"
let planned = prepareAccumulationTransfer(initial, AccumulationTransferDestination(99),
    TransferBalance(0), Gas(0), default(TransferMemo), parameters(), ServiceIndex(77),
        AccumulationFundingMode(2)).value
check(context(initial), [])
let deferred = commitAccumulationTransfer(planned, ElementLimit(1)).value
check(context(deferred), [77'u32])
assert root(context(deferred)) == root(context(initial)), "zero deferred amount marks its source without changing account bytes"
let direct = recordAccumulationDirectTransfer(initial, ServiceIndex(77),
    AccumulationTransferDestination(99), TransferBalance(0), AccumulationFundingMode(0), parameters()).value
check(context(direct), [77'u32, 99])
assert root(context(direct)) == root(context(initial)), "zero direct amount marks both unchanged endpoints"
let crossed = recordAccumulationDirectTransfer(initial, ServiceIndex(77),
    AccumulationTransferDestination(77), TransferBalance(0), AccumulationFundingMode(1), parameters()).value
check(context(crossed), [77'u32])
let ejected = recordAccumulationEject(initial, AccumulationEjectTarget(77), parameters()).value
check(context(ejected), [42'u32, 77])
assert context(ejected).effectAccounts.value.lookup(chapterServiceKey(StateChapter(255),
    ServiceIndex(77))).error ==

StateStoreError.MissingKey, "deleted identities remain members after their account disappears"

# Non-account effects preserve the set without adding their external provision targets.
let roles = PrivilegeState(manager: ServiceIndex(42), delegator: ServiceIndex(42),
    registrar: ServiceIndex(42), assigners: @[ServiceIndex(42), ServiceIndex(42)])
let blessed = recordAccumulationBless(initial, roles, pvmContextConfig().privileges).value
let assigned = recordAccumulationAssign(initial, AuthorizationCoreIndex(0), newSeq[AuthorizerHash](
    80), ServiceIndex(42), pvmContextConfig().queues, pvmContextConfig().privileges).value
let designated = recordAccumulationDesignate(initial, newSeq[StateValidator](6), pvmContextConfig().staging).value
let yielded = recordAccumulationYield(initial, default(OutputCommitment)).value
let provided = recordAccumulationProvision(initial, ServiceIndex(99), blob,
    AccumulationProvisionLimits(items: ElementLimit(1), perBlob: ByteLimit(3),
        totalBlobBytes: ByteLimit(3))).value
for unchanged in [blessed, assigned, designated, yielded, provided]:
  check(context(unchanged), []) # Non-account outputs never create implicit modification facts.
let yieldingAfter = recordAccumulationYield(direct, default(OutputCommitment)).value
check(context(yieldingAfter), [77'u32, 99])

# Capacity counts unique successful identities; failure preserves every older owner and never hashes a candidate.
let oneMember = pair(prepared, 1)
let once = recordAccumulationUpgrade(oneMember, default(CodeHash), Gas(0), Gas(0), ServiceIndex(77)).value
let twice = recordAccumulationSupervisor(once, ServiceIndex(77), ServiceIndex(42)).value
check(context(twice), [77'u32])
failHash(1)
let over = recordAccumulationDirectTransfer(oneMember, ServiceIndex(77),
    AccumulationTransferDestination(99), TransferBalance(0), AccumulationFundingMode(0), parameters())
assert over.error == AccumulationEffectError.LimitExceeded and hashCalls() == 0,
    "complete unique-membership capacity is checked before candidate map hashing"
failHash(0)
check(context(oneMember), [])
failHash(1)
let broken = recordAccumulationUpgrade(initial, default(CodeHash), Gas(1), Gas(0), ServiceIndex(77))
assert broken.error == AccumulationEffectError.BackendFailure, "failed account hashing cannot publish earlier prepared membership"
failHash(0)
check(context(initial), [])
let unknown = recordAccumulationSupervisor(initial, ServiceIndex(12345), ServiceIndex(42))
assert unknown.error == AccumulationEffectError.UnknownService, "protocol refusal grants no membership successor"
check(context(initial), [])
let checkpoint = checkpointAccumulationEffects(upgraded).value
let later = recordAccumulationDirectTransfer(checkpoint, ServiceIndex(42),
    AccumulationTransferDestination(99), TransferBalance(0), AccumulationFundingMode(0), parameters()).value
check(context(later), [77'u32, 42, 99])
check(context(later, AccumulationDimension.Exceptional), [77'u32])
check(context(initial), [])

# Real guest programs verify dispatch wiring and terminal-selected facts independently of direct API calls.
proc upgrade(address = 196608'u64): seq[seq[byte]] =
  ## Target a real supervised account with a complete fixed hash capture and unchanged minimum gas fields.
  @[registerImmediate(7, 77), registerImmediate(8, address), registerImmediate(9, 0),
      registerImmediate(10, 0), @[10'u8, 21]]
for checkpoint in [false, true]:
  var instructions = upgrade()
  if checkpoint: instructions.add(@[10'u8, 19]) # Y captures exactly the completed successful no-op.
  instructions.add(@[0'u8])
  let completed = run(source(instructions))
  assert completed.error == AccumulationDispatchError.None and completed.value.exit ==
      StepExit.Panic,
      "genuine upgrade/no-op guest reaches the selected exceptional terminal"
  check(context(completed.effects), [77'u32])
  let selected = normalizeAccumulationOutcome(completed).value.outcomeContext.value
  assert selected.effectAccountWriteFactCount.value == (if checkpoint: 1 else: 0),
      "terminal selection restores physical facts together with matching account membership"
  if checkpoint: check(selected, [77'u32])
  else: check(selected, []) # Panic restores membership together with the initial accounts.
var restoring = upgrade()
for instruction in upgrade(196640): restoring.add(instruction)
restoring.add(@[50'u8, 0])
var input = newSeq[byte](128)
input[0] = 1
let restored = run(source(restoring, input))
check(context(restored.effects), [77'u32])
assert root(context(restored.effects)) == root(context(restored.effects,
    AccumulationDimension.Exceptional)),
    "genuine changed-then-restored guest retains membership at an equal final root"
let missed = run(source(@[registerImmediate(7, 12345), registerImmediate(8, 42), @[10'u8, 29], @[
    50'u8, 0]]))
check(context(missed.effects), [])

# Initial incoming-transfer membership is based on presence, including a zero credit and unchanged root.
var incoming = batchFixture(incoming = false, firstEnvelope = guestEnvelope([@[50'u8, 0]]),
    secondEnvelope = guestEnvelope([@[50'u8, 0]]))
incoming.inputs = prepareAccumulationInputs(incoming.inputs.invocationOperands.value,
    [DeferredTransfer(source: ServiceIndex(1), destination: ServiceIndex(42),
        amount: TransferBalance(0))],
    [AlwaysAccumulate(service: ServiceIndex(42), gas: PrivilegeGas(100000))],
    AccumulationInputConfig(inputs: ElementLimit(1), allowances: ElementLimit(1),
        services: ElementLimit(1))).value
let credited = batchExecution(incoming, 0, parameters = parameters(),
    modifiedAccounts = ElementLimit(1), accountWriteFacts = ElementLimit(1))
assert credited.error == AccumulationDispatchError.None, "zero credit executes within an explicit one-member budget"
check(context(credited.effects), [42'u32])
check(context(credited.effects, AccumulationDimension.Exceptional), [42'u32])
assert root(context(credited.effects)) == array[32, byte](
    incoming.state.snapshot.value.commitment.root),
    "zero incoming credit marks the recipient at an unchanged complete-state root"

# Physical write facts bind actual keys to their logical account, independently of membership.
proc checkFacts(owner: AccumulationEffectContext, services: openArray[uint32], keys: openArray[StateKey]) =
  ## A copied descriptor grants no mutable access to the retained fact set or account values.
  let count = owner.effectAccountWriteFactCount
  assert count.error == AccumulationEffectError.None, "queried fixtures explicitly enable physical write facts"
  assert services.len == keys.len and count.value == keys.len,
      "exact unique account/key fact count"
  for index, key in keys:
    let value = owner.effectAccountWriteFactAt(AccumulationAccountWriteFactIndex(uint64(index))).value
    assert uint32(value.service) == services[index] and array[31, byte](value.key) == array[31,
        byte](key),
        "successful physical key remains bound to its actual account owner"
  let past = owner.effectAccountWriteFactAt(AccumulationAccountWriteFactIndex(high(uint64)))
  assert past.error == AccumulationEffectError.InvalidIndex, "full-width fact ordinal is checked before native indexing"
let ownKey = chapterServiceKey(StateChapter(255), ServiceIndex(42))
let juniorKey = chapterServiceKey(StateChapter(255), ServiceIndex(77))
let otherKey = chapterServiceKey(StateChapter(255), ServiceIndex(99))
let storageKey = serviceStorageKey(ServiceIndex(77), [1'u8], ByteLimit(1)).value
let absentKey = serviceStorageKey(ServiceIndex(77), [9'u8], ByteLimit(1)).value
let requestKey = serviceRequestKey(ServiceIndex(77), default(ServicePreimageHash), RequestLength(3),
    ByteLimit(32)).value
checkFacts(context(initial), [], [])
checkFacts(context(stored), [77'u32, 77], [juniorKey, storageKey])
checkFacts(context(absentWrite), [77'u32, 77], [juniorKey, absentKey])
checkFacts(context(solicited), [77'u32, 77], [requestKey, juniorKey])
checkFacts(context(forgotten), [77'u32, 77], [requestKey, juniorKey])
assert context(forgotten).effectAccounts.value.lookup(requestKey).error ==
    StateStoreError.MissingKey,
    "a retained successful key fact does not fabricate a final value after deletion"
checkFacts(context(upgraded), [77'u32], [juniorKey])
checkFacts(context(supervised), [77'u32], [juniorKey])
let childKey = chapterServiceKey(StateChapter(255), born.service)
let childRequest = serviceRequestKey(born.service, default(ServicePreimageHash), RequestLength(3),
    ByteLimit(32)).value
let childId = uint32(born.service)
checkFacts(context(born.effects), [77'u32, childId, childId], [juniorKey, childKey, childRequest])
checkFacts(context(deferred), [77'u32], [juniorKey])
checkFacts(context(direct), [77'u32, 99], [juniorKey, otherKey])
checkFacts(context(crossed), [77'u32], [juniorKey])
checkFacts(context(ejected), [77'u32, 42], [juniorKey, ownKey])
checkFacts(context(yieldingAfter), [77'u32, 99], [juniorKey, otherKey])
for unchanged in [blessed, assigned, designated, yielded, provided]:
  checkFacts(context(unchanged), [], []) # Global chapters and provision payloads add no account key facts.
checkFacts(context(later), [77'u32, 42, 99], [juniorKey, ownKey, otherKey])
checkFacts(context(later, AccumulationDimension.Exceptional), [77'u32], [juniorKey])
checkFacts(context(restored.effects), [77'u32], [juniorKey])
checkFacts(context(missed.effects), [], [])
checkFacts(context(credited.effects), [42'u32], [ownKey])
checkFacts(context(credited.effects, AccumulationDimension.Exceptional), [42'u32], [ownKey])
var copied = context(upgraded).effectAccountWriteFactAt(AccumulationAccountWriteFactIndex(0)).value
copied.service = ServiceIndex(99)
copied.key = default(StateKey)
checkFacts(context(upgraded), [77'u32], [juniorKey])
let noFacts = pair(prepared, 8, 0)
assert context(noFacts).effectAccountWriteFactCount.error ==
    AccumulationEffectError.AccountWriteFactsDisabled,
    "disabled fact capture is distinct from an enabled empty trace"
let disabledFact = context(noFacts).effectAccountWriteFactAt(AccumulationAccountWriteFactIndex(0))
assert disabledFact.error == AccumulationEffectError.AccountWriteFactsDisabled, "disabled extraction grants no copied account/key descriptor"
let defaultFact = default(AccumulationEffectContext).effectAccountWriteFactAt(
    AccumulationAccountWriteFactIndex(0))
assert defaultFact.error == AccumulationEffectError.Uninitialized, "default contexts supply no fact payload"
let oneFact = pair(prepared, 8, 1)
let touched = recordAccumulationUpgrade(oneFact, default(CodeHash), Gas(0), Gas(0), ServiceIndex(77)).value
let repeated = recordAccumulationSupervisor(touched, ServiceIndex(77), ServiceIndex(42)).value
checkFacts(context(repeated), [77'u32], [juniorKey])
let oneCrossed = recordAccumulationDirectTransfer(oneFact, ServiceIndex(77),
    AccumulationTransferDestination(77), TransferBalance(0), AccumulationFundingMode(1), parameters()).value
checkFacts(context(oneCrossed), [77'u32], [juniorKey])
failHash(1)
let twoFacts = recordAccumulationDirectTransfer(oneFact, ServiceIndex(77),
    AccumulationTransferDestination(99), TransferBalance(0), AccumulationFundingMode(0), parameters())
assert twoFacts.error == AccumulationEffectError.LimitExceeded and hashCalls() == 0,
    "complete physical-key fact capacity precedes account hashing and publication"
failHash(0)
check(context(oneFact), [])
checkFacts(context(oneFact), [], [])
let twoFactBudget = pair(prepared, 8, 2)
let refusedChild = recordAccumulationNew(twoFactBudget, AccumulationNewService(
    length: RequestLength(3)), parameters(),

ServiceProbeLimit(1), ServiceIndex(77), AccumulationFundingMode(0))
assert refusedChild.error == AccumulationEffectError.LimitExceeded, "creation requires payer, child metadata and child request facts atomically"
checkFacts(context(twoFactBudget), [], [])
failHash(1)
let failedFact = recordAccumulationUpgrade(initial, default(CodeHash), Gas(1), Gas(0), ServiceIndex(77))
assert failedFact.error == AccumulationEffectError.BackendFailure, "failed hashing publishes neither a fact nor an account version"
failHash(0)
checkFacts(context(initial), [], [])
let independent = pair(prepared, 0, 2)
let recorded = recordAccumulationDirectTransfer(independent, ServiceIndex(77),
    AccumulationTransferDestination(99), TransferBalance(0), AccumulationFundingMode(0), parameters()).value
checkFacts(context(recorded), [77'u32, 99], [juniorKey, otherKey])
assert context(recorded).effectModifiedAccountCount.error ==
    AccumulationEffectError.ModifiedAccountsDisabled,
    "physical write capture and logical membership ceilings remain independent"
# Expired two-slot forgetting captures the third physical key, not only metadata/history.
let expired = pair(source(history = unavailableHistory(RequestSlot(4), RequestSlot(7)),
    retained = true, slot = HeaderSlot(20000)))
let expiredForget = recordAccumulationForget(expired, hash, RequestLength(3), parameters(),
    ServiceIndex(99))
assert expiredForget.error == AccumulationEffectError.None, "expired two-slot request reaches complete removal"
let removed = expiredForget.value
let expiredRequest = serviceRequestKey(ServiceIndex(99), hash, RequestLength(3), ByteLimit(32)).value
let retainedKey = servicePreimageKey(ServiceIndex(99), hash, ByteLimit(32)).value
checkFacts(context(removed), [99'u32, 99, 99], [otherKey, expiredRequest, retainedKey])
let absentRetained = context(removed).effectAccounts.value.lookup(retainedKey)
let priorRetained = context(expired).effectAccounts.value.lookup(retainedKey).value.bytes
assert absentRetained.error == StateStoreError.MissingKey, "expired forgetting retains the removed physical preimage key fact"
assert priorRetained == blob, "prior raw preimage owner remains independent of later deletion"
let before = getOccupiedMem()
for iteration in 0..<1000:
  let owned = pair(prepared)
  let modified = recordAccumulationDirectTransfer(owned, ServiceIndex(77),
      AccumulationTransferDestination(99), TransferBalance(0), AccumulationFundingMode(0),
          parameters()).value
  check(context(modified), [77'u32, 99]) # Release immutable membership and source-bound checkpoints on every iteration.
  checkFacts(context(modified), [77'u32, 99], [juniorKey,
      otherKey]) # Fixed facts retain no mutable account values or parent chains.
let after = getOccupiedMem()
assert before == after, "modified-account owners release without retaining prior effect graphs"
recordArcRelease("pvm_modified_accounts", 1000, before, after)
echo "PVM modified accounts passed"
echo "ARC_RELEASE cycles=1000 unchanged"
