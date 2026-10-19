# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real guest provide witnesses verify exact charging, protocol priorities and immutable implications.
## Covers local failure rollback, checkpoint separation, full-width arithmetic and repeated ARC release.

import std/[assertions, syncio]
import ../../../src/state/[accumulation_machine, accumulation_dispatch, accumulation_effects,
  accumulation_context, accumulation_invocation, accumulation_service, store]
import ../../../src/codec/[bounded, state_layout, state_trie]
import ../../../src/pvm/[machine, program, step, gas]
import ../../support/[pvm_accumulation_provision, arc_evidence]

## Refuse payload hashing after genuine initialization, or the following canonical namespace hash.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Allow a fixed number of successful hashes before backend refusal.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

## Give every tested request a genuinely initialized full-width call descriptor.
func provide(service = high(uint64), address = 65536'u64, length = 3'u64): ProvisionGuestCall =
  ProvisionGuestCall(id: 27, r7: service, r8: address, r9: length)

## Isolate the independent instruction-block price so exact host costs do not depend on code length assumptions.
proc price(source: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(source.accumulationMachine.value).value, CodeAddress(5), GasCycleLimit(10000)).value)

## Inspect a selected dimension only after successful execution; copied bytes never alias the retained provision.
proc check(done: AccumulationDispatchResult, regular, exceptional: int) =
  assert done.error == AccumulationDispatchError.None
  let pair = done.effects
  assert pair.effectContext(AccumulationDimension.Regular).value.effectInfo.value.provisions == regular
  assert pair.effectContext(AccumulationDimension.Exceptional).value.effectInfo.value.provisions == exceptional
  let source = pair.effectsSource.value.initialContext(AccumulationDimension.Regular).value
  let original = source.contextInvocation.value.bootstrapService.value.serviceState.value
  assert array[32, byte](original.commitment.root) == array[32, byte](
      source.contextAccounts.value.commitment.root)
  let before = original.lookup(chapterServiceKey(StateChapter(255),
      source.contextInfo.value.service)).value
  let after = source.contextAccounts.value.lookup(chapterServiceKey(StateChapter(255),
      source.contextInfo.value.service)).value
  assert before.bytes == after.bytes # Provide does not fulfill requests, publish accounts or apply incoming credit again.

for service in [0'u64, 42'u64, 99'u64, uint64(high(uint32)), high(uint64)]:
  # Service boundaries and the exact self sentinel retain the correct target instead of truncating register bits.
  let done = runProvision(provisionMachine([provide(service)]))
  check(done, 1, 0)
  assert done.value.exit == StepExit.Halt
  let retained = done.effects.effectContext(
      AccumulationDimension.Regular).value.effectProvisionAt(AccumulationProvisionIndex(0)).value
  let expected = if service == high(uint64): 42'u64 else: service
  assert uint64(uint32(retained.provisionInfo.value.service)) == expected
  assert uint64(machineInfo(done.value.machine).value.registers[7]) == 0
  var bytes = retained.copyProvisionBytes.value
  assert bytes == @[9'u8, 8, 7]
  bytes[0] = 1
  assert retained.copyProvisionBytes.value == @[9'u8, 8, 7]
for service in [98'u64, 0x10000002a'u64, high(uint64)-1]:
  # Unknown in-domain and full-width out-of-domain indices all return WHO after the successful guest read.
  let done = runProvision(provisionMachine([provide(service)]))
  check(done, 0, 0)
  assert done.value.exit == StepExit.Halt
  assert uint64(machineInfo(done.value.machine).value.registers[7]) == high(uint64)-3
let duplicate = runProvision(provisionMachine([provide(), provide()]), provisionPolicy(items = 1,
    perBlob = 3, total = 3))
check(duplicate, 1, 0)
assert uint64(machineInfo(duplicate.value.machine).value.registers[7]) == high(uint64)-8
let separateTargets = runProvision(provisionMachine([provide(), provide(99)]), provisionPolicy(
    items = 2, perBlob = 3, total = 6))
check(separateTargets, 2, 0)
for history in [@[1'u8, 1, 0, 0, 0], @[2'u8, 1, 0, 0, 0, 2, 0, 0, 0],
    @[3'u8, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0]]:
  # Canonical nonempty histories are ordinary HUH, never malformed-state errors.
  let done = runProvision(provisionMachine([provide()], history = history))
  check(done, 0, 0)
  assert uint64(machineInfo(done.value.machine).value.registers[7]) == high(uint64)-8
let absent = runProvision(provisionMachine([provide()], requested = false))
check(absent, 0, 0)
assert uint64(machineInfo(absent.value.machine).value.registers[7]) == high(uint64)-8
for history in [newSeq[byte](0), @[0'u8, 0], @[4'u8]]:
  # Raw empty, suffixes and impossible request cardinalities remain local malformed-state refusals.
  assert runProvision(provisionMachine([provide()], history = history)).error ==
      AccumulationDispatchError.MalformedState
assert runProvision(provisionMachine([provide(99)], malformedAccount = true)).error ==
    AccumulationDispatchError.MalformedState
let empty = runProvision(provisionMachine([provide(address = high(uint64), length = 0)]),
  provisionPolicy(items = 1, perBlob = 0, total = 0), copyBytes = 0)
check(empty, 1, 0)
assert empty.effects.effectContext(AccumulationDimension.Regular).value.effectProvisionAt(
  AccumulationProvisionIndex(0)).value.copyProvisionBytes.value.len == 0
for size in [0, 1, 3, 1023, 1024, 1025]:
  # Direct small-width multiplication gives an independent mathematical host-price witness at rounding boundaries.
  var bytes = newSeq[byte](size)
  for i in 0..<size: bytes[i] = byte(i mod 256)
  let call = provide(length = uint64(size))
  let instructionGas = price(provisionMachine([call], data = bytes))
  let cost = 3980'u64+(2264'u64*uint64(size)+1023) div 1024
  for available in [0'u64, cost-1, cost, cost+1]:
    let done = runProvision(provisionMachine([call], data = bytes,
        credit = instructionGas+available))
    assert done.error == AccumulationDispatchError.None
    let cpu = machineInfo(done.value.machine).value
    if available < cost:
      # Host charging leaves r7 and both implication dimensions untouched before any memory/hash work.
      check(done, 0, 0)
      assert done.value.exit == StepExit.OutOfGas and uint64(cpu.gas) == 0
      assert uint64(cpu.gasDeficit) == cost-available and uint64(cpu.registers[7]) == high(uint64)
    else:
      check(done, 1, 0)
      assert done.value.exit == StepExit.Halt and uint64(cpu.gas) == available-cost
      assert uint64(cpu.gasDeficit) == 0 and uint64(cpu.registers[7]) == 0
      let retained = done.effects.effectContext(
          AccumulationDimension.Regular).value.effectProvisionAt(AccumulationProvisionIndex(0)).value
      assert retained.copyProvisionBytes.value == bytes # Check every byte, including long memory-copy/rounding witnesses.
let invalidLength = runProvision(provisionMachine([provide(address = high(uint64),
    length = 0x100000000'u64)], credit = 10000000000'u64),
  provisionPolicy(items = 0, perBlob = 0, total = 0), copyBytes = 0)
check(invalidLength, 0, 0)
assert invalidLength.value.exit == StepExit.Halt
assert uint64(machineInfo(invalidLength.value.machine).value.registers[7]) == high(uint64)-8
for pointer in [0'u64, 69631'u64, high(uint64)]:
  # Memory panic wins over an unknown target; nonwrapping cross-page and full-width ranges are preserved.
  let done = runProvision(provisionMachine([provide(98, address = pointer)]))
  check(done, 0, 0)
  assert done.value.exit == StepExit.Panic
  assert uint64(machineInfo(done.value.machine).value.registers[7]) == 98
let starvedCall = provide(address = high(uint64))
let starvedSource = provisionMachine([starvedCall], credit = price(provisionMachine([
    starvedCall]))+3979)
let starved = runProvision(starvedSource, provisionPolicy(items = 0, perBlob = 0, total = 0), copyBytes = 0)
check(starved, 0, 0)
assert starved.value.exit == StepExit.OutOfGas # Underfunding precedes both invalid memory and local budgets.
let hugeCall = provide(length = 0x8000000000000000'u64)
let hugeSource = provisionMachine([hugeCall], credit = high(uint64))
let huge = runProvision(hugeSource)
check(huge, 0, 0)
assert huge.value.exit == StepExit.OutOfGas
assert uint64(machineInfo(huge.value.machine).value.gasDeficit) == 1945555039024058253'u64+price(hugeSource)
assert runProvision(provisionMachine([provide(length = high(uint64))], credit = high(
    uint64))).error ==
  AccumulationDispatchError.GasRangeExceeded # Exact debt exceeds the machine's signed terminal domain.
let accepted = provisionMachine([provide()])
for policy in [provisionPolicy(items = 0), provisionPolicy(perBlob = 2), provisionPolicy(total = 2)]:
  # Each local retention ceiling refuses without publishing the charged CPU or any partial effect set.
  assert runProvision(accepted, policy).error == AccumulationDispatchError.LimitExceeded
assert runProvision(accepted, copyBytes = 2).error == AccumulationDispatchError.LimitExceeded
failHash(1)
assert runProvision(accepted).error == AccumulationDispatchError.BackendFailure
failHash(0)
hashAfter(1)
assert runProvision(accepted).error == AccumulationDispatchError.BackendFailure
failHash(0)
let mixedSource = provisionMachine([ProvisionGuestCall(id: 26, r7: 65536), provide(),
  ProvisionGuestCall(id: 18), provide(99)], data = newSeq[byte](32),
  extra = @[provisionRequest(42, @[0'u8, 0, 0]), provisionRequest(99, @[0'u8, 0, 0])])
let mixed = runProvision(mixedSource)
check(mixed, 2, 1)
for dimension in [AccumulationDimension.Regular, AccumulationDimension.Exceptional]:
  # Both dimensions preserve the earlier present all-zero yield across provides and the checkpoint.
  let current = mixed.effects.effectContext(dimension).value
  assert current.effectInfo.value.hasYield
  assert array[32, byte](current.effectYield.value) == default(array[32, byte])
let latePanic = runProvision(provisionMachine([provide(), ProvisionGuestCall(id: 18), provide(99,
    address = high(uint64))]))
check(latePanic, 1, 1)
assert latePanic.value.exit == StepExit.Panic
assert runProvision(mixedSource, calls = 3).error == AccumulationDispatchError.ExecutionFailure
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Successful mixed effects and late callback/engine failures release every private owner without a cycle.
  check(runProvision(mixedSource), 2, 1)
  assert runProvision(mixedSource, calls = 3).error == AccumulationDispatchError.ExecutionFailure
  assert runProvision(mixedSource, provisionPolicy(items = 1)).error ==
      AccumulationDispatchError.LimitExceeded
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_accumulation_provision", 1000, before, after)
echo "PVM accumulation provision passed"
echo "ARC_RELEASE cycles=1000 unchanged"
