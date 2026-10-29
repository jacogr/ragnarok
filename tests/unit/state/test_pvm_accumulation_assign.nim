# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_assign_arc_release"}

## Authored assign programs exercise ordered queue capture, current authority and atomic checkpoints.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite]
import ../../../src/codec/state/[layout as state_layout, privileges as state_privileges,
    authorization as state_authorization]
import ../../../src/codec/work/report as work_report
import ../../../src/codec/c2_records
import ../../../src/state/accumulation/[dispatch as accumulation_dispatch,
    effects as accumulation_effects, context as accumulation_context,
    machine as accumulation_machine, invocation as accumulation_invocation,
    outcome as accumulation_outcome]
import ../../../src/state/store
import ../../../src/pvm/[machine, program, step, gas, host_fetch]
import ../../support/[pvm_accumulation_program, pvm_accumulation_context, arc_evidence]

# Inject a failed hash only after authentic fixture construction.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
# Observe whether input/authorization refusals attempted state Merklization.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
# Refuse after completed child hashes to exercise cleanup of a partly built candidate tree.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

# Match the two-core fixture and the pinned queue length; other parameters retain their validated values.
proc parameters(): Parameters =
  var bytes = encodeParameters(pvmParameters())
  for i in 0..<24:
    bytes[i] = 0 # Free deposits isolate later storage preservation checks.
  bytes[24] = 2
  bytes[25] = 0
  bytes[82] = 80
  bytes[83] = 0 # E2 authQueueLen follows slotPeriodSec in the pinned parameter tuple.
  result = decodeParameters(bytes).value
  assert result.get(authQueueLen) == 80, "fixture queue parameter offset"

# Every hash and octet varies independently enough to expose truncation or reordered queue members.
proc payload(): seq[byte] =
  result = newSeq[byte](2560)
  for i in 0..<80:
    for j in 0..<32:
      result[i*32+j] = byte((i*3+j*7) mod 256) # Bounded arithmetic precedes byte narrowing.

# Authentic programs load full-width arguments before executing the assign ecalli.
proc source(core = 0'u64, address = 196608'u64, assigner = 99'u64,
    initialAssigner = 42'u32, credit = 100000'u64, data: seq[byte] = payload(),
    suffix: seq[seq[byte]] = @[@[50'u8, 0]]): PreparedAccumulationMachine =
  var instructions = @[registerImmediate(7, core), registerImmediate(8, address),
    registerImmediate(9, assigner), @[10'u8, 17]]
  for instruction in suffix:
    instructions.add(instruction) # Execute follow-up instructions through the production engine.
  guestProgram(instructions, credit, assigner = initialAssigner, manager = 42, writable = data,
      spareEntries = 1)

# Execution and copy limits are explicit policies, independent of fixed protocol cost.
proc run(prepared: PreparedAccumulationMachine, limit = 2560'u64,
    params: Parameters = parameters(), profile: AccumulationContextConfig = pvmContextConfig()): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, params,
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132))), MemoryByteLimit(limit),
    ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000), profile)

# Price the authored basic block separately from the independently fixed host charge.
proc price(prepared: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(prepared.accumulationMachine.value).value, CodeAddress(5),
    GasCycleLimit(1000)).value)

# Retain one complete implication dimension for state and checkpoint comparisons.
proc context(done: AccumulationDispatchResult, dimension = AccumulationDimension.Regular): AccumulationEffectContext =
  assert done.error == AccumulationDispatchError.None, "completed execution grants effects"
  done.effects.effectContext(dimension).value

# Compare both typed owners against the independently expected row and complete serialized chapters.
proc checkState(owner: AccumulationEffectContext, selected: int, assigner: uint32,
    expected: openArray[byte]) =
  let queues = owner.effectQueues.value
  let roles = owner.effectPrivileges.value
  let info = roles.privilegeInfo.value
  assert info.cores == 2 and info.always == 0, "preserve core count and empty allowance set"
  assert uint32(info.manager) == 42 and uint32(info.delegator) == 0 and uint32(info.registrar) == 0, "preserve unrelated roles"
  let map = owner.effectAccounts.value
  let qBytes = map.lookup(chapterKey(StateChapter(2))).value.bytes
  let pBytes = map.lookup(chapterKey(StateChapter(12))).value.bytes
  let decodedQueues = decodeAuthorization(AuthorizationKind.Queues, qBytes, pvmContextConfig().queues).value
  let decodedRoles = decodePrivilegeState(pBytes, pvmContextConfig().privileges).value
  assert decodedQueues.consumed == qBytes.len and qBytes.len == 5120, "canonical complete C2"
  assert decodedRoles.consumed == pBytes.len, "canonical complete C12"
  for c in 0..<2:
    let role = (if c == selected: assigner else: 42'u32)
    assert uint32(roles.privilegeAssignerAt(PrivilegeCoreIndex(uint64(c))).value) == role, "current positional assigner"
    assert uint32(decodedRoles.snapshot.privilegeAssignerAt(PrivilegeCoreIndex(uint64(c))).value) ==
        role, "serialized positional assigner"
    assert queues.authorizerCount(AuthorizationCoreIndex(uint64(c))).value == 80, "fixed queue extent"
    for i in 0..<80:
      let hash = queues.authorizerAt(AuthorizationCoreIndex(uint64(c)), AuthorizationIndex(uint64(i))).value
      let encoded = decodedQueues.snapshot.authorizerAt(AuthorizationCoreIndex(uint64(c)),
          AuthorizationIndex(uint64(i))).value
      for j in 0..<32:
        let octet = (if c == selected: expected[i*32+j] else: 0'u8)
        assert hash.bytes[j] == octet and encoded.bytes[j] == octet, "ordered hash and untouched other core"

let valid = source()
let done = run(valid)
assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt, "funded assign halts"
assert uint64(machineInfo(done.value.machine).value.registers[7]) == 0, "assign returns OK"
checkState(context(done), 0, 99, payload())
checkState(context(done, AccumulationDimension.Exceptional), 0, 42, newSeq[byte](2560))
assert uint64(machineInfo(valid.accumulationMachine.value).value.gas) == 100000, "source CPU immutable"
let originalMemory = memoryOf(valid.accumulationMachine.value).value
let currentMemory = memoryOf(done.value.machine).value
assert readBytes(originalMemory, MemoryAddress(196608), MemoryLength(2560), MemoryByteLimit(
    2560)).value ==
  readBytes(currentMemory, MemoryAddress(196608), MemoryLength(2560), MemoryByteLimit(2560)).value, "assign never writes guest input"
for core in [0'u64, 1]:
  for assigner in [0'u64, uint64(high(uint32))]:
    # Every protocol-valid proposed ID is accepted without an account-existence lookup.
    let completed = run(source(core = core, assigner = assigner))
    checkState(context(completed), int(core), uint32(assigner), payload())
let zeros = newSeq[byte](2560)
checkState(context(run(source(data = zeros))), 0, 99, zeros) # Duplicate all-zero hashes are positional data.
for core in [2'u64, 0x100000000'u64, high(uint64)]:
  let refused = run(source(core = core, initialAssigner = 0, assigner = high(uint64)))
  assert uint64(machineInfo(refused.value.machine).value.registers[7]) == high(uint64)-5, "CORE precedes HUH and WHO"
for proposed in [0x100000000'u64, high(uint64)]:
  let unauthorized = run(source(initialAssigner = 0, assigner = proposed))
  assert uint64(machineInfo(unauthorized.value.machine).value.registers[7]) == high(uint64)-8, "HUH precedes WHO"
  let badId = run(source(assigner = proposed))
  assert uint64(machineInfo(badId.value.machine).value.registers[7]) == high(uint64)-3, "WHO validates full-width service"
  checkState(context(badId), 0, 42, zeros)
for address in [0'u64, 65536'u64+4096-1280, 196608'u64+8192-1280, 0x100000000'u64, high(uint64)]:
  # Input interval failure precedes even deliberately invalid core, authority and proposed ID.
  let failed = run(source(address = address, core = high(uint64), initialAssigner = 0,
      assigner = high(uint64)))
  assert failed.error == AccumulationDispatchError.None and failed.value.exit == StepExit.Panic, "memory panic precedes guest validation"
  assert uint64(machineInfo(failed.value.machine).value.registers[7]) == high(uint64), "panic preserves core register"
var ro = newSeq[byte](2560)
ro[0] = 73
checkState(context(run(source(address = 65536))), 0, 99, ro) # Read-only pages remain readable queue input.
checkState(context(run(source(address = 196608'u64+4096-1280))), 0, 99,
    zeros) # Adjacent RW pages permit a complete crossing read.
assert run(valid, limit = 2559).error == AccumulationDispatchError.LimitExceeded, "copy ceiling before queue capture"
assert run(valid, params = pvmParameters()).error == AccumulationDispatchError.InvalidContext, "incoherent core profile refuses"
var wrongQueue = encodeParameters(parameters())
wrongQueue[82] = 79
assert run(valid, params = decodeParameters(wrongQueue).value).error ==
    AccumulationDispatchError.InvalidContext, "incoherent queue profile refuses"
for available in [0'u64, 1817, 1818, 1819]:
  let completed = run(source(credit = price(valid)+available))
  assert completed.error == AccumulationDispatchError.None, "host gas edge completes"
  let cpu = machineInfo(completed.value.machine).value
  if available < 1818:
    assert completed.value.exit == StepExit.OutOfGas and uint64(cpu.gasDeficit) == 0, "exact assign gas deficit"
    assert uint64(cpu.registers[7]) == 0, "OOG preserves core register"
    checkState(context(completed), 0, 42, zeros)
  else:
    assert completed.value.exit == StepExit.Halt and uint64(cpu.gas) == available-1818, "exact funded assign gas"
let low = source(address = high(uint64), credit = price(valid))
assert run(low, limit = 0, params = pvmParameters()).value.exit == StepExit.OutOfGas, "charge precedes input and profile checks"
let huge = run(source(credit = high(uint64)))
assert uint64(machineInfo(huge.value.machine).value.gas) == high(uint64)-price(valid)-1818, "full-width credit subtraction"
# After handoff the same invoking service cannot authorize another replacement of that core.
let handed = run(source(suffix = @[registerImmediate(7, 0), @[10'u8, 17], @[50'u8, 0]]))
assert uint64(machineInfo(handed.value.machine).value.registers[7]) == high(uint64)-8, "next call observes current assigner"
checkState(context(handed), 0, 99, payload())
for checkpoint in [false, true]:
  let suffix = (if checkpoint: @[@[10'u8, 19], @[0'u8]] else: @[@[0'u8]])
  let completed = run(source(suffix = suffix))
  assert completed.value.exit == StepExit.Panic, "authored terminal panic"
  let normalized = normalizeAccumulationOutcome(completed)
  checkState(normalized.value.outcomeContext.value, 0, (if checkpoint: 99'u32 else: 42'u32),
    (if checkpoint: payload() else: zeros)) # Checkpoint selects both chapters and both typed owners together.
for checkpoint in [false, true]:
  let suffix = (if checkpoint: @[@[10'u8, 19], registerImmediate(7, 0), @[10'u8, 17], @[50'u8, 0]] else:
    @[registerImmediate(7, 0), @[10'u8, 17], @[50'u8, 0]])
  let completed = run(source(credit = price(valid)+2000, suffix = suffix))
  assert completed.error == AccumulationDispatchError.None and completed.value.exit ==
      StepExit.OutOfGas, "second assign exhausts gas"
  assert normalizeAccumulationOutcome(completed).value.outcomeContext.value.effectInfo.value.hasAssignments ==
      checkpoint, "OOG selects assignment provenance with the exact checkpoint"
  checkState(normalizeAccumulationOutcome(completed).value.outcomeContext.value, 0,
    (if checkpoint: 99'u32 else: 42'u32), (if checkpoint: payload() else: zeros)) # OOG selects the exact complete checkpoint.
# Preserve accepted queues across later storage and yield mutations through all EffectData constructors.
let preserved = run(source(suffix = @[registerImmediate(7, 65536), @[10'u8, 27],
  @[51'u8, 7, 255], registerImmediate(8, 65536), registerImmediate(9, 1), registerImmediate(10, 196608),
  registerImmediate(11, 3), @[10'u8, 5], @[50'u8, 0]]))
assert preserved.error == AccumulationDispatchError.None, "assign/yield/storage execution succeeds"
checkState(context(preserved), 0, 99, payload())
assert context(preserved).effectInfo.value.hasYield, "yield remains present after storage"
assert context(preserved).effectInfo.value.hasAssignments, "yield and storage retain assignment provenance"
# The direct API repeats authority checks, captures borrowed hashes, and retains initial owners.
let initial = done.effects.effectContext(AccumulationDimension.Exceptional).value
let prepared = prepareAccumulationEffects(done.effects.effectsSource.value).value
let borrowedBytes = payload()
var hashes = newSeq[AuthorizerHash](80)
for i in 0..<80:
  for j in 0..<32:
    hashes[i].bytes[j] = borrowedBytes[i*32+j] # Independent caller-owned sequence.
let captured = recordAccumulationAssign(prepared, AuthorizationCoreIndex(0), hashes,
  ServiceIndex(99), pvmContextConfig().queues, pvmContextConfig().privileges)
assert captured.error == AccumulationEffectError.None, "direct assign accepted"
hashes[0].bytes[0] = 255
checkState(captured.value.effectContext(AccumulationDimension.Regular).value, 0, 99, payload())
checkState(initial, 0, 42, zeros)
assert recordAccumulationAssign(captured.value, AuthorizationCoreIndex(0), hashes,
  ServiceIndex(42), pvmContextConfig().queues, pvmContextConfig().privileges).error ==
  AccumulationEffectError.NotAssigner, "direct API uses current authority"
assert recordAccumulationAssign(prepared, AuthorizationCoreIndex(high(uint64)), hashes,
  ServiceIndex(42), pvmContextConfig().queues, pvmContextConfig().privileges).error ==
  AccumulationEffectError.InvalidCore, "direct API bounds full-width core"
assert recordAccumulationAssign(prepared, AuthorizationCoreIndex(0), hashes.toOpenArray(0, 78),
  ServiceIndex(42), pvmContextConfig().queues, pvmContextConfig().privileges).error ==
  AccumulationEffectError.InvalidState, "direct API requires exactly eighty hashes"
var small = pvmContextConfig().queues
small.maxHashes = ElementLimit(159)
assert recordAccumulationAssign(prepared, AuthorizationCoreIndex(0), hashes,
  ServiceIndex(42), small, pvmContextConfig().privileges).error ==
  AccumulationEffectError.LimitExceeded, "aggregate hash budget preflight"
small = pvmContextConfig().queues
small.maxBytes = ByteLimit(5119)
assert recordAccumulationAssign(prepared, AuthorizationCoreIndex(0), hashes,
  ServiceIndex(42), small, pvmContextConfig().privileges).error ==
  AccumulationEffectError.LimitExceeded, "complete queue byte budget"
var smallRoles = pvmContextConfig().privileges
smallRoles.maxBytes = ByteLimit(1)
assert recordAccumulationAssign(prepared, AuthorizationCoreIndex(0), hashes,
  ServiceIndex(42), pvmContextConfig().queues, smallRoles).error ==
  AccumulationEffectError.LimitExceeded, "privilege byte budget independent of queues"
# Bless observes and preserves current queues; its authority changes govern subsequent assign.
let roles = PrivilegeState(manager: ServiceIndex(42), delegator: ServiceIndex(0),
    registrar: ServiceIndex(0),
  assigners: @[ServiceIndex(42), ServiceIndex(42)])
let blessed = recordAccumulationBless(captured.value, roles, pvmContextConfig().privileges)
assert blessed.error == AccumulationEffectError.None, "bless after assign"
checkState(blessed.value.effectContext(AccumulationDimension.Regular).value, 0, 42, payload())
let reauthorized = recordAccumulationAssign(blessed.value, AuthorizationCoreIndex(0), hashes,
  ServiceIndex(99), pvmContextConfig().queues, pvmContextConfig().privileges)
assert reauthorized.error == AccumulationEffectError.None, "assign uses blessed current authority"
var richProfile = pvmContextConfig().privileges
richProfile.maxAlways = ElementLimit(2)
let richRoles = PrivilegeState(manager: ServiceIndex(42), delegator: ServiceIndex(7),
    registrar: ServiceIndex(8),
  assigners: @[ServiceIndex(42), ServiceIndex(42)],
  always: @[AlwaysAccumulate(service: ServiceIndex(9), gas: PrivilegeGas(high(uint64)))])
let rich = recordAccumulationBless(prepared, richRoles, richProfile).value
let assignedRich = recordAccumulationAssign(rich, AuthorizationCoreIndex(1), hashes,
  ServiceIndex(0), pvmContextConfig().queues, richProfile).value.effectContext(
      AccumulationDimension.Regular).value
let richInfo = assignedRich.effectPrivileges.value.privilegeInfo.value
let allowance = assignedRich.effectPrivileges.value.alwaysAccumulateAt(PrivilegeEntryIndex(0)).value
assert uint32(richInfo.delegator) == 7 and uint32(richInfo.registrar) == 8 and richInfo.always == 1, "preserve nonzero unrelated roles"
assert uint32(allowance.service) == 9 and uint64(allowance.gas) == high(uint64), "preserve full-width always allowance"
let serializedRich = decodePrivilegeState(assignedRich.effectAccounts.value.lookup(chapterKey(
    StateChapter(12))).value.bytes, richProfile).value.snapshot
assert uint64(serializedRich.alwaysAccumulateAt(PrivilegeEntryIndex(0)).value.gas) == high(uint64), "serialized full-width allowance retained"
# Hash failure must leave both original serialized chapters and typed snapshots accessible and unchanged.
failHash(1)
let failed = recordAccumulationAssign(prepared, AuthorizationCoreIndex(0), hashes,
  ServiceIndex(99), pvmContextConfig().queues, pvmContextConfig().privileges)
assert failed.error == AccumulationEffectError.BackendFailure and hashCalls() == 1, "atomic Merklization failure"
failHash(0)
failAfter(2)
let lateFailure = recordAccumulationAssign(prepared, AuthorizationCoreIndex(0), hashes,
  ServiceIndex(99), pvmContextConfig().queues, pvmContextConfig().privileges)
assert lateFailure.error == AccumulationEffectError.BackendFailure and hashCalls() == 3, "atomic cleanup after completed child hashes"
failHash(0)
checkState(prepared.effectContext(AccumulationDimension.Regular).value, 0, 42, zeros)
failHash(1)
assert run(valid).error == AccumulationDispatchError.BackendFailure, "dispatcher preserves backend failure"
failHash(0)
let unauthorized = source(initialAssigner = 0)
failHash(1)
assert uint64(machineInfo(run(unauthorized).value.machine).value.registers[7]) == high(uint64)-8 and
    hashCalls() == 0, "unauthorized call does not hash"
failHash(0)
assert default(AccumulationEffectContext).effectQueues.error ==
    AccumulationEffectError.Uninitialized, "default queue extraction refuses"
assert recordAccumulationAssign(default(AccumulationEffects), AuthorizationCoreIndex(0), hashes,
  ServiceIndex(42), pvmContextConfig().queues, pvmContextConfig().privileges).error ==
  AccumulationEffectError.Uninitialized, "default assign refuses"
let before = getOccupiedMem()
for iteration in 0..<1000:
  let completed = run(valid)
  checkState(context(completed), 0, 99, payload()) # Release every queue, privilege and serialized-map successor.
let after = getOccupiedMem()
assert before == after, "assign releases all ARC-owned versions"
recordArcRelease("pvm_accumulation_assign", 1000, before, after)
echo "PVM accumulation assign passed"
echo "ARC_RELEASE cycles=1000 unchanged"
