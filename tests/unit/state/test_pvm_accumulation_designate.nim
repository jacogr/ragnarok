# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_designate_arc_release"}

## Authored designate programs verify exact costs, opaque ordered rosters and current delegator authority.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, state_layout, state_privileges, state_safrole,
    state_trie, c2_records]
import ../../../src/state/[accumulation_dispatch, accumulation_effects, accumulation_context,
  accumulation_machine, accumulation_invocation, accumulation_outcome, store]
import ../../../src/pvm/[machine, program, step, gas, host_fetch]
import ../../support/[pvm_accumulation_program, pvm_accumulation_context, arc_evidence]

# Inject failure after authentic fixture construction, independently of protocol input validation.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
# Count attempted Merklization hashes to detect state work on refused calls.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
# Refuse after completed child hashes to exercise cleanup of a partial candidate tree.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

# Match the three-core authored profile and fixed queue length; deposits are free for storage witnesses.
proc parameters(cores = 3'u64): Parameters =
  assert cores >= 2 and cores <= 3, "bounded authored parameter profile"
  var bytes = encodeParameters(pvmParameters())
  for i in 0..<24:
    bytes[i] = 0 # Isolate staging preservation from unrelated balance/deposit policy.
  bytes[24] = byte(cores)
  bytes[25] = 0
  bytes[82] = 80
  bytes[83] = 0 # Independently pinned E2 positions for core count and authQueueLen.
  decodeParameters(bytes).value

# Distinct octets across all four fields expose truncation and record/field reordering.
proc payload(count = 9, seed = 1): seq[byte] =
  assert count >= 0 and count <= 9 and seed >= 0 and seed <= 255, "bounded authored payload"
  result = newSeq[byte](count*336)
  for i in 0..<count:
    for j in 0..<336:
      result[i*336+j] = byte((i*31+j*7+seed) mod 256) # Prove small arithmetic before narrowing.

# Assemble genuine guest calls; the three-core fixture starts with six staging validators.
proc source(count = 9'u64, address = 196608'u64, initialDelegator = 42'u32,
    credit = 100000'u64, cores = 3'u64, data: seq[byte] = payload(),
    suffix: seq[seq[byte]] = @[@[50'u8, 0]]): PreparedAccumulationMachine =
  var instructions = @[registerImmediate(7, address), registerImmediate(8, count), @[10'u8, 17]]
  for instruction in suffix:
    instructions.add(instruction) # Follow-up effects execute through the same decoded production program.
  guestProgram(instructions, credit, cores = cores, manager = 42, delegator = initialDelegator,
    assigner = 42, writable = data, spareEntries = 1)

# Capture, engine and component policies remain explicit and separate from protocol gas.
proc run(prepared: PreparedAccumulationMachine, limit = 3024'u64,
    params: Parameters = parameters(), profile: AccumulationContextConfig = pvmContextConfig(
        3)): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, params,
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132))), MemoryByteLimit(limit),
    ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000), profile)

# Price authored instructions independently of the host's complete mathematical item charge.
proc price(prepared: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(prepared.accumulationMachine.value).value, CodeAddress(5),
    GasCycleLimit(1000)).value)

# Retain one exact dimension only after completed execution grants an effects owner.
proc context(done: AccumulationDispatchResult, dimension = AccumulationDimension.Regular): AccumulationEffectContext =
  assert done.error == AccumulationDispatchError.None, "completed execution grants staging effects"
  done.effects.effectContext(dimension).value

# Encode copied fixed fields in test-only order, without invoking the production staging encoder.
proc raw(record: StateValidator): seq[byte] =
  result = @[]
  for octet in array[32, byte](record.bandersnatch):
    result.add(octet) # First raw key occupies bytes 0..31.
  for octet in array[32, byte](record.ed25519):
    result.add(octet) # Second raw key occupies bytes 32..63.
  for octet in array[144, byte](record.bls):
    result.add(octet) # Preserve all 144 BLS bytes as opaque data.
  for octet in array[128, byte](record.metadata):
    result.add(octet) # Metadata finishes the exact 336-octet tuple.

# Require both current typed and serialized state to match the independent raw payload exactly.
proc checkStaging(owner: AccumulationEffectContext, expected: openArray[byte]) =
  let count = expected.len div 336
  assert count in [6, 9] and expected.len == 336*count, "bounded expected roster"
  let staging = owner.effectStaging.value
  assert staging.validatorCount.value == count, "current population can differ from initial population"
  let bytes = owner.effectAccounts.value.lookup(chapterKey(StateChapter(7))).value.bytes
  assert bytes.len == expected.len+1 and bytes[0] == byte(count), "C7 adds the exact canonical compact count"
  let decoded = decodeStateValidators(bytes, pvmContextConfig(3).staging).value
  assert decoded.consumed == bytes.len and decoded.value.validatorCount.value == count, "complete serialized roster"
  for i in 0..<count:
    let typed = raw(staging.validatorAt(StateValidatorIndex(uint64(i))).value)
    let encoded = raw(decoded.value.validatorAt(StateValidatorIndex(uint64(i))).value)
    for j in 0..<336:
      assert typed[j] == expected[i*336+j] and encoded[j] == expected[i*336+j] and
        bytes[1+i*336+j] == expected[i*336+j], "ordered opaque fields agree in all representations"

let valid = source()
let done = run(valid)
assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt, "funded designate completes"
assert uint64(machineInfo(done.value.machine).value.registers[7]) == 0, "designate returns OK"
checkStaging(context(done), payload())
let zeros = newSeq[byte](2016)
let initial = context(done, AccumulationDimension.Exceptional)
checkStaging(initial, zeros)
assert context(done).effectInitialContext.value.contextStaging.value.validatorCount.value == 6, "initial provenance retains six validators"
for chapter in [2, 12]:
  assert context(done).effectAccounts.value.lookup(chapterKey(StateChapter(chapter))).value.bytes ==
    initial.effectAccounts.value.lookup(chapterKey(StateChapter(chapter))).value.bytes, "unrelated chapter unchanged"
assert uint64(machineInfo(valid.accumulationMachine.value).value.gas) == 100000, "source CPU unchanged"
let beforeMemory = memoryOf(valid.accumulationMachine.value).value
let afterMemory = memoryOf(done.value.machine).value
assert readBytes(beforeMemory, MemoryAddress(196608), MemoryLength(3024), MemoryByteLimit(
    3024)).value ==
  readBytes(afterMemory, MemoryAddress(196608), MemoryLength(3024), MemoryByteLimit(3024)).value, "read-only host input"
for count in [6, 9]:
  let bytes = payload(count)
  checkStaging(context(run(source(count = uint64(count), data = bytes))),
      bytes) # Both allowed populations succeed.
let twoCore = run(source(count = 6, cores = 2, data = payload(6)), params = parameters(2),
    profile = pvmContextConfig())
checkStaging(context(twoCore), payload(6)) # The default two-core profile still permits exactly six validators.
let twoCoreTooMany = run(source(cores = 2), params = parameters(2), profile = pvmContextConfig())
assert uint64(machineInfo(twoCoreTooMany.value.machine).value.registers[7]) == high(uint64)-8, "count bound follows configured cores"
checkStaging(context(run(source(data = newSeq[byte](3024)))), newSeq[byte](
    3024)) # Duplicate zero records remain valid.
for count in [0'u64, 1, 2, 3, 4, 5, 7, 8, 10, 11, 12, 24]:
  let refused = run(source(count = count), limit = 8064)
  assert refused.error == AccumulationDispatchError.None and refused.value.exit == StepExit.Halt, "readable invalid count completes"
  assert uint64(machineInfo(refused.value.machine).value.registers[7]) == high(uint64)-8, "invalid count returns HUH"
  checkStaging(context(refused), zeros)
for delegator in [0'u32, 99, high(uint32)]:
  let refused = run(source(initialDelegator = delegator))
  assert uint64(machineInfo(refused.value.machine).value.registers[7]) == high(uint64)-8, "only current delegator has authority"
  checkStaging(context(refused), zeros)
for count in [1'u64, 5, 9, 12]:
  for address in [0'u64, 65536'u64+4096-1, 196608'u64+8192-1, 0x100000000'u64, high(uint64)]:
    let failed = run(source(count = count, address = address, initialDelegator = 0), limit = 8064)
    assert failed.error == AccumulationDispatchError.None and failed.value.exit == StepExit.Panic, "input failure precedes bad count and authority"
    assert uint64(machineInfo(failed.value.machine).value.registers[7]) == address, "panic preserves full-width pointer"
for address in [0'u64, high(uint64)]:
  let empty = run(source(count = 0, address = address), limit = 0)
  assert empty.value.exit == StepExit.Halt and uint64(machineInfo(
      empty.value.machine).value.registers[7]) == high(uint64)-8, "empty capture accepts any pointer before HUH"
var ro = newSeq[byte](3024)
ro[0] = 73
checkStaging(context(run(source(address = 65536))), ro) # RO pages are valid raw input.
checkStaging(context(run(source(address = 196608'u64+4096-1512, data = newSeq[byte](3024)))),
  newSeq[byte](3024)) # Adjacent writable pages permit a complete crossing read.
for count in [0x100000000'u64 div 336+1, 0x100000006'u64, high(uint64) div 336+1, 1'u64 shl 55]:
  let failed = run(source(count = count, credit = high(uint64), initialDelegator = 0), limit = 0)
  assert failed.error == AccumulationDispatchError.None and failed.value.exit == StepExit.Panic, "funded impossible extent panics before multiplication or HUH"
assert run(valid, limit = 3023).error == AccumulationDispatchError.LimitExceeded, "raw copy budget exact edge"
assert run(source(count = 5), limit = 0).error == AccumulationDispatchError.LimitExceeded, "capture policy precedes HUH"
assert run(valid, params = parameters(2)).error == AccumulationDispatchError.InvalidContext, "profile mismatch refuses locally"
var small = pvmContextConfig(3)
small.staging.validators = ElementLimit(8)
assert run(valid, profile = small).error == AccumulationDispatchError.LimitExceeded, "typed record budget after valid input"
assert uint64(machineInfo(run(source(initialDelegator = 0),
    profile = small).value.machine).value.registers[7]) == high(uint64)-8, "HUH precedes candidate component limit"
small = pvmContextConfig(3)
small.staging.maxBytes = ByteLimit(3024)
assert run(valid, profile = small).error == AccumulationDispatchError.LimitExceeded, "C7 count prefix consumes component budget"
# Adding a new chapter fills inherited map policy without changing the initial component profile.
let fullMap = guestProgram([registerImmediate(7, 196608), registerImmediate(8, 9), @[10'u8, 17], @[
    50'u8, 0]],
  cores = 3, manager = 42, delegator = 42, assigner = 42, writable = payload(),
  extra = @[StateEntry(key: chapterKey(StateChapter(100)), value: newSeq[byte](7000))])
failHash(1)
assert run(fullMap).error == AccumulationDispatchError.LimitExceeded and hashCalls() == 0, "aggregate store limit refuses before Merklization"
failHash(0)
for count in [0'u64, 1, 6, 9, 12]:
  let cost = 1100+302*count # Small independent arithmetic witness, separate from the implementation's limbs.
  let prototype = source(count = count)
  for available in [0'u64, cost-1, cost, cost+1]:
    let completed = run(source(count = count, credit = price(prototype)+available), limit = 4032)
    assert completed.error == AccumulationDispatchError.None, "gas boundary completes"
    let cpu = machineInfo(completed.value.machine).value
    if available < cost:
      assert completed.value.exit == StepExit.OutOfGas and uint64(cpu.gasDeficit) == cost-available, "exact item deficit"
      assert uint64(cpu.registers[7]) == 196608, "OOG preserves original pointer"
      checkStaging(context(completed), zeros)
    else:
      assert completed.value.exit == StepExit.Halt and uint64(cpu.gas) == available-cost, "exact funded gas subtraction"
let huge = run(source(count = 1'u64 shl 56, credit = high(uint64)), limit = 0)
assert huge.error == AccumulationDispatchError.None and huge.value.exit == StepExit.OutOfGas, "full cost above uint64 is retained"
assert uint64(machineInfo(huge.value.machine).value.gasDeficit) == 46'u64*(1'u64 shl 56)+1101+price(
    valid), "exact high-limb borrowing"
let boundaryCost = 302'u64*(1'u64 shl 55)+1100 # This known product is below UINT64_MAX.
let boundaryCredit = boundaryCost-0x8000000000000000'u64+price(valid)
let boundary = run(source(count = 1'u64 shl 55, credit = boundaryCredit), limit = 0)
assert boundary.value.exit == StepExit.OutOfGas and uint64(machineInfo(
    boundary.value.machine).value.gasDeficit) == 0x8000000000000000'u64, "exact signed negative boundary"
assert run(source(count = 1'u64 shl 55, credit = boundaryCredit-1), limit = 0).error ==
    AccumulationDispatchError.GasRangeExceeded, "unrepresentable signed debt remains explicit"
assert run(source(count = high(uint64), credit = high(uint64)), limit = 0).error ==
    AccumulationDispatchError.GasRangeExceeded, "all count bits enter charge"
assert run(source(address = high(uint64), credit = price(valid)), limit = 0,
  params = parameters(2)).value.exit == StepExit.OutOfGas, "charge precedes memory and profile work"
let fullCredit = run(source(credit = high(uint64)))
assert uint64(machineInfo(fullCredit.value.machine).value.gas) == high(uint64)-price(valid)-3818, "full-width gas credit"
for checkpoint in [false, true]:
  let suffix = (if checkpoint: @[@[10'u8, 18], @[0'u8]] else: @[@[0'u8]])
  let failed = run(source(suffix = suffix))
  assert failed.value.exit == StepExit.Panic, "authored terminal panic"
  assert normalizeAccumulationOutcome(failed).value.outcomeContext.value.effectInfo.value.hasStaging == checkpoint
  checkStaging(normalizeAccumulationOutcome(failed).value.outcomeContext.value,
    (if checkpoint: payload() else: zeros)) # Select the coherent roster and C7 version together.
  let exhausted = run(source(credit = price(valid)+4000, suffix = (if checkpoint:
    @[@[10'u8, 18], @[10'u8, 17], @[50'u8, 0]] else: @[@[10'u8, 17], @[50'u8, 0]])))
  assert exhausted.error == AccumulationDispatchError.None and exhausted.value.exit ==
      StepExit.OutOfGas, "second designate is unaffordable"
  assert normalizeAccumulationOutcome(exhausted).value.outcomeContext.value.effectInfo.value.hasStaging == checkpoint
  checkStaging(normalizeAccumulationOutcome(exhausted).value.outcomeContext.value,
    (if checkpoint: payload() else: zeros)) # OOG retains the same exact exceptional checkpoint.
# Later yield, storage and assign publish new versions without losing the accepted staging roster.
let preserved = run(source(suffix = @[registerImmediate(7, 65536), @[10'u8, 26],
  registerImmediate(7, 65536), registerImmediate(8, 1), registerImmediate(9, 196608),
  registerImmediate(10, 3), @[10'u8, 5], @[50'u8, 0]]))
checkStaging(context(preserved), payload())
assert context(preserved).effectInfo.value.hasStaging, "yield/storage preserve designation provenance"
assert context(preserved).effectInfo.value.hasYield, "yield preserved beside staging and storage"
let assigned = run(source(suffix = @[registerImmediate(7, 0), registerImmediate(8, 65536),
  registerImmediate(9, 99), @[10'u8, 16], @[50'u8, 0]]))
checkStaging(context(assigned), payload())
assert uint32(context(assigned).effectPrivileges.value.privilegeAssignerAt(PrivilegeCoreIndex(
    0)).value) == 99, "assign succeeds without discarding staging"
# Bless transfers current delegator authority; a subsequent designate observes the handoff.
let handed = run(source(suffix = @[registerImmediate(7, 42), registerImmediate(8, 65536),
  registerImmediate(9, 99), registerImmediate(10, 0), registerImmediate(11, high(uint64)),
  registerImmediate(12, 0), @[10'u8, 15], registerImmediate(7, 196608),
  registerImmediate(8, 6), @[10'u8, 17], @[50'u8, 0]]))
assert uint64(machineInfo(handed.value.machine).value.registers[7]) == high(uint64)-8, "designate uses blessed current delegator"
checkStaging(context(handed), payload())
# The direct state API repeats authorization and owns independent copies of accepted borrowed records.
let prepared = prepareAccumulationEffects(done.effects.effectsSource.value).value
var records = newSeq[StateValidator](9)
for i in 0..<9:
  records[i] = context(done).effectStaging.value.validatorAt(StateValidatorIndex(uint64(
      i))).value # Copy from a retained source owner.
let captured = recordAccumulationDesignate(prepared, records, pvmContextConfig(3).staging)
assert captured.error == AccumulationEffectError.None, "direct designate succeeds"
records[0] = default(StateValidator)
checkStaging(captured.value.effectContext(AccumulationDimension.Regular).value, payload())
checkStaging(prepared.effectContext(AccumulationDimension.Regular).value, zeros)
let shrunk = recordAccumulationDesignate(captured.value, records.toOpenArray(0, 5),
    pvmContextConfig(3).staging)
assert shrunk.error == AccumulationEffectError.None and shrunk.value.effectContext(
    AccumulationDimension.Regular).value.effectStaging.value.validatorCount.value == 6, "subsequent roster can shrink"
assert recordAccumulationDesignate(prepared, records.toOpenArray(0, 4), pvmContextConfig(
    3).staging).error == AccumulationEffectError.InvalidValidatorCount, "direct invalid count refuses"
let unauthorized = run(source(initialDelegator = 0, count = 0))
assert recordAccumulationDesignate(unauthorized.effects, records, pvmContextConfig(
    3).staging).error == AccumulationEffectError.NotDelegator, "direct current authority refuses"
assert recordAccumulationDesignate(prepared, records, pvmContextConfig().staging).error ==
    AccumulationEffectError.InvalidState, "direct profile cannot replace state cardinality"
var smallRoster = pvmContextConfig(3).staging
smallRoster.validators = ElementLimit(8)
assert recordAccumulationDesignate(prepared, records, smallRoster).error ==
    AccumulationEffectError.LimitExceeded, "direct record ceiling"
# Reauthorization through bless preserves the roster and independent full-width allowances.
var privilegePolicy = pvmContextConfig(3).privileges
privilegePolicy.maxAlways = ElementLimit(1)
let roles = PrivilegeState(manager: ServiceIndex(42), delegator: ServiceIndex(42),
    registrar: ServiceIndex(7),
  assigners: @[ServiceIndex(42), ServiceIndex(42), ServiceIndex(42)],
  always: @[AlwaysAccumulate(service: ServiceIndex(9), gas: PrivilegeGas(high(uint64)))])
let blessed = recordAccumulationBless(handed.effects, roles, privilegePolicy).value
checkStaging(blessed.effectContext(AccumulationDimension.Regular).value, payload())
let reauthorized = recordAccumulationDesignate(blessed, records, pvmContextConfig(3).staging)
assert reauthorized.error == AccumulationEffectError.None, "direct designate sees restored authority"
let retainedRoles = reauthorized.value.effectContext(
    AccumulationDimension.Regular).value.effectPrivileges.value
assert uint32(retainedRoles.privilegeInfo.value.registrar) == 7 and uint64(
    retainedRoles.alwaysAccumulateAt(PrivilegeEntryIndex(0)).value.gas) == high(uint64), "designate retains unrelated roles and allowances"
for successful in [0, 2]:
  failAfter(cint(successful))
  let failed = recordAccumulationDesignate(prepared, records, pvmContextConfig(3).staging)
  assert failed.error == AccumulationEffectError.BackendFailure and hashCalls() == cint(
      successful+1), "atomic immediate or delayed Merklization refusal"
  failHash(0)
  checkStaging(prepared.effectContext(AccumulationDimension.Regular).value,
      zeros) # Source survives either failure unchanged.
failHash(1)
assert run(valid).error == AccumulationDispatchError.BackendFailure, "host propagates backend refusal"
failHash(0)
let noAuthority = source(initialDelegator = 0)
failHash(1)
assert uint64(machineInfo(run(noAuthority).value.machine).value.registers[7]) == high(uint64)-8 and
    hashCalls() == 0, "HUH performs no state hashes"
failHash(0)
assert default(AccumulationEffectContext).effectStaging.error ==
    AccumulationEffectError.Uninitialized, "default roster query refuses"
assert recordAccumulationDesignate(default(AccumulationEffects), records, pvmContextConfig(
    3).staging).error == AccumulationEffectError.Uninitialized, "default mutation refuses"
let before = getOccupiedMem()
for iteration in 0..<1000:
  let completed = run(valid)
  checkStaging(context(completed), payload()) # Release every current map, roster and CPU successor.
let after = getOccupiedMem()
assert before == after, "designate releases all ARC-owned versions"
recordArcRelease("pvm_accumulation_designate", 1000, before, after)
echo "PVM accumulation designate passed"
echo "ARC_RELEASE cycles=1000 unchanged"
