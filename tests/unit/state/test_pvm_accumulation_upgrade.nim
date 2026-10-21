# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_upgrade_arc_release"}

## Authored upgrade programs verify self-only metadata replacement and unchanged current execution/checkpoints.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, state_layout, state_accounts, state_requests,
  state_service_values, state_privileges, state_safrole, state_outputs, state_trie, c2_records]
import ../../../src/state/[accumulation_dispatch, accumulation_effects, accumulation_context,
  accumulation_machine, accumulation_invocation, accumulation_outcome, store]
import ../../../src/pvm/[machine, program, step, gas, host_fetch]
import ../../../src/crypto/primitives
import ../../support/[pvm_accumulation_program, pvm_accumulation_context, arc_evidence]

# Inject backend refusal after authentic fixture construction.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
# Count attempts to distinguish memory/store preflight from actual Merklization.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
# Exercise atomic cleanup after successful child hashes.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

# Select coherent tiny-profile parameters; optional full-width rates prove upgrade does not require funding.
proc parameters(rate = 0'u64): Parameters =
  var bytes = encodeParameters(pvmParameters())
  for field in 0..<3:
    for i in 0..<8:
      bytes[field*8+i] = byte((rate shr (8*i)) and 255) # Independent E8 deposit construction.
  bytes[24] = 2
  bytes[25] = 0
  bytes[82] = 80
  bytes[83] = 0 # Match current queue/core profiles for subsequent effects.
  decodeParameters(bytes).value

# Opaque offered hash bytes are independent from the actual executing program's hash.
proc payload(seed = 3): seq[byte] =
  assert seed >= 0 and seed <= 255, "bounded authored hash seed"
  result = newSeq[byte](32)
  for i in 0..<32:
    result[i] = byte((seed+i*7) mod 256) # Small arithmetic is bounded before narrowing.

# Distinct fixed fields expose accidental reset or reconstruction of any non-upgrade metadata.
proc original(): ServiceMetadata =
  ServiceMetadata(balance: AccountBalance(23), depositOffset: AccountBalance(31),
    storageItems: AccountStorageItems(2), storageBytes: AccountStorageBytes(86),
    minimumAccumulationGas: Gas(17), minimumTransferGas: Gas(19),
    created: AccountSlot(43), lastAccumulation: AccountSlot(47), parent: ServiceIndex(53))

# Keep an independent current new-service request after the offered hash for upgrade/creation interaction witnesses.
proc creationData(data: seq[byte]): seq[byte] =
  result = newSeq[byte](max(data.len, 92))
  for i, octet in data:
    result[i] = octet # Preserve all authored original guest data.
  for i in 0..<32:
    let octet = result[i]
    result[32+i] = octet # Bind the immutable read before borrowing the result for mutation.
  result[64] = 5
  result[68] = 1
  result[76] = 2

# Real guest instructions use explicit metadata/policy and the ordinary unprivileged fixture roles.
proc source(address = 196608'u64, accumulation = 123'u64, transfer = 456'u64,
    credit = 100000'u64, data: seq[byte] = payload(), account: ServiceMetadata = original(),
    extra: seq[StateEntry] = @[], writes = 2'u64,
    suffix: seq[seq[byte]] = @[@[50'u8, 0]]): PreparedAccumulationMachine =
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, address),
    registerImmediate(9, accumulation), registerImmediate(10, transfer), @[10'u8, 21]]
  for instruction in suffix:
    instructions.add(instruction) # Continue the original decoded program after its own metadata changes.
  guestProgram(instructions, credit, account = account, writable = creationData(data),
      extra = extra,
    writes = writes, spareEntries = 2)

# Copy/execution/probe policies remain explicit; no persistent successor state is published.
proc run(prepared: PreparedAccumulationMachine, limit = 60'u64,
    params: Parameters = parameters()): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, params,
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132))), MemoryByteLimit(limit),
    ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000), pvmContextConfig(),
    serviceProbes = ServiceProbeLimit(1))

# Instruction pricing is independent of the fixed 1028 host cost.
proc price(prepared: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(prepared.accumulationMachine.value).value, CodeAddress(5),
    GasCycleLimit(1000)).value)

# Retain only a completed execution's exact regular or exceptional version.
proc context(done: AccumulationDispatchResult, dimension = AccumulationDimension.Regular): AccumulationEffectContext =
  assert done.error == AccumulationDispatchError.None, "completed execution grants upgrade effects"
  done.effects.effectContext(dimension).value

# Current canonical self metadata is the only target accepted by the upgrade operation.
proc accountBytes(owner: AccumulationEffectContext): seq[byte] =
  owner.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      42))).value.bytes

# Both typed metadata and exact encoded field positions must retain all offered bits.
proc checkCode(owner: AccumulationEffectContext, expected: openArray[byte], accumulation = 123'u64,
    transfer = 456'u64) =
  assert expected.len == 32, "complete expected raw hash"
  let bytes = accountBytes(owner)
  let decoded = decodeServiceMetadata(bytes, ByteLimit(ServiceMetadataBytes)).value
  assert decoded.consumed == ServiceMetadataBytes and bytes[0] == 0, "canonical complete version-zero metadata"
  let hash = array[32, byte](decoded.metadata.codeHash)
  for i in 0..<32:
    assert hash[i] == expected[i] and bytes[1+i] == expected[i], "offered hash retained in typed and serialized fields"
  assert uint64(decoded.metadata.minimumAccumulationGas) == accumulation and
    uint64(decoded.metadata.minimumTransferGas) == transfer, "full-width gas values retained"
  for i in 0..<8:
    assert bytes[57+i] == byte((accumulation shr (8*i)) and 255) and
      bytes[65+i] == byte((transfer shr (8*i)) and 255), "minimum gas uses exact E8 slots"

# All other metadata octets, including balances/counters/timestamps/parent, must stay identical.
proc checkRemainder(before, after: AccumulationEffectContext) =
  let previous = accountBytes(before)
  let current = accountBytes(after)
  assert previous.len == ServiceMetadataBytes and current.len == ServiceMetadataBytes, "fixed metadata extents"
  for i in 0..<ServiceMetadataBytes:
    if i == 0 or (i >= 33 and i < 57) or i >= 73:
      assert previous[i] == current[i], "only the three pinned upgrade fields may change"

let valid = source()
let done = run(valid)
assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt, "funded upgrade completes original execution"
assert uint64(machineInfo(done.value.machine).value.registers[7]) == 0, "upgrade returns OK"
let initial = context(done, AccumulationDimension.Exceptional)
checkCode(context(done), payload())
checkRemainder(initial, context(done))
assert accountBytes(initial) == initial.effectInitialContext.value.contextAccounts.value.lookup(
  chapterServiceKey(StateChapter(255), ServiceIndex(42))).value.bytes, "initial provenance and checkpoint unchanged"
assert uint32(context(done).effectInfo.value.nextService) == uint32(
    initial.effectInfo.value.nextService), "upgrade retains allocation cursor"
for chapter in [2, 7, 12]:
  assert context(done).effectAccounts.value.lookup(chapterKey(StateChapter(chapter))).value.bytes ==
    initial.effectAccounts.value.lookup(chapterKey(StateChapter(chapter))).value.bytes, "unrelated state chapter unchanged"
let oldHash = ServicePreimageHash(array[32, byte](decodeServiceMetadata(accountBytes(initial),
    ByteLimit(ServiceMetadataBytes)).value.metadata.codeHash))
let oldCodeKey = servicePreimageKey(ServiceIndex(42), oldHash, ByteLimit(32)).value
assert context(done).effectAccounts.value.lookup(oldCodeKey).value.bytes ==
    initial.effectAccounts.value.lookup(oldCodeKey).value.bytes, "original code preimage remains unchanged"
let other = serviceMetadataEntry(ServiceIndex(99), ServiceMetadata(balance: AccountBalance(777)),
    ByteLimit(ServiceMetadataBytes)).value
let withOther = run(source(extra = @[other]))
assert context(withOther).effectAccounts.value.lookup(other.key).value.bytes == other.value, "upgrade cannot substitute another account target"
let offeredHash = array[32, byte](decodeServiceMetadata(accountBytes(context(done)), ByteLimit(
    ServiceMetadataBytes)).value.metadata.codeHash)
assert context(done).effectAccounts.value.lookup(servicePreimageKey(ServiceIndex(42),
  ServicePreimageHash(offeredHash), ByteLimit(32)).value).error == StateStoreError.MissingKey, "offered code need not be available"
assert readBytes(memoryOf(valid.accumulationMachine.value).value, MemoryAddress(196608),
    MemoryLength(32), MemoryByteLimit(32)).value ==
  readBytes(memoryOf(done.value.machine).value, MemoryAddress(196608), MemoryLength(32),
      MemoryByteLimit(32)).value, "upgrade never writes guest memory"
assert uint64(machineInfo(valid.accumulationMachine.value).value.gas) == 100000, "source CPU unchanged"
for accumulation in [0'u64, 0x8000000000000000'u64, high(uint64)]:
  for transfer in [0'u64, high(uint64)]:
    let completed = run(source(accumulation = accumulation, transfer = transfer))
    checkCode(context(completed), payload(), accumulation,
        transfer) # No signed narrowing or extra gas-domain restriction.
    checkRemainder(context(completed, AccumulationDimension.Exceptional), context(completed))
checkCode(context(run(source(data = newSeq[byte](32)))), newSeq[byte](
    32)) # Zero hashes are valid opaque offers.
let unfunded = run(source(account = ServiceMetadata(balance: AccountBalance(0))),
    params = parameters(high(uint64)))
checkCode(context(unfunded), payload()) # Upgrade does not test funding, minimum balance or roles.
for address in [0'u64, 65536'u64+4096-16, 196608'u64+8192-16, 0x100000000'u64, high(uint64)]:
  let failed = run(source(address = address))
  assert failed.error == AccumulationDispatchError.None and failed.value.exit == StepExit.Panic, "unreadable offered hash panics"
  assert uint64(machineInfo(failed.value.machine).value.registers[7]) == high(uint64), "panic preserves self selector"
  assert accountBytes(context(failed)) == accountBytes(context(failed,
      AccumulationDimension.Exceptional)), "memory failure changes no metadata"
var ro = newSeq[byte](32)
ro[0] = 73
checkCode(context(run(source(address = 65536))), ro) # Read-only memory is a valid offered hash source.
checkCode(context(run(source(address = 196608'u64+4096-16))), newSeq[byte](
    32)) # Adjacent RW pages permit crossing reads.
assert run(valid, limit = 31).error == AccumulationDispatchError.LimitExceeded, "fixed capture budget exact edge"
for available in [0'u64, 1027, 1028, 1029]:
  let completed = run(source(credit = price(valid)+available))
  assert completed.error == AccumulationDispatchError.None, "fixed gas boundary completes"
  let cpu = machineInfo(completed.value.machine).value
  if available < 1028:
    assert completed.value.exit == StepExit.OutOfGas and uint64(cpu.gasDeficit) == 0, "exact upgrade gas deficit"
    assert uint64(cpu.registers[7]) == high(uint64), "OOG preserves self selector"
    assert accountBytes(context(completed)) == accountBytes(context(completed,
        AccumulationDimension.Exceptional)), "OOG performs no metadata replacement"
  else:
    assert completed.value.exit == StepExit.Halt and uint64(cpu.gas) == available-1028, "exact funded upgrade charge"
assert run(source(address = high(uint64), credit = price(valid)), limit = 0).value.exit ==
    StepExit.OutOfGas, "charge precedes pointer and copy policy"
let fullCredit = run(source(credit = high(uint64)))
assert uint64(machineInfo(fullCredit.value.machine).value.gas) == high(uint64)-price(valid)-1028, "full-width credit subtraction"
for checkpoint in [false, true]:
  let suffix = (if checkpoint: @[@[10'u8, 19], @[0'u8]] else: @[@[0'u8]])
  let failed = run(source(suffix = suffix))
  assert failed.value.exit == StepExit.Panic, "authored terminal panic"
  let selected = normalizeAccumulationOutcome(failed).value.outcomeContext.value
  assert accountBytes(selected) == accountBytes(context(failed, AccumulationDimension.Exceptional)), "panic selects exact metadata checkpoint"
  if checkpoint:
    checkCode(selected, payload()) # Checkpoint owns the successful upgrade before terminal panic.
  else:
    assert accountBytes(selected) == selected.effectInitialContext.value.contextAccounts.value.lookup(
      chapterServiceKey(StateChapter(255), ServiceIndex(42))).value.bytes, "panic selects its own original program metadata"
  let exhausted = run(source(credit = price(valid)+1200, suffix = (if checkpoint:
    @[@[10'u8, 19], registerImmediate(7, high(uint64)), @[10'u8, 21], @[50'u8, 0]] else:
    @[registerImmediate(7, high(uint64)), @[10'u8, 21], @[50'u8, 0]])))
  assert exhausted.value.exit == StepExit.OutOfGas, "second upgrade is unaffordable"
  let retained = normalizeAccumulationOutcome(exhausted).value.outcomeContext.value
  assert accountBytes(retained) == accountBytes(context(exhausted,
      AccumulationDimension.Exceptional)), "OOG selects matching metadata checkpoint"
# Later info executes the original program while reading the newly upgraded current metadata.
let inspected = run(source(accumulation = high(uint64), transfer = high(uint64), suffix = @[
  registerImmediate(7, high(uint64)), registerImmediate(8, 196608), registerImmediate(9, 0),
  registerImmediate(10, 112), @[10'u8, 6], @[50'u8, 0]]), limit = 112)
assert inspected.error == AccumulationDispatchError.None and inspected.value.exit == StepExit.Halt, "original program continues after upgrade"
let info = readBytes(memoryOf(inspected.value.machine).value, MemoryAddress(196608), MemoryLength(
    112), MemoryByteLimit(112)).value
let expectedInfoHash = payload()
for i in 0..<32:
  assert info[i] == expectedInfoHash[i], "info observes current upgraded code hash"
for i in 64..<80:
  assert info[i] == 255, "info observes both full-width upgraded gas fields"
# Repeated calls can replace all three fields again using another captured memory region.
let repeated = run(source(suffix = @[registerImmediate(7, high(uint64)), registerImmediate(8, 65536),
  registerImmediate(9, 0), registerImmediate(10, high(uint64)), @[10'u8, 21], @[50'u8, 0]]))
checkCode(context(repeated), ro, 0, high(uint64))
checkRemainder(initial, context(repeated))
# Storage uses the current upgraded metadata; yield is independently retained beside it.
let preserved = run(source(suffix = @[registerImmediate(7, 65536), @[10'u8, 27],
  @[51'u8, 7, 255], registerImmediate(8, 65536), registerImmediate(9, 1), registerImmediate(10, 196608),
  registerImmediate(11, 3), @[10'u8, 5], @[50'u8, 0]]))
assert uint64(machineInfo(preserved.value.machine).value.registers[7]) == high(uint64), "storage after upgrade succeeds"
checkCode(context(preserved), payload())
assert context(preserved).effectInfo.value.hasYield, "later yield remains present"
# New service creation retains the upgrade and advances its independent allocation cursor.
let created = run(source(writes = 3, suffix = @[registerImmediate(7, high(uint64)),
  registerImmediate(8, high(uint64)), registerImmediate(9, 0), registerImmediate(10, 196640),
  @[10'u8, 20], @[50'u8, 0]]))
checkCode(context(created), payload())
assert uint32(context(created).effectInfo.value.nextService) != uint32(
    initial.effectInfo.value.nextService), "new advances current cursor after upgrade"
let child = ServiceIndex(uint32(uint64(machineInfo(created.value.machine).value.registers[7])))
assert context(created).effectAccounts.value.lookup(chapterServiceKey(StateChapter(255),
    child)).error == StateStoreError.None, "new child exists after upgrade"
# Upgrade after creation preserves the new child and already advanced cursor.
let beforeNew = guestProgram([registerImmediate(7, high(uint64)), registerImmediate(8, high(uint64)),
  registerImmediate(9, 0), registerImmediate(10, 196640), @[10'u8, 20], registerImmediate(7, high(uint64)),
  registerImmediate(8, 196608), registerImmediate(9, 123), registerImmediate(10, 456), @[10'u8, 21],
      @[50'u8, 0]],
  credit = 100000, account = original(), writable = creationData(payload()), writes = 3,
      spareEntries = 2)
let afterNew = run(beforeNew)
checkCode(context(afterNew), payload())
assert uint32(context(afterNew).effectInfo.value.nextService) == uint32(context(
    created).effectInfo.value.nextService), "upgrade retains advanced cursor"
assert context(afterNew).effectAccounts.value.lookup(chapterServiceKey(StateChapter(255),
    child)).error == StateStoreError.None, "upgrade preserves current child account"
# Retained provisions, yield and checkpoint are preserved by the state API, independent of guest assembly.
let blob = @[4'u8, 5, 6]
let blobHash = ServicePreimageHash(array[32, byte](blake2b256(blob).value))
let request = serviceRequestEntry(ServiceIndex(42), blobHash, RequestLength(3), requestedHistory(),
  RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(0),
      maxBytes: ByteLimit(1)))).value
let withRequest = source(extra = @[request])
let prepared = prepareAccumulationEffects(prepareAccumulationContexts(
    withRequest.machineBootstrap.value, pvmContextConfig()).value).value
let provided = recordAccumulationProvision(prepared, ServiceIndex(42), blob,
    AccumulationProvisionLimits(
  items: ElementLimit(1), perBlob: ByteLimit(3), totalBlobBytes: ByteLimit(3))).value
var commitment = default(array[32, byte])
commitment[0] = 99
let yielded = recordAccumulationYield(provided, OutputCommitment(commitment)).value
let checkpointed = checkpointAccumulationEffects(yielded).value
var hash = default(array[32, byte])
let offeredBytes = payload()
for i in 0..<32:
  hash[i] = offeredBytes[i] # Fixed typed value remains independent of caller-owned payload storage.
let upgraded = recordAccumulationUpgrade(checkpointed, CodeHash(hash), Gas(123), Gas(456))
assert upgraded.error == AccumulationEffectError.None, "direct upgrade succeeds"
hash[0] = 255
let regular = upgraded.value.effectContext(AccumulationDimension.Regular).value
checkCode(regular, payload())
checkRemainder(prepared.effectContext(AccumulationDimension.Regular).value, regular)
assert regular.effectInfo.value.provisions == 1 and array[32, byte](regular.effectYield.value) ==
    commitment, "upgrade retains provision and yield owners"
assert regular.effectProvisionAt(AccumulationProvisionIndex(0)).value.copyProvisionBytes.value ==
    blob, "retained provision payload unchanged"
assert accountBytes(upgraded.value.effectContext(AccumulationDimension.Exceptional).value) ==
  accountBytes(prepared.effectContext(AccumulationDimension.Regular).value), "direct upgrade preserves prior checkpoint metadata"
assert regular.effectAccounts.value.lookup(request.key).value.bytes == request.value, "upgrade does not change existing requests"
assert recordAccumulationUpgrade(default(AccumulationEffects), CodeHash(hash), Gas(0), Gas(
    0)).error == AccumulationEffectError.Uninitialized, "default pair cannot select self"
assert run(source(writes = 0)).error == AccumulationDispatchError.LimitExceeded, "inherited write capacity is explicit"
for successful in [0, 2]:
  failAfter(cint(successful))
  let failed = recordAccumulationUpgrade(prepared, CodeHash(hash), Gas(0), Gas(high(uint64)))
  assert failed.error == AccumulationEffectError.BackendFailure and hashCalls() == cint(
      successful+1), "atomic immediate/delayed Merklization refusal"
  failHash(0)
  assert accountBytes(prepared.effectContext(AccumulationDimension.Regular).value) == accountBytes(
      initial), "failed upgrade leaves prior metadata unchanged"
failHash(1)
assert run(valid).error == AccumulationDispatchError.BackendFailure, "host propagates Merklization refusal"
failHash(0)
let noRead = source(address = high(uint64))
failHash(1)
assert run(noRead).value.exit == StepExit.Panic and hashCalls() == 0, "bad memory never reaches state hashing"
failHash(0)
let before = getOccupiedMem()
for iteration in 0..<1000:
  let completed = run(valid)
  checkCode(context(completed), payload()) # Release every map, metadata and guest successor.
let after = getOccupiedMem()
assert before == after, "upgrade releases all ARC-owned successor versions"
recordArcRelease("pvm_accumulation_upgrade", 1000, before, after)
echo "PVM accumulation upgrade passed"
echo "ARC_RELEASE cycles=1000 unchanged"
