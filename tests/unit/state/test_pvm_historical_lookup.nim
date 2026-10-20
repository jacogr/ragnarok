# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_historical_lookup_arc_release"}

## Literal historical intervals, full-width gas/memory and genuine host execution verify read-only refinement lookup.

import std/[assertions, syncio]
import ../../../src/state/[refinement_lookup, store]
import ../../../src/codec/[bounded, state_accounts, state_layout, state_service_values,
  state_requests, state_trie, work_report]
import ../../../src/pvm/[machine, program, step, gas]
import ../../support/arc_evidence

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

proc identity(): ServicePreimageHash =
  ## Opaque dictionary identities are supplied bytes, independently of content integrity validation.
  var bytes = default(array[32, byte])
  bytes[0] = 73
  ServicePreimageHash(bytes)
proc payload(length = 40): seq[byte] =
  ## Freeze an independently patterned value, including a present empty blob.
  result = newSeq[byte](length)
  for index in 0..<length: result[index] = byte(index+1)
proc fixture(history: seq[byte], anchor = 20'u32, damage = 0,
    length = 40): HistoricalLookupContext =
  ## Construct an owned serialized map; damage selectors retain deliberately malformed or absent data.
  var entries: seq[StateEntry] = @[]
  for service in [42'u32, 99, 0, high(uint32), 77]:
    if service != 77 and not (service == 42 and damage == 6):
      var account = serviceMetadataEntry(ServiceIndex(service), ServiceMetadata(), ByteLimit(89)).value
      if service == 42 and damage == 3: account.value = @[0'u8] # Malformed selected metadata is a local error.
      entries.add(account)
    if not (service == 42 and damage == 1):
      entries.add(servicePreimageEntry(ServiceIndex(service), identity(), payload(length),
        ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(uint64(length)))).value)
    if not (service == 42 and damage == 2):
      let size = if damage == 5: length+1 else: length
      let key = serviceRequestKey(ServiceIndex(service), identity(), RequestLength(uint32(size)),
          ByteLimit(32)).value
      entries.add(StateEntry(key: key, value: history)) # History octets are literal and never produced by the decoder under test.
  let limits = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(32),
    perValue: ByteLimit(20000), totalValueBytes: ByteLimit(100000), nodes: TrieNodeLimit(10000)),
    writes: ElementLimit(32), writeValueBytes: ByteLimit(100000))
  let state = newStateStore(entries, limits).value
  captureHistoricalLookup(state.snapshot.value, ServiceIndex(42), LookupSlot(anchor)).value
proc memory(): Memory =
  ## A fixed readable hash and one writable output page expose missing-page atomicity at its end.
  var hash = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly,
    bytes: default(array[4096, byte]))
  hash.bytes[0] = 73
  var output = PageImage(index: PageIndex(48), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))
  for index in 0..<4096: output.bytes[index] = 204 # Distinct untouched bytes surround each clipped write.
  captureMemory([hash, output], PageLimit(2)).value
proc registers(): RegisterFile =
  ## Every unaffected register has a nonzero sentinel; r7's all-ones service chooses self.
  result = default(RegisterFile)
  for index in 0..<13: result[index] = RegisterValue(uint64(index+100))
  result[7] = RegisterValue(high(uint64))
  result[8] = RegisterValue(65536)
  result[9] = RegisterValue(196608)
  result[10] = RegisterValue(0)
  result[11] = RegisterValue(12)
proc run(context: HistoricalLookupContext, regs: RegisterFile, mem: Memory,
    credit = 100000'u64, limit = 64'u64): HistoricalLookupResult[HostResponse] =
  ## The wrapper changes no input and leaves host selection to the eventual refine dispatcher.
  historicalLookupResponse(context, MachineGas(credit), regs, mem, MemoryByteLimit(limit))
proc checkRegisters(response: HostResponse, before: RegisterFile) =
  ## Only the documented return register may differ after a funded successful lookup.
  for index in 0..<13:
    if index != 7: assert uint64(response.registers[index]) == uint64(before[index])
proc respond(context: var HistoricalLookupContext, stopped: StepOutcome): HostResult[
    HistoricalLookupError] {.raises: [].} =
  ## A real fallible host callback delegates only host 7 and propagates local refusals.
  assert stopped.exit == StepExit.Host and uint64(stopped.hostCall) == 7
  let cpu = stopped.machine.machineInfo.value
  let response = historicalLookupResponse(context, cpu.gas, cpu.registers,
    stopped.machine.memoryOf.value, MemoryByteLimit(64))
  if response.error != HistoricalLookupError.None: return hostFailure(response.error)
  hostSuccess[HistoricalLookupError](response.value)

let input = registers()
let mem = memory()
let supplied = @[1'u8, 10, 0, 0, 0]
let context = fixture(supplied)
# Every endpoint comes from the pinned half-open interval equation, including deliberately unordered histories.
for history in [@[0'u8], supplied, @[2'u8, 10, 0, 0, 0, 20, 0, 0, 0],
    @[3'u8, 10, 0, 0, 0, 20, 0, 0, 0, 30, 0, 0, 0]]:
  for time in [0'u32, 9, 10, 19, 20, 29, 30, high(uint32)]:
    let available = if history.len == 1: false
      elif history.len == 5: time >= 10
      elif history.len == 9: time >= 10 and time < 20
      else: (time >= 10 and time < 20) or time >= 30
    let owner = fixture(history, time)
    let response = run(owner, input, mem).value
    assert response.action == HostAction.Continue
    assert uint64(response.gas) == 98871 # Literal 1125+ceil(264*12/1024)=1129.
    assert uint64(response.registers[7]) == (if available: 40'u64 else: high(uint64))
    let actual = readBytes(response.memory, MemoryAddress(196608), MemoryLength(12),
        MemoryByteLimit(12)).value
    if available:
      assert actual == payload(12) # Every copied byte follows the independently authored payload.
    else:
      for octet in actual: assert octet == 204 # Unavailable values leave the entire output untouched.
    checkRegisters(response, input)
# No extra chronology rules: restoration alone can establish availability under the literal disjunction.
let unusual = fixture(@[3'u8, 30, 0, 0, 0, 20, 0, 0, 0, 10, 0, 0, 0], 10)
assert uint64(run(unusual, input, mem).value.registers[7]) == 40
# Explicit self/other/zero/max IDs, missing accounts, orphan values and high-bit non-aliasing.
for target in [42'u64, 99, 0, uint64(high(uint32)), high(uint64), 77, 78, 0x10000002a'u64]:
  var regs = input
  regs[7] = RegisterValue(target)
  let response = run(context, regs, mem).value
  let exists = target in [42'u64, 99, 0, uint64(high(uint32)), high(uint64)]
  assert uint64(response.registers[7]) == (if exists: 40'u64 else: high(uint64))
# Missing preimages/accounts return NONE; inconsistent present preimages violate the account invariant.
for damage in [1, 6]:
  let owner = fixture(supplied, damage = damage)
  assert uint64(run(owner, input, mem).value.registers[7]) == high(uint64)
for damage in [2, 5]:
  assert run(fixture(supplied, damage = damage), input, mem).error ==
      HistoricalLookupError.MalformedState
# A complete request value is required; counts, truncation and trailing bytes are local malformed-state errors.
for history in [newSeq[byte](), @[4'u8], @[1'u8, 10], @[1'u8, 10, 0, 0, 0, 0]]:
  let owner = fixture(history)
  assert run(owner, input, mem).error == HistoricalLookupError.MalformedState
assert run(fixture(supplied, damage = 3), input, mem).error == HistoricalLookupError.MalformedState
# Zero-cardinality absence and present-empty both ignore impossible output pointers, but return different values.
for empty in [true, false]:
  let owner = fixture(if empty: supplied else: @[0'u8], length = 0)
  var regs = input
  regs[9] = RegisterValue(high(uint64))
  let response = run(owner, regs, mem, limit = 0).value
  assert response.action == HostAction.Continue
  assert uint64(response.registers[7]) == (if empty: 0'u64 else: high(uint64))
# Full-width offsets clip before narrowing; exact/short output budgets apply to the clipped slice only.
for offset in [0'u64, 37, 40, high(uint64)]:
  var regs = input
  regs[10] = RegisterValue(offset)
  let response = run(context, regs, mem).value
  let count = if offset == 0: 12 elif offset == 37: 3 else: 0
  assert uint64(response.registers[7]) == 40
  let expected = if count == 0: newSeq[byte]() elif offset == 0: payload(12) else: @[38'u8, 39, 40]
  assert readBytes(response.memory, MemoryAddress(196608), MemoryLength(uint64(count)),
      MemoryByteLimit(12)).value == expected
assert run(context, input, mem, limit = 12).error == HistoricalLookupError.None
assert run(context, input, mem, limit = 11).error == HistoricalLookupError.LimitExceeded
# Hash-read panic precedes account absence; affordability precedes both hash memory and namespace work.
var bad = input
bad[7] = RegisterValue(78)
bad[8] = RegisterValue(high(uint64))
failHash(3)
let panic = run(context, bad, mem).value
assert panic.action == HostAction.Panic and uint64(panic.registers[7]) == 78
assert hashCalls() == 0
let starved = run(context, bad, mem, credit = 1128).value
assert starved.action == HostAction.OutOfGas and uint64(starved.gasDeficit) == 1
for index in 0..<13: assert uint64(starved.registers[index]) == uint64(bad[index])
assert hashCalls() == 0
failHash(0)
# Destination failures preserve both the old output page and r7, including a write spanning a missing second page.
for address in [65536'u64, 200698, high(uint64)]:
  var regs = input
  regs[9] = RegisterValue(address)
  let response = run(context, regs, mem).value
  assert response.action == HostAction.Panic
  assert uint64(response.registers[7]) == high(uint64)
  assert response.memory.pageImage(PageIndex(48)).value.bytes == mem.pageImage(PageIndex(
      48)).value.bytes
# Maximal requested length has a frozen independently calculated price, with exact debt and no overflow.
var huge = input
huge[11] = RegisterValue(high(uint64))
let hugeResponse = run(context, huge, mem, credit = 0).value
assert hugeResponse.action == HostAction.OutOfGas
assert uint64(hugeResponse.gasDeficit) == 4755801206503244901'u64
# Independently frozen prices cover ceiling boundaries and fully funded maximal requests.
for pair in [(0'u64, 1125'u64), (1'u64, 1126'u64), (1024'u64, 1389'u64),
    (1025'u64, 1390'u64), (high(uint64), 4755801206503244901'u64)]:
  var regs = input
  regs[11] = RegisterValue(pair[0])
  let funded = run(context, regs, mem, credit = pair[1], limit = 40).value
  assert funded.action == HostAction.Continue and uint64(funded.gas) == 0
  assert uint64(funded.registers[7]) == 40
  let short = run(context, regs, mem, credit = pair[1]-1).value
  assert short.action == HostAction.OutOfGas and uint64(short.gasDeficit) == 1
  for index in 0..<13: assert uint64(short.registers[index]) == uint64(regs[index])
  assert short.memory.pageImage(PageIndex(48)).value.bytes == mem.pageImage(PageIndex(
      48)).value.bytes
for octet in mem.pageImage(PageIndex(48)).value.bytes:
  assert octet == 204 # Successful successors never mutate the caller's retained memory owner.
# Namespace hash failures are local and never mutate guest memory or the captured full map.
for successful in [0, 1]:
  failAfter(cint(successful))
  assert run(context, input, mem).error == HistoricalLookupError.BackendFailure
  failHash(0)
assert captureHistoricalLookup(default(StateStoreSnapshot), ServiceIndex(42), LookupSlot(
    0)).error == HistoricalLookupError.InvalidContext
assert run(default(HistoricalLookupContext), input, mem).error ==
    HistoricalLookupError.InvalidContext
assert run(context, input, default(Memory)).error == HistoricalLookupError.InvalidMemory
# A context survives all original store handles; replacing caller memory/registers cannot change retained inputs.
var detached = default(HistoricalLookupContext)
block:
  detached = fixture(supplied)
assert uint64(run(detached, input, mem).value.registers[7]) == 40
# Run an actual ecalli-7/halt through the generic host loop, preserving ordinary instruction charging.
let code = decodeProgram([0'u8, 0, 4, 10, 7, 50, 0, 5], CodeAddress(0), ProgramByteLimit(32),
    JumpCountLimit(0)).value
var cpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(100000), blockCharged: true,
    registers: input)
cpu.registers[0] = RegisterValue(0xffff0000'u64)
let captured = captureMachine(code, mem, cpu).value
var hostedContext = context
let hosted = executeWithHost(captured, hostedContext, respond, ExecutionStepLimit(2), HostCallLimit(
    1), GasCycleLimit(1000))
assert hosted.error == HostExecutionError.None and hosted.value.exit == StepExit.Halt
assert uint64(hosted.value.machine.machineInfo.value.registers[7]) == 40
# Fresh contexts, successful private memory successors and refused scratch must all retire each cycle.
let before = getOccupiedMem()
for iteration in 0..<1000:
  let owner = fixture(supplied)
  assert uint64(run(owner, input, mem).value.registers[7]) == 40
  assert run(owner, input, mem, limit = 11).error == HistoricalLookupError.LimitExceeded
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_historical_lookup", 1000, before, after)
echo "PVM historical lookup passed"
echo "ARC_RELEASE cycles=1000 unchanged"
