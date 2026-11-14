# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Four service/version/backend workers retain code only for one full-state Services lifetime.
## Acquire after authenticated code classification, before initialization; the opaque lease stays
## exclusive through callbacks and immutable publication. Workers may retain bounded baseline/scratch
## memory; live CPU, gas, host callbacks, results and chain state never belong to this context.

import std/assertions
import ../../codec/composite
import ../../codec/work/digest
import ../../pvm/[worker, initialize, machine, program, step]
import ../../pvm/gas/gas

type
  ResidentSlot = object ## A complete authenticated version and actual backend select one bounded worker.
    service: ServiceIndex
    version: CodeHash
    backend: PvmBackend
    worker: ExecutionWorker
    ready: bool
  ServiceExecutionContext* = object ## Stable exclusive owner; four workers, with no fifth miss-staging slot.
    slots: array[4, ResidentSlot]
    next: int
    busy: bool
    nativeRuntime: NativeRuntime # Safe closed anchor; compiler never reads this context.
  ServiceExecutionLease* = object ## Noncopyable scoped admission exposes operations, never a worker handle.
    owner: nil ptr ServiceExecutionContext
    index: int

proc `=copy`*(destination: var ServiceExecutionContext, source: ServiceExecutionContext) {.error.}
  ## Services owns the context; aliases cannot copy its mutable workers.

proc `=dup`*(source: ServiceExecutionContext): ServiceExecutionContext {.error.}
  ## Duplication cannot create an independent-looking owner of shared caches.

proc `=wasMoved`*(context: var ServiceExecutionContext) {.nodestroy, inline,
    requires: not context.busy.} =
  ## Only an idle, unborrowed owner may relocate; Services separately requires joined preparation.
  `=wasMoved`(context.slots)
  `=wasMoved`(context.nativeRuntime)
  for index in 0..<context.slots.len:
    # Child moves disarm owned refs without decrementing them; primitive state needs explicit reset.
    context.slots[index].service = default(ServiceIndex)
    context.slots[index].version = default(CodeHash)
    context.slots[index].backend = default(PvmBackend)
    context.slots[index].ready = false
  context.next = 0
  context.busy = false

proc `=destroy`*(context: ServiceExecutionContext) =
  ## No live lease may outlast the stable context; child workers release their acyclic code storage.
  assert not context.busy
  `=destroy`(context.slots)
  `=destroy`(context.nativeRuntime)

proc `=copy`*(destination: var ServiceExecutionLease, source: ServiceExecutionLease) {.error.}
  ## Exactly one scope releases an admitted invocation.

proc `=dup`*(source: ServiceExecutionLease): ServiceExecutionLease {.error.}
  ## A second handle must never bypass the pre-initialization exclusion.

proc `=wasMoved`*(lease: var ServiceExecutionLease) {.nodestroy, inline.} =
  ## A transferred lease leaves no release authority in its source.
  lease.owner = nil
  lease.index = 0

proc `=destroy`*(lease: ServiceExecutionLease) =
  ## Every success/refusal/return releases admission after invocation-local owners have retired.
  let owner = lease.owner
  if owner != nil:
    assert owner[].busy
    if not owner[].slots[lease.index].ready:
      # Adapter preflight can refuse before the initializer; an uninitialized miss leaves no entry.
      owner[].slots[lease.index] = default(ResidentSlot)
    owner[].busy = false

func initialized*(lease: ServiceExecutionLease): bool =
  ## A default result is a local busy refusal, never an executed guest or protocol outcome.
  lease.owner != nil

func residentServices*(context: ServiceExecutionContext): int {.requires: not context.busy.} =
  ## Idle-only bounded occupancy does not expose mutable worker aliases or promise RSS accounting.
  result = 0
  for slot in context.slots:
    if slot.ready:
      inc result

proc residentMemoryPayloadBytes*(context: ServiceExecutionContext): uint64 {.requires:
    not context.busy.} =
  ## Sum observed idle baseline and private payload across the bounded resident workers.
  result = 0
  for index in 0..<context.slots.len:
    if context.slots[index].ready:
      let info = workerInfo(context.slots[index].worker)
      if info.error == PreparationError.None:
        result += info.value.prepared.retainedMemoryPayloadBytes

proc residentServiceInfo*(context: ServiceExecutionContext, service: ServiceIndex,
    version: CodeHash, backend: PvmBackend): PreparationResult[PreparedCacheInfo]
    {.requires: not context.busy.} =
  ## Copy existing preparation/hit/occupancy facts; callers must also hold the enclosing job's idle gate.
  for index in 0..<context.slots.len:
    if context.slots[index].ready and uint32(context.slots[index].service) == uint32(service) and
        array[32, byte](context.slots[index].version) == array[32, byte](version) and
        context.slots[index].backend == backend:
      return workerInfo(context.slots[index].worker)
  workerInfo(default(ExecutionWorker)) # An absent/unprepared owner retains the existing typed refusal.

proc bindNativeRuntime*(context: var ServiceExecutionContext, runtime: NativeRuntime) {.requires:
    not context.busy.} =
  ## Bind only an empty idle context; every worker's prepared cache captures this exact runtime anchor.
  assert residentServices(context) == 0
  context.nativeRuntime = runtime

proc acquireServiceExecution*(context: var ServiceExecutionContext, service: ServiceIndex,
    version: CodeHash, backend: PvmBackend): ServiceExecutionLease =
  ## Caller has already rechecked account/preimage/envelope/size classification on this invocation.
  ## Nested calls refuse before touching initialization; invalid misses may evict valid idle code.
  if context.busy:
    return default(ServiceExecutionLease)
  context.busy = true
  var selected = -1
  for index in 0..<context.slots.len:
    if context.slots[index].ready and
        uint32(context.slots[index].service) == uint32(service) and
        array[32, byte](context.slots[index].version) == array[32, byte](version) and
        context.slots[index].backend == backend:
      selected = index
      break # Exact authenticated key only; the worker still validates parse and execution policies.
  if selected < 0:
    for index in 0..<context.slots.len:
      if not context.slots[index].ready:
        selected = index
        break # Prefer unused capacity before the fixed round-robin eviction position.
    if selected < 0:
      selected = context.next
    # Retire the old worker BEFORE allocating a miss; no temporary fifth worker is retained.
    context.slots[selected] = default(ResidentSlot)
    context.slots[selected] = ResidentSlot(service: service, version: version, backend: backend,
      worker: newExecutionWorker(context.nativeRuntime))
    context.next = if selected == context.slots.high: 0 else: selected + 1
  ServiceExecutionLease(owner: addr context, index: selected)

proc initializeMachine*(input, arguments: openArray[byte], entry: CodeAddress,
    gas: MachineGas, limits: InitializationLimits,
        lease: ServiceExecutionLease): InitializationResult
    {.requires: lease.owner != nil.} =
  ## Preserve all envelope/parse/entry/resource checks and build a fresh CPU/memory/argument owner.
  let owner = lease.owner
  assert owner != nil and owner[].busy
  result = initializeMachine(input, arguments, entry, gas, limits, owner[].slots[
      lease.index].worker)
  owner[].slots[lease.index].ready = result.error == InitializationError.None

proc initializeJamProgram*(input, arguments: openArray[byte], entry: CodeAddress,
    gas: MachineGas, limits: InitializationLimits,
        lease: ServiceExecutionLease): InitializationResult
    {.requires: lease.owner != nil.} =
  ## Preserve all envelope/parse/entry/resource checks and build a fresh CPU/memory/argument owner.
  let owner = lease.owner
  if owner == nil or not owner[].busy:
    return default(InitializationResult)
  result = initializeJamProgram(input, arguments, entry, gas, limits, owner[].slots[
      lease.index].worker)
  owner[].slots[lease.index].ready = result.error == InitializationError.None

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
        raises: [].},
    steps: ExecutionStepLimit, calls: HostCallLimit, cycles: GasCycleLimit,
    selected: PvmBackend, lease: ServiceExecutionLease): HostExecutionResult[Reason]
    {.requires: lease.owner != nil.} =
  ## Existing full prepared keys and invocation-local host/CPU/memory/publication behavior stay authoritative.
  let owner = lease.owner
  assert owner != nil and owner[].busy
  assert owner[].slots[lease.index].backend == selected
  executeWithHost(source, context, handler, steps, calls, cycles, selected,
    owner[].slots[lease.index].worker)

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason]
      {.nimcall, raises: [].},
    steps: ExecutionStepLimit, calls: HostCallLimit, cycles: GasCycleLimit,
    selected: PvmBackend, lease: ServiceExecutionLease, scalarCalls: ScalarHostSelector,
    scalarHandler: FallibleScalarHostCallback[Context, Reason],
    read32: HostRead32[Context, Reason] = default(HostRead32[Context,
        Reason])): HostExecutionResult[Reason]
    {.requires: lease.owner != nil.} =
  ## Keep the admitted service lease active through scalar and owned callbacks and final publication.
  let owner = lease.owner
  assert owner != nil and owner[].busy
  assert owner[].slots[lease.index].backend == selected
  executeWithHost(source, context, handler, steps, calls, cycles, selected,
    owner[].slots[lease.index].worker, scalarCalls, scalarHandler, read32)
