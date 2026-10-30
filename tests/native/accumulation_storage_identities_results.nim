# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine storage calls retain bounded original raw identities through immutable effects and actual terminal selection.
import std/[assertions, syncio, envvars, cmdline]
import ../support/[pvm_accumulation_program, pvm_accumulation_context, arc_evidence]
import ../../src/state/accumulation/[effects as accumulation_effects,
    dispatch as accumulation_dispatch, context as accumulation_context,
    machine as accumulation_machine, outcome as accumulation_outcome,
    invocation as accumulation_invocation]
import ../../src/chain/parameters
import ../../src/codec/bounded
import ../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    requests as state_requests]
import ../../src/pvm/[machine, step]
import ../../src/pvm/gas/gas
import ../../src/pvm/host/fetch as host_fetch
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Genuine backend failure leaves original effect and raw fact ownership unchanged.
proc failAfter(count: cint) {.importc: "ro_blake_after", cdecl.}
  ## Fail a required map hash after physical-key derivation and private phase preparation.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Per-key resource refusal must precede namespace hashing.
const policy = AccumulationStorageFactLimits(items: ElementLimit(2), perKey: ByteLimit(2),
    totalKeyBytes: ByteLimit(2))
proc schedule(): Parameters =
  ## Literal small E8 deposit fields keep storage funding independent of maximal unrelated fixture parameters.
  var wire = encodeParameters(pvmParameters())
  for field, amount in [2'u64, 1'u64, 10'u64]:
    for i in 0..<8:
      wire[field*8+i] = byte((amount shr (8*i)) and 255) # Three leading E8 deposit fields retain canonical width.
  decodeParameters(wire).value
proc initial(limits: AccumulationStorageFactLimits, lifecycle = false): AccumulationEffects =
  ## Authentic machine bootstrap supplies original input provenance; no result or private source is forged.
  let prepared = guestProgram([@[50'u8, 0]], account = ServiceMetadata(balance: AccountBalance(
      1000000000)), spareEntries = 4, registrar = (if lifecycle: 42'u32 else: 0'u32),
      writes = (if lifecycle: 3'u64 else: 2'u64))
  prepareAccumulationEffects(prepareAccumulationContexts(prepared.machineBootstrap.value,
      pvmContextConfig()).value, storageFacts = limits,
    createdAccounts = ElementLimit(if lifecycle: 2 else: 0),
    deletedAccounts = ElementLimit(if lifecycle: 2 else: 0)).value
proc run(checkpoint, panic: bool, limits: AccumulationStorageFactLimits,
    credit = 100000'u64): AccumulationOutcome =
  ## Actual guest writes one raw byte then either halts or panics, optionally preserving it through the real checkpoint host call.
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 65536),
      registerImmediate(9, 1), registerImmediate(10, 196608), registerImmediate(11, 1), @[10'u8, 5]]
  if checkpoint: instructions.add(@[10'u8, 19]) # The real checkpoint call selects current implications for future exceptional exit.
  instructions.add(if panic: @[0'u8] else: @[50'u8, 0])
  let prepared = guestProgram(instructions, credit = credit, account = ServiceMetadata(
      balance: AccountBalance(1000000000)), spareEntries = 2)
  let done = executeAccumulationMachine(prepared, schedule(), FetchAccumulationLimits(
      items: ElementLimit(0), bytes: ByteLimit(1)), MemoryByteLimit(64), ExecutionStepLimit(100),
      HostCallLimit(10), GasCycleLimit(1000), pvmContextConfig(), storageFacts = limits)
  assert done.error == AccumulationDispatchError.None
  normalizeAccumulationOutcome(done).value
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(AccumulationEffectResult[AccumulationStorageFact])
  if mode == "value":
    discard empty.value
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  let phaseSource = initial(policy, lifecycle = true)
  let phaseFirst = recordAccumulationStorage(phaseSource, @[7'u8], @[1'u8], schedule(), ByteLimit(
      2)).value.effects
  let phaseCheckpoint = checkpointAccumulationEffects(phaseFirst).value
  let preparedBirth = recordAccumulationNew(phaseCheckpoint, AccumulationNewService(
      codeHash: default(CodeHash),
    length: RequestLength(1), desired: AccumulationDesiredService(7)), schedule(),
        ServiceProbeLimit(8))
  assert preparedBirth.error == AccumulationEffectError.None, $preparedBirth.error
  let birth = preparedBirth.value
  let beforePhase = birth.effects.effectContext(AccumulationDimension.Regular).value.effectStorageFactAt(
      AccumulationStorageFactIndex(0)).value
  failAfter(1)
  assert recordAccumulationStorage(birth.effects, @[7'u8], @[2'u8], schedule(), ByteLimit(
      2)).error == AccumulationEffectError.BackendFailure
  fail(0)
  assert uint64(beforePhase.storageFactInfo.value.phase) == 0
  let phaseChanged = recordAccumulationStorage(birth.effects, @[7'u8], @[2'u8], schedule(),
      ByteLimit(2)).value.effects
  let afterPhase = phaseChanged.effectContext(AccumulationDimension.Regular).value
  assert afterPhase.effectStorageFactCount.value == 1
  assert uint64(afterPhase.effectStorageFactAt(AccumulationStorageFactIndex(
      0)).value.storageFactInfo.value.phase) == 1
  assert uint64(phaseChanged.effectContext(AccumulationDimension.Exceptional).value.effectStorageFactAt(
      AccumulationStorageFactIndex(0)).value.storageFactInfo.value.phase) == 0
  assert beforePhase.copyStorageFactKey(ByteLimit(1)).value == @[7'u8]
  let original = initial(policy)
  let regular = AccumulationDimension.Regular
  let exceptional = AccumulationDimension.Exceptional
  assert original.effectContext(regular).value.effectStorageFactCount.value == 0
  assert initial(default(AccumulationStorageFactLimits)).effectContext(
      regular).value.effectStorageFactCount.error ==
      AccumulationEffectError.StorageWriteFactsDisabled
  assert default(AccumulationStorageFact).storageFactInfo.error ==
      AccumulationEffectError.Uninitialized
  assert default(AccumulationStorageFact).copyStorageFactKey(ByteLimit(2)).error ==
      AccumulationEffectError.Uninitialized
  var raw = @[7'u8]
  let first = recordAccumulationStorage(original, raw, @[1'u8], schedule(), ByteLimit(
      2)).value.effects
  raw[0] = 9
  let context = first.effectContext(regular).value
  let fact = context.effectStorageFactAt(AccumulationStorageFactIndex(0)).value
  assert fact.copyStorageFactKey(ByteLimit(1)).value == @[7'u8]
  let info = fact.storageFactInfo.value
  assert uint32(info.service) == 42 and info.rawBytes == 1
  assert context.effectStorageFactAt(AccumulationStorageFactIndex(high(uint64))).error ==
      AccumulationEffectError.InvalidIndex
  assert fact.copyStorageFactKey(ByteLimit(0)).error == AccumulationEffectError.LimitExceeded
  var detached = fact.copyStorageFactKey(ByteLimit(1)).value
  detached[0] = 99
  assert fact.copyStorageFactKey(ByteLimit(1)).value == @[7'u8]
  let rewritten = recordAccumulationStorage(first, @[7'u8], @[2'u8], schedule(), ByteLimit(
      2)).value.effects
  let deleted = recordAccumulationStorage(rewritten, @[7'u8], @[], schedule(), ByteLimit(
      2)).value.effects
  assert deleted.effectContext(regular).value.effectStorageFactCount.value == 1
  let checked = checkpointAccumulationEffects(deleted).value
  let extra = recordAccumulationStorage(checked, @[], @[3'u8], schedule(), ByteLimit(
      2)).value.effects
  assert extra.effectContext(regular).value.effectStorageFactCount.value == 2
  assert extra.effectContext(exceptional).value.effectStorageFactCount.value == 1
  assert extra.effectContext(regular).value.effectStorageFactAt(AccumulationStorageFactIndex(
      1)).value.copyStorageFactKey(ByteLimit(0)).value.len == 0
  assert original.effectContext(regular).value.effectStorageFactCount.value == 0
  assert first.effectContext(exceptional).value.effectStorageFactCount.value == 0
  assert recordAccumulationStorage(extra, @[8'u8], @[4'u8], schedule(), ByteLimit(2)).error ==
      AccumulationEffectError.LimitExceeded
  var short = policy
  short.totalKeyBytes = ByteLimit(1)
  let narrow = initial(short)
  assert recordAccumulationStorage(narrow, @[1'u8, 2], @[4'u8], schedule(), ByteLimit(
      2)).error == AccumulationEffectError.LimitExceeded
  short.perKey = ByteLimit(0)
  let noKey = initial(short)
  fail(1)
  assert recordAccumulationStorage(noKey, @[1'u8], @[4'u8], schedule(), ByteLimit(2)).error ==
      AccumulationEffectError.LimitExceeded and calls() == 0
  assert recordAccumulationStorage(original, @[1'u8], @[4'u8], schedule(), ByteLimit(
      2)).error == AccumulationEffectError.BackendFailure
  assert original.effectContext(regular).value.effectStorageFactCount.value == 0
  fail(0)
  assert recordAccumulationStorage(original, @[1'u8], @[4'u8], schedule(), ByteLimit(
      2)).value.effects.effectContext(regular).value.effectStorageFactCount.value == 1
  for checkpoint in [false, true]:
    for panic in [false, true]:
      # Actual terminal normalization must select the raw facts paired with the chosen account state.
      let selected = run(checkpoint, panic, policy).outcomeContext.value
      assert selected.effectStorageFactCount.value == (if not panic or checkpoint: 1 else: 0)
  let exhausted = run(false, false, policy, 0)
  assert exhausted.outcomeInfo.value.termination == AccumulationTermination.OutOfGas
  assert exhausted.outcomeContext.value.effectStorageFactCount.value == 0
  for i in 0..<25: discard recordAccumulationStorage(original, @[7'u8], @[1'u8], schedule(),
      ByteLimit(2)).value
  let before = getOccupiedMem()
  for i in 0..<1000:
    # Both first touch and a phase refresh release every private owner while retaining shared immutable raw bytes.
    discard recordAccumulationStorage(original, @[7'u8], @[1'u8], schedule(), ByteLimit(2)).value
    discard recordAccumulationStorage(birth.effects, @[7'u8], @[2'u8], schedule(), ByteLimit(2)).value
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_storage_identities", 1000, before, after)
  echo "accumulation-storage-identities: ok"
try:
  main()
except:
  quit(2) # Unexpected setup failure cannot satisfy a guarded result rejection.
