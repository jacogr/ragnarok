# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_heap_arc_release"}

## Actual heap calls preserve immutable CPUs and adopted gas/address rules under bounded allocation.

import std/[assertions, syncio]
import ../../../src/state/accumulation/[machine as accumulation_machine,
    dispatch as accumulation_dispatch, context as accumulation_context,
    effects as accumulation_effects, outcome as accumulation_outcome,
    invocation as accumulation_invocation, service as accumulation_service,
    inputs as accumulation_inputs, batch as accumulation_batch]
import ../../../src/state/store
import ../../../src/codec/[bounded, composite, header, c2_records]
import ../../../src/codec/state/[safrole as state_safrole, accounts as state_accounts,
    layout as state_layout, trie as state_trie]
import ../../../src/pvm/[initialize, machine, program, step]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/host/fetch as host_fetch
import ../../support/[pvm_accumulation_context, pvm_accumulation_program,
  accumulation_batch_context, accumulation_provision_integration, arc_evidence]

# Each independent authored full-width request tests validation before any narrowing or cost arithmetic.
proc instructions(request: uint64, repeat = false, panic = false): seq[seq[byte]] =
  result = @[]
  if panic:
    result.add(@[10'u8, 19]) # Retain account checkpoint before heap growth; terminal CPU memory must still include growth.
  result.add(registerImmediate(7, request))
  result.add(@[10'u8, 1])
  if repeat:
    result.add(@[10'u8, 1]) # Returned endpoint queries the newly grown region without paying growth twice.
  if panic:
    result.add(@[0'u8])
  else:
    result.add(@[50'u8, 0]) # Dynamic return halts without fabricating an engine outcome.

# Stack extent is encoded into the exact original envelope before service/bootstrap ownership is captured.
proc prepared(code: seq[seq[byte]], credit = 10000'u64, pages = 8'u32,
    stack = 1'u32): PreparedAccumulationMachine =
  assert stack < 0x1000000'u32
  var envelope = guestEnvelope(code)
  for index in 0..<3:
    envelope[8+index] = byte((stack shr (index*8)) and
        255) # E3 field and real initializer share the same captured code.
  initializeAccumulationMachine(pvmBootstrap(envelope, credit, includeContexts = true),
    InitializationLimits(envelope: InitializationByteLimit(512), program: ProgramByteLimit(256),
      jumps: JumpCountLimit(0), pages: PageLimit(pages))).value

# Parameter/input capture and CPU/host budgets are independent of memory allocation capacity.
proc run(source: PreparedAccumulationMachine, calls = 8'u64): AccumulationDispatchResult =
  executeAccumulationMachine(source, pvmParameters(),
    FetchAccumulationLimits(items: ElementLimit(2), bytes: ByteLimit(512),
      operand: OperandLimits(maxBytes: ByteLimit(512))), MemoryByteLimit(0),
    ExecutionStepLimit(32), HostCallLimit(calls), GasCycleLimit(1000), pvmContextConfig())

# Compute only instruction prepayment through the production gas analyzer; host prices remain authored literals.
proc price(source: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(source.accumulationMachine.value).value,
    CodeAddress(5), GasCycleLimit(1000)).value)

# Compare every new byte and each outside page against the retained original immutable CPU.
proc checkMemory(source: PreparedAccumulationMachine, outcome: AccumulationDispatchResult,
    past: uint32) =
  let original = memoryOf(source.accumulationMachine.value).value
  let current = memoryOf(outcome.value.machine).value
  for page in [16'u32, 48'u32, 49'u32, 0xfefdf'u32, 0xfeff0'u32]:
    let before = original.pageImage(PageIndex(page)).value
    let after = current.pageImage(PageIndex(page)).value
    assert before.access == after.access and before.bytes == after.bytes,
      "RO/RW/initial heap/stack/arguments retain exact access and bytes"
  for page in 50'u32..<past:
    let image = current.pageImage(PageIndex(page)).value
    assert image.access == PageAccess.ReadWrite and image.bytes == default(array[4096, byte]),
      "new pages are zero-filled and writable"
    assert original.pageImage(PageIndex(page)).value.access == PageAccess.Inaccessible,
      "completed growth never changes the original CPU memory owner"
  assert uint32(current.writablePageCount(PageIndex(48), PageIndex(0xfefc0)).value) == past-48,
    "heap count excludes writable stack pages and RO/input memory"

for request in [0'u64, 49, 50, 51, 52, high(uint64)]:
  let code = instructions(request)
  let instructionCost = price(prepared(code))
  let cost = if request == 51: 396'u64 elif request == 52: 517'u64 else: 275'u64
  for available in [0'u64, cost-1, cost, cost+1]:
    # Adopted affordability precedes register/memory mutations; exact and spare funding complete the row.
    let source = prepared(code, instructionCost+available)
    let done = run(source)
    if available < cost:
      assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.OutOfGas
      let cpu = machineInfo(done.value.machine).value
      assert uint64(cpu.gas) == 0 and uint64(cpu.gasDeficit) == 0 and
          uint64(cpu.registers[7]) == request and uint64(cpu.pc) == 15,
        "merged #533 drains credit without debt and preserves the causing host PC and original request"
      checkMemory(source, done, 50)
    else:
      assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt
      let cpu = machineInfo(done.value.machine).value
      let past = if request == 51 or request == 52: uint32(request) else: 50'u32
      assert uint64(cpu.registers[7]) == uint64(past) and uint64(cpu.gas) == available-cost,
        "literal host base/per-page charges and returned ordinal are exact"
      checkMemory(source, done, past)
    assert uint64(machineInfo(source.accumulationMachine.value).value.gas) ==
        instructionCost+available,
      "completed and refused calls retain the original CPU gas"

for stack in [0'u32, 1, 4096, 65535, 65536, 65537]:
  let source = prepared(instructions(0), pages = 32, stack = stack)
  let bounds = source.machineHeapBounds.value
  let expected = if stack == 0: 0xfefd0'u32 elif stack <= 65536: 0xfefc0'u32 else: 0xfefb0'u32
  assert uint32(bounds.first) == 48 and uint32(bounds.past) == expected,
    "owned geometry uses zone-rounded RO start and the adopted stack ceiling"
  assert run(source).error == AccumulationDispatchError.None,
    "affordable queries work for zero, page and zone-sized stack reservations"
  var copy = bounds
  copy.first = PageIndex(0)
  assert uint32(source.machineHeapBounds.value.first) == 48,
    "copied geometry cannot replace prepared-machine provenance"
assert default(PreparedAccumulationMachine).machineHeapBounds.error ==
    AccumulationMachineError.Uninitialized

for request in [0xfefc1'u64, 0xfefcf, 0x100000, high(uint64)]:
  # Out-of-range operands query the current endpoint at base cost, before any narrowing or multiplication.
  let source = prepared(instructions(request))
  let done = run(source)
  assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt
  let cpu = machineInfo(done.value.machine).value
  assert uint64(cpu.registers[7]) == 50 and uint64(cpu.gas) == 10000-price(source)-275
  checkMemory(source, done, 50)
block maximum_request:
  let code = instructions(0xfefc0)
  let source = prepared(code, price(prepared(code))+275+(0xfefc0'u64-50)*121)
  assert run(source).error == AccumulationDispatchError.LimitExceeded,
    "exact adopted ceiling is in scope but still cannot exceed local page allocation capacity"
for pages in [5'u32, 6, 7]:
  let source = prepared(instructions(52), pages = pages)
  let done = run(source)
  if pages < 7:
    assert done.error == AccumulationDispatchError.LimitExceeded,
      "all existing RO/RW/stack/input pages count toward the allocation ceiling"
  else:
    assert done.error == AccumulationDispatchError.None, "exact posterior allocation limit succeeds"
    checkMemory(source, done, 52)
block host_budget:
  let done = run(prepared(instructions(51)), calls = 0)
  assert done.error == AccumulationDispatchError.ExecutionFailure and
      done.executionError == StepError.HostCallLimitExceeded,
    "heap allocation never bypasses the engine's independent host-call budget"
block repeated_growth:
  let code = instructions(52, repeat = true)
  let done = run(prepared(code, price(prepared(code))+517+275))
  assert done.error == AccumulationDispatchError.None and uint64(machineInfo(
      done.value.machine).value.gas) == 0,
    "repeat request queries the grown endpoint at base cost only"
block grown_page_guest_access:
  let source = prepared(@[registerImmediate(7, 51), @[10'u8, 1], registerImmediate(8, 81),
    @[59'u8, 8, 0, 32, 3, 0], @[52'u8, 9, 0, 32, 3, 0], @[50'u8, 0]])
  let done = run(source)
  assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt
  assert uint64(machineInfo(done.value.machine).value.registers[9]) == 81,
    "real guest store/load instructions access the newly grown page"
  assert readBytes(memoryOf(done.value.machine).value, MemoryAddress(204800), MemoryLength(1),
    MemoryByteLimit(1)).value == @[81'u8]
  assert pageImage(memoryOf(source.accumulationMachine.value).value, PageIndex(50)).value.access ==
    PageAccess.Inaccessible, "guest writes after growth preserve the original CPU snapshot"
block checkpoint_panic:
  let source = prepared(instructions(51, panic = true))
  let done = run(source)
  assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Panic
  checkMemory(source, done, 51)
  let selected = normalizeAccumulationOutcome(done).value.outcomeContext.value
  let initial = source.machineBootstrap.value.bootstrapService.value.serviceState.value
  assert sameStateSnapshot(initial, selected.effectAccounts.value),
    "checkpoint account selection preserves original account ownership beside grown CPU memory"
block detached_owner:
  var retained = default(PreparedAccumulationMachine)
  block inputs:
    retained = prepared(instructions(51)) # All caller code/service/bootstrap owners leave scope.
  let done = run(retained)
  assert done.error == AccumulationDispatchError.None
  checkMemory(retained, done, 51)
block batch_publication:
  let fixture = batchFixture(firstEnvelope = guestEnvelope(instructions(51)),
    secondEnvelope = guestEnvelope([@[50'u8, 0]]))
  let service = prepareAccumulationService(fixture.inputs, InvocationServiceIndex(0),
    fixture.state.snapshot.value, HeaderSlot(128),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))).value
  let invoked = prepareAccumulationInvocation(service, default(StateEntropyWord), ServiceProbeLimit(1)).value
  let machine = initializeAccumulationMachine(invoked,
    InitializationLimits(envelope: InitializationByteLimit(512), program: ProgramByteLimit(256),
      jumps: JumpCountLimit(0), pages: PageLimit(8))).value
  let first = run(machine)
  assert first.error == AccumulationDispatchError.None and
    uint64(machineInfo(first.value.machine).value.registers[7]) == 51,
    "real growth completes with the exact common batch input/prior owners"
  let second = batchExecution(fixture, 1)
  let plan = prepareCompleteAccumulationBatch(fixture.inputs, fixture.state.snapshot.value,
    [first, second], [], HeaderSlot(128), batchPolicy()).value
  var state = fixture.state
  discard applyAccumulationBatch(state, plan).value
  var rows: seq[StateEntry] = @[]
  for entry in fixture.entries:
    var row = entry
    for ordinal, service in [42'u32, 99'u32]:
      # Author only literal incoming credits; heap queries have no persistent account writes.
      if array[31, byte](entry.key) == array[31, byte](chapterServiceKey(StateChapter(255),
          ServiceIndex(service))):
        var metadata = decodeServiceMetadata(entry.value, ByteLimit(
            ServiceMetadataBytes)).value.metadata
        metadata.balance = AccountBalance(if ordinal == 0: 17 else: 31)
        row = serviceMetadataEntry(ServiceIndex(service), metadata, ByteLimit(
            ServiceMetadataBytes)).value
    rows.add(row)
  let expected = newStateStore(rows, integrationStoreLimits()).value
  assert array[32, byte](state.snapshot.value.commitment.root) == array[32, byte](
      expected.snapshot.value.commitment.root),
    "actual heap growth composes with complete-map incoming-credit publication"

let source = prepared(instructions(52, repeat = true))
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Each fresh execution creates/reclaims its own grown snapshots and implication owners.
  let done = run(source)
  assert done.error == AccumulationDispatchError.None
  checkMemory(source, done, 52)
let after = getOccupiedMem()
assert before == after, "heap execution releases all temporary ARC owners"
recordArcRelease("pvm_accumulation_heap", 1000, before, after)
echo "PVM accumulation heap passed"
echo "ARC_RELEASE cycles=1000 unchanged"
