# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_provide_arc_release"}

## Authored provide guest programs verify charging, exact row ordering, requested capture and checkpoint rollback.
## Includes wide gas/target/pointer witnesses, normalized provision ownership, local refusals and ARC release.

import std/[assertions, syncio]
import ../../../src/state/[accumulation_dispatch, accumulation_machine, accumulation_outcome,
  accumulation_effects, accumulation_context, accumulation_invocation, accumulation_service, store]
import ../../../src/codec/[bounded, composite, state_accounts, state_requests, state_service_values,
  state_layout, state_trie, c2_records]
import ../../../src/pvm/[machine, program, gas, step, host_fetch]
import ../../../src/crypto/primitives
import ../../support/[pvm_accumulation_context, pvm_accumulation_program, arc_evidence]

## Inject payload-hash and namespace-hash refusal independently after immutable fixture preparation.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Restore real hashing and reset the observer counters.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Count calls to prove underfunded/invalid-memory/unknown-target preflight never reaches hashing.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Independent capture ceilings; these do not alter gas or guest-visible WHO/HUH results.
proc policy(items = 4'u64, perBlob = 8192'u64, total = 16384'u64): AccumulationProvisionLimits =
  AccumulationProvisionLimits(items: ElementLimit(items), perBlob: ByteLimit(perBlob),
    totalBlobBytes: ByteLimit(total))

## Construct one outstanding request using existing canonical key derivation, not a replacement lookup implementation.
proc request(service: uint32, payload: seq[byte], history: seq[byte] = @[0'u8]): StateEntry =
  let digest = ServicePreimageHash(array[32, byte](blake2b256(payload).value))
  StateEntry(key: serviceRequestKey(ServiceIndex(service), digest,
    RequestLength(uint32(payload.len)), ByteLimit(32)).value, value: history)

## Authored page contents are a leading value followed by zero-filled physical bytes.
proc blob(size: int, first: byte): seq[byte] =
  result = newSeq[byte](size)
  if size > 0:
    result[0] = first # Empty payloads have no octet to write.

## Real account targets 0/99/UINT32_MAX and requested RO/RW/empty/cross-page buffers are independent pairs.
proc entries(): seq[StateEntry] =
  result = @[]
  for service in [0'u32, 99'u32, high(uint32)]:
    result.add(serviceMetadataEntry(ServiceIndex(service), ServiceMetadata(), ByteLimit(
        89)).value) # Self is supplied by bootstrap.
  for service in [0'u32, 42'u32, 99'u32, high(uint32)]:
    for payload in [blob(0, 0), blob(1, 73), blob(1, 81), blob(1025, 73), blob(32, 0)]:
      result.add(request(service, payload)) # All histories start empty and remain unfulfilled after provide.

let halt = @[50'u8, 0]
let provideCall = @[10'u8, 27]
let checkpointCall = @[10'u8, 18]
let regular = AccumulationDimension.Regular
let exceptional = AccumulationDimension.Exceptional
let who = high(uint64)-3
let huh = high(uint64)-8
let fixture = entries()

## Assemble a standalone provide call with complete immutable account/request provenance.
proc source(target: uint64, address = 65536'u64, size = 1'u64,
    credit = 100000'u64, extra: seq[StateEntry] = entries()): PreparedAccumulationMachine =
  guestProgram([registerImmediate(7, target), registerImmediate(8, address),
    registerImmediate(9, size), provideCall, halt], credit, extra = extra)

## Run with explicit copy/provision policy; existing callers may still omit provision capacity.
proc run(prepared: PreparedAccumulationMachine, copyLimit = 8192'u64,
    limits = policy(), steps = 100'u64, calls = 10'u64): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, pvmParameters(),
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132))), MemoryByteLimit(copyLimit),
    ExecutionStepLimit(steps), HostCallLimit(calls), GasCycleLimit(1000), pvmContextConfig(), limits)

## The full guest block is paid before provide; independent host-cost literals are added separately.
proc blockPrice(prepared: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(prepared.accumulationMachine.value).value,
    CodeAddress(5), GasCycleLimit(1000)).value)

## Copy a dimension's current count; extraction stays owner-bound after normalization or source release.
proc count(done: AccumulationDispatchResult, dimension = AccumulationDimension.Regular): int =
  done.effects.effectContext(dimension).value.effectInfo.value.provisions

## Verify exact target/raw bytes, independent extraction ownership and the selected final count.
proc checkProvision(context: AccumulationEffectContext, ordinal: uint64,
    target: uint32, expected: seq[byte]) =
  let provision = context.effectProvisionAt(AccumulationProvisionIndex(ordinal)).value
  assert uint32(provision.provisionInfo.value.service) == target
  assert provision.copyProvisionBytes.value == expected
  var copy = provision.copyProvisionBytes.value
  if copy.len > 0:
    copy[0] = copy[0] xor 255 # Caller mutations never change a retained provision's bytes.
  assert provision.copyProvisionBytes.value == expected

for target in [0'u64, 42, 99, uint64(high(uint32)), high(uint64)]:
  # Self's exact UINT64_MAX sentinel and the full uint32 domain select their genuine request records.
  let prepared = source(target)
  let done = run(prepared)
  assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt
  let cpu = machineInfo(done.value.machine).value
  assert uint64(cpu.registers[7]) == 0
  assert uint64(cpu.gas) == 100000-blockPrice(prepared)-3983
  for i in 0..<13:
    if i != 7 and i != 8 and i != 9:
      assert uint64(cpu.registers[i]) == uint64(machineInfo(
          prepared.accumulationMachine.value).value.registers[i]) # Unrelated registers persist.
  assert count(done) == 1 and count(done, exceptional) == 0
  let normalized = normalizeAccumulationOutcome(done).value
  assert normalized.outcomeInfo.value.provisions == 1
  checkProvision(normalized.outcomeContext.value, 0, (if target == high(
      uint64): 42'u32 else: uint32(target)), blob(1, 73))
for target in [100'u64, 0x10000002a'u64, high(uint64)-1]:
  # Missing accounts and out-of-domain targets become WHO only after complete guest memory validation.
  let done = run(source(target))
  assert uint64(machineInfo(done.value.machine).value.registers[7]) == who and count(done) == 0
for address in [0'u64, 69616, 0xffffffff'u64, 0x100010000'u64, high(uint64)]:
  let done = run(source(100, address, 32))
  assert done.value.exit == StepExit.Panic # Guest unreadability precedes WHO for an absent target.
  assert uint64(machineInfo(done.value.machine).value.registers[7]) == 100
  assert count(done) == 0 and count(done, exceptional) == 0
# Zero-length reads accept every pointer, yet still require a real outstanding empty-blob request.
let empty = run(source(high(uint64), high(uint64), 0))
assert uint64(machineInfo(empty.value.machine).value.registers[7]) == 0
checkProvision(empty.effects.effectContext(regular).value, 0, 42, @[])
# A request for 32 zero bytes can be fulfilled from across the two adjacent readable RW pages.
let cross = run(source(42, 196608'u64+4096-16, 32))
assert uint64(machineInfo(cross.value.machine).value.registers[7]) == 0
checkProvision(cross.effects.effectContext(regular).value, 0, 42, blob(32, 0))
# An unrequested payload and a nonempty canonical history are HUH, retaining both dimensions.
let notRequested = run(source(42, 196609, 1))
assert uint64(machineInfo(notRequested.value.machine).value.registers[7]) == huh
var nonempty = @[request(42, blob(1, 73), @[1'u8, 1, 0, 0, 0])]
let past = run(source(42, extra = nonempty))
assert uint64(machineInfo(past.value.machine).value.registers[7]) == huh and count(past) == 0
# The same payload requested by different services remains two pairs; a third exact duplicate is HUH at capacity.
let pairs = guestProgram([registerImmediate(7, 42), registerImmediate(8, 65536), registerImmediate(9, 1),
  provideCall, registerImmediate(7, 99), provideCall, registerImmediate(7, 42), provideCall, halt],
  100000, extra = fixture)
let paired = run(pairs, limits = policy(items = 2, perBlob = 1, total = 2))
assert uint64(machineInfo(paired.value.machine).value.registers[7]) == huh and count(paired) == 2
checkProvision(paired.effects.effectContext(regular).value, 0, 42, blob(1, 73))
checkProvision(paired.effects.effectContext(regular).value, 1, 99, blob(1, 73))
# Checkpoint preserves the first payload when a later successful provide changes regular membership.
let historyInstructions = [registerImmediate(7, 42), registerImmediate(8, 65536), registerImmediate(9, 1),
  provideCall, checkpointCall, registerImmediate(7, 42), registerImmediate(8, 196608), provideCall, halt]
let history = guestProgram(historyInstructions, 100000, extra = fixture)
let completed = run(history)
assert count(completed) == 2 and count(completed, exceptional) == 1
let normalized = normalizeAccumulationOutcome(completed).value
assert normalized.outcomeInfo.value.provisions == 2
checkProvision(normalized.outcomeContext.value, 1, 42, blob(1, 81))
let trapped = run(guestProgram([registerImmediate(7, 42), registerImmediate(8, 65536),
    registerImmediate(9, 1),
  provideCall, checkpointCall, registerImmediate(7, 42), registerImmediate(8, 196608), provideCall,
      @[0'u8]],
  100000, extra = fixture))
let rollback = normalizeAccumulationOutcome(trapped).value
assert rollback.outcomeInfo.value.provisions == 1
checkProvision(rollback.outcomeContext.value, 0, 42, blob(1, 73))
# Actual regular provisions survive readable hash-return override and all other return boundaries.
for length in [31'u64, 32, 33]:
  for address in [0'u64, 65536, 196609, high(uint64)]:
    let execution = run(guestProgram([registerImmediate(7, 196608), @[10'u8, 26],
      registerImmediate(7, 42), registerImmediate(8, 65536), registerImmediate(9, 1),
      provideCall, registerImmediate(7, address), registerImmediate(8, length), halt],
      100000, extra = fixture))
    let selected = normalizeAccumulationOutcome(execution).value
    let context = selected.outcomeContext.value
    assert selected.outcomeInfo.value.provisions == 1 and selected.outcomeInfo.value.hasYield
    checkProvision(context, 0, 42, blob(1, 73))
    let commitment = array[32, byte](context.effectYield.value)
    let expected = if length == 32 and address == 65536: 73'u8
      elif length == 32 and address == 196609: 0'u8 else: 81'u8
    assert commitment[0] == expected,
      "only an accessible exactly-32-byte return overrides the prior yield beside retained X provisions"
    for index in 1..<32:
      assert commitment[index] == 0, "zero bytes are retained even for a present all-zero override hash"
    let original = execution.effects.effectContext(AccumulationDimension.Regular).value
    assert array[32, byte](original.effectYield.value)[0] == 81,
      "returned-hash normalization does not replace the original execution's yield"
for witness in [(0'u64, 3980'u64), (1'u64, 3983'u64), (1023'u64, 6242'u64),
    (1024'u64, 6244'u64), (1025'u64, 6247'u64), (4294967295'u64, 9495908234'u64),
    (4294967296'u64, 9495908236'u64)]:
  let (size, expectedCost) = witness
  # Frozen GP formula witnesses cover exact multiples, rounding and the uint32-length boundary.
  let prototype = source(42, size = size)
  let price = blockPrice(prototype)
  for available in [0'u64, expectedCost-1]:
    let done = run(source(42, size = size, credit = price+available), copyLimit = 0,
        limits = policy(items = 0))
    assert done.value.exit == StepExit.OutOfGas
    let cpu = machineInfo(done.value.machine).value
    assert uint64(cpu.gas) == 0 and uint64(cpu.gasDeficit) == expectedCost-available
    assert uint64(cpu.registers[7]) == 42 and count(done) == 0
  for available in [expectedCost, expectedCost+1]:
    # Exact affordability reaches row semantics even with zero gas left; boundary buffers never require large allocations.
    let done = run(source(42, size = size, credit = price+available))
    let cpu = machineInfo(done.value.machine).value
    assert uint64(cpu.gas) == available-expectedCost and uint64(cpu.gasDeficit) == 0
    if size == 4294967295'u64:
      assert done.value.exit == StepExit.Panic and uint64(cpu.registers[7]) ==
          42 # Natural address interval crosses 2^32.
      assert count(done) == 0
    else:
      assert done.value.exit == StepExit.Halt # Length validity precedes memory for the 2^32 case.
      let accepted = size == 0 or size == 1 or size == 1025
      assert uint64(cpu.registers[7]) == (if accepted: 0'u64 else: huh)
      assert count(done) == (if accepted: 1 else: 0)
# Funded invalid lengths return HUH before unreadable pointers or exhausted copy/provision budgets.
for witness in [(4294967296'u64, 9495908236'u64),
    (4611686018427387904'u64, 10196149556366806924'u64)]:
  let (size, expectedCost) = witness
  let prototype = source(42, high(uint64), size)
  let done = run(source(42, high(uint64), size, high(uint64)), copyLimit = 0, limits = policy(items = 0))
  assert done.value.exit == StepExit.Halt
  assert uint64(machineInfo(done.value.machine).value.registers[7]) == huh
  assert uint64(machineInfo(done.value.machine).value.gas) == high(uint64)-blockPrice(
      prototype)-expectedCost
# A cost above uint64 can still produce representable terminal debt after subtracting the full initial credit.
let wide = source(42, size = 9223372036854775808'u64, credit = high(uint64))
let wideDone = run(wide, copyLimit = 0)
assert wideDone.value.exit == StepExit.OutOfGas
assert uint64(machineInfo(wideDone.value.machine).value.gasDeficit) ==
  1945555039024058253'u64+blockPrice(wide)
assert uint64(normalizeAccumulationOutcome(wideDone).value.outcomeInfo.value.gasUsed) == high(uint64)
# The exact negative-domain boundary is supported; one extra debt unit and 66-bit excess refuse locally.
let largeSize = 4611686018427387904'u64
let largeCost = 10196149556366806924'u64
let largePrice = blockPrice(source(42, size = largeSize))
let edgeCredit = largePrice+largeCost-0x8000000000000000'u64
let edge = run(source(42, size = largeSize, credit = edgeCredit))
assert edge.value.exit == StepExit.OutOfGas
assert uint64(machineInfo(edge.value.machine).value.gasDeficit) == 0x8000000000000000'u64
assert run(source(42, size = largeSize, credit = edgeCredit-1)).error ==
    AccumulationDispatchError.GasRangeExceeded
assert run(source(42, size = high(uint64), credit = high(uint64))).error ==
    AccumulationDispatchError.GasRangeExceeded
# A second underfunded provide retains the checkpoint and caps normalized gas consumption at the original credit.
let debtCredit = blockPrice(history)+3983+103+3982
let debt = run(guestProgram(historyInstructions, debtCredit, extra = fixture))
assert debt.value.exit == StepExit.OutOfGas and count(debt) == 1 and count(debt, exceptional) == 1
assert normalizeAccumulationOutcome(debt).value.outcomeInfo.value.provisions == 1
assert uint64(normalizeAccumulationOutcome(debt).value.outcomeInfo.value.gasUsed) == debtCredit
for limits in [policy(items = 0), policy(perBlob = 0), policy(total = 0)]:
  assert run(source(42), limits = limits).error ==
      AccumulationDispatchError.LimitExceeded # No partial provision result.
assert run(source(42), copyLimit = 0).error == AccumulationDispatchError.LimitExceeded
assert run(history, limits = policy(items = 1)).error == AccumulationDispatchError.LimitExceeded
assert run(history, calls = 1).executionError == StepError.HostCallLimitExceeded
assert run(history, steps = 5).executionError == StepError.StepLimitExceeded
for malformed in [@[request(42, blob(1, 73), @[1'u8])],
    @[StateEntry(key: chapterServiceKey(StateChapter(255), ServiceIndex(99)), value: @[0'u8])]]:
  # Malformed request history and malformed other-service metadata are local errors, never HUH or WHO.
  let target = (if malformed[0].value.len == 1 and malformed[0].value[0] == 0: 99'u64 else: 42'u64)
  assert run(source(target, extra = malformed)).error == AccumulationDispatchError.MalformedState
let backendSource = source(42)
for successful in [0.cint, 1.cint]:
  hashAfter(successful)
  assert run(backendSource).error == AccumulationDispatchError.BackendFailure # Neither hash failure becomes HUH.
  assert hashCalls() == successful+1
  failHash(0)
let missing = source(100)
failHash(1)
assert uint64(machineInfo(run(missing).value.machine).value.registers[7]) == who
assert hashCalls() == 0
failHash(0)
# Normalization/extraction need no backend and all immutable initial request records remain retained.
failHash(1)
checkProvision(normalizeAccumulationOutcome(completed).value.outcomeContext.value, 0, 42, blob(1, 73))
assert hashCalls() == 0
failHash(0)
assert count(run(history)) == 2 # Retry starts from the unchanged bootstrap, not the earlier successful effects.
assert uint64(machineInfo(history.accumulationMachine.value).value.gas) == 100000
let before = getOccupiedMem()
for iteration in 0..<1000:
  let done = run(history)
  assert count(done) == 2 and count(done, exceptional) == 1 # Each run owns a fresh bounded execution history.
  checkProvision(normalizeAccumulationOutcome(done).value.outcomeContext.value, 1, 42, blob(1, 81))
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_accumulation_provide", 1000, before, after)
echo "PVM accumulation provide passed"
echo "ARC_RELEASE cycles=1000 unchanged"
