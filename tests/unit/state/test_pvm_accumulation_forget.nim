# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_forget_arc_release"}

## Authored forget programs project pinned empty deletion and verify every history transition, expiry and immutable checkpoint.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, state_layout, state_accounts, state_requests,
  state_service_values, state_outputs, state_trie, c2_records, header]
import ../../../src/state/[accumulation_dispatch, accumulation_effects, accumulation_context,
  accumulation_machine, accumulation_invocation, accumulation_outcome, store]
import ../../../src/pvm/[machine, program, step, gas, host_fetch]
import ../../../src/crypto/primitives
import ../../support/[pvm_accumulation_program, pvm_accumulation_context, arc_evidence]

# Inject primitive failure after genuine fixture preparation.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
# Observe exact failure positions and no namespace work on preflight refusals.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
# Fail after bounded successful namespace/trie hashes.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

let blob = @[5'u8, 7, 9]
let hash = ServicePreimageHash(array[32, byte](blake2b256(blob).value))
# Literal pinned accumulate/tiny/preimage_len_bound-3 request identity, not an independently chosen substitute.
let vectorHash = ServicePreimageHash([0x94'u8, 0x3e, 0x3d, 0x42, 0xcf, 0x24, 0x8c, 0x99, 0xfa, 0x63,
    0x46, 0xc2, 0x4b, 0x66, 0x74, 0x10, 0x90, 0xbd, 0x2c, 0x78, 0xf9, 0xff, 0x69, 0x1c, 0x5f, 0xd7,
    0xa8, 0x8e, 0xf5, 0x1d, 0x27, 0xe2])
let config = RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
    items: ElementLimit(3), maxBytes: ByteLimit(13)))

# Fixed E4 anchor offset makes the standard expunge period 19,200; deposits can be huge to prove no funding check.
proc parameters(anchor = 14400'u32, deposits = 0'u64): Parameters =
  var wire = encodeParameters(pvmParameters())
  for field in 0..<3:
    for i in 0..<8:
      wire[field*8+i] = byte((deposits shr (8*i)) and 255) # Exact E8 deposit tuple, independent from expiry.
  wire[24] = 2
  wire[25] = 0
  wire[82] = 80
  wire[83] = 0
  for i in 0..<4:
    wire[74+i] = byte((anchor shr (8*i)) and 255) # maxLookupAnchorAge has exact E4 domain.
    wire[110+i] = 0 # Transfer memo profile supports retained-transfer witnesses.
  wire[110] = 128
  result = decodeParameters(wire).value
  assert result.get(maxLookupAnchorAge) == uint64(anchor), "independent expunge parameter offset"

# Supply the fixed authored digest through a typed routine so default arguments do not depend on runtime-let inference.
proc authoredHash(): ServicePreimageHash = hash

# Independent fixed input capture supports the exact vector hash as well as authored interaction hashes.
proc payload(lookupHash = authoredHash()): seq[byte] =
  result = newSeq[byte](32)
  let bytes = array[32, byte](lookupHash)
  for i in 0..<32:
    result[i] = bytes[i] # No string framing or caller-backed view enters guest memory.

# Build genuine current-self requests, a coherent footprint, and independent other-account witnesses.
proc source(history = availableHistory(RequestSlot(4)), present = true, length = 3'u32,
    offered = 3'u64, lookupHash = authoredHash(), service = 42'u32, address = 196608'u64,
    credit = 100000'u64, slot = 20000'u32, writes = 3'u64,
    items = 2'u32, octets = 84'u64, preimage = true, malformed = false,
    wire: seq[byte] = @[], data: seq[byte] = @[], suffix: seq[seq[byte]] = @[@[50'u8, 0]],
    extra: seq[StateEntry] = @[]): PreparedAccumulationMachine =
  var entries = extra
  entries.add(serviceMetadataEntry(ServiceIndex(99), default(ServiceMetadata), ByteLimit(
      ServiceMetadataBytes)).value)
  entries.add(serviceRequestEntry(ServiceIndex(99), lookupHash, RequestLength(length),
      requestedHistory(), config).value)
  if present:
    var request = serviceRequestEntry(ServiceIndex(service), lookupHash, RequestLength(length),
        history, config).value
    if malformed:
      request.value = wire # Let the production decoder enforce exact canonical shape and consumption.
    entries.add(request)
  if preimage:
    entries.add(servicePreimageEntry(ServiceIndex(service), lookupHash, blob,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(
          3))).value) # Removed/unavailable histories retain old blobs until expunge.
  var input = data
  if input.len == 0:
    input = payload(lookupHash) # Vector identity and authored hashes use exactly the same capture path.
  var instructions = @[registerImmediate(7, address), registerImmediate(8, offered), @[10'u8, 26]]
  for instruction in suffix:
    instructions.add(instruction) # Later hosts observe this exact current implication version.
  guestProgram(instructions, credit, extra = entries, writable = input, writes = writes,
    account = ServiceMetadata(balance: AccountBalance(1000), storageItems: AccountStorageItems(
        items), storageBytes: AccountStorageBytes(octets)),
    slot = HeaderSlot(slot), spareEntries = 4, service = ServiceIndex(service))

# Explicit capture and execution capacities keep protocol HUH separate from local refusal.
proc run(prepared: PreparedAccumulationMachine, copy = 128'u64, params = parameters()): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, params,
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1), operand: OperandLimits(
        maxBytes: ByteLimit(132))),
    MemoryByteLimit(copy), ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000),
        pvmContextConfig(),
    provisionLimits = AccumulationProvisionLimits(items: ElementLimit(1), perBlob: ByteLimit(3),
        totalBlobBytes: ByteLimit(3)))

# Inspect basic-block instruction pricing independently of fixed forget gas.
proc price(prepared: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(prepared.accumulationMachine.value).value, CodeAddress(5),
      GasCycleLimit(1000)).value)

# Retain only a completed execution's exact current or exceptional owner.
proc context(done: AccumulationDispatchResult, dimension = AccumulationDimension.Regular): AccumulationEffectContext =
  assert done.error == AccumulationDispatchError.None, "completed execution grants matching effects"
  done.effects.effectContext(dimension).value

# Read complete canonical current caller metadata, including the vector service-zero identity.
proc metadata(owner: AccumulationEffectContext, service = 42'u32): ServiceMetadata =
  let found = owner.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      service))).value
  decodeServiceMetadata(found.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata

# Check both host output registers, including unchanged advertised length on every funded row result.
proc resultCode(done: AccumulationDispatchResult, code: uint64, second = 3'u64) =
  assert done.value.exit == StepExit.Halt, "funded row resumes guest"
  let cpu = machineInfo(done.value.machine).value
  assert uint64(cpu.registers[7]) == code and uint64(cpu.registers[8]) == second,
      "exact verdict/second: expected " & $code & "/" & $second & " got " & $uint64(cpu.registers[
      7]) & "/" & $uint64(cpu.registers[8])

# A removal makes both selected maps absent and subtracts only that request's footprint.
proc removed(owner: AccumulationEffectContext, lookupHash = authoredHash(), length = 3'u32,
    service = 42'u32) =
  assert owner.effectRequestHistory(lookupHash, RequestLength(length)).error ==
      AccumulationEffectError.NotRequested, "request is absent after removal"
  assert owner.effectAccounts.value.lookup(servicePreimageKey(ServiceIndex(service), lookupHash,
      ByteLimit(32)).value).error == StateStoreError.MissingKey,
    "retained preimage is absent after removal"

let valid = source()
let done = run(valid)
resultCode(done, 0)
let current = context(done)
let retired = current.effectRequestHistory(hash, RequestLength(3)).value
assert retired.state == RequestState.Unavailable and uint32(retired.availableFrom) == 4 and uint32(
    retired.unavailableFrom) == 20000,
  "available request appends actual invocation time"
assert uint32(metadata(current).storageItems) == 2 and uint64(metadata(current).storageBytes) ==
    84 and uint64(metadata(current).balance) == 1000,
  "replacement preserves footprint and balance"
assert current.effectAccounts.value.lookup(servicePreimageKey(ServiceIndex(42), hash, ByteLimit(
    32)).value).value.bytes == blob,
  "replacement retains preimage bytes"
assert uint64(machineInfo(done.value.machine).value.gas) == 100000-price(valid)-3250, "fixed forget fee"
assert context(done, AccumulationDimension.Exceptional).effectRequestHistory(hash, RequestLength(
    3)).value.state == RequestState.Available,
  "exceptional history remains independent"
for chapter in [2, 7, 12]:
  assert current.effectAccounts.value.lookup(chapterKey(StateChapter(chapter))).value.bytes ==
    context(done, AccumulationDimension.Exceptional).effectAccounts.value.lookup(chapterKey(
        StateChapter(chapter))).value.bytes, "unrelated chapters preserved"
assert readBytes(memoryOf(done.value.machine).value, MemoryAddress(196608), MemoryLength(32),
    MemoryByteLimit(32)).value == payload(),
  "forget never writes hash input memory"
# The historical max-E4 vector is outside the current domain; derive a legal edge with its public hash/slot.
assert serviceRequestKey(ServiceIndex(0), vectorHash, RequestLength(high(uint32)), ByteLimit(
    32)).error == RequestError.InvalidLength
let vector = run(source(history = requestedHistory(), length = high(uint32)-2, offered = (uint64(
    high(uint32))-2),
  lookupHash = vectorHash, service = 0, slot = 45, octets = 81'u64+(uint64(high(uint32))-2),
      preimage = false))
resultCode(vector, 0, (uint64(high(uint32))-2))
removed(context(vector), lookupHash = vectorHash, length = high(uint32)-2, service = 0)
assert uint32(metadata(context(vector), 0).storageItems) == 0 and uint64(metadata(context(vector),
    0).storageBytes) == 0,
  "pinned empty request drops before any possible expiry cutoff"
for slot in [0'u32, 128, high(uint32)]:
  let empty = run(source(history = requestedHistory(), slot = slot))
  resultCode(empty, 0)
  removed(context(empty)) # Immediate empty deletion has no invented timestamp or age condition.
  let available = run(source(history = availableHistory(RequestSlot(high(uint32))), slot = slot, writes = 1))
  let history = context(available).effectRequestHistory(hash, RequestLength(3)).value
  assert uint32(history.availableFrom) == high(uint32) and uint32(history.unavailableFrom) == slot,
    "one-slot transition preserves high bits and does not impose chronology or expiry"
for removal in [799'u32, 800, 801, high(uint32)]:
  for restored in [false, true]:
    let history = (if restored: reavailableHistory(RequestSlot(1), RequestSlot(removal),
        RequestSlot(high(uint32)))
      else: unavailableHistory(RequestSlot(4), RequestSlot(removal)))
    let completed = run(source(history = history))
    resultCode(completed, (if removal < 800: 0'u64 else: high(uint64)-8))
    if removal < 800:
      if restored:
        let changed = context(completed).effectRequestHistory(hash, RequestLength(3)).value
        assert changed.state == RequestState.Unavailable and uint32(changed.availableFrom) == high(
            uint32) and uint32(changed.unavailableFrom) == 20000,
          "three-slot expiry uses second slot and retains the third as latest availability"
      else:
        removed(context(completed)) # Exactly aged two-slot requests remove both maps.
        assert uint32(metadata(context(completed)).storageItems) == 0 and uint64(metadata(context(
            completed)).storageBytes) == 0, "exact removal footprint"
for slot in [0'u32, 128, 19199, 19200, 19201]:
  let completed = run(source(history = unavailableHistory(RequestSlot(0), RequestSlot(0)), slot = slot))
  resultCode(completed, (if slot > 19200: 0'u64 else: high(
      uint64)-8)) # Widened strict comparison cannot wrap a nonpositive mathematical cutoff.
resultCode(run(source(history = unavailableHistory(RequestSlot(0), RequestSlot(0)), slot = high(uint32)),
  params = parameters(high(uint32))), high(uint64)-8) # Full E4 anchor plus safety margin remains widened.
resultCode(run(source(present = false)), high(uint64)-8) # Other-service history and orphan self preimage cannot create membership.
resultCode(run(source(offered = 4)), high(uint64)-8, 4) # Advertised length is part of exact request identity.
for length in [0'u32, high(uint32)-2]:
  let completed = run(source(history = requestedHistory(), length = length, offered = uint64(length),
    octets = 81'u64+uint64(length), preimage = false, writes = 3))
  resultCode(completed, 0, uint64(length))
  removed(context(completed), length = length) # Current request/preimage keys remain distinct and are removed atomically.
for items in [0'u32, 1]:
  assert run(source(history = requestedHistory(), items = items)).error ==
      AccumulationDispatchError.MalformedState,
    "removal refuses inconsistent item counters without underflow"
for octets in [0'u64, 83]:
  assert run(source(history = requestedHistory(), octets = octets)).error ==
      AccumulationDispatchError.MalformedState,
    "removal refuses inconsistent octet counters without underflow"
let maximal = run(source(history = requestedHistory(), items = high(uint32), octets = high(uint64)))
assert uint32(metadata(context(maximal)).storageItems) == high(uint32)-2 and uint64(metadata(
    context(maximal)).storageBytes) == high(uint64)-84,
  "full-width footprint subtraction remains exact"
resultCode(run(valid, params = parameters(deposits = high(uint64))),
    0) # No funding check applies to history replacement.
resultCode(run(source(history = requestedHistory()), params = parameters(deposits = high(uint64))),
    0) # Nor to removal.
for offered in [uint64(high(uint32))-1, uint64(high(uint32)), 0x100000003'u64, high(uint64)]:
  let prepared = source(offered = offered, address = high(uint64), malformed = true)
  failHash(1)
  let completed = run(prepared, copy = 0)
  assert hashCalls() == 0, "invalid length HUH precedes capture policy and namespace hashing"
  failHash(0)
  resultCode(completed, high(uint64)-8, offered)
for address in [0'u64, 65536'u64+4096-16, 196608'u64+8192-16, 0x100000000'u64, high(uint64)]:
  let completed = run(source(address = address))
  let cpu = machineInfo(completed.value.machine).value
  assert completed.value.exit == StepExit.Panic and uint64(cpu.registers[7]) == address and uint64(
      cpu.registers[8]) == 3,
    "memory failure precedes history checks with original inputs"
  assert uint64(cpu.gas) == 100000-price(valid)-3250, "memory panic pays fixed fee"
resultCode(run(source(address = 65536)), high(uint64)-8) # Readable RO hash is absent rather than inaccessible.
resultCode(run(source(address = 196608'u64+4096-16)), high(
    uint64)-8) # Complete cross-page capture remains readable.
assert run(valid, copy = 31).error == AccumulationDispatchError.LimitExceeded, "exact fixed input copy bound"
for wire in [newSeq[byte](0), @[4'u8], @[128'u8, 0], @[1'u8], @[2'u8, 0], @[0'u8, 0], newSeq[byte](14)]:
  assert run(source(malformed = true, wire = wire)).error ==
      AccumulationDispatchError.MalformedState,
    "malformed/noncanonical/truncated/trailing histories remain local failures"
for available in [0'u64, 3249, 3250, 3251]:
  let completed = run(source(credit = price(valid)+available))
  let cpu = machineInfo(completed.value.machine).value
  if available < 3250:
    assert completed.value.exit == StepExit.OutOfGas and uint64(cpu.gasDeficit) == 0 and
      uint64(cpu.registers[7]) == 196608 and uint64(cpu.registers[8]) == 3, "exact fee deficit preserves inputs"
  else:
    resultCode(completed, 0)
    assert uint64(cpu.gas) == available-3250, "funded fixed fee edge"
let underfunded = source(credit = price(valid)+3249, offered = high(uint64), address = high(uint64), writes = 0)
failHash(1)
assert run(underfunded, copy = 0).value.exit == StepExit.OutOfGas and hashCalls() == 0, "OOG precedes length/memory/namespace work"
failHash(0)
let fullCredit = run(source(credit = high(uint64)))
assert uint64(machineInfo(fullCredit.value.machine).value.gas) == high(uint64)-price(valid)-3250, "full-width gas credit"
let repeated = run(source(history = requestedHistory(), suffix = @[registerImmediate(7, 196608), @[
    10'u8, 26], @[50'u8, 0]]))
resultCode(repeated, high(uint64)-8)
assert uint32(metadata(context(repeated)).storageItems) == 0, "repeat removal cannot decrement footprint twice"
let queried = run(source(history = requestedHistory(), suffix = @[registerImmediate(7, 196608), @[
    10'u8, 24], @[50'u8, 0]]))
resultCode(queried, high(uint64), 0) # Current query sees removal rather than initial history.
let restored = run(source(suffix = @[registerImmediate(7, 196608), @[10'u8, 25], @[50'u8, 0]]))
resultCode(restored, 0)
assert context(restored).effectRequestHistory(hash, RequestLength(3)).value.state ==
    RequestState.Reavailable,
  "solicit sees newly unavailable current history and restores it"
var provideInput = payload()
for octet in blob:
  provideInput.add(octet) # Explicit byte append uses the pinned runtime's supported sequence operations.
let resupplied = run(source(history = requestedHistory(), suffix = @[registerImmediate(7, 196608),
    @[10'u8, 25],
  registerImmediate(7, 42), registerImmediate(8, 196640), registerImmediate(9, 3), @[10'u8, 28], @[
      50'u8, 0]], data = provideInput))
assert context(resupplied).effectInfo.value.provisions == 1 and context(
    resupplied).effectProvisionAt(AccumulationProvisionIndex(0)).value.copyProvisionBytes.value == blob,
  "forget, fresh solicit and provide share the same current request state"
let prepared = prepareAccumulationEffects(done.effects.effectsSource.value).value
assert recordAccumulationForget(default(AccumulationEffects), hash, RequestLength(3), parameters(
  )).error == AccumulationEffectError.Uninitialized,
  "default pairs cannot forget"
assert recordAccumulationForget(prepared, hash, RequestLength(3), default(Parameters)).error ==
    AccumulationEffectError.InvalidParameters,
  "default parameters cannot authorize expiry"
let removalSource = run(source(history = requestedHistory()))
let removalPair = prepareAccumulationEffects(removalSource.effects.effectsSource.value).value
for successful in [0, 1, 2, 4]:
  failAfter(cint(successful))
  let failed = recordAccumulationForget(removalPair, hash, RequestLength(3), parameters())
  assert failed.error == AccumulationEffectError.BackendFailure and hashCalls() == cint(
      successful+1), "atomic early/late namespace and trie failure"
  failHash(0)
  let owner = removalPair.effectContext(AccumulationDimension.Regular).value
  assert owner.effectRequestHistory(hash, RequestLength(3)).value.state ==
      RequestState.Requested and uint32(metadata(owner).storageItems) == 2,
    "failed removal retains history and footprint"
for writes in [0'u64, 1, 2]:
  assert run(source(history = requestedHistory(), writes = writes)).error ==
      AccumulationDispatchError.LimitExceeded,
    "distinct-key removal requires atomic three-write policy"
assert run(source(writes = 0)).error == AccumulationDispatchError.LimitExceeded, "history replacement needs one write"
resultCode(run(source(writes = 1)), 0)
# Pending transfer/provision/yield owners survive deletion even when their source request is forgotten later.
let initiallyRequested = run(source(history = requestedHistory()))
let owners = prepareAccumulationEffects(initiallyRequested.effects.effectsSource.value).value
let provided = recordAccumulationProvision(owners, ServiceIndex(42), blob,
  AccumulationProvisionLimits(items: ElementLimit(1), perBlob: ByteLimit(3),
      totalBlobBytes: ByteLimit(3))).value
let yielded = recordAccumulationYield(provided, default(OutputCommitment)).value
let plan = prepareAccumulationTransfer(yielded, AccumulationTransferDestination(99),
    TransferBalance(5), Gas(0), default(TransferMemo), parameters()).value
let sent = commitAccumulationTransfer(plan, ElementLimit(1)).value
let checkpointed = checkpointAccumulationEffects(sent).value
let changed = recordAccumulationForget(checkpointed, hash, RequestLength(3), parameters()).value
let retained = changed.effectContext(AccumulationDimension.Regular).value
removed(retained)
assert retained.effectInfo.value.transfers == 1 and retained.effectInfo.value.provisions == 1 and
    retained.effectInfo.value.hasYield,
  "forget preserves all nonempty implication owners"
assert uint64(retained.effectTransferAt(AccumulationTransferIndex(0)).value.amount) == 5 and
  retained.effectProvisionAt(AccumulationProvisionIndex(0)).value.copyProvisionBytes.value == blob and
  array[32, byte](retained.effectYield.value) == default(array[32, byte]), "retained effect payloads remain exact"
assert changed.effectContext(AccumulationDimension.Exceptional).value.effectRequestHistory(hash,
    RequestLength(3)).value.state == RequestState.Requested,
  "checkpoint retains original request independently"
for checkpoint in [false, true]:
  let failed = run(source(history = requestedHistory(), suffix = (if checkpoint: @[@[10'u8, 19], @[
      0'u8]] else: @[@[0'u8]])))
  let selected = normalizeAccumulationOutcome(failed).value.outcomeContext.value
  assert selected.effectRequestHistory(hash, RequestLength(3)).error ==
    (if checkpoint: AccumulationEffectError.NotRequested else: AccumulationEffectError.None), "panic chooses matching request deletion checkpoint"
  let exhausted = run(source(history = requestedHistory(), credit = price(valid)+3500, suffix = (if checkpoint:
    @[@[10'u8, 19], registerImmediate(7, 196608), @[10'u8, 26], @[50'u8, 0]] else:
    @[registerImmediate(7, 196608), @[10'u8, 26], @[50'u8, 0]])))
  assert exhausted.value.exit == StepExit.OutOfGas, "second fixed fee is unaffordable"
  let selectedOog = normalizeAccumulationOutcome(exhausted).value.outcomeContext.value
  assert selectedOog.effectRequestHistory(hash, RequestLength(3)).error ==
    (if checkpoint: AccumulationEffectError.NotRequested else: AccumulationEffectError.None), "OOG chooses matching deletion checkpoint"
let before = getOccupiedMem()
for iteration in 0..<1000:
  let completed = run(valid)
  resultCode(completed, 0) # Release every history/CPU/map candidate while retaining only immutable original fixtures.
let after = getOccupiedMem()
assert before == after, "forget releases all ARC-owned versions"
recordArcRelease("pvm_accumulation_forget", 1000, before, after)
echo "PVM accumulation forget passed"
echo "ARC_RELEASE cycles=1000 unchanged"
