# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native accounts/Psi_A entry-gate tests: independent envelopes, immutable inputs and bound parent/slot.
## Hastur entry point covers refusal boundaries, backend failures and ARC release without executing a PVM.

# @@Verification={"arc": "accumulation_service_arc_release"}

import std/assertions
import std/envvars
import std/strutils
import std/parseutils
import std/syncio
import ../../../src/state/accumulation_service as state_accumulation_service
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_operands as state_accumulation_operands
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/work_digest as codec_work_digest
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_privileges as codec_state_privileges
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../../src/codec/header as codec_header
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/c2_records as codec_c2_records
import ../../../src/crypto/primitives as crypto_primitives
import ../../support/state_report_context
import ../../support/state_report_admission_context
import ../../support/testing_arc_evidence

## Fail the maintained crypto observer only after constructing genuine state fixtures.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Reject a later hash to distinguish namespace-key and preimage-content backend failures.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Count attempts to prove local byte preflight precedes complete preimage hashing.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

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
proc inputs(): PreparedAccumulationInputs =
  let queue = planAccumulationQueues([], newSeq[byte](12), newSeq[byte](12), HeaderSlot(0),
      queueConfig()).value
  let operand = prepareAccumulationOperands(queue, AccumulationReportPrefix(0), roundConfig().operands).value
  prepareAccumulationInputs(operand, [], [AlwaysAccumulate(service: ServiceIndex(42),
      gas: PrivilegeGas(0))],
    roundConfig().inputs).value

## Store raw preimages through the genuine namespace constructor; hash identity is computed independently of lookup.
proc entries(raw: seq[byte], includeCode = true): seq[StateEntry] =
  let hash = array[32, byte](blake2b256(raw).value)
  # These account fields must not become extra invocation-time balance/minimum-gas eligibility filters.
  let account = ServiceMetadata(codeHash: CodeHash(hash), balance: AccountBalance(0),
    minimumAccumulationGas: Gas(high(uint64)), minimumTransferGas: Gas(high(uint64)),
    created: AccountSlot(7), lastAccumulation: AccountSlot(8), parent: ServiceIndex(9))
  result = @[serviceMetadataEntry(ServiceIndex(42), account, ByteLimit(ServiceMetadataBytes)).value]
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

## Replay independently framed metadata/code suffixes and protocol versus local-limit verdicts.
proc projections() {.raises.} =
  let source = inputs()
  var count = 0
  # Every row carries independent raw bytes and protocol/resource gate expectations.
  for line in readFile(getEnv("RAGNAROK_ACCUMULATION_SERVICE")).splitLines:
    if line.len == 0: continue # Ignore only the final fixture transport newline.
    let f = line.splitWhitespace
    let raw = unhex(f[3])
    let context = prepareAccumulationService(source, InvocationServiceIndex(0), snapshot(entries(raw)),
      HeaderSlot(123), AccumulationServiceConfig(codeLimit: ServiceCodeLimit(number(f[1])),
          preimageBytes: ByteLimit(number(f[2]))))
    if f[4] == "LimitExceeded":
      assert context.error == AccumulationServiceError.LimitExceeded # No resource refusal becomes unavailable-code success.
    else:
      assert context.error == AccumulationServiceError.None, f[0] & " " & $context.error
      let owner = context.value
      let info = owner.serviceInfo.value
      assert $info.code == f[4]
      assert uint32(info.service) == 42 and uint32(info.slot) == 123 and uint64(info.gas) == 0
      assert uint64(info.account.minimumAccumulationGas) == high(uint64) and uint64(
          info.account.balance) == 0
      assert info.operands == 0 and info.transfers == 0
      if info.code == AccumulationCodeStatus.Ready:
        var code = owner.serviceCode.value
        assert code == unhex(f[5]) and info.codeBytes == code.len
        if code.len != 0:
          code[0] = code[0] xor 1 # Mutable extraction is an independent copy.
          assert owner.serviceCode.value == unhex(f[5])
      else:
        assert owner.serviceCode.error == AccumulationServiceError.CodeUnavailable # Unavailable code cannot fabricate a valid empty blob.
        if info.code == AccumulationCodeStatus.Oversized:
          assert info.codeBytes == unhex(f[5]).len # Size counts only code after metadata.
    inc count
  assert count == 408

## Refuse invalid sources, hostile indices and corrupt state; ordinary absent code retains the actual account.
proc boundaries(): PreparedAccumulationService =
  let source = inputs()
  let config = AccumulationServiceConfig(codeLimit: ServiceCodeLimit(1), preimageBytes: ByteLimit(100000))
  var records = entries(@[0'u8, 7])
  let state = snapshot(records)
  let owner = prepareAccumulationService(source, InvocationServiceIndex(0), state, HeaderSlot(3), config).value
  records[1].value[1] = 9
  assert owner.serviceCode.value == @[7'u8] # Caller state-entry mutation cannot alter owned code.
  assert owner.serviceInputAt(InvocationInputIndex(high(uint64))).error ==
      AccumulationServiceError.InvalidIndex
  assert prepareAccumulationService(source, InvocationServiceIndex(high(uint64)), state, HeaderSlot(
      3), config).error == AccumulationServiceError.InvalidIndex
  assert prepareAccumulationService(default(PreparedAccumulationInputs), InvocationServiceIndex(0),
      state, HeaderSlot(3), config).error == AccumulationServiceError.InvalidInputs
  assert prepareAccumulationService(source, InvocationServiceIndex(0), default(StateStoreSnapshot),
      HeaderSlot(3), config).error == AccumulationServiceError.InvalidState
  assert prepareAccumulationService(source, InvocationServiceIndex(0), snapshot(@[]), HeaderSlot(3),
      config).error == AccumulationServiceError.MissingAccount
  let missing = prepareAccumulationService(source, InvocationServiceIndex(0), snapshot(entries(@[
      0'u8], false)), HeaderSlot(3), config).value
  assert missing.serviceInfo.value.code == AccumulationCodeStatus.Missing
  assert missing.serviceCode.error == AccumulationServiceError.CodeUnavailable
  # Malformed fixed metadata may not be normalized or treated as an absent account.
  for mode in 0..<3:
    var damaged = entries(@[0'u8, 7])
    case mode
    of 0: damaged[0].value.setLen(88) # Truncated fixed record.
    of 1: damaged[0].value.add(0) # Suffix after the fixed version-zero schema.
    else: damaged[0].value[0] = 1 # Unknown account schema version.
    assert prepareAccumulationService(source, InvocationServiceIndex(0), snapshot(damaged),
        HeaderSlot(3), config).error == AccumulationServiceError.MalformedAccount
  var corrupted = entries(@[0'u8, 7])
  corrupted[1].value[1] = 8
  assert prepareAccumulationService(source, InvocationServiceIndex(0), snapshot(corrupted),
      HeaderSlot(3), config).error == AccumulationServiceError.InvalidState
  # Both namespace derivation and complete-preimage hashing failures remain backend refusals.
  for successful in 0..1:
    hashAfter(cint(successful))
    assert prepareAccumulationService(source, InvocationServiceIndex(0), state, HeaderSlot(3),
        config).error == AccumulationServiceError.BackendFailure
    failHash(0)
  var limited = config
  limited.preimageBytes = ByteLimit(1)
  assert prepareAccumulationService(source, InvocationServiceIndex(0), state, HeaderSlot(3),
      limited).error == AccumulationServiceError.LimitExceeded
  assert hashCalls() == 1 # Namespace hash is required for lookup; oversized value bytes are never hashed.
  failHash(0)
  let transferred = prepareAccumulationInputs(source.invocationOperands.value,
    [DeferredTransfer(destination: ServiceIndex(42))], [], roundConfig().inputs).value
  assert prepareAccumulationService(transferred, InvocationServiceIndex(0), state, HeaderSlot(3),
      config).error == AccumulationServiceError.None # Zero transfers are valid and preserve the balance.
  assert array[32, byte](owner.serviceState.value.commitment.root) == array[32, byte](
      state.commitment.root)
  let empty = default(PreparedAccumulationService)
  assert empty.serviceInfo.error == AccumulationServiceError.Uninitialized
  assert empty.serviceCode.error == AccumulationServiceError.Uninitialized
  assert empty.serviceState.error == AccumulationServiceError.Uninitialized
  assert empty.serviceInputAt(InvocationInputIndex(0)).error ==
      AccumulationServiceError.Uninitialized
  assert default(BlockAccumulationService).serviceProjection.error ==
      AccumulationServiceError.Uninitialized
  assert default(BlockAccumulationService).serviceBlockRound.error ==
      AccumulationServiceError.Uninitialized
  assert prepareBlockAccumulationService(default(BlockAccumulationRound), InvocationServiceIndex(0),
      config).error == AccumulationServiceError.InvalidRound
  result = owner

## Signed block fixtures bind source accounts to parent state and derive the actual candidate slot.
proc boundCase(base: OwnedReport): InvocationInput =
  let raw = @[1'u8, 99, 7]
  let codeEntries = entries(raw)
  let privileges = privilegeStateEntry(PrivilegeState(assigners: newSeq[ServiceIndex](2), always: @[
    ]), roundConfig().privileges).value
  # Recompute signed report code identity and parent account metadata together for real policy admission.
  var signedOptions0 = signedBlockFixtureConfig()
  signedOptions0.withAvailable = true
  signedOptions0.extra = @[privileges, codeEntries[1]]
  signedOptions0.accountCode = raw
  let context = authored(base, signedOptions0)
  let bound = planBlockAccumulationQueue(planBlockReports(context.staged, context.older, config(
    )).value, queueConfig()).value
  let round = planBlockInitialAccumulation(bound, roundConfig()).value
  let prepared = prepareBlockAccumulationService(round, InvocationServiceIndex(0),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(1), preimageBytes: ByteLimit(3)))
  assert prepared.error == AccumulationServiceError.None
  let service = prepared.value.serviceProjection.value
  assert uint32(service.serviceInfo.value.slot) == 2
  assert uint64(service.serviceInfo.value.gas) == 10
  assert service.serviceCode.value == @[7'u8]
  assert prepared.value.serviceBlockRound.value.roundProjection.value.roundInfo.error ==
      AccumulationRoundError.None
  result = service.serviceInputAt(InvocationInputIndex(0)).value

## Repeated success/refusal releases copied code, context and retained references completely.
proc lifetime() =
  let source = inputs()
  let state = snapshot(entries(@[0'u8, 7]))
  let config = AccumulationServiceConfig(codeLimit: ServiceCodeLimit(1), preimageBytes: ByteLimit(2))
  let refused = AccumulationServiceConfig(codeLimit: ServiceCodeLimit(1), preimageBytes: ByteLimit(1))
  discard prepareAccumulationService(source, InvocationServiceIndex(0), state, HeaderSlot(2), config)
  discard prepareAccumulationService(source, InvocationServiceIndex(0), state, HeaderSlot(2), refused)
  let before = getOccupiedMem()
  # All scratch, copied code and shared owners must leave scope on both exits.
  for i in 0..<1000:
    assert prepareAccumulationService(source, InvocationServiceIndex(0), state, HeaderSlot(2),
        config).error == AccumulationServiceError.None
    assert prepareAccumulationService(source, InvocationServiceIndex(0), state, HeaderSlot(2),
        refused).error == AccumulationServiceError.LimitExceeded
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_accumulation_service", 1000, before, after)

## Run native assertions and retain child data after all source scopes end.
proc main() {.raises.} =
  projections()
  let retained = boundaries()
  assert retained.serviceCode.value == @[7'u8]
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for i in 0..<raw.len: wire[i] = byte(raw[i]) # Preserve exact binary fixture octets.
  let input = boundCase(decodeOwnedReport(wire, 2).value)
  assert input.kind == AccumulationKind.Operand and operandInfo(input.operand).error ==
      RecordError.None
  lifetime()
  echo "PASS accumulation service: code gate, parent/slot binding, immutable inputs, bounds and ARC"
try:
  main() # Exercise every assertion through the supported native runner.
except:
  quit(2) # I/O and unexpected exceptions remain test failures.
