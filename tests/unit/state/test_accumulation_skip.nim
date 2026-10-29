# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native non-executing Psi_A outcomes: independent envelope gates, exact unchanged state and zero/empty effects.
## Hastur entry point checks signed provenance, source replacement, strict refusal and complete ARC release.

# @@Verification={"arc": "accumulation_skip_arc_release"}

import std/[assertions, envvars, strutils, parseutils, syncio]
import ../../../src/state/accumulation/[skip as accumulation_skip, service as accumulation_service,
    round as accumulation_round, inputs as accumulation_inputs, operands as accumulation_operands,
    queue as accumulation_queue]
import ../../../src/state/report/admission as report_admission
import ../../../src/state/store
import ../../../src/codec/[bounded, composite]
import ../../../src/codec/work/digest as work_digest
import ../../../src/codec/state/[accounts as state_accounts, privileges as state_privileges,
    service_values as state_service_values, trie as state_trie, layout as state_layout,
    workqueues as state_workqueues]
import ../../../src/codec/[header, report_owned, c2_records]
import ../../../src/crypto/primitives
import ../../support/[report_context, report_admission_context, arc_evidence]

## Refuse provider hashing only after certified service construction, proving outcome construction does no hashing.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

## Independent local operand/input ceilings bound the authored service-only and report-driven contexts.
proc roundConfig(): AccumulationRoundConfig =
  AccumulationRoundConfig(blockGas: Gas(100), reportGas: Gas(0),
    privileges: PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(10),
        maxBytes: ByteLimit(1000)),
    operands: AccumulationOperandConfig(reports: ElementLimit(10), operands: ElementLimit(100),
      services: ElementLimit(100), totalBytes: ByteLimit(1000000), totalBlobBytes: ByteLimit(
          1000000),
      operand: OperandLimits(outputBytes: ByteLimit(100000), authBytes: ByteLimit(100000),
        totalBlobBytes: ByteLimit(200000), maxBytes: ByteLimit(1000000))),
    inputs: AccumulationInputConfig(inputs: ElementLimit(100), allowances: ElementLimit(10),
        services: ElementLimit(100)))

## Match the genuinely signed tiny-profile queue chapters without weakening their independent local limits.
proc queueConfig(): AccumulationQueueConfig =
  AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(2), epochSlots: EpochSlots(12),
    perSlot: ElementLimit(100), totalItems: ElementLimit(100), perDependencies: ElementLimit(100),
    totalDependencies: ElementLimit(1000), reportBytes: ByteLimit(100000), maxBytes: ByteLimit(
        1000000)),
    items: ElementLimit(100), dependencies: ElementLimit(1000))

## A zero-allowance service has no operands but still receives a legitimate prepared invocation.
proc inputs(gas = 0'u64): PreparedAccumulationInputs =
  let queue = planAccumulationQueues([], newSeq[byte](12), newSeq[byte](12), HeaderSlot(0),
      queueConfig()).value
  let operand = prepareAccumulationOperands(queue, AccumulationReportPrefix(0), roundConfig().operands).value
  prepareAccumulationInputs(operand, [], [AlwaysAccumulate(service: ServiceIndex(42),
      gas: PrivilegeGas(gas))],
    roundConfig().inputs).value

## Store raw preimages through the genuine namespace constructor; hash identity is computed independently of lookup.
proc entries(raw: seq[byte], includeCode = true): seq[StateEntry] =
  let hash = array[32, byte](blake2b256(raw).value)
  # These account fields must not become extra invocation-time balance/minimum-gas eligibility filters.
  let account = ServiceMetadata(codeHash: CodeHash(hash), balance: AccountBalance(0),
    minimumAccumulationGas: Gas(high(uint64)), minimumTransferGas: Gas(high(uint64)),
    created: AccountSlot(7), lastAccumulation: AccountSlot(8), parent: ServiceIndex(9))
  result = @[serviceMetadataEntry(ServiceIndex(42), account, ByteLimit(ServiceMetadataBytes)).value,
    serviceMetadataEntry(ServiceIndex(99), ServiceMetadata(balance: AccountBalance(123)), ByteLimit(
        ServiceMetadataBytes)).value,
    StateEntry(key: chapterKey(StateChapter(250)), value: @[9'u8, 4, 2])]
  if includeCode:
    result.add(servicePreimageEntry(ServiceIndex(42), ServicePreimageHash(hash), raw,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(
          100000))).value) # Complete raw value, without added framing.

## Build a complete authored map; ordinary unit fixtures are not claims of full chain STF execution.
proc snapshot(source: seq[StateEntry]): StateStoreSnapshot = newStateStore(source, limits()).value.snapshot.value

## Trusted decimal transport carries local lengths only, with an explicit parse-success assertion.
proc number(text: string): uint64 =
  var value = 0'u64
  assert parseBiggestUInt(text, value) == text.len
  value

## Assert complete unchanged source identity and every protocol no-execution outcome field.
proc checkSkip(outcome: SkippedAccumulation, source: PreparedAccumulationService) =
  let info = outcome.skipInfo.value
  let original = source.serviceInfo.value
  assert uint32(info.service) == uint32(original.service) and uint32(info.slot) == uint32(original.slot)
  assert info.code == original.code and info.code != AccumulationCodeStatus.Ready
  assert uint64(info.gasUsed) == 0 and info.transfers == 0 and info.provisions == 0 and
      not info.hasYield
  assert array[32, byte](outcome.skipState.value.commitment.root) == array[32, byte](
      source.serviceState.value.commitment.root)
  let account = chapterServiceKey(StateChapter(255), original.service)
  assert outcome.skipState.value.lookup(account).value.bytes == source.serviceState.value.lookup(
      account).value.bytes
  assert outcome.skipService.value.serviceInfo.value.code == original.code
  var copied = info
  copied.gasUsed = Gas(123)
  assert uint64(outcome.skipInfo.value.gasUsed) == 0

## Replay every independent code-envelope/protocol/resource witness without inventing a second interpretation.
proc projections() {.raises.} =
  let selected = inputs()
  var count = 0
  var skipped = 0
  var required = 0
  var refused = 0
  # Each independent row specifies the exact code status or preparation refusal before outcome selection.
  for line in readFile(getEnv("RAGNAROK_ACCUMULATION_SERVICE")).splitLines:
    if line.len == 0: continue # Only the final transport newline is ignored.
    let f = line.splitWhitespace
    let raw = unhex(f[3])
    let prepared = prepareAccumulationService(selected, InvocationServiceIndex(0), snapshot(entries(raw)),
      HeaderSlot(123), AccumulationServiceConfig(codeLimit: ServiceCodeLimit(number(f[1])),
          preimageBytes: ByteLimit(number(f[2]))))
    if f[4] == "LimitExceeded":
      assert prepared.error == AccumulationServiceError.LimitExceeded # Local exhaustion cannot yield a skipped success.
      inc refused
    else:
      assert prepared.error == AccumulationServiceError.None
      let service = prepared.value
      assert $service.serviceInfo.value.code == f[4]
      let completed = finishUninvokedAccumulation(service)
      if f[4] == "Ready":
        assert completed.error == AccumulationSkipError.ExecutionRequired # Empty programs are included in Ready.
        inc required
      else:
        assert completed.error == AccumulationSkipError.None
        checkSkip(completed.value, service)
        assert completed.value.skipState.value.lookup(chapterKey(StateChapter(250))).value.bytes ==
            @[9'u8, 4, 2]
        inc skipped
    inc count
  assert count == 408 and skipped > 0 and required > 0 and refused > 0

## Resolve explicit source cases while preserving the offered gas independently of actual gas usage.
proc service(raw: seq[byte], present: bool, codeLimit: uint64,
    gas = 0'u64): PreparedAccumulationService =
  prepareAccumulationService(inputs(gas), InvocationServiceIndex(0), snapshot(entries(raw,
      present)), HeaderSlot(77),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(codeLimit), preimageBytes: ByteLimit(100000))).value

## Cover absence, malformed code, exact/over code limits, offered-gas extremes and default extraction boundaries.
proc boundaries(): SkippedAccumulation =
  result = default(SkippedAccumulation) # Initialize before loop-carried assignment under Nimony.
  # Protocol outcomes are independent of the unspent offered gas and account minimums/balance.
  for gas in [0'u64, high(uint64)]:
    let missing = service(@[0'u8], false, 0, gas)
    let malformed = service(@[128'u8], true, 0, gas)
    let oversized = service(@[0'u8, 7], true, 0, gas)
    for source in [missing, malformed, oversized]:
      assert uint64(source.serviceInfo.value.gas) == gas
      let outcome = finishUninvokedAccumulation(source).value
      checkSkip(outcome, source)
      let state = outcome.skipState.value
      assert uint64(decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255),
          ServiceIndex(99))).value.bytes,
        ByteLimit(ServiceMetadataBytes)).value.metadata.balance) == 123
      var bytes = state.lookup(chapterKey(StateChapter(250))).value.bytes
      bytes[0] = 255
      assert state.lookup(chapterKey(StateChapter(250))).value.bytes == @[9'u8, 4, 2]
    assert missing.serviceInfo.value.code == AccumulationCodeStatus.Missing
    assert malformed.serviceInfo.value.code == AccumulationCodeStatus.Malformed
    assert oversized.serviceInfo.value.code == AccumulationCodeStatus.Oversized
    result = finishUninvokedAccumulation(missing).value
  # Valid empty and exact-limit nonempty code both require execution, not an empty-code fallback.
  for source in [service(@[0'u8], true, 0), service(@[0'u8, 7], true, 1)]:
    assert finishUninvokedAccumulation(source).error == AccumulationSkipError.ExecutionRequired
  assert finishUninvokedAccumulation(default(PreparedAccumulationService)).error ==
      AccumulationSkipError.InvalidService
  assert finishBlockUninvokedAccumulation(default(BlockAccumulationService)).error ==
      AccumulationSkipError.InvalidService
  let empty = default(SkippedAccumulation)
  assert empty.skipInfo.error == AccumulationSkipError.Uninitialized
  assert empty.skipState.error == AccumulationSkipError.Uninitialized
  assert empty.skipService.error == AccumulationSkipError.Uninitialized
  assert default(BlockSkippedAccumulation).skipProjection.error ==
      AccumulationSkipError.Uninitialized
  assert default(BlockSkippedAccumulation).skipBlockService.error ==
      AccumulationSkipError.Uninitialized
  let ready = service(@[0'u8], true, 0)
  let missing = result.skipService.value
  failHash(1)
  checkSkip(finishUninvokedAccumulation(missing).value, missing)
  assert finishUninvokedAccumulation(ready).error == AccumulationSkipError.ExecutionRequired
  failHash(0)

## Genuine block certificates select each non-executing code gate without reading entropy or constructing I.
proc boundCase(base: OwnedReport): BlockSkippedAccumulation =
  result = default(BlockSkippedAccumulation) # Every return path owns an explicitly initialized handle.
  # Each case is signed against its actual account code hash; no code/preimage identity is forged.
  for mode in 0..<4:
    let raw = if mode == 1: @[128'u8] else: @[0'u8, 7] # One malformed envelope versus a real one-byte program.
    let hash = array[32, byte](blake2b256(raw).value)
    var extra = @[privilegeStateEntry(PrivilegeState(assigners: newSeq[ServiceIndex](2)),
        roundConfig().privileges).value]
    if mode != 0:
      extra.add(servicePreimageEntry(ServiceIndex(42), ServicePreimageHash(hash), raw,
        ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(
            100000))).value) # Mode zero intentionally has no code preimage.
    var signedOptions0 = signedBlockFixtureConfig()
    signedOptions0.withAvailable = true
    signedOptions0.extra = extra
    signedOptions0.accountCode = raw
    let context = authored(base, signedOptions0)
    let admitted = planBlockReports(context.staged, context.older, config()).value
    let queue = planBlockAccumulationQueue(admitted, queueConfig()).value
    let round = planBlockInitialAccumulation(queue, roundConfig()).value
    let limit = if mode == 3: 1'u64 else: 0'u64 # Final case proves the exact-size bound still requires execution.
    let bound = prepareBlockAccumulationService(round, InvocationServiceIndex(0),
      AccumulationServiceConfig(codeLimit: ServiceCodeLimit(limit), preimageBytes: ByteLimit(100000))).value
    let outcome = finishBlockUninvokedAccumulation(bound)
    if mode == 3:
      assert outcome.error == AccumulationSkipError.ExecutionRequired # A bound certificate cannot turn Ready into skip.
    else:
      assert outcome.error == AccumulationSkipError.None
      let pure = outcome.value.skipProjection.value
      checkSkip(pure, bound.serviceProjection.value)
      assert uint32(pure.skipInfo.value.slot) == 2
      assert pure.skipService.value.serviceInputAt(InvocationInputIndex(0)).value.kind ==
          AccumulationKind.Operand
      assert array[32, byte](pure.skipState.value.commitment.root) == array[32, byte](
          context.original.snapshot.value.commitment.root)
      # Replacing a caller-owned store does not mutate the retained outcome map or source certificate.
      var replacement = context.original
      discard replacement.apply([StateWrite(key: chapterKey(StateChapter(250)),
          kind: StateWriteKind.Put, value: @[255'u8])]).value
      assert pure.skipState.value.lookup(chapterKey(StateChapter(250))).value.bytes == @[9'u8, 4, 2]
      assert outcome.value.skipBlockService.value.serviceBlockRound.error ==
          AccumulationServiceError.None
      result = outcome.value

## Repeated complete/refused outcome construction releases every acyclic owner without touching source state.
proc lifetime() =
  let sources = [service(@[0'u8], false, 0), service(@[128'u8], true, 0), service(@[0'u8, 7], true, 0)]
  let ready = service(@[0'u8], true, 0)
  for source in sources: discard finishUninvokedAccumulation(
      source) # Warm every successful branch before measurement.
  discard finishUninvokedAccumulation(ready)
  let before = getOccupiedMem()
  # No root, argument, identifier-probe or effect buffers survive each discarded initial outcome.
  for i in 0..<1000:
    for source in sources: assert finishUninvokedAccumulation(source).error ==
        AccumulationSkipError.None # Every unavailable-code reason releases its owner.
    assert finishUninvokedAccumulation(ready).error == AccumulationSkipError.ExecutionRequired
    assert finishUninvokedAccumulation(default(PreparedAccumulationService)).error ==
        AccumulationSkipError.InvalidService
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_skip", 1000, before, after)

## Run every native assertion and use retained children after all construction locals disappear.
proc main() {.raises.} =
  projections()
  let retained = boundaries()
  assert retained.skipInfo.value.code == AccumulationCodeStatus.Missing
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i]) # Preserve exact pinned binary report bytes.
  let bound = boundCase(decodeOwnedReport(bytes, 2).value)
  assert bound.skipProjection.value.skipService.value.serviceInputAt(InvocationInputIndex(
      0)).value.kind == AccumulationKind.Operand
  lifetime()
  echo "PASS accumulation skip: certified code gates, zero effects, unchanged state and ARC"
try:
  main() # Execute all independent and signed cases through Hastur.
except:
  quit(2) # Missing fixtures or unexpected exceptions remain failing executions.
