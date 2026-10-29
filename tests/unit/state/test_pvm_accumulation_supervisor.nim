# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_supervisor_arc_release"}

## Genuine supervisor guests check incarnation-bound authority, atomic metadata and checkpoint ownership.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite]
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    outputs as state_outputs, trie as state_trie]
import ../../../src/codec/c2_records
import ../../../src/state/accumulation/[dispatch as accumulation_dispatch,
    effects as accumulation_effects, context as accumulation_context,
    machine as accumulation_machine, invocation as accumulation_invocation]
import ../../../src/state/store
import ../../../src/pvm/[machine, program, step, gas, host_fetch]
import ../../support/[pvm_accumulation_context, pvm_accumulation_program, arc_evidence]

# Inject refusal only after authentic account/guest preparation.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
# Count backend attempts to distinguish protocol refusal from store hashing.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
# Refuse after successful internal hashes to protect late atomicity.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

proc account(): ServiceMetadata =
  ## Distinguishable self fields expose accidental reset of anything outside the supervisor pair.
  ServiceMetadata(supervisor: ServiceIndex(42), supervisorCreated: AccountSlot(43),
      balance: AccountBalance(91), supervisorBalance: AccountBalance(17),
      depositOffset: AccountBalance(13), minimumAccumulationGas: Gas(23), minimumTransferGas: Gas(29),
      storageItems: AccountStorageItems(2), storageBytes: AccountStorageBytes(86),
      created: AccountSlot(43), lastAccumulation: AccountSlot(47), parent: ServiceIndex(53))

proc entry(service: uint32, supervisor = 42'u32, incarnation = 43'u32,
    created = 7'u32): StateEntry =
  ## Other accounts retain a fixed creation identity and distinct balances without code eligibility requirements.
  serviceMetadataEntry(ServiceIndex(service), ServiceMetadata(supervisor: ServiceIndex(supervisor),
      supervisorCreated: AccountSlot(incarnation), created: AccountSlot(created),
      balance: AccountBalance(71), supervisorBalance: AccountBalance(19)), ByteLimit(
          ServiceMetadataBytes)).value

proc source(target = high(uint64), supervisor = high(uint64), credit = 10000'u64,
    metadata: ServiceMetadata = account(), extra: seq[StateEntry] = @[], writes = 2'u64,
    suffix: seq[seq[byte]] = @[@[50'u8, 0]]): PreparedAccumulationMachine =
  ## Ordinary program preparation binds account provenance and executes the real current host29.
  var instructions = @[registerImmediate(7, target), registerImmediate(8, supervisor), @[10'u8, 29]]
  for instruction in suffix:
    instructions.add(instruction) # Continue the original program through optional reassignment/checkpoint witnesses.
  guestProgram(instructions, credit, account = metadata, extra = extra, writes = writes,
      spareEntries = 4)

proc run(prepared: PreparedAccumulationMachine): AccumulationDispatchResult =
  ## This host needs no guest-memory copy allowance; every finite work policy stays explicit.
  executeAccumulationMachine(prepared, pvmParameters(), FetchAccumulationLimits(items: ElementLimit(
      0), bytes: ByteLimit(1), operand: OperandLimits(maxBytes: ByteLimit(132))), MemoryByteLimit(0),
      ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000), pvmContextConfig())

proc initial(prepared: PreparedAccumulationMachine): AccumulationEffects =
  ## Retain the exact authentic pre-execution context for state-API and immutability comparisons.
  prepareAccumulationEffects(prepareAccumulationContexts(prepared.machineBootstrap.value,
      pvmContextConfig()).value).value

proc context(done: AccumulationDispatchResult, dimension = AccumulationDimension.Regular): AccumulationEffectContext =
  ## Failed local execution supplies no selectable context; successful guest terminals retain both dimensions.
  assert done.error == AccumulationDispatchError.None, "completed supervisor execution grants effects"
  done.effects.effectContext(dimension).value

proc bytes(owner: AccumulationEffectContext, service: uint32): seq[byte] =
  ## Copy one existing canonical record from its immutable current snapshot.
  owner.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      service))).value.bytes

proc check(before, after: AccumulationEffectContext, target, supervisor, created: uint32) =
  ## Check both typed identity and independent exact E4 positions; all other105-byte fields stay unchanged.
  let old = before.bytes(target)
  let wire = after.bytes(target)
  let metadata = decodeServiceMetadata(wire, ByteLimit(ServiceMetadataBytes)).value.metadata
  assert uint32(metadata.supervisor) == supervisor and uint32(metadata.supervisorCreated) ==
      created,
      "selected current supervisor identity is retained"
  for index in 0..<ServiceMetadataBytes:
    if index notin 33..40:
      assert wire[index] == old[index], "only the supervisor identity pair may change"
  for index in 0..<4:
    assert wire[33+index] == byte((supervisor shr (8*index)) and 255) and
        wire[37+index] == byte((created shr (8*index)) and 255), "supervisor pair uses exact canonical E4 slots"

let nominee = entry(99, created = 11)
let child = entry(77)
let valid = source(supervisor = 99, extra = @[nominee])
let prior = initial(valid).effectContext(AccumulationDimension.Regular).value
let done = run(valid)
assert done.value.exit == StepExit.Halt and uint64(machineInfo(done.value.machine).value.registers[
    7]) == 0,
    "self supervisor reassignment returns OK"
check(prior, context(done), 42, 99, 11)
assert context(done).effectAccountScope.value == AccumulationAccountScope.SelfMetadata,
    "self supervisor metadata retains the existing publication proof"
assert context(done, AccumulationDimension.Exceptional).bytes(42) == prior.bytes(42),
    "uncheckpointed reassignment preserves prior exceptional state"
assert context(done).bytes(99) == nominee.value, "nominee metadata never changes"

# Both sentinel positions and explicit self identify the same service, including a repeated no-op assignment.
for target in [42'u64, high(uint64)]:
  for supervisor in [42'u64, high(uint64)]:
    let completed = run(source(target, supervisor))
    assert uint64(machineInfo(completed.value.machine).value.registers[7]) == 0,
        "explicit self and sentinels share authority"
    check(context(completed, AccumulationDimension.Exceptional), context(completed), 42, 42, 43)

# Both E4 endpoints are real account IDs, distinct from the full64-bit self sentinel.
for target in [0'u32, high(uint32)]:
  let completed = run(source(target = uint64(target), supervisor = 99,
      extra = @[entry(target), nominee]))
  check(context(completed, AccumulationDimension.Exceptional), context(completed), target, 99, 11)
let maximum = run(source(supervisor = uint64(high(uint32)),
    extra = @[entry(high(uint32), created = high(uint32))]))
check(context(maximum, AccumulationDimension.Exceptional), context(maximum), 42, high(uint32), high(uint32))

# Full-width IDs never alias low account bits; missing nominee has WHO priority over authority.
for target in [100'u64, uint64(high(uint32))+43, high(uint64)-1]:
  let rejected = run(source(target = target, supervisor = 99, extra = @[nominee]))
  assert uint64(machineInfo(rejected.value.machine).value.registers[7]) == high(uint64)-3,
      "unknown full-width target returns WHO"
for supervisor in [100'u64, uint64(high(uint32))+43, high(uint64)-1]:
  let rejected = run(source(target = 77, supervisor = supervisor,
      extra = @[entry(77, supervisor = 99, incarnation = 11), nominee]))
  assert uint64(machineInfo(rejected.value.machine).value.registers[7]) == high(uint64)-3,
      "missing nominee precedes unauthorized caller HUH"

# Existing matching foreign supervision removes self's ability to reassign itself; stale/missing designation restores it.
for stale in [false, true]:
  var metadata = account()
  metadata.supervisor = ServiceIndex(99)
  metadata.supervisorCreated = AccountSlot(if stale: 10 else: 11)
  let completed = run(source(metadata = metadata, extra = @[nominee]))
  assert uint64(machineInfo(completed.value.machine).value.registers[7]) ==
      (if stale: 0'u64 else: high(uint64)-8), "creation-slot match determines effective authority"
  if not stale:
    assert context(completed).bytes(42) == context(completed,
        AccumulationDimension.Exceptional).bytes(42),
        "unauthorized self reassignment changes no metadata"
var missingDesignation = account()
missingDesignation.supervisor = ServiceIndex(100)
let fallback = run(source(metadata = missingDesignation))
check(context(fallback, AccumulationDimension.Exceptional), context(fallback), 42, 42, 43)

# A genuine supervisor can reassign a foreign target, after which the old supervisor loses authority.
let foreign = source(target = 77, supervisor = 99, extra = @[child, nominee])
let changed = run(foreign)
check(context(changed, AccumulationDimension.Exceptional), context(changed), 77, 99, 11)
assert context(changed).bytes(42) == context(changed, AccumulationDimension.Exceptional).bytes(42),
    "foreign reassignment preserves all invoker metadata"
assert context(changed).effectAccountScope.value == AccumulationAccountScope.Unsupported,
    "foreign execution cannot fabricate parallel publication provenance"
let lost = recordAccumulationSupervisor(changed.effects, ServiceIndex(77), ServiceIndex(42))
assert lost.error == AccumulationEffectError.NotRequested, "prior supervisor cannot reclaim delegated authority"
# Only a self target falls back to this invoker when a third-party supervisor is missing or recreated.
for incumbent in [entry(77, supervisor = 100), entry(77, supervisor = 99, incarnation = 10)]:
  let rejected = run(source(target = 77, extra = @[incumbent, nominee]))
  assert uint64(machineInfo(rejected.value.machine).value.registers[7]) == high(uint64)-8,
      "foreign fallback authorizes the target rather than this unrelated caller"

# Both checkpoint alternatives keep account bytes and mutation ancestry paired on guest panic.
for checkpoint in [false, true]:
  let failed = run(source(supervisor = 99, extra = @[nominee], suffix = (if checkpoint:
    @[@[10'u8, 19], @[0'u8]] else: @[@[0'u8]])))
  assert failed.value.exit == StepExit.Panic, "original guest continues after reassignment"
  let selected = context(failed, AccumulationDimension.Exceptional)
  let metadata = decodeServiceMetadata(selected.bytes(42), ByteLimit(
      ServiceMetadataBytes)).value.metadata
  assert uint32(metadata.supervisor) == (if checkpoint: 99'u32 else: 42'u32),
      "panic selects precisely its retained checkpoint"

# Price the original first block independently, then prove exact/short host gas with no state hashing on shortage.
let instructionCost = uint64(blockGas(valid.accumulationMachine.value.programOf.value, CodeAddress(
    5), GasCycleLimit(1000)).value)
for available in [999'u64, 1000]:
  let prepared = source(supervisor = 99, extra = @[nominee], credit = instructionCost+available)
  if available < 1000:
    failHash(1) # Genuine preparation is complete before refusing all backend work.
  let completed = run(prepared)
  assert completed.value.exit == (if available < 1000: StepExit.OutOfGas else: StepExit.Halt),
      "host gas shortage precedes metadata work"
  if available < 1000:
    assert hashCalls() == 0 and uint64(machineInfo(completed.value.machine).value.gas) == 0,
        "underfunding clamps gas without backend work"
    failHash(0)
assert run(source(supervisor = 99, extra = @[nominee], writes = 0)).error ==
    AccumulationDispatchError.LimitExceeded, "store write policy refuses atomically"
let pair = initial(valid)
for successful in [0, 2]:
  failAfter(cint(successful))
  let refused = recordAccumulationSupervisor(pair, ServiceIndex(42), ServiceIndex(99))
  assert refused.error == AccumulationEffectError.BackendFailure, "immediate/late hashing failure exposes no successor"
  failHash(0)
  assert pair.effectContext(AccumulationDimension.Regular).value.bytes(42) == prior.bytes(42),
      "failed hashing preserves the original immutable account"
let defaultResult = recordAccumulationSupervisor(default(AccumulationEffects), ServiceIndex(42),
    ServiceIndex(99))
assert defaultResult.error == AccumulationEffectError.Uninitialized, "default effects grant no authority"
let bad = StateEntry(key: nominee.key, value: newSeq[byte](ServiceMetadataBytes-1))
assert run(source(supervisor = 99, extra = @[bad])).error ==
    AccumulationDispatchError.MalformedState,
    "malformed nominee is a local state refusal"

proc cycle(prepared: PreparedAccumulationMachine) =
  ## Release each metadata/map/host-response successor without retaining either dimension across iterations.
  let completed = run(prepared)
  assert completed.value.exit == StepExit.Halt, "supervisor cycle completes"
cycle(valid)
cycle(foreign)
let before = getOccupiedMem()
for iteration in 0..<1000:
  cycle(valid)
  cycle(foreign) # Exercise supported self metadata and explicit foreign publication ancestry together.
let after = getOccupiedMem()
assert before == after, "supervisor transitions release all ARC owners"
recordArcRelease("pvm_accumulation_supervisor", 1000, before, after)
echo "PVM accumulation supervisor passed"
echo "ARC_RELEASE cycles=1000 unchanged"
