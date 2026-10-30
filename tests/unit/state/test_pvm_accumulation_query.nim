# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_query_arc_release"}

## Authored query programs verify exact packed history words, row ordering and immutable current-state reads.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite]
import ../../../src/codec/state/[layout as state_layout, accounts as state_accounts,
    requests as state_requests, service_values as state_service_values, outputs as state_outputs,
    trie as state_trie]
import ../../../src/codec/c2_records
import ../../../src/state/accumulation/[dispatch as accumulation_dispatch,
    effects as accumulation_effects, context as accumulation_context,
    machine as accumulation_machine, invocation as accumulation_invocation,
    outcome as accumulation_outcome]
import ../../../src/state/store
import ../../../src/pvm/[machine, program, step]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/host/fetch as host_fetch
import ../../support/[pvm_accumulation_program, pvm_accumulation_context, arc_evidence]

# Inject primitive failure only after constructing genuine complete-map and CPU fixtures.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
# Observe absence of namespace/state hashes on OOG or invalid-length paths.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Independent fixed opaque hash pattern is neither a string nor recomputed from captured bytes.
proc payload(): seq[byte] =
  result = newSeq[byte](32)
  for i in 0..<32:
    result[i] = byte(i*7+3) # Every index fits one byte and distinguishes exact lookup identity.

var hashBytes = default(array[32, byte])
for i, octet in payload():
  hashBytes[i] = octet # Fixed value copies cannot retain caller backing storage.
let hash = ServicePreimageHash(hashBytes)
let config = RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
    items: ElementLimit(3), maxBytes: ByteLimit(13)))

# Zero deposits keep unrelated storage/yield interaction witnesses independent of funding policy.
proc parameters(): Parameters =
  var wire = encodeParameters(pvmParameters())
  for i in 0..<24:
    wire[i] = 0 # Preserve all other validated clock/population settings.
  decodeParameters(wire).value

# Build a current self request alongside an independently different other-service history.
proc source(history = requestedHistory(), present = true, length = 3'u32,
    offered = 3'u64, address = 196608'u64, credit = 100000'u64,
    malformed = false, wire: seq[byte] = @[], writes = 0'u64,
    account = ServiceMetadata(balance: AccountBalance(100)),
    selector = high(uint64), suffix: seq[seq[byte]] = @[@[50'u8, 0]]): PreparedAccumulationMachine =
  var entries = @[serviceMetadataEntry(ServiceIndex(99), default(ServiceMetadata), ByteLimit(
      ServiceMetadataBytes)).value,
    serviceRequestEntry(ServiceIndex(99), hash, RequestLength(length), availableHistory(RequestSlot(
        73)), config).value]
  if present:
    var entry = serviceRequestEntry(ServiceIndex(42), hash, RequestLength(length), history, config).value
    if malformed:
      entry.value = wire # Genuine malformed record reaches only the production canonical decoder.
    entries.add(entry)
  var instructions = @[registerImmediate(7, selector), registerImmediate(8, address),
    registerImmediate(9, offered), @[10'u8, 24]]
  for instruction in suffix:
    instructions.add(instruction) # Continue in the same immutable CPU/effect execution stream.
  guestProgram(instructions, credit, extra = entries, writable = payload(), writes = writes,
      account = account, spareEntries = 4)

# Explicit local copy and execution policies never supply replacement history or effects.
proc run(prepared: PreparedAccumulationMachine, copy = 32'u64): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, parameters(),
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1), operand: OperandLimits(
        maxBytes: ByteLimit(132))),
    MemoryByteLimit(copy), ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000),
        pvmContextConfig())

# Basic-block instruction charging is independent of the fixed 643 host fee.
proc price(prepared: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(prepared.accumulationMachine.value).value, CodeAddress(5),
      GasCycleLimit(1000)).value)

# Completed effect extraction binds every observer to this execution's own current owner.
proc context(done: AccumulationDispatchResult, dimension = AccumulationDimension.Regular): AccumulationEffectContext =
  assert done.error == AccumulationDispatchError.None, "completed execution exposes matching effects"
  done.effects.effectContext(dimension).value

# Verify exact words without deriving expected values through the production packing implementation.
proc words(done: AccumulationDispatchResult, first, second: uint64) =
  assert done.value.exit == StepExit.Halt, "funded query returns to guest"
  let cpu = machineInfo(done.value.machine).value
  assert uint64(cpu.registers[7]) == first and uint64(cpu.registers[8]) == second, "two exact unsigned packed query words"

let valid = source()
let done = run(valid)
words(done, 0, 0)
assert uint64(machineInfo(done.value.machine).value.gas) == 100000-price(valid)-643, "fixed query fee"
let regularCommitment = context(done).effectAccounts.value.commitment
let exceptionalCommitment = context(done, AccumulationDimension.Exceptional).effectAccounts.value.commitment
assert array[32, byte](regularCommitment.root) == array[32, byte](exceptionalCommitment.root) and
  regularCommitment.entries == exceptionalCommitment.entries and regularCommitment.nodes ==
      exceptionalCommitment.nodes,
  "query leaves the complete-map commitment unchanged"
assert context(done).effectInfo.value.transfers == 0 and context(
    done).effectInfo.value.provisions == 0 and
  not context(done).effectInfo.value.hasYield, "query introduces no implications"
assert readBytes(memoryOf(done.value.machine).value, MemoryAddress(196608), MemoryLength(32),
    MemoryByteLimit(32)).value == payload(),
  "query never writes input memory"
words(run(source(present = false)), high(uint64), 0) # Other service's same pair cannot substitute for self membership.
words(run(source(history = availableHistory(RequestSlot(0)))), 1, 0)
words(run(source(history = availableHistory(RequestSlot(high(uint32))))), 0xffffffff00000001'u64, 0)
words(run(source(history = unavailableHistory(RequestSlot(0), RequestSlot(0)))), 2, 0)
words(run(source(history = unavailableHistory(RequestSlot(0x80000000'u32), RequestSlot(high(
    uint32))))),
  0x8000000000000002'u64, 0xffffffff'u64)
words(run(source(history = reavailableHistory(RequestSlot(0), RequestSlot(0), RequestSlot(0)))), 3, 0)
words(run(source(history = reavailableHistory(RequestSlot(high(uint32)), RequestSlot(
    0x80000000'u32), RequestSlot(high(uint32))))),
  0xffffffff00000003'u64, 0xffffffff80000000'u64)
words(run(source(history = reavailableHistory(RequestSlot(9), RequestSlot(3), RequestSlot(1)))),
  0x0000000900000003'u64, 0x0000000100000003'u64) # Query preserves positional shape without sorting or chronology validation.
for length in [0'u32, high(uint32)-2]:
  words(run(source(length = length, offered = uint64(length))), 0,
      0) # Current legal boundary excludes the two reserved namespace prefixes.
words(run(source(offered = 4)), high(uint64), 0) # Exact length is part of membership.
for offered in [uint64(high(uint32))-1, uint64(high(uint32)), 0x100000003'u64, high(uint64)]:
  let prepared = source(offered = offered, address = high(uint64), malformed = true)
  failHash(1)
  let completed = run(prepared, copy = 0)
  assert hashCalls() == 0, "HUH precedes memory policy and namespace hashing"
  failHash(0)
  words(completed, high(uint64)-8, high(uint64))
# Current selection supports explicit self, foreign reads, absent service and non-narrowing WHO.
words(run(source(selector = 42)), 0, 0)
words(run(source(selector = 99)), 1'u64 + (73'u64 shl 32), 0)
words(run(source(selector = 99, offered = 4)), high(uint64), 0)
words(run(source(selector = 99, malformed = true)), 1'u64 + (73'u64 shl 32), 0)
for selector in [0'u64, 0x100000063'u64]:
  words(run(source(selector = selector)), high(uint64)-3, 196608)
for address in [0'u64, 65536'u64+4096-16, 196608'u64+8192-16, 0x100000000'u64, high(uint64)]:
  let completed = run(source(address = address))
  let cpu = machineInfo(completed.value.machine).value
  assert completed.value.exit == StepExit.Panic and uint64(cpu.registers[7]) == high(uint64) and
      uint64(cpu.registers[8]) == address and
    uint64(cpu.registers[9]) == 3,
    "valid length memory panic preserves both inputs"
  assert uint64(cpu.gas) == 100000-price(valid)-643, "memory panic pays fixed fee"
words(run(source(address = 65536)), high(uint64), 0) # Readable RO hash is absent, rather than panic.
words(run(source(address = 196608'u64+4096-16)), high(uint64), 0) # Complete cross-page RW capture is readable.
assert run(valid, copy = 31).error == AccumulationDispatchError.LimitExceeded, "exact fixed hash copy ceiling"
for wire in [newSeq[byte](0), @[4'u8], @[128'u8, 0], @[1'u8], @[2'u8, 0], @[0'u8, 0], newSeq[byte](14)]:
  assert run(source(malformed = true, wire = wire)).error ==
      AccumulationDispatchError.MalformedState,
    "malformed/noncanonical/truncated/trailing histories are local refusals"
for available in [0'u64, 642, 643, 644]:
  let completed = run(source(credit = price(valid)+available))
  let cpu = machineInfo(completed.value.machine).value
  if available < 643:
    assert completed.value.exit == StepExit.OutOfGas and uint64(cpu.gasDeficit) == 0 and
      uint64(cpu.registers[7]) == high(uint64) and uint64(cpu.registers[8]) == 196608 and uint64(
          cpu.registers[9]) == 3, "exact fixed fee deficit with original registers"
  else:
    words(completed, 0, 0)
    assert uint64(cpu.gas) == available-643, "funded exact fee boundary"
let underfunded = source(credit = price(valid)+642, offered = high(uint64), address = high(uint64),
    malformed = true)
failHash(1)
assert run(underfunded, copy = 0).value.exit == StepExit.OutOfGas and hashCalls() == 0, "OOG precedes HUH/capture/backend work"
failHash(0)
let fullCredit = run(source(credit = high(uint64)))
assert uint64(machineInfo(fullCredit.value.machine).value.gas) == high(uint64)-price(valid)-643, "full-width credit without signed narrowing"
failHash(1)
assert run(valid).error == AccumulationDispatchError.BackendFailure and hashCalls() == 1, "namespace hashing refusal cannot fabricate NONE"
failHash(0)
# The public read retains copied tagged fields and cannot fabricate a history from defaults or absence.
let owner = context(done)
assert owner.effectRequestHistory(hash, RequestLength(3)).value.state == RequestState.Requested, "direct current owner read"
assert owner.effectRequestHistory(hash, RequestLength(4)).error ==
    AccumulationEffectError.NotRequested, "absence has no history payload"
assert default(AccumulationEffectContext).effectRequestHistory(hash, RequestLength(3)).error ==
    AccumulationEffectError.Uninitialized,
  "default owner grants no request identity"
# Storage writes and legal maximum-length requests now occupy distinct current namespaces.
let separated = run(source(length = high(uint32)-2, offered = uint64(high(uint32))-2, writes = 2,
  account = ServiceMetadata(balance: AccountBalance(100), storageItems: AccountStorageItems(2),
    storageBytes: AccountStorageBytes(81'u64+uint64(high(uint32))-2))))
let prior = context(separated)
let advanced = recordAccumulationStorage(separated.effects, hashBytes, [1'u8, 7, 0, 0, 128],
  parameters(), ByteLimit(32)).value.effects
let current = advanced.effectContext(AccumulationDimension.Regular).value
assert current.effectRequestHistory(hash, RequestLength(high(uint32)-2)).value.state ==
    RequestState.Requested,
  "storage writes cannot overwrite a current request history"
assert prior.effectRequestHistory(hash, RequestLength(high(uint32)-2)).value.state ==
    RequestState.Requested,
  "retained prior request remains independent"
let yielded = recordAccumulationYield(advanced, default(OutputCommitment)).value
assert yielded.effectContext(AccumulationDimension.Regular).value.effectRequestHistory(hash,
  RequestLength(high(uint32)-2)).value.state == RequestState.Requested, "yield preserves the separate request owner"
for length in [high(uint32)-1, high(uint32)]:
  failHash(1)
  assert owner.effectRequestHistory(hash, RequestLength(length)).error ==
      AccumulationEffectError.InvalidLength
  assert recordAccumulationSolicit(done.effects, hash, RequestLength(length), parameters()).error ==
      AccumulationEffectError.InvalidLength
  assert recordAccumulationForget(done.effects, hash, RequestLength(length), parameters()).error ==
      AccumulationEffectError.InvalidLength
  assert hashCalls() == 0, "invalid public lengths precede namespace hashing"
  failHash(0)
for checkpoint in [false, true]:
  let completed = run(source(suffix = (if checkpoint: @[@[10'u8, 19], @[0'u8]] else: @[@[0'u8]])))
  let selected = normalizeAccumulationOutcome(completed).value.outcomeContext.value
  assert selected.effectRequestHistory(hash, RequestLength(3)).value.state ==
      RequestState.Requested,
    "query leaves panic/checkpoint history selection intact"
let before = getOccupiedMem()
for iteration in 0..<1000:
  let completed = run(valid)
  words(completed, 0, 0) # Release each decoded history, context and CPU result without retaining snapshots.
let after = getOccupiedMem()
assert before == after, "query releases all ARC-owned execution state"
recordArcRelease("pvm_accumulation_query", 1000, before, after)
echo "PVM accumulation query passed"
echo "ARC_RELEASE cycles=1000 unchanged"
