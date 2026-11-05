# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_service_residency_arc_release"}

## Resident A/B/A code keeps fresh arguments/gas/memory; eviction and refusals preserve old immutable outputs.

import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/state/accumulation/residency
import ../../../src/codec/composite
import ../../../src/codec/work/digest
import ../../../src/pvm/[program, machine, initialize, step]
import ../../../src/pvm/gas/gas

func envelope(last = 0'u8): seq[byte] =
  ## Literal Y envelope contains a writable sentinel and host/halt instructions with a fixed mask.
  @[0'u8, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 91, 8, 0, 0, 0, 0, 0, 4, 10, last, 50, 0, 5]

func limits(): InitializationLimits =
  ## Independent allocation bounds match this literal, including one argument page and one data page.
  InitializationLimits(envelope: InitializationByteLimit(128), program: ProgramByteLimit(64),
    jumps: JumpCountLimit(0), pages: PageLimit(2))

func version(value: byte): CodeHash =
  ## The registry receives already authenticated versions; classification itself is tested at service resolution.
  var bytes = default(array[32, byte])
  bytes[0] = value
  CodeHash(bytes)

proc capture(context: var ServiceExecutionContext, service: uint32, argument: byte,
    selected = PvmBackend.Interpreted): Machine =
  ## Acquire before initialization; return an immutable machine that safely outlives the scoped lease.
  assert service <= 255
  let lease = acquireServiceExecution(context, ServiceIndex(service), version(byte(service)), selected)
  assert lease.initialized
  let created = initializeMachine(envelope(), [argument], CodeAddress(0), MachineGas(100+uint64(
      argument)),
    limits(), lease)
  assert created.error == InitializationError.None
  created.value

type
  ProbeError {.pure.} = enum ## The normal host always succeeds; unexpected conditions fail assertions.
    Unexpected
  Probe = object ## Invocation-local state borrows the context only during the already admitted callback.
    owner: ptr ServiceExecutionContext
    calls: int

proc respond(context: var Probe, stopped: StepOutcome): HostResult[ProbeError] {.raises: [].} =
  ## Even another service cannot mutate an initializer while this invocation retains exclusive admission.
  inc context.calls
  let refused = acquireServiceExecution(context.owner[], ServiceIndex(99), version(99),
      PvmBackend.Interpreted)
  assert not refused.initialized
  let cpu = stopped.machine.machineInfo.value
  hostSuccess[ProbeError](HostResponse(action: HostAction.Panic, gas: MachineGas(77),
    gasDeficit: GasDeficit(0), registers: cpu.registers, memory: stopped.machine.memoryOf.value))

proc witness() =
  ## Real identity, complete input bytes, host outcomes and retained outputs supplement finite occupancy checks.
  var context = default(ServiceExecutionContext)
  block:
    # A preflight refusal before initialization cannot leave a negative resident entry.
    let unused = acquireServiceExecution(context, ServiceIndex(99), version(99),
        PvmBackend.Interpreted)
    assert unused.initialized
  assert context.residentServices == 0
  let a = capture(context, 1, 11)
  let b = capture(context, 2, 22)
  let again = capture(context, 1, 33)
  assert programOf(a).value == programOf(again).value
  assert programOf(a).value != programOf(b).value
  assert uint64(a.machineInfo.value.gas) == 111
  assert uint64(again.machineInfo.value.gas) == 133
  assert a.memoryOf.value.pageImage(PageIndex(0xfeff0000'u32 div 4096)).value.bytes[0] == 11
  assert again.memoryOf.value.pageImage(PageIndex(0xfeff0000'u32 div 4096)).value.bytes[0] == 33
  assert a.memoryOf.value.pageImage(PageIndex(32)).value.bytes[0] == 91
  block:
    # Admission is already exclusive before the first initializer or host callback executes.
    var lease = acquireServiceExecution(context, ServiceIndex(1), version(1),
        PvmBackend.Interpreted)
    let admitted = move(lease)
    assert admitted.initialized and not lease.initialized
    let refused = acquireServiceExecution(context, ServiceIndex(2), version(2),
        PvmBackend.Interpreted)
    assert not refused.initialized
    var host = Probe(owner: addr context, calls: 0)
    let done = executeWithHost(again, host, respond, ExecutionStepLimit(10), HostCallLimit(1),
      GasCycleLimit(1000), PvmBackend.Interpreted, admitted)
    assert done.error == HostExecutionError.None and host.calls == 1
    assert done.value.exit == StepExit.Panic
    assert uint64(done.value.machine.machineInfo.value.gas) == 77
    assert done.value.machine.memoryOf.value.pageImage(PageIndex(32)).value.bytes[0] == 91
  block:
    # Failed initialization keeps this exact live worker/backend, including after a lease move.
    var lease = acquireServiceExecution(context, ServiceIndex(1), version(1),
        PvmBackend.Interpreted)
    let firstFailure = initializeMachine([], [], CodeAddress(0), MachineGas(100), limits(), lease)
    assert firstFailure.error == InitializationError.InvalidEnvelope
    let admitted = move(lease)
    assert admitted.initialized and not lease.initialized
    let repeated = initializeMachine([], [], CodeAddress(0), MachineGas(101), limits(), admitted)
    assert repeated.error == InitializationError.InvalidEnvelope
    let valid = initializeMachine(envelope(), [44'u8], CodeAddress(0), MachineGas(144), limits(), admitted)
    assert valid.error == InitializationError.None
    assert programOf(valid.value).value == programOf(
        a).value # A default one-shot fallback would create another Program identity.
    assert uint64(valid.value.machineInfo.value.gas) == 144
    assert valid.value.memoryOf.value.pageImage(PageIndex(0xfeff0000'u32 div 4096)).value.bytes[
        0] == 44
    var host = Probe(owner: addr context, calls: 0)
    let done = executeWithHost(valid.value, host, respond, ExecutionStepLimit(10), HostCallLimit(1),
      GasCycleLimit(1000), PvmBackend.Interpreted, admitted)
    assert done.error == HostExecutionError.None and done.value.exit == StepExit.Panic
    assert host.calls == 1 and uint64(done.value.machine.machineInfo.value.gas) == 77
  assert context.residentServices == 2 # Valid reinitialization restores retention eligibility on release.
  block:
    # A matching key still rechecks parse policies and cannot supply an invalid entry from cache.
    let lease = acquireServiceExecution(context, ServiceIndex(1), version(1),
        PvmBackend.Interpreted)
    var changed = limits()
    changed.jumps = JumpCountLimit(1)
    let parsed = initializeMachine(envelope(), [], CodeAddress(0), MachineGas(100), changed, lease)
    assert parsed.error == InitializationError.None
    assert programOf(parsed.value).value != programOf(a).value
    let bad = initializeMachine(envelope(), [], CodeAddress(1), MachineGas(100), changed, lease)
    assert bad.error == InitializationError.InvalidProgram
  assert context.residentServices == 1 # Failed initialization leaves no negative entry.
  discard capture(context, 1, 44)
  discard capture(context, 3, 55)
  discard capture(context, 4, 66)
  assert context.residentServices == 4
  block:
    # A malformed fifth key evicts before construction and retains no failed-key history.
    let lease = acquireServiceExecution(context, ServiceIndex(5), version(5),
        PvmBackend.Interpreted)
    let invalid = initializeMachine([], [], CodeAddress(0), MachineGas(100), limits(), lease)
    assert invalid.error != InitializationError.None
  assert context.residentServices == 3
  let replaced = capture(context, 1, 77, PvmBackend.Jit)
  assert programOf(replaced).value != programOf(a).value
  assert a.memoryOf.value.pageImage(PageIndex(0xfeff0000'u32 div 4096)).value.bytes[0] == 11
  assert b.memoryOf.value.pageImage(PageIndex(0xfeff0000'u32 div 4096)).value.bytes[0] == 22
  assert context.residentServices == 4
  let moved = move(context)
  assert moved.residentServices == 4 and context.residentServices == 0

witness()
let before = getOccupiedMem()
for iteration in 0..<1000: witness()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_service_residency", 1000, before, after)
echo "PVM service residency passed"
echo "ARC_RELEASE cycles=1000 unchanged"
