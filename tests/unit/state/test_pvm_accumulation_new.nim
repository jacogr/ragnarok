# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_new_arc_release"}

## Authored new-service programs verify exact funding, bounded IDs and atomic account/cursor versions.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, header, state_layout, state_accounts, state_requests,
  state_service_values, state_privileges, state_safrole, state_trie, c2_records]
import ../../../src/state/[accumulation_dispatch, accumulation_effects, accumulation_context,
  accumulation_machine, accumulation_invocation, accumulation_outcome, store]
import ../../../src/pvm/[machine, program, step, gas, host_fetch]
import ../../../src/crypto/primitives
import ../../support/[pvm_accumulation_program, pvm_accumulation_context, arc_evidence]

# Inject refusal after authentic bootstrap construction, without replacing the maintained crypto backend.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
# Count hashes to distinguish request-key derivation from complete-map publication work.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
# Refuse after successful child hashes to exercise cleanup of a partial candidate tree.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

# Author deposit rates independently in the fixed parameter tuple; all other settings retain validated values.
proc parameters(base = 10'u64, item = 3'u64, octet = 2'u64): Parameters =
  var bytes = encodeParameters(pvmParameters())
  for field, value in [item, octet, base]:
    for i in 0..<8:
      bytes[field*8+i] = byte((value shr (8*i)) and 255) # Exact E8 field order is item/byte/account.
  bytes[24] = 2
  bytes[25] = 0
  bytes[82] = 80
  bytes[83] = 0 # Match the tiny prepared profile for subsequent privilege/queue calls.
  decodeParameters(bytes).value

# All offered hash bytes are opaque; creation must not require their preimage to exist.
proc offered(): seq[byte] =
  result = newSeq[byte](32)
  for i in 0..<32:
    result[i] = byte(i*7+3) # This bounded independent pattern spans every raw code-hash octet.

# Build authentic guest instructions while preserving explicitly selected initial authority and store policy.
proc source(length = 5'u64, address = 196608'u64, accumulation = 123'u64, transfer = 456'u64,
    gratis = 0'u64, desired = high(uint64), manager = 0'u32, registrar = 0'u32,
    credit = 100000'u64, account = ServiceMetadata(balance: AccountBalance(1000)),
    data: seq[byte] = offered(), extra: seq[StateEntry] = @[], spareEntries = 6,
    writes = 3'u64, bootstrapProbes = 1'u64,
    suffix: seq[seq[byte]] = @[@[50'u8, 0]]): PreparedAccumulationMachine =
  var instructions = @[registerImmediate(7, address), registerImmediate(8, length),
    registerImmediate(9, accumulation), registerImmediate(10, transfer), registerImmediate(11,
        gratis),
    registerImmediate(12, desired), @[10'u8, 19]]
  for instruction in suffix:
    instructions.add(instruction) # Later effects execute through the same decoded production guest stream.
  guestProgram(instructions, credit, manager = manager, registrar = registrar, delegator = 42,
    assigner = 42, account = account, writable = data, extra = extra, spareEntries = spareEntries,
    writes = writes, probes = bootstrapProbes)

# Probe, copy, provision and execution ceilings are local policies, distinct from fixed protocol gas.
proc run(prepared: PreparedAccumulationMachine, params: Parameters = parameters(), limit = 32'u64,
    probes = 3'u64, provisions = default(AccumulationProvisionLimits)): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, params,
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132))), MemoryByteLimit(limit),
    ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000), pvmContextConfig(), provisions,
    ServiceProbeLimit(probes))

# Instruction costs are priced independently of the new row's fixed 3855 gas.
proc price(prepared: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(prepared.accumulationMachine.value).value, CodeAddress(5),
      GasCycleLimit(1000)).value)

# Retain one complete effects version only after actual guest execution succeeds.
proc context(done: AccumulationDispatchResult, dimension = AccumulationDimension.Regular): AccumulationEffectContext =
  assert done.error == AccumulationDispatchError.None, "completed execution grants service effects"
  done.effects.effectContext(dimension).value

# Read complete canonical metadata by its actual current account identity.
proc metadata(owner: AccumulationEffectContext, service: ServiceIndex): ServiceMetadata =
  let found = owner.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255), service))
  assert found.error == StateStoreError.None and found.value.byteLength == 89, "complete current account metadata"
  let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(89))
  assert decoded.error == ServiceMetadataError.None and decoded.value.consumed == 89, "canonical metadata encoding"
  decoded.value.metadata

# Independently step the small public ID interval, with all intermediate values below 2^33.
proc advance(start: ServiceIndex, offset = 42'u64): ServiceIndex =
  ServiceIndex(uint32(FirstPublicService+(uint64(uint32(start))-FirstPublicService+offset) mod
    (PublicServiceEnd-FirstPublicService)))

# Hash-derived initial ID depends on invocation identity/entropy/slot, not code, gas or child parameters.
proc initialId(): ServiceIndex =
  initialAccumulationService(ServiceIndex(42), default(StateEntropyWord), HeaderSlot(128)).value

# Verify exact metadata, a single empty request and absent code/storage in this coherent successor.
proc checkChild(owner: AccumulationEffectContext, service: ServiceIndex, childBalance = 188'u64,
    length = 5'u32, accumulation = 123'u64, transfer = 456'u64, gratis = 0'u64,
    hashBytes: seq[byte] = offered()) =
  let child = metadata(owner, service)
  assert uint64(child.balance) == childBalance and uint64(child.depositOffset) == gratis, "exact child threshold and gratis"
  assert uint32(child.storageItems) == 2 and uint64(child.storageBytes) == 81'u64+uint64(length), "one request has two items and 81+length octets"
  assert uint64(child.minimumAccumulationGas) == accumulation and uint64(
      child.minimumTransferGas) == transfer, "full-width minimum gas fields"
  assert uint32(child.created) == 128 and uint32(child.lastAccumulation) == 0 and uint32(
      child.parent) == 42, "slot and parent derive from provenance"
  let hash = array[32, byte](child.codeHash)
  for i in 0..<32:
    assert hash[i] == hashBytes[i], "offered raw hash preserved"
  let map = owner.effectAccounts.value
  let request = serviceRequestKey(service, ServicePreimageHash(hash), RequestLength(length),
      ByteLimit(32)).value
  assert map.lookup(request).value.bytes == @[0'u8], "single canonical empty requested history"
  let absent = servicePreimageKey(service, ServicePreimageHash(hash), ByteLimit(32)).value
  assert map.lookup(absent).error == StateStoreError.MissingKey, "creation does not fabricate a code preimage"
  let storage = serviceStorageKey(service, [], ByteLimit(0)).value
  assert map.lookup(storage).error == StateStoreError.MissingKey, "new service has no empty-key storage"

let valid = source()
let done = run(valid)
assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt, "funded creation completes"
let selected = ServiceIndex(uint32(uint64(machineInfo(done.value.machine).value.registers[7])))
assert uint32(selected) == uint32(initialId()), "first creation returns prepared public ID"
checkChild(context(done), selected)
assert uint64(metadata(context(done), ServiceIndex(42)).balance) == 812, "creator funds exact child balance"
assert uint32(context(done).effectInfo.value.nextService) == uint32(advance(selected)), "current public cursor advances by 42"
let initial = context(done, AccumulationDimension.Exceptional)
assert initial.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255), selected)).error ==
    StateStoreError.MissingKey, "initial account map retains absence"
assert uint32(initial.effectInfo.value.nextService) == uint32(selected) and uint64(metadata(initial,
    ServiceIndex(42)).balance) == 1000, "checkpoint retains original cursor and balance"
assert uint32(context(done).effectInitialContext.value.contextInfo.value.nextService) == uint32(
    selected), "historical initial cursor never advances"
for chapter in [2, 7, 12]:
  assert context(done).effectAccounts.value.lookup(chapterKey(StateChapter(chapter))).value.bytes ==
    initial.effectAccounts.value.lookup(chapterKey(StateChapter(chapter))).value.bytes, "unrelated component preserved"
assert readBytes(memoryOf(valid.accumulationMachine.value).value, MemoryAddress(196608),
    MemoryLength(32), MemoryByteLimit(32)).value ==
  readBytes(memoryOf(done.value.machine).value, MemoryAddress(196608), MemoryLength(32),
      MemoryByteLimit(32)).value, "creation reads without writing guest memory"
assert uint64(machineInfo(valid.accumulationMachine.value).value.gas) == 100000, "source CPU unchanged"
for balance in [197'u64, 198, 199]:
  let completed = run(source(account = ServiceMetadata(balance: AccountBalance(balance))))
  if balance == 197:
    assert uint64(machineInfo(completed.value.machine).value.registers[7]) == high(uint64)-6, "CASH leaves creator's own threshold funded"
    assert uint64(metadata(context(completed), ServiceIndex(42)).balance) == balance, "CASH does not debit"
  else:
    checkChild(context(completed), selected)
    assert uint64(metadata(context(completed), ServiceIndex(42)).balance) == balance-188, "exact creator funding boundary"
for gratis in [1'u64, 100, 188, high(uint64)]:
  let authorized = run(source(gratis = gratis, manager = 42))
  let minimum = (if gratis >= 188: 0'u64 else: 188-gratis)
  checkChild(context(authorized), selected, childBalance = minimum, gratis = gratis)
  assert uint64(metadata(context(authorized), ServiceIndex(42)).balance) == 1000-minimum, "gratis reduces only child debit"
  let unauthorized = run(source(gratis = gratis, manager = 0, registrar = 42, desired = 42,
    account = ServiceMetadata(balance: AccountBalance(0))))
  assert uint64(machineInfo(unauthorized.value.machine).value.registers[7]) == high(uint64)-8, "HUH precedes CASH and reserved FULL"
for desired in [0'u64, 7, 65535]:
  let reserved = run(source(registrar = 42, desired = desired), probes = 0)
  assert uint64(machineInfo(reserved.value.machine).value.registers[7]) == desired, "registrar selects exact reserved ID"
  checkChild(context(reserved), ServiceIndex(uint32(desired)))
  assert uint32(context(reserved).effectInfo.value.nextService) == uint32(selected), "reserved creation preserves public cursor without probes"
for desired in [0'u64, 42, 65536, 0x100000007'u64, high(uint64)]:
  # Non-registrars ignore the complete desired register, including occupied reserved IDs and high bits.
  let automatic = run(source(desired = desired))
  assert uint64(machineInfo(automatic.value.machine).value.registers[7]) == uint64(uint32(
      selected)), "non-registrar uses automatic ID"
for desired in [65536'u64, 0x100000007'u64, high(uint64)]:
  assert uint64(machineInfo(run(source(registrar = 42,
      desired = desired)).value.machine).value.registers[7]) == uint64(uint32(selected)), "registrar non-reserved proposal uses automatic ID"
let full = run(source(registrar = 42, desired = 42))
assert uint64(machineInfo(full.value.machine).value.registers[7]) == high(uint64)-4, "reserved collision returns exact FULL constant"
let cashBeforeFull = run(source(registrar = 42, desired = 42, account = ServiceMetadata(
    balance: AccountBalance(197))))
assert uint64(machineInfo(cashBeforeFull.value.machine).value.registers[7]) == high(uint64)-6, "CASH precedes FULL"
for address in [0'u64, 65536'u64+4096-16, 196608'u64+8192-16, 0x100000000'u64, high(uint64)]:
  let failed = run(source(address = address, gratis = 1, registrar = 42, desired = 42))
  assert failed.error == AccumulationDispatchError.None and failed.value.exit == StepExit.Panic, "bad hash memory precedes HUH/CASH/FULL"
  assert uint64(machineInfo(failed.value.machine).value.registers[7]) == address, "panic preserves full pointer"
for length in [0x100000000'u64, high(uint64)]:
  let failed = run(source(length = length, gratis = 1), limit = 0)
  assert failed.value.exit == StepExit.Panic, "out-of-domain advertised length panics without truncation"
for length in [0'u64, uint64(high(uint32))]:
  let completed = run(source(length = length, accumulation = high(uint64), transfer = high(uint64)),
      params = parameters(0, 0, 0))
  checkChild(context(completed), selected, childBalance = 0, length = uint32(length),
    accumulation = high(uint64), transfer = high(uint64)) # No reserved length or signed-gas restriction is invented.
assert run(valid, limit = 31).error == AccumulationDispatchError.LimitExceeded, "fixed hash capture ceiling"
for available in [0'u64, 3854, 3855, 3856]:
  let completed = run(source(credit = price(valid)+available))
  assert completed.error == AccumulationDispatchError.None, "fixed gas boundary completes"
  let cpu = machineInfo(completed.value.machine).value
  if available < 3855:
    assert completed.value.exit == StepExit.OutOfGas and uint64(cpu.gasDeficit) == 3855-available, "exact creation deficit"
    assert uint64(cpu.registers[7]) == 196608 and uint32(context(
        completed).effectInfo.value.nextService) == uint32(selected), "OOG preserves pointer and cursor"
  else:
    assert completed.value.exit == StepExit.Halt and uint64(cpu.gas) == available-3855, "exact funded charge"
assert run(source(length = high(uint64), address = high(uint64), credit = price(valid)),
    limit = 0).value.exit == StepExit.OutOfGas, "charge precedes input validation"
checkChild(context(run(source(data = newSeq[byte](32)))), selected, hashBytes = newSeq[byte](
    32)) # Zero offered hashes are ordinary values.
let fullCredit = run(source(credit = high(uint64)))
assert uint64(machineInfo(fullCredit.value.machine).value.gas) == high(uint64)-price(valid)-3855, "full-width gas credit subtraction"
# Repeated creation consumes the current cursor and current balance, retaining all prior children.
let repeated = run(source(suffix = @[registerImmediate(7, 196608), @[10'u8, 19], registerImmediate(
    7, 196608), @[10'u8, 19], @[50'u8, 0]]))
for ordinal in 0..<3:
  checkChild(context(repeated), advance(selected, uint64(
      42*ordinal))) # All created accounts and requests remain present.
assert uint64(metadata(context(repeated), ServiceIndex(42)).balance) == 436, "three exact creator debits"
assert uint32(context(repeated).effectInfo.value.nextService) == uint32(advance(selected, 126)), "third public cursor advancement"
# Initial collision scanning and successor collision scanning have independently explicit ceilings.
let occupiedA = serviceMetadataEntry(advance(selected), default(ServiceMetadata), ByteLimit(89)).value
let occupiedB = serviceMetadataEntry(advance(selected, 43), default(ServiceMetadata), ByteLimit(89)).value
let colliding = source(extra = @[occupiedA, occupiedB])
assert run(colliding, probes = 2).error == AccumulationDispatchError.LimitExceeded, "final absence check consumes a probe"
let skipped = run(colliding, probes = 3)
assert uint32(context(skipped).effectInfo.value.nextService) == uint32(advance(selected, 44)), "successor skips occupied initial IDs"
let initialOccupied = serviceMetadataEntry(selected, default(ServiceMetadata), ByteLimit(89)).value
let initialSkipped = run(source(extra = @[initialOccupied], bootstrapProbes = 2))
assert uint64(machineInfo(initialSkipped.value.machine).value.registers[7]) == uint64(uint32(
    advance(selected, 1))), "bootstrap selects first unused public ID"
assert run(valid, probes = 0).error == AccumulationDispatchError.LimitExceeded, "automatic successor requires explicit probe capacity"
let initialMap = initial.effectAccounts.value
assert uint32(nextAccumulationService(initialMap, ServiceIndex(uint32(PublicServiceEnd-1)),
    ServiceProbeLimit(1)).value) == uint32(FirstPublicService+41), "plus-42 wraps within the exact public interval"
for id in [0'u64, FirstPublicService-1, PublicServiceEnd, uint64(high(uint32))]:
  assert nextAccumulationService(initialMap, ServiceIndex(uint32(id)), ServiceProbeLimit(
      1)).error == AccumulationInvocationError.InvalidIndex, "reserved inputs cannot enter public advancement"
assert nextAccumulationService(initialMap, selected, ServiceProbeLimit(0)).error ==
    AccumulationInvocationError.LimitExceeded, "advancement does not bypass zero probe policy"
# Snapshot membership is explicit: created IDs belong to current state but not invocation-start state.
let preceding = ServiceIndex(uint32(FirstPublicService+(uint64(uint32(
    selected))-FirstPublicService +
  (PublicServiceEnd-FirstPublicService)-42) mod (PublicServiceEnd-FirstPublicService)))
assert uint32(nextAccumulationService(initialMap, preceding, ServiceProbeLimit(1)).value) == uint32(
    selected), "initial membership retains created-ID absence"
assert uint32(nextAccumulationService(context(done).effectAccounts.value, preceding,
    ServiceProbeLimit(2)).value) == uint32(advance(selected, 1)), "current membership independently observes the created ID"
# Full-width deposit terms and carry arithmetic cannot wrap into an affordable creation.
let wealthy = ServiceMetadata(balance: AccountBalance(high(uint64)), depositOffset: AccountBalance(
    high(uint64)))
let allFunded = run(source(account = wealthy), params = parameters(high(uint64), 0, 0))
checkChild(context(allFunded), selected, childBalance = high(uint64))
assert uint64(metadata(context(allFunded), ServiceIndex(42)).balance) == 0, "exact full-width child debit"
let carried = run(source(account = wealthy, manager = 42, gratis = high(uint64)),
    params = parameters(high(uint64), 0, 0))
checkChild(context(carried), selected, childBalance = 0, gratis = high(uint64))
assert uint64(metadata(context(carried), ServiceIndex(42)).balance) == high(uint64), "balance-plus-gratis retains its carry"
for rates in [(0'u64, 0'u64, high(uint64)), (high(uint64), high(uint64), high(uint64))]:
  let (base, item, octet) = rates
  let refused = run(source(account = wealthy, manager = 42, gratis = high(uint64)),
      params = parameters(base, item, octet))
  assert uint64(machineInfo(refused.value.machine).value.registers[7]) == high(uint64)-6, "wide deposit products return CASH without saturation"
for checkpoint in [false, true]:
  let suffix = (if checkpoint: @[@[10'u8, 18], @[0'u8]] else: @[@[0'u8]])
  let failed = run(source(suffix = suffix))
  assert failed.value.exit == StepExit.Panic, "authored terminal panic"
  let chosen = normalizeAccumulationOutcome(failed).value.outcomeContext.value
  assert chosen.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255), selected)).error ==
    (if checkpoint: StateStoreError.None else: StateStoreError.MissingKey), "panic selects complete account checkpoint"
  assert uint32(chosen.effectInfo.value.nextService) == uint32(if checkpoint: advance(
      selected) else: selected), "panic selects matching cursor checkpoint"
  let exhausted = run(source(credit = price(valid)+4000, suffix = (if checkpoint:
    @[@[10'u8, 18], registerImmediate(7, 196608), @[10'u8, 19], @[50'u8, 0]] else:
    @[registerImmediate(7, 196608), @[10'u8, 19], @[50'u8, 0]])))
  assert exhausted.value.exit == StepExit.OutOfGas, "second creation is unaffordable"
  let retained = normalizeAccumulationOutcome(exhausted).value.outcomeContext.value
  assert uint32(retained.effectInfo.value.nextService) == uint32(if checkpoint: advance(
      selected) else: selected), "OOG selects matching cursor checkpoint"
# Later regular mutations retain both the created child and the advanced cursor.
let preserved = run(source(suffix = @[registerImmediate(7, 65536), @[10'u8, 26],
  registerImmediate(7, 65536), registerImmediate(8, 1), registerImmediate(9, 196608),
  registerImmediate(10, 3), @[10'u8, 5], @[50'u8, 0]]))
assert uint64(machineInfo(preserved.value.machine).value.registers[7]) == high(uint64), "storage write succeeds after creation"
assert context(preserved).effectInfo.value.hasYield and uint32(context(
    preserved).effectInfo.value.nextService) == uint32(advance(selected)), "yield/storage retain advanced cursor"
checkChild(context(preserved), selected)
let assigned = run(source(suffix = @[registerImmediate(7, 0), registerImmediate(8, 65536),
  registerImmediate(9, 99), @[10'u8, 16], @[50'u8, 0]]), limit = 2560)
assert uint64(machineInfo(assigned.value.machine).value.registers[7]) == 0 and uint32(context(
    assigned).effectInfo.value.nextService) == uint32(advance(selected)), "assign retains advanced cursor"
checkChild(context(assigned), selected)
let designated = run(source(suffix = @[registerImmediate(7, 65536), registerImmediate(8, 6), @[
    10'u8, 17], @[50'u8, 0]]), limit = 2016)
assert uint64(machineInfo(designated.value.machine).value.registers[7]) == 0 and uint32(context(
    designated).effectInfo.value.nextService) == uint32(advance(selected)), "designate retains advanced cursor"
checkChild(context(designated), selected)
# Current info observes the creator debit after the new account batch.
let inspected = run(source(suffix = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
  registerImmediate(9, 0), registerImmediate(10, 96), @[10'u8, 6], @[50'u8, 0]]), limit = 96)
assert inspected.error == AccumulationDispatchError.None and inspected.value.exit == StepExit.Halt, "current info after creation"
let info = readBytes(memoryOf(inspected.value.machine).value, MemoryAddress(196608), MemoryLength(
    96), MemoryByteLimit(96)).value
assert info[32] == 44 and info[33] == 3, "info encodes current creator balance 812"
# Provide can see the child's newly installed request without discarding the advanced cursor.
let blob = @[7'u8, 8, 9]
let blobHash = array[32, byte](blake2b256(blob).value)
var input: seq[byte] = @[]
for octet in blobHash:
  input.add(octet) # Offered code hash occupies the first 32 guest bytes.
for octet in blob:
  input.add(octet) # Raw preimage bytes follow the offered hash.
let provided = run(source(length = 3, data = input, suffix = @[registerImmediate(8, 196640),
  registerImmediate(9, 3), @[10'u8, 27], @[50'u8, 0]]), provisions = AccumulationProvisionLimits(
    items: ElementLimit(1), perBlob: ByteLimit(3), totalBlobBytes: ByteLimit(3)))
assert provided.error == AccumulationDispatchError.None and uint64(machineInfo(
    provided.value.machine).value.registers[7]) == 0, "provide sees the new request"
assert context(provided).effectInfo.value.provisions == 1 and uint32(context(
    provided).effectInfo.value.nextService) == uint32(advance(selected)), "provision retains allocation cursor"
# Direct state entry points derive provenance and repeat authorization, funding and collision checks.
let prepared = prepareAccumulationEffects(done.effects.effectsSource.value).value
let offeredBytes = offered()
var hash = default(array[32, byte])
for i in 0..<32:
  hash[i] = offeredBytes[i] # Independent fixed proposal copy.
let proposal = AccumulationNewService(codeHash: CodeHash(hash), length: RequestLength(5),
  accumulationGas: Gas(123), transferGas: Gas(456), desired: AccumulationDesiredService(high(uint64)))
let created = recordAccumulationNew(prepared, proposal, parameters(), ServiceProbeLimit(1))
assert created.error == AccumulationEffectError.None and uint32(created.value.service) == uint32(
    selected), "direct state creation"
checkChild(created.value.effects.effectContext(AccumulationDimension.Regular).value, selected)
assert recordAccumulationNew(prepared, proposal, default(Parameters), ServiceProbeLimit(1)).error ==
    AccumulationEffectError.InvalidParameters, "default deposit schedule refuses"
assert recordAccumulationNew(default(AccumulationEffects), proposal, parameters(),
    ServiceProbeLimit(1)).error == AccumulationEffectError.Uninitialized, "default pair cannot create a service"
assert recordAccumulationNew(prepared, proposal, parameters(), ServiceProbeLimit(0)).error ==
    AccumulationEffectError.LimitExceeded, "direct probe exhaustion carries no successor"
# Bless uses current authority and preserves the allocation cursor while handing manager/registrar roles off.
let managed = run(source(manager = 42))
var privilegePolicy = pvmContextConfig().privileges
privilegePolicy.maxAlways = ElementLimit(1)
let handedRoles = PrivilegeState(manager: ServiceIndex(99), registrar: ServiceIndex(42),
    delegator: ServiceIndex(42),
  assigners: @[ServiceIndex(42), ServiceIndex(42)],
  always: @[AlwaysAccumulate(service: ServiceIndex(7), gas: PrivilegeGas(high(uint64)))])
let blessed = recordAccumulationBless(managed.effects, handedRoles, privilegePolicy).value
assert uint32(blessed.effectContext(AccumulationDimension.Regular).value.effectInfo.value.nextService) ==
    uint32(advance(selected)), "bless retains advanced cursor"
var reservedProposal = proposal
reservedProposal.desired = AccumulationDesiredService(7)
reservedProposal.gratis = AccountBalance(100)
assert recordAccumulationNew(blessed, reservedProposal, parameters(), ServiceProbeLimit(0)).error ==
    AccumulationEffectError.NotManager, "new sees current manager handoff"
reservedProposal.gratis = AccountBalance(0)
let newlyReserved = recordAccumulationNew(blessed, reservedProposal, parameters(),
    ServiceProbeLimit(0))
assert newlyReserved.error == AccumulationEffectError.None and uint32(
    newlyReserved.value.service) == 7, "new sees current registrar grant"
let reservedOwner = newlyReserved.value.effects.effectContext(AccumulationDimension.Regular).value
checkChild(reservedOwner, ServiceIndex(7))
checkChild(reservedOwner, selected)
assert uint32(reservedOwner.effectInfo.value.nextService) == uint32(advance(selected)), "reserved new preserves advanced cursor"
assert uint64(reservedOwner.effectPrivileges.value.alwaysAccumulateAt(PrivilegeEntryIndex(
    0)).value.gas) == high(uint64), "new preserves full-width allowances"
# A repeated reserved proposal observes current membership, with no publication or cursor change.
assert recordAccumulationNew(newlyReserved.value.effects, reservedProposal, parameters(),
    ServiceProbeLimit(0)).error == AccumulationEffectError.ServiceExists, "reserved collision checks current accounts"
# Inherited store ceilings apply to the complete three-write batch and both added entries.
assert run(source(writes = 2)).error == AccumulationDispatchError.LimitExceeded, "three-write capacity is explicit"
assert run(source(spareEntries = 1)).error == AccumulationDispatchError.LimitExceeded, "two new mapping entries need capacity"
for successful in [0, 2]:
  failAfter(cint(successful))
  let refused = recordAccumulationNew(prepared, proposal, parameters(), ServiceProbeLimit(1))
  assert refused.error == AccumulationEffectError.BackendFailure and hashCalls() == cint(
      successful+1), "request or delayed tree hashing refuses atomically"
  failHash(0)
  assert prepared.effectContext(AccumulationDimension.Regular).value.effectAccounts.value.lookup(
      chapterServiceKey(StateChapter(255), selected)).error == StateStoreError.MissingKey, "failed creation publishes no child"
  assert uint32(prepared.effectContext(AccumulationDimension.Regular).value.effectInfo.value.nextService) ==
      uint32(selected), "failed creation does not consume cursor"
failHash(1)
assert run(valid).error == AccumulationDispatchError.BackendFailure, "host propagates request-key backend refusal"
failHash(0)
let noAuthority = source(gratis = 1)
failHash(1)
assert uint64(machineInfo(run(noAuthority).value.machine).value.registers[7]) == high(uint64)-8 and
    hashCalls() == 0, "authority refusal does no hashing"
failHash(0)
let before = getOccupiedMem()
for iteration in 0..<1000:
  let completed = run(valid)
  checkChild(context(completed), selected) # Release every map/request/cursor and guest successor.
let after = getOccupiedMem()
assert before == after, "creation releases all ARC-owned successors"
recordArcRelease("pvm_accumulation_new", 1000, before, after)
echo "PVM accumulation new passed"
echo "ARC_RELEASE cycles=1000 unchanged"
