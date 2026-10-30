# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine solicit/forget/new effects retain original request identities, expiry evidence and actual checkpoint/terminal selection under independent trace bounds.
import std/[assertions, syncio, envvars, cmdline]
import ../support/[pvm_accumulation_program, pvm_accumulation_context, arc_evidence]
import ../../src/state/accumulation/[effects as accumulation_effects,
    context as accumulation_context, machine as accumulation_machine,
    dispatch as accumulation_dispatch, outcome as accumulation_outcome,
    invocation as accumulation_invocation]
import ../../src/state/store
import ../../src/codec/bounded
import ../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    requests as state_requests, service_values as state_service_values, trie as state_trie]
import ../../src/codec/header
import ../../src/chain/parameters
import ../../src/pvm/[machine, step]
import ../../src/pvm/gas/gas
import ../../src/pvm/host/fetch as host_fetch
import ../../src/crypto/primitives
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Genuine backend refusal cannot publish prepared request identities.
proc failAfter(count: cint) {.importc: "ro_blake_after", cdecl.}
  ## Admit both request namespace hashes, then fail the private map after fact preparation.
proc parameters(): Parameters =
  ## Independent fixed E8 deposits and E4 zero anchor age permit ordinary funded requests and expired removal at slot20000.
  var wire = encodeParameters(pvmParameters())
  for field, value in [2'u64, 1'u64, 10'u64]:
    for i in 0..<8: wire[field*8+i] = byte((value shr (8*i)) and 255) # Exact existing deposit tuple order.
  for i in 74..<78: wire[i] = 0 # maxLookupAnchorAge retains its documented E4 position.
  decodeParameters(wire).value
proc initial(hash: ServicePreimageHash, expired = false, capacity = 2'u64,
    lifecycle = false): AccumulationEffects =
  ## Authentic original bootstrap contains either no request or one coherent expired request/preimage pair.
  var entries: seq[StateEntry] = @[]
  if expired:
    entries.add(serviceRequestEntry(ServiceIndex(42), hash, RequestLength(3), unavailableHistory(
        RequestSlot(1), RequestSlot(2)), RequestEntryConfig(keyBytes: ByteLimit(32),
        history: RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(13)))).value)
    entries.add(servicePreimageEntry(ServiceIndex(42), hash, [97'u8, 98, 99], ServiceEntryLimits(
        keyBytes: ByteLimit(32), valueBytes: ByteLimit(3))).value)
  let prepared = guestProgram([@[50'u8, 0]], account = ServiceMetadata(balance: AccountBalance(
      1000000000), storageItems: AccountStorageItems(if expired: 2'u32 else: 0'u32),
      storageBytes: AccountStorageBytes(if expired: 84'u64 else: 0'u64)), extra = entries,
      spareEntries = 4, writes = 3, registrar = 42, slot = HeaderSlot(20000))
  prepareAccumulationEffects(prepareAccumulationContexts(prepared.machineBootstrap.value,
      pvmContextConfig()).value, requestFacts = ElementLimit(capacity),
    createdAccounts = ElementLimit(if lifecycle: 2 else: 0),
    deletedAccounts = ElementLimit(if lifecycle: 2 else: 0)).value
proc run(checkpoint, panic: bool, credit = 100000'u64): AccumulationOutcome =
  ## A real solicit of the literal zero digest tests selected regular/exceptional effects without a synthetic dispatch result.
  var code = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608), registerImmediate(
      9, 3), @[10'u8, 25]]
  if checkpoint: code.add(@[10'u8, 19]) # Real checkpoint retains successful requested identity before exceptional exit.
  code.add(if panic: @[0'u8] else: @[50'u8, 0])
  let prepared = guestProgram(code, credit = credit, account = ServiceMetadata(
      balance: AccountBalance(1000000000)), writable = newSeq[byte](32), spareEntries = 2)
  let done = executeAccumulationMachine(prepared, parameters(), FetchAccumulationLimits(
      items: ElementLimit(0), bytes: ByteLimit(1)), MemoryByteLimit(64), ExecutionStepLimit(100),
      HostCallLimit(10), GasCycleLimit(1000), pvmContextConfig(), requestFacts = ElementLimit(2))
  assert done.error == AccumulationDispatchError.None
  normalizeAccumulationOutcome(done).value
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(AccumulationEffectResult[AccumulationRequestFact])
  if mode == "value":
    discard empty.value
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  let hash = ServicePreimageHash(array[32, byte](blake2b256([97'u8, 98, 99]).value))
  let regular = AccumulationDimension.Regular
  let exceptional = AccumulationDimension.Exceptional
  let phaseSource = initial(hash, expired = true, lifecycle = true)
  let phaseForgotten = recordAccumulationForget(phaseSource, hash, RequestLength(3), parameters()).value
  let phaseCheckpoint = checkpointAccumulationEffects(phaseForgotten).value
  let birth = recordAccumulationNew(phaseCheckpoint, AccumulationNewService(codeHash: default(
      CodeHash),
    length: RequestLength(0), desired: AccumulationDesiredService(7)), parameters(),
        ServiceProbeLimit(8)).value
  let beforePhase = birth.effects.effectContext(regular).value.effectRequestFactAt(
      AccumulationRequestFactIndex(0)).value
  failAfter(2)
  assert recordAccumulationSolicit(birth.effects, hash, RequestLength(3), parameters()).error ==
      AccumulationEffectError.BackendFailure
  fail(0)
  let phaseRestored = recordAccumulationSolicit(birth.effects, hash, RequestLength(3), parameters()).value
  let phaseCurrent = phaseRestored.effectContext(regular).value
  assert phaseCurrent.effectRequestFactCount.value == 2
  let refreshed = phaseCurrent.effectRequestFactAt(AccumulationRequestFactIndex(0)).value
  assert uint64(beforePhase.phase) == 0 and uint64(refreshed.phase) == 1
  assert beforePhase.removedPreimage and refreshed.removedPreimage
  assert uint64(phaseRestored.effectContext(exceptional).value.effectRequestFactAt(
      AccumulationRequestFactIndex(0)).value.phase) == 0
  let source = initial(hash)
  assert initial(hash, capacity = 0).effectContext(regular).value.effectRequestFactCount.error ==
      AccumulationEffectError.RequestFactsDisabled
  assert source.effectContext(regular).value.effectRequestFactCount.value == 0
  let first = recordAccumulationSolicit(source, hash, RequestLength(3), parameters()).value
  let fact = first.effectContext(regular).value.effectRequestFactAt(AccumulationRequestFactIndex(0)).value
  assert uint32(fact.service) == 42 and uint32(fact.length) == 3
  assert array[32, byte](fact.hash) == array[32, byte](hash) and not fact.removedPreimage
  assert first.effectContext(regular).value.effectAccounts.value.lookup(fact.key).error ==
      StateStoreError.None
  var detached = fact
  detached.length = RequestLength(4)
  assert uint32(first.effectContext(regular).value.effectRequestFactAt(AccumulationRequestFactIndex(
      0)).value.length) == 3
  assert first.effectContext(regular).value.effectRequestFactAt(AccumulationRequestFactIndex(high(
      uint64))).error == AccumulationEffectError.InvalidIndex
  let removed = recordAccumulationForget(first, hash, RequestLength(3), parameters()).value
  assert removed.effectContext(regular).value.effectRequestFactCount.value == 1
  assert not removed.effectContext(regular).value.effectRequestFactAt(AccumulationRequestFactIndex(
      0)).value.removedPreimage
  let repeated = recordAccumulationSolicit(removed, hash, RequestLength(3), parameters()).value
  assert repeated.effectContext(regular).value.effectRequestFactCount.value == 1
  let checked = checkpointAccumulationEffects(first).value
  let next = recordAccumulationSolicit(checked, default(ServicePreimageHash), RequestLength(7),
      parameters()).value
  assert next.effectContext(regular).value.effectRequestFactCount.value == 2
  assert next.effectContext(exceptional).value.effectRequestFactCount.value == 1
  let narrow = initial(hash, capacity = 1)
  let once = recordAccumulationSolicit(narrow, hash, RequestLength(3), parameters()).value
  let refused = recordAccumulationSolicit(once, default(ServicePreimageHash),
      RequestLength(7), parameters())
  assert refused.error == AccumulationEffectError.LimitExceeded
  let expired = initial(hash, expired = true)
  let expunged = recordAccumulationForget(expired, hash, RequestLength(3), parameters()).value
  let expiredFact = expunged.effectContext(regular).value.effectRequestFactAt(
      AccumulationRequestFactIndex(0)).value
  assert expiredFact.removedPreimage
  let restored = recordAccumulationSolicit(expunged, hash, RequestLength(3), parameters()).value
  assert restored.effectContext(regular).value.effectRequestFactAt(AccumulationRequestFactIndex(
      0)).value.removedPreimage
  assert source.effectContext(regular).value.effectRequestFactCount.value == 0
  failAfter(2)
  assert recordAccumulationSolicit(source, hash, RequestLength(3), parameters()).error ==
      AccumulationEffectError.BackendFailure
  assert source.effectContext(regular).value.effectRequestFactCount.value == 0
  fail(0)
  let created = recordAccumulationNew(source, AccumulationNewService(codeHash: CodeHash(array[32,
      byte](hash)), length: RequestLength(3), desired: AccumulationDesiredService(7)), parameters(),
      ServiceProbeLimit(8)).value
  let seeded = created.effects.effectContext(regular).value.effectRequestFactAt(
      AccumulationRequestFactIndex(0)).value
  assert uint32(seeded.service) == uint32(created.service) and uint32(seeded.length) == 3
  assert array[32, byte](seeded.hash) == array[32, byte](hash)
  for checkpoint in [false, true]:
    for panic in [false, true]:
      let chosen = run(checkpoint, panic).outcomeContext.value
      assert chosen.effectRequestFactCount.value == (if not panic or checkpoint: 1 else: 0)
  assert run(false, false, 0).outcomeContext.value.effectRequestFactCount.value == 0
  for i in 0..<25: discard recordAccumulationSolicit(source, hash, RequestLength(3), parameters()).value # Warm this exact immutable request capture/retirement path.
  let before = getOccupiedMem()
  for i in 0..<1000:
    # Refreshing full-capacity unique identity metadata must not add descriptors or retain old effect graphs.
    discard recordAccumulationSolicit(source, hash, RequestLength(3), parameters()).value
    discard recordAccumulationSolicit(birth.effects, hash, RequestLength(3), parameters()).value
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_request_identities", 1000, before, after)
  echo "accumulation-request-identities: ok"
try:
  main()
except:
  quit(2) # Unexpected source/setup failure cannot satisfy a guarded extraction probe.
