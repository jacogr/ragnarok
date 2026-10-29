# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native Psi_A/I bootstrap witnesses: compact bytes, bounded ID probing and posterior-entropy provenance.
## Hastur entry point verifies independent reference cases, retained owners and complete ARC release.

# @@Verification={"arc": "accumulation_invocation_arc_release"}

import std/[assertions, envvars, strutils, parseutils, syncio]
import ../../../src/state/accumulation/[invocation as accumulation_invocation,
    service as accumulation_service, inputs as accumulation_inputs,
    operands as accumulation_operands, round as accumulation_round, queue as accumulation_queue]
import ../../../src/state/report/admission as report_admission
import ../../../src/state/store
import ../../../src/codec/bounded
import ../../../src/codec/state/[safrole as state_safrole, privileges as state_privileges,
    workqueues as state_workqueues, accounts as state_accounts,
    service_values as state_service_values, layout as state_layout, trie as state_trie]
import ../../../src/codec/[composite, header, report_owned, c2_records]
import ../../../src/crypto/primitives
import ../../support/[report_context, report_admission_context, arc_evidence]

## Refuse only the maintained test crypto provider, after real fixture construction is complete.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

## All queue inputs use finite tiny-profile budgets, retaining the shared genuinely signed fixture semantics.
proc queueConfig(): AccumulationQueueConfig =
  AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(2), epochSlots: EpochSlots(12),
    perSlot: ElementLimit(100), totalItems: ElementLimit(100), perDependencies: ElementLimit(100),
    totalDependencies: ElementLimit(1000), reportBytes: ByteLimit(100000), maxBytes: ByteLimit(
        1000000)),
    items: ElementLimit(100), dependencies: ElementLimit(1000))

## Reuse independent operand/input ceilings for both service-only and signed report-driven preparations.
proc roundConfig(): AccumulationRoundConfig =
  AccumulationRoundConfig(blockGas: Gas(100), reportGas: Gas(0),
    privileges: PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(10),
        maxBytes: ByteLimit(1000)),
    operands: AccumulationOperandConfig(reports: ElementLimit(10), operands: ElementLimit(100),
        services: ElementLimit(100),
      totalBytes: ByteLimit(1000000), totalBlobBytes: ByteLimit(1000000),
      operand: OperandLimits(outputBytes: ByteLimit(100000), authBytes: ByteLimit(100000),
        totalBlobBytes: ByteLimit(200000), maxBytes: ByteLimit(1000000))),
    inputs: AccumulationInputConfig(inputs: ElementLimit(100), allowances: ElementLimit(10),
        services: ElementLimit(100)))

## Capture an existing service's eligible empty code and valid zero-allowance inputs through real APIs.
proc service(includeCode = true): PreparedAccumulationService =
  let queue = planAccumulationQueues([], newSeq[byte](12), newSeq[byte](12), HeaderSlot(0),
      queueConfig()).value
  let operands = prepareAccumulationOperands(queue, AccumulationReportPrefix(0), roundConfig().operands).value
  let inputs = prepareAccumulationInputs(operands, [], [AlwaysAccumulate(service: ServiceIndex(
      42))], roundConfig().inputs).value
  let raw = @[0'u8]
  let hash = array[32, byte](blake2b256(raw).value)
  var entries = @[serviceMetadataEntry(ServiceIndex(42), ServiceMetadata(codeHash: CodeHash(hash)),
      ByteLimit(ServiceMetadataBytes)).value]
  if includeCode:
    entries.add(servicePreimageEntry(ServiceIndex(42), ServicePreimageHash(hash), raw,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(
          1))).value) # Empty code after a valid zero metadata length.
  let state = newStateStore(entries, limits()).value.snapshot.value
  prepareAccumulationService(inputs, InvocationServiceIndex(0), state, HeaderSlot(128),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(0), preimageBytes: ByteLimit(1))).value

## Full-width fixture counts never pass through signed native parsing.
proc number(text: string): uint64 =
  var value = 0'u64
  assert parseBiggestUInt(text, value) == text.len
  value

## Copy fixed entropy transport into its nominal domain, never retaining a mutable source buffer.
proc word(text: string): StateEntropyWord =
  let raw = unhex(text)
  assert raw.len == 32
  var bytes = default(array[32, byte])
  for i in 0..<32: bytes[i] = raw[i] # Exact fixed width was proved before access.
  StateEntropyWord(bytes)

## Compare independent Blake2b seeds, full compact arguments and bounded membership-search outcomes.
proc projections() {.raises.} =
  var count = 0
  # Every row carries exact scalar/entropy inputs and an independently constructed occupied prefix.
  for line in readFile(getEnv("RAGNAROK_ACCUMULATION_INVOCATION")).splitLines:
    if line.len == 0: continue # Ignore only the final fixture newline.
    let f = line.splitWhitespace
    let id = ServiceIndex(uint32(number(f[0])))
    let slot = HeaderSlot(uint32(number(f[1])))
    assert accumulationArguments(slot, id, AccumulationArgumentCount(number(f[2]))) == unhex(f[5])
    let first = initialAccumulationService(id, word(f[3]), slot)
    assert first.error == AccumulationInvocationError.None and uint32(first.value) == uint32(number(f[4]))
    var entries: seq[StateEntry] = @[]
    if f[6] != "-":
      for item in f[6].split(','):
        entries.add(serviceMetadataEntry(ServiceIndex(uint32(number(item))), ServiceMetadata(),
            ByteLimit(ServiceMetadataBytes)).value) # Occupancy uses genuine metadata keys.
    let state = newStateStore(entries, limits()).value.snapshot.value
    let unused = findUnusedAccumulationService(state, first.value, ServiceProbeLimit(number(f[7])))
    if f[8] == "LimitExceeded":
      assert unused.error == AccumulationInvocationError.LimitExceeded # The final absence check consumes a probe too.
    else:
      assert unused.error == AccumulationInvocationError.None
      assert uint32(unused.value) == uint32(number(f[8]))
    inc count
  assert count == 384

## Exercise explicit wraparound, reserved endpoints, orphan entries and backend/default/result boundaries.
proc boundaries(): PreparedAccumulationInvocation =
  var entries: seq[StateEntry] = @[]
  # The final public ID wraps to the first; low and top-256 reserved intervals are never probed.
  for id in [PublicServiceEnd-1, FirstPublicService]:
    entries.add(serviceMetadataEntry(ServiceIndex(uint32(id)), ServiceMetadata(), ByteLimit(
        ServiceMetadataBytes)).value)
  let state = newStateStore(entries, limits()).value.snapshot.value
  assert uint32(findUnusedAccumulationService(state, ServiceIndex(uint32(PublicServiceEnd-1)),
      ServiceProbeLimit(3)).value) == uint32(FirstPublicService+1)
  assert findUnusedAccumulationService(state, ServiceIndex(uint32(PublicServiceEnd-1)),
      ServiceProbeLimit(2)).error == AccumulationInvocationError.LimitExceeded
  # Invalid domains fail before lookup rather than silently entering the public cycle.
  for id in [0'u64, FirstPublicService-1, PublicServiceEnd, uint64(high(uint32))]:
    assert findUnusedAccumulationService(state, ServiceIndex(uint32(id)), ServiceProbeLimit(
        1)).error == AccumulationInvocationError.InvalidIndex
  assert findUnusedAccumulationService(default(StateStoreSnapshot), ServiceIndex(uint32(
      FirstPublicService)), ServiceProbeLimit(1)).error == AccumulationInvocationError.InvalidState
  let ready = service()
  var entropy = default(array[32, byte])
  entropy[0] = 7
  let prepared = prepareAccumulationInvocation(ready, StateEntropyWord(entropy), ServiceProbeLimit(1)).value
  entropy[0] = 9
  assert array[32, byte](prepared.bootstrapInfo.value.entropy)[0] == 7
  var args = prepared.bootstrapArguments.value
  args[0] = args[0] xor 1
  assert prepared.bootstrapArguments.value == @[128'u8, 128, 42,
      0] # Compact slot 128, service 42, input count zero.
  assert prepared.bootstrapService.value.serviceCode.value.len == 0
  assert prepareAccumulationInvocation(ready, default(StateEntropyWord), ServiceProbeLimit(
      0)).error == AccumulationInvocationError.LimitExceeded
  assert prepareAccumulationInvocation(service(false), default(StateEntropyWord), ServiceProbeLimit(
      1)).error == AccumulationInvocationError.CodeUnavailable
  assert prepareAccumulationInvocation(default(PreparedAccumulationService), default(
      StateEntropyWord), ServiceProbeLimit(1)).error == AccumulationInvocationError.InvalidService
  failHash(1)
  assert prepareAccumulationInvocation(ready, default(StateEntropyWord), ServiceProbeLimit(
      1)).error == AccumulationInvocationError.BackendFailure
  failHash(0)
  let empty = default(PreparedAccumulationInvocation)
  assert empty.bootstrapInfo.error == AccumulationInvocationError.Uninitialized
  assert empty.bootstrapService.error == AccumulationInvocationError.Uninitialized
  assert empty.bootstrapArguments.error == AccumulationInvocationError.Uninitialized
  assert default(BlockAccumulationInvocation).bootstrapProjection.error ==
      AccumulationInvocationError.Uninitialized
  assert default(BlockAccumulationInvocation).bootstrapBlockService.error ==
      AccumulationInvocationError.Uninitialized
  assert prepareBlockAccumulationInvocation(default(BlockAccumulationService), ServiceProbeLimit(
      1)).error == AccumulationInvocationError.InvalidService
  # An orphan preimage does not establish an occupied account metadata key.
  let orphan = servicePreimageEntry(ServiceIndex(uint32(FirstPublicService)), default(
      ServicePreimageHash), [],
    ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(0))).value
  let orphanState = newStateStore([orphan], limits()).value.snapshot.value
  assert uint32(findUnusedAccumulationService(orphanState, ServiceIndex(uint32(FirstPublicService)),
      ServiceProbeLimit(1)).value) == uint32(FirstPublicService)
  result = prepared

## Derive entropy from the genuine posterior C(6); parent entropy is deliberately different.
proc boundCase(base: OwnedReport): PreparedAccumulationInvocation =
  let raw = @[0'u8]
  let hash = array[32, byte](blake2b256(raw).value)
  let code = servicePreimageEntry(ServiceIndex(42), ServicePreimageHash(hash), raw,
    ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1))).value
  let privileges = privilegeStateEntry(PrivilegeState(assigners: newSeq[ServiceIndex](2)),
      roundConfig().privileges).value
  var signedOptions0 = signedBlockFixtureConfig()
  signedOptions0.withAvailable = true
  signedOptions0.extra = @[privileges, code]
  signedOptions0.accountCode = raw
  let context = authored(base, signedOptions0)
  let admitted = planBlockReports(context.staged, context.older, config()).value
  let queue = planBlockAccumulationQueue(admitted, queueConfig()).value
  let round = planBlockInitialAccumulation(queue, roundConfig()).value
  let boundService = prepareBlockAccumulationService(round, InvocationServiceIndex(0),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(0), preimageBytes: ByteLimit(1))).value
  let prepared = prepareBlockAccumulationInvocation(boundService, ServiceProbeLimit(1)).value
  let posterior = decodeStateEntropy(context.staged.value.snapshot.lookup(chapterKey(StateChapter(
      6))).value.bytes).value.value[0]
  let parent = decodeStateEntropy(context.original.snapshot.value.lookup(chapterKey(StateChapter(
      6))).value.bytes).value.value[0]
  assert array[32, byte](posterior) != array[32, byte](parent)
  let pure = prepared.bootstrapProjection.value
  assert array[32, byte](pure.bootstrapInfo.value.entropy) == array[32, byte](posterior)
  assert pure.bootstrapArguments.value == @[2'u8, 42, 1]
  assert uint32(pure.bootstrapInfo.value.nextService) == uint32(initialAccumulationService(
      ServiceIndex(42), posterior, HeaderSlot(2)).value)
  assert prepared.bootstrapBlockService.value.serviceProjection.value.serviceInfo.error ==
      AccumulationServiceError.None
  result = pure

## Every success and probe-exhaustion exit releases all acyclic bootstrap storage.
proc lifetime() =
  let ready = service()
  discard prepareAccumulationInvocation(ready, default(StateEntropyWord), ServiceProbeLimit(1))
  discard prepareAccumulationInvocation(ready, default(StateEntropyWord), ServiceProbeLimit(0))
  let before = getOccupiedMem()
  # No identifier reservation, retained scratch or copied arguments survive each discarded result.
  for i in 0..<1000:
    assert prepareAccumulationInvocation(ready, default(StateEntropyWord), ServiceProbeLimit(
        1)).error == AccumulationInvocationError.None
    assert prepareAccumulationInvocation(ready, default(StateEntropyWord), ServiceProbeLimit(
        0)).error == AccumulationInvocationError.LimitExceeded
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_invocation", 1000, before, after)

## Execute all assertions and retain source inputs past every block-context local scope.
proc main() {.raises.} =
  projections()
  let retained = boundaries()
  assert retained.bootstrapService.value.serviceCode.value.len == 0
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i]) # Preserve binary fixture bytes without text conversion.
  let bound = boundCase(decodeOwnedReport(bytes, 2).value)
  assert bound.bootstrapService.value.serviceInputAt(InvocationInputIndex(0)).value.kind ==
      AccumulationKind.Operand
  lifetime()
  echo "PASS accumulation invocation: compact arguments, bounded ID search, posterior entropy and ARC"
try:
  main() # Run the entire focused suite through Hastur.
except:
  quit(2) # Missing transport or unexpected exceptions remain failing executions.
