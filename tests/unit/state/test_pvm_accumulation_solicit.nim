# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_solicit_arc_release"}

## Authored solicit programs verify exact funding, immutable request/footprint publication and current query/provide consumers.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite]
import ../../../src/codec/state/[layout as state_layout, accounts as state_accounts,
    requests as state_requests, service_values as state_service_values, outputs as state_outputs,
    trie as state_trie]
import ../../../src/codec/[c2_records, header]
import ../../../src/state/accumulation/[dispatch as accumulation_dispatch,
    effects as accumulation_effects, context as accumulation_context,
    machine as accumulation_machine, invocation as accumulation_invocation,
    outcome as accumulation_outcome]
import ../../../src/state/store
import ../../../src/pvm/[machine, program, step, gas, host_fetch]
import ../../../src/crypto/primitives
import ../../support/[pvm_accumulation_program, pvm_accumulation_context, arc_evidence]

# Inject maintained-primitive refusal after genuine fixture preparation.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
# Observe charge-before-work and exact injected failure position.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
# Reject after a bounded number of successful namespace/trie hashes.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

let blob = @[5'u8, 7, 9]
let hash = ServicePreimageHash(array[32, byte](blake2b256(blob).value))
let config = RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
    items: ElementLimit(3), maxBytes: ByteLimit(13)))

# Exact E8 deposit offsets and independent fixed profile fields keep thresholds auditable.
proc parameters(base = 10'u64, item = 2'u64, octet = 3'u64): Parameters =
  var wire = encodeParameters(pvmParameters())
  for field, value in [item, octet, base]:
    for i in 0..<8:
      wire[field*8+i] = byte((value shr (8*i)) and 255) # Wire tuple order is item/byte/account.
  wire[24] = 2
  wire[25] = 0
  wire[82] = 80
  wire[83] = 0
  for i in 110..<114:
    wire[i] = 0 # Fixed transfer memo profile supports retained-transfer witnesses.
  wire[110] = 128
  decodeParameters(wire).value

# Fixed copied digest input; optional payload tails support later provide calls in the same guest.
proc payload(): seq[byte] =
  result = newSeq[byte](32)
  let digest = array[32, byte](hash)
  for i in 0..<32:
    result[i] = digest[i] # No string framing or pointer alias enters guest capture.

# Construct genuine current-self/other-service histories and explicitly bounded write capacity.
proc source(present = false, history = requestedHistory(), length = 3'u32, offered = 3'u64,
    address = 196608'u64, selector = high(uint64), credit = 100000'u64, slot = 128'u32,
    account = ServiceMetadata(balance: AccountBalance(1000)), writes = 2'u64,
    malformed = false, wire: seq[byte] = @[], preimage = false,
    data: seq[byte] = payload(), suffix: seq[seq[byte]] = @[@[50'u8, 0]], extra: seq[
        StateEntry] = @[]): PreparedAccumulationMachine =
  var entries = extra
  entries.add(serviceMetadataEntry(ServiceIndex(99), default(ServiceMetadata), ByteLimit(
      ServiceMetadataBytes)).value)
  entries.add(serviceRequestEntry(ServiceIndex(99), hash, RequestLength(length), requestedHistory(), config).value)
  var metadata = account
  if present:
    var entry = serviceRequestEntry(ServiceIndex(42), hash, RequestLength(length), history, config).value
    if malformed:
      entry.value = wire # Canonical decoding, not the fixture, determines the local refusal.
    entries.add(entry)
    if uint32(metadata.storageItems) == 0 and uint64(metadata.storageBytes) == 0:
      metadata.storageItems = AccountStorageItems(2)
      metadata.storageBytes = AccountStorageBytes(81'u64+uint64(
          length)) # Default existing-request fixtures have a coherent one-request footprint.
  if preimage:
    entries.add(servicePreimageEntry(ServiceIndex(42), hash, blob,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(
          3))).value) # Restoration must preserve the retained unavailable blob.
  var instructions = @[registerImmediate(7, selector), registerImmediate(8, address),
    registerImmediate(9, offered), @[10'u8, 25]]
  for instruction in suffix:
    instructions.add(instruction) # Later hosts observe this exact execution's current effects.
  guestProgram(instructions, credit, extra = entries, writable = data, account = metadata,
    writes = writes, slot = HeaderSlot(slot), spareEntries = 4)

# Independent bounded policy grants only this invocation's actual mutation/provision capacities.
proc run(prepared: PreparedAccumulationMachine, copy = 128'u64, params = parameters(),
    traces = 0'u64): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, params,
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1), operand: OperandLimits(
        maxBytes: ByteLimit(132))),
    MemoryByteLimit(copy), ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000),
        pvmContextConfig(),
    provisionLimits = AccumulationProvisionLimits(items: ElementLimit(1), perBlob: ByteLimit(3),
        totalBlobBytes: ByteLimit(3)), accountWriteKeys = ElementLimit(traces))

# Basic-block instruction prices remain independent from the fixed 2193 host fee.
proc price(prepared: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(prepared.accumulationMachine.value).value, CodeAddress(5),
      GasCycleLimit(1000)).value)

# Retain only completed execution's exact regular or exceptional context.
proc context(done: AccumulationDispatchResult, dimension = AccumulationDimension.Regular): AccumulationEffectContext =
  assert done.error == AccumulationDispatchError.None, "completed execution grants matching effects"
  done.effects.effectContext(dimension).value

# Inspect canonical current caller metadata independently from request decoding.
proc metadata(owner: AccumulationEffectContext): ServiceMetadata =
  let found = owner.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(42))).value
  decodeServiceMetadata(found.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata

# Assert exact guest result and unchanged advertised length on every funded row verdict.
proc resultCode(done: AccumulationDispatchResult, code: uint64, second = 196608'u64) =
  ## Check the exact verdict and second output/input word, including query calls in a composed guest.
  assert done.value.exit == StepExit.Halt, "funded row resumes guest"
  let cpu = machineInfo(done.value.machine).value
  assert uint64(cpu.registers[7]) == code and uint64(cpu.registers[8]) == second,
    "expected verdict/word " & $code & "/" & $second & " got " & $uint64(cpu.registers[7]) & "/" &
        $uint64(cpu.registers[8])


# An existing unsupervised foreign account is HUH; full-width out-of-domain selection is WHO.
resultCode(run(source(selector = 99)), high(uint64)-8)
resultCode(run(source(selector = 0x10000002a'u64)), high(uint64)-3)
resultCode(run(source(selector = 42)), 0)
let valid = source()
let done = run(valid)
resultCode(done, 0)
let current = context(done)
let initial = context(done, AccumulationDimension.Exceptional)
assert current.effectRequestHistory(hash, RequestLength(3)).value.state ==
    RequestState.Requested and
  initial.effectRequestHistory(hash, RequestLength(3)).error ==
      AccumulationEffectError.NotRequested, "new current request is absent from the checkpoint"
let account = metadata(current)
assert uint32(account.storageItems) == 2 and uint64(account.storageBytes) == 84 and uint64(
    account.balance) == 1000,
  "new request adds exact footprint without a balance debit"
assert uint64(machineInfo(done.value.machine).value.gas) == 100000-price(valid)-2193, "fixed solicit fee"
for chapter in [2, 7, 12]:
  assert current.effectAccounts.value.lookup(chapterKey(StateChapter(chapter))).value.bytes ==
    initial.effectAccounts.value.lookup(chapterKey(StateChapter(chapter))).value.bytes, "unrelated chapters unchanged"
assert readBytes(memoryOf(done.value.machine).value, MemoryAddress(196608), MemoryLength(32),
    MemoryByteLimit(32)).value == payload(),
  "solicit never writes input memory"
for balance in [265'u64, 266, 267]:
  let completed = run(source(account = ServiceMetadata(balance: AccountBalance(balance))))
  resultCode(completed, (if balance < 266: high(uint64)-4 else: 0'u64))
  assert uint64(metadata(context(completed)).balance) == balance, "FULL and OK never debit balance"
  assert uint32(metadata(context(completed)).storageItems) == (if balance < 266: 0'u32 else: 2'u32), "FULL preserves prior footprint"
for gratis in [265'u64, 266, 267]:
  resultCode(run(source(account = ServiceMetadata(depositOffset: AccountBalance(gratis)))),
    (if gratis < 266: high(uint64)-4 else: 0'u64)) # Gratis offsets the exact threshold, including zero balance.
let combined = run(source(account = ServiceMetadata(balance: AccountBalance(265),
    depositOffset: AccountBalance(1))))
resultCode(combined, 0)
for base in [0'u64, 1]:
  resultCode(run(source(account = ServiceMetadata(balance: AccountBalance(high(uint64)),
      depositOffset: AccountBalance(high(uint64)))),
    params = parameters(base, high(uint64), 0)), (if base == 0: 0'u64 else: high(
        uint64)-4)) # Two-limb balance+gratis and two full-width item products meet exactly.
resultCode(run(source(account = ServiceMetadata(balance: AccountBalance(high(uint64)))),
  params = parameters(0, 0, high(uint64))), high(uint64)-4) # Large products cannot wrap into a funded threshold.
for history in [requestedHistory(), availableHistory(RequestSlot(7)), reavailableHistory(
    RequestSlot(1), RequestSlot(2), RequestSlot(3))]:
  let refused = run(source(present = true, history = history, account = default(ServiceMetadata), writes = 0))
  resultCode(refused, high(uint64)-8) # Existing shape HUH precedes underfunding and store policy.
for slot in [0'u32, 128, high(uint32)]:
  let restored = run(source(present = true, history = unavailableHistory(RequestSlot(high(uint32)),
      RequestSlot(high(uint32))),
    slot = slot, preimage = true, writes = 1))
  resultCode(restored, 0)
  let owner = context(restored)
  let history = owner.effectRequestHistory(hash, RequestLength(3)).value
  assert history.state == RequestState.Reavailable and uint32(history.originalFrom) == high(
      uint32) and
    uint32(history.removedAt) == high(uint32) and uint32(history.restoredAt) == slot, "append full-width actual invocation slot with no expiry or chronology restriction"
  assert uint32(metadata(owner).storageItems) == 2 and uint64(metadata(owner).storageBytes) == 84, "restoration does not add footprint"
  assert owner.effectAccounts.value.lookup(servicePreimageKey(ServiceIndex(42), hash, ByteLimit(
      32)).value).value.bytes == blob,
    "retained unavailable preimage remains unchanged"
let restoreFull = run(source(present = true, history = unavailableHistory(RequestSlot(1),
    RequestSlot(2)),
  account = ServiceMetadata(balance: AccountBalance(265)), writes = 0))
resultCode(restoreFull, high(uint64)-4) # Unchanged footprint still requires current funding before resource policy.
assert context(restoreFull).effectRequestHistory(hash, RequestLength(3)).value.state ==
    RequestState.Unavailable, "FULL does not restore history"
for length in [0'u32, high(uint32)-2]:
  let completed = run(source(length = length, offered = uint64(length)), params = parameters(0, 0, 0))
  resultCode(completed, 0)
  assert uint64(machineInfo(completed.value.machine).value.registers[9]) == uint64(length)
  assert uint64(metadata(context(completed)).storageBytes) == 81'u64+uint64(length), "complete E4 footprint and pinned namespace prefixes"
for offered in [uint64(high(uint32))-1, uint64(high(uint32)), 0x100000003'u64, high(uint64)]:
  let prepared = source(offered = offered, address = high(uint64), malformed = true)
  failHash(1)
  let completed = run(prepared, copy = 0)
  assert hashCalls() == 0, "HUH precedes capture policy and hashing"
  failHash(0)
  resultCode(completed, high(uint64)-8, high(uint64))
  assert uint64(machineInfo(completed.value.machine).value.registers[9]) == offered
for address in [0'u64, 65536'u64+4096-16, 196608'u64+8192-16, 0x100000000'u64, high(uint64)]:
  let completed = run(source(address = address))
  let cpu = machineInfo(completed.value.machine).value
  assert completed.value.exit == StepExit.Panic and uint64(cpu.registers[7]) == high(uint64) and
      uint64(cpu.registers[8]) == address and
    uint64(cpu.registers[9]) == 3,
    "memory panic preserves original inputs before state checks"
  assert uint64(cpu.gas) == 100000-price(valid)-2193, "charged memory panic"
resultCode(run(source(address = 65536)), 0, second = 65536) # Any readable RO hash can be solicited without a preimage.
resultCode(run(source(address = 196608'u64+4096-16)), 0,
    second = 196608'u64+4096-16) # Complete cross-page RW hash is readable.
assert run(valid, copy = 31).error == AccumulationDispatchError.LimitExceeded, "exact fixed input copy budget"
for wire in [newSeq[byte](0), @[4'u8], @[128'u8, 0], @[2'u8, 0], @[0'u8, 0], newSeq[byte](14)]:
  assert run(source(present = true, malformed = true, wire = wire)).error ==
      AccumulationDispatchError.MalformedState,
    "malformed/noncanonical/truncated/trailing histories are local refusals"
for available in [0'u64, 2192, 2193, 2194]:
  let completed = run(source(credit = price(valid)+available))
  let cpu = machineInfo(completed.value.machine).value
  if available < 2193:
    assert completed.value.exit == StepExit.OutOfGas and uint64(cpu.gasDeficit) == 0 and
      uint64(cpu.registers[7]) == high(uint64) and uint64(cpu.registers[8]) == 196608 and uint64(
          cpu.registers[9]) == 3, "exact fee deficit preserves original registers"
  else:
    resultCode(completed, 0)
    assert uint64(cpu.gas) == available-2193, "funded fixed fee edge"
let underfunded = source(credit = price(valid)+2192, offered = high(uint64), address = high(uint64), writes = 0)
failHash(1)
assert run(underfunded, copy = 0).value.exit == StepExit.OutOfGas and hashCalls() == 0, "OOG precedes HUH/copy/namespace work"
failHash(0)
let fullCredit = run(source(credit = high(uint64)))
assert uint64(machineInfo(fullCredit.value.machine).value.gas) == high(uint64)-price(valid)-2193, "full-width guest credit"
for items in [high(uint32)-2, high(uint32)-1, high(uint32)]:
  let completed = run(source(account = ServiceMetadata(storageItems: AccountStorageItems(items))),
      params = parameters(0, 0, 0))
  if items == high(uint32)-2:
    assert uint32(metadata(context(completed)).storageItems) == high(uint32), "exact E4 item addition edge"
  else:
    assert completed.error == AccumulationDispatchError.InvalidContext, "unrepresentable item count remains local"
for octets in [high(uint64)-84, high(uint64)-83, high(uint64)]:
  let completed = run(source(account = ServiceMetadata(storageBytes: AccountStorageBytes(octets))),
      params = parameters(0, 0, 0))
  if octets == high(uint64)-84:
    assert uint64(metadata(context(completed)).storageBytes) == high(uint64), "exact E8 octet addition edge"
  else:
    assert completed.error == AccumulationDispatchError.InvalidContext, "unrepresentable footprint remains local"
let repeated = run(source(suffix = @[registerImmediate(7, high(uint64)), registerImmediate(8,
    196608), @[10'u8, 25], @[50'u8, 0]]))
resultCode(repeated, high(uint64)-8)
assert uint32(metadata(context(repeated)).storageItems) == 2, "repeated solicitation cannot double-count footprint"
let twice = run(source(suffix = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
    registerImmediate(9, 4), @[10'u8, 25], @[50'u8, 0]]))
resultCode(twice, 0)
assert uint64(machineInfo(twice.value.machine).value.registers[9]) == 4
assert uint32(metadata(context(twice)).storageItems) == 4 and uint64(metadata(context(
    twice)).storageBytes) == 169,
  "same hash with distinct lengths creates independent requests"
let queried = run(source(suffix = @[registerImmediate(7, high(uint64)), registerImmediate(8,
    196608), @[10'u8, 24], @[50'u8, 0]]))
resultCode(queried, 0, 0) # Current query sees new empty history rather than NONE.
let queriedRestore = run(source(present = true, history = unavailableHistory(RequestSlot(1),
    RequestSlot(2)),
  suffix = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608), @[10'u8, 24], @[
      50'u8, 0]]))
resultCode(queriedRestore, 0x0000000100000003'u64,
    0x0000008000000002'u64) # Current query observes the appended slot 128.
var providedInput = payload()
for octet in blob:
  providedInput.add(octet) # Real provided bytes follow the fixed solicitation hash.
let provided = run(source(data = providedInput, suffix = @[registerImmediate(7, 42),
    registerImmediate(8, 196640),
  registerImmediate(9, 3), @[10'u8, 28], @[50'u8, 0]]))
assert context(provided).effectInfo.value.provisions == 1 and
  context(provided).effectProvisionAt(AccumulationProvisionIndex(
      0)).value.copyProvisionBytes.value == blob, "provide sees newly solicited current-self request"
let prepared = prepareAccumulationEffects(done.effects.effectsSource.value).value
assert recordAccumulationSolicit(default(AccumulationEffects), hash, RequestLength(3), parameters(
  )).error == AccumulationEffectError.Uninitialized,
  "default pair cannot solicit"
assert recordAccumulationSolicit(prepared, hash, RequestLength(3), default(Parameters)).error ==
    AccumulationEffectError.InvalidParameters,
  "default schedule cannot authorize funding"
for successful in [0, 1, 3]:
  failAfter(cint(successful))
  let failed = recordAccumulationSolicit(prepared, hash, RequestLength(3), parameters())
  assert failed.error == AccumulationEffectError.BackendFailure and hashCalls() == cint(
      successful+1), "atomic namespace/late Merklization failure"
  failHash(0)
  assert prepared.effectContext(AccumulationDimension.Regular).value.effectRequestHistory(hash,
      RequestLength(3)).error ==
    AccumulationEffectError.NotRequested, "failed candidate leaves original request absent"
for writes in [0'u64, 1]:
  assert run(source(writes = writes)).error == AccumulationDispatchError.LimitExceeded, "new request needs both history and metadata write capacity"
assert run(source(present = true, history = unavailableHistory(RequestSlot(1), RequestSlot(2)),
    writes = 0)).error ==
  AccumulationDispatchError.LimitExceeded, "restoration needs one write, distinct from protocol FULL"
# Nonempty retained effects survive solicitation through the shared immutable successor helper.
let otherBlob = @[1'u8]
let otherHash = ServicePreimageHash(array[32, byte](blake2b256(otherBlob).value))
let otherRequest = serviceRequestEntry(ServiceIndex(42), otherHash, RequestLength(1),
    requestedHistory(), config).value
let withOther = run(source(extra = @[otherRequest], account = ServiceMetadata(
    balance: AccountBalance(1000),
  storageItems: AccountStorageItems(2), storageBytes: AccountStorageBytes(82))))
let owners = prepareAccumulationEffects(withOther.effects.effectsSource.value).value
let supplied = recordAccumulationProvision(owners, ServiceIndex(42), otherBlob,
  AccumulationProvisionLimits(items: ElementLimit(1), perBlob: ByteLimit(1),
      totalBlobBytes: ByteLimit(1))).value
let yielded = recordAccumulationYield(supplied, default(OutputCommitment)).value
let plan = prepareAccumulationTransfer(yielded, AccumulationTransferDestination(99),
    TransferBalance(5), Gas(0), default(TransferMemo), parameters()).value
let sent = commitAccumulationTransfer(plan, ElementLimit(1)).value
let checkpointed = checkpointAccumulationEffects(sent).value
let changed = recordAccumulationSolicit(checkpointed, hash, RequestLength(3), parameters()).value
let retained = changed.effectContext(AccumulationDimension.Regular).value
assert retained.effectInfo.value.transfers == 1 and retained.effectInfo.value.provisions == 1 and
    retained.effectInfo.value.hasYield,
  "solicitation preserves nonempty transfer/provision/yield owners"
assert uint64(retained.effectTransferAt(AccumulationTransferIndex(0)).value.amount) == 5 and
  retained.effectProvisionAt(AccumulationProvisionIndex(0)).value.copyProvisionBytes.value ==
      otherBlob and
  array[32, byte](retained.effectYield.value) == default(array[32, byte]), "retained payloads remain exact"
assert changed.effectContext(AccumulationDimension.Exceptional).value.effectRequestHistory(hash,
    RequestLength(3)).error ==
  AccumulationEffectError.NotRequested, "exceptional history stays independent"
for checkpoint in [false, true]:
  let panicked = run(source(suffix = (if checkpoint: @[@[10'u8, 19], @[0'u8]] else: @[@[0'u8]])))
  let selected = normalizeAccumulationOutcome(panicked).value.outcomeContext.value
  assert selected.effectRequestHistory(hash, RequestLength(3)).error ==
    (if checkpoint: AccumulationEffectError.None else: AccumulationEffectError.NotRequested), "panic selects matching request/footprint checkpoint"
  let exhausted = run(source(credit = price(valid)+2400, suffix = (if checkpoint:
    @[@[10'u8, 19], registerImmediate(7, high(uint64)), registerImmediate(8, 196608), @[10'u8, 25],
        @[50'u8, 0]] else:
    @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608), @[10'u8, 25], @[50'u8, 0]])))
  assert exhausted.value.exit == StepExit.OutOfGas, "second solicitation fee is unaffordable"
  let selectedOog = normalizeAccumulationOutcome(exhausted).value.outcomeContext.value
  assert selectedOog.effectRequestHistory(hash, RequestLength(3)).error ==
    (if checkpoint: AccumulationEffectError.None else: AccumulationEffectError.NotRequested), "OOG selects matching request/footprint checkpoint"
# Foreign request fixtures use the same hash but independent account, history and preimage namespaces.
proc foreignRows(present = false, history = requestedHistory(), supervisor = 42'u32,
    incarnation = 0'u32, balance = 1000'u64, protected = 17'u64): seq[StateEntry] =
  ## The invoker was created at slot0; target timestamps are deliberately different from invocation time.
  result = @[serviceMetadataEntry(ServiceIndex(77), ServiceMetadata(supervisor: ServiceIndex(
      supervisor), supervisorCreated: AccountSlot(incarnation), balance: AccountBalance(balance),
          supervisorBalance: AccountBalance(protected),
      storageItems: AccountStorageItems(if present: 2'u32 else: 0'u32),
      storageBytes: AccountStorageBytes(if present: 84'u64 else: 0'u64),
      created: AccountSlot(7), lastAccumulation: AccountSlot(11), parent: ServiceIndex(13)),
          ByteLimit(ServiceMetadataBytes)).value]
  if present:
    result.add(serviceRequestEntry(ServiceIndex(77), hash, RequestLength(3), history, config).value)
    result.add(servicePreimageEntry(ServiceIndex(77), hash, blob,
        ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(
            3))).value) # Stored bytes expose accidental cross-namespace deletion.
let targetKey = chapterServiceKey(StateChapter(255), ServiceIndex(77))
let targetPreimage = servicePreimageKey(ServiceIndex(77), hash, ByteLimit(32)).value
# Invalid lengths remain HUH before memory and target selection; valid memory faults precede WHO.
for selector in [100'u64, 0x10000002a'u64]:
  let unknown = source(selector = selector)
  failHash(1)
  let rejected = run(unknown)
  resultCode(rejected, high(uint64)-3)
  assert hashCalls() == 0, "WHO precedes namespace work"
  failHash(0)
  let invalid = run(source(selector = selector, offered = high(uint64), address = high(uint64)), copy = 0)
  resultCode(invalid, high(uint64)-8, high(uint64))
  assert run(source(selector = selector, address = high(uint64))).value.exit == StepExit.Panic,
      "valid-length memory panic precedes target WHO"
for rows in [foreignRows(supervisor = 77), foreignRows(incarnation = 1)]:
  let prepared = source(selector = 77, extra = rows)
  failHash(1)
  resultCode(run(prepared), high(uint64)-8)
  assert hashCalls() == 0, "foreign authority refusal precedes request hashing"
  failHash(0)
# Creation and restoration use only target funding/counters and append the actual invocation slot128.
for present in [false, true]:
  let rows = foreignRows(present, unavailableHistory(RequestSlot(4), RequestSlot(7)))
  let completed = run(source(selector = 77, extra = rows))
  resultCode(completed, 0)
  let selected = context(completed)
  let history = selected.effectServiceRequestHistory(ServiceIndex(77), hash, RequestLength(3)).value
  assert history.state == (if present: RequestState.Reavailable else: RequestState.Requested),
      "target creation/restoration selects exact history shape"
  if present:
    assert uint32(history.originalFrom) == 4 and uint32(history.removedAt) == 7 and uint32(
        history.restoredAt) == 128,
        "restoration uses invocation time rather than target timestamps"
    assert selected.effectAccounts.value.lookup(targetPreimage).value.bytes == blob,
        "restoration retains target preimage"
  let facts = decodeServiceMetadata(selected.effectAccounts.value.lookup(targetKey).value.bytes,
      ByteLimit(ServiceMetadataBytes)).value.metadata
  assert uint32(facts.storageItems) == 2 and uint64(facts.storageBytes) == 84,
      "target reservation footprint is exact"
  let selfKey = chapterServiceKey(StateChapter(255), ServiceIndex(42))
  assert selected.effectAccounts.value.lookup(selfKey).value.bytes == context(completed,
      AccumulationDimension.Exceptional).effectAccounts.value.lookup(selfKey).value.bytes,
      "foreign request leaves invoker metadata unchanged"
  assert selected.effectAccountScope.value == AccumulationAccountScope.Unsupported,
      "foreign requests require parallel modified-account selection"
for protected in [265'u64, 266]:
  let completed = run(source(selector = 77, extra = foreignRows(balance = 0,
      protected = protected)))
  resultCode(completed, if protected == 266: 0'u64 else: high(uint64)-4)
  assert uint64(decodeServiceMetadata(context(completed).effectAccounts.value.lookup(
      targetKey).value.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata.supervisorBalance) ==
          protected,
      "target funding combines balances without debiting protected funds"
let foreignSource = source(selector = 77, extra = foreignRows())
let tracedForeign = run(foreignSource, traces = 1)
let laterSelf = recordAccumulationSolicit(tracedForeign.effects, hash, RequestLength(3), parameters()).value
assert laterSelf.effectContext(AccumulationDimension.Regular).value.effectAccountScope.value ==
    AccumulationAccountScope.Unsupported,
    "enabled self tracing cannot erase foreign request ancestry"
for checkpoint in [false, true]:
  let failed = run(source(selector = 77, extra = foreignRows(), suffix = (if checkpoint:
    @[@[10'u8, 19], @[0'u8]] else: @[@[0'u8]])))
  let selected = normalizeAccumulationOutcome(failed).value.outcomeContext.value
  assert (selected.effectServiceRequestHistory(ServiceIndex(77), hash, RequestLength(3)).error ==
      AccumulationEffectError.None) == checkpoint,
      "panic retains precisely the selected foreign creation checkpoint"
let foreignPair = prepareAccumulationEffects(prepareAccumulationContexts(
    foreignSource.machineBootstrap.value, pvmContextConfig()).value).value
for successful in [0, 1, 3]:
  failAfter(cint(successful))
  let refused = recordAccumulationSolicit(foreignPair, hash, RequestLength(3), parameters(),
      ServiceIndex(77))
  assert refused.error == AccumulationEffectError.BackendFailure, "foreign request namespace/store refusal is atomic"
  failHash(0)
assert run(source(selector = 77, extra = foreignRows(), writes = 1)).error ==
    AccumulationDispatchError.LimitExceeded,
    "fresh foreign reservation requires both request and metadata writes"
let before = getOccupiedMem()
for iteration in 0..<1000:
  let completed = run(valid)
  resultCode(completed, 0) # Release request/metadata candidates, CPU and complete-map snapshots every cycle.
  resultCode(run(foreignSource), 0) # Release the target account/history successor alongside the self successor.
let after = getOccupiedMem()
assert before == after, "solicit releases all ARC-owned versions"
recordArcRelease("pvm_accumulation_solicit", 1000, before, after)
echo "PVM accumulation solicit passed"
echo "ARC_RELEASE cycles=1000 unchanged"
