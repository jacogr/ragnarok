# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native initial-accseq tests: independent prefixes/service bytes, gas boundaries and parent binding.
## Hastur entry point checks immutable retention, bounded refusals and complete ARC release.

# @@Verification={"arc": "accumulation_round_arc_release"}

import std/[assertions, envvars, strutils, parseutils, syncio]
import ../../../src/state/[accumulation_round, accumulation_inputs, accumulation_operands,
  accumulation_queue, report_admission, store]
import ../../../src/codec/[bounded, composite, header, work_digest, report_owned,
  c2_records, state_workqueues, state_privileges, state_layout, state_trie]
import ../../support/[report_context, report_admission_context, arc_evidence]

## Finite local budgets independently bound parent decoding, traversal and materialized service inputs.
proc cfg(cores = 2'u64): AccumulationRoundConfig =
  AccumulationRoundConfig(reportGas: Gas(0), blockGas: Gas(100),
    privileges: PrivilegeConfig(cores: CoreCount(cores), maxAlways: ElementLimit(1000),
      maxBytes: ByteLimit(100000)),
    operands: AccumulationOperandConfig(reports: ElementLimit(1000), operands: ElementLimit(16000),
      services: ElementLimit(16000), totalBytes: ByteLimit(10000000),
      totalBlobBytes: ByteLimit(10000000), operand: OperandLimits(outputBytes: ByteLimit(100000),
        authBytes: ByteLimit(100000), totalBlobBytes: ByteLimit(200000), maxBytes: ByteLimit(
            1000000))),
    inputs: AccumulationInputConfig(inputs: ElementLimit(16000), allowances: ElementLimit(1000),
      services: ElementLimit(16000)))

## Queue policy matches each explicit fixture's core and epoch profile.
proc queueConfig(cores = 2'u64, slots = 12'u64): AccumulationQueueConfig =
  AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(cores),
    epochSlots: EpochSlots(slots), perSlot: ElementLimit(10000), totalItems: ElementLimit(10000),
    perDependencies: ElementLimit(80000), totalDependencies: ElementLimit(80000),
    reportBytes: ByteLimit(1000000), maxBytes: ByteLimit(10000000)),
    items: ElementLimit(10000), dependencies: ElementLimit(80000))

## Capture complete canonical C(12) bytes through the real codec, never forge a valid snapshot.
proc entry(allowances: seq[AlwaysAccumulate], cores = 2'u64): StateEntry =
  privilegeStateEntry(PrivilegeState(manager: ServiceIndex(77), assigners: newSeq[ServiceIndex](
    int(cores)), always: allowances), cfg(cores).privileges).value

## Decode a complete authored privilege owner; arrays are not exposed by the resulting handle.
proc privileges(allowances: seq[AlwaysAccumulate], cores = 2'u64): PrivilegeSnapshot =
  decodePrivilegeState(entry(allowances, cores).value, cfg(cores).privileges).value.snapshot

## Construct a valid pure priority queue, including the empty case, from immutable report owners.
proc queue(reports: openArray[OwnedReport]): AccumulationQueuePlan =
  planAccumulationQueues(reports, newSeq[byte](12), newSeq[byte](12), HeaderSlot(0), queueConfig()).value

## Full unsigned fixture transport must never narrow gas through a signed native integer.
proc number(text: string): uint64 =
  var value = 0'u64
  assert parseBiggestUInt(text, value) == text.len
  value

## Compare complete C.2 operands, not just counts or gas, against independent oracle output.
proc bytes(input: InvocationInput): seq[byte] =
  assert input.kind == AccumulationKind.Operand
  let owner = input.operand
  result = newSeq[byte](operandInfo(owner).value.consumed)
  assert encodeOwnedOperand(owner, cfg().operands.operand, result).value == result.len

## Replay exhaustive-prefix expectations over unchanged pinned inputs and authored gas-boundary reports.
proc projections() {.raises.} =
  var total = 0
  var refused = 0
  # Each record includes the original queue chapters, explicit gas policy and sorted allowance dictionary.
  for line in readFile(getEnv("RAGNAROK_ACCUMULATION_ROUND")).splitLines:
    if line.len == 0: continue # Only the final transport newline is ignored.
    let f = line.splitWhitespace
    var reports: seq[OwnedReport] = @[]
    if f[6] != "-":
      for raw in f[6].split(','):
        reports.add(decodeOwnedReport(unhex(raw), number(f[1])).value) # Keep the full exact report wire.
    let source = planAccumulationQueues(reports, unhex(f[4]), unhex(f[5]), HeaderSlot(number(f[3])),
      queueConfig(number(f[1]), number(f[2]))).value
    var allowances: seq[AlwaysAccumulate] = @[]
    if f[9] != "-":
      for raw in f[9].split(','):
        let pair = raw.split(':') # Trusted sorted transport, validated again by the real C(12) codec.
        allowances.add(AlwaysAccumulate(service: ServiceIndex(uint32(number(pair[0]))),
          gas: PrivilegeGas(number(pair[1]))))
    var config = cfg(number(f[1]))
    config.reportGas = Gas(number(f[7]))
    config.blockGas = Gas(number(f[8]))
    let outcome = planInitialAccumulation(source, privileges(allowances, number(f[1])), config)
    if f[10] == "overflow":
      assert outcome.error == AccumulationRoundError.GasOverflow, f[0] # No wrapped initial budget.
      inc refused
    else:
      assert outcome.error == AccumulationRoundError.None, f[0] & " " & $outcome.error
      let plan = outcome.value
      let expected = f[10].split(',')
      let info = plan.roundInfo.value
      assert uint64(info.budget) == number(expected[0])
      assert uint64(info.allowanceGas) == number(expected[1])
      assert uint64(info.prefix) == number(expected[2])
      assert uint64(info.reportGas) == number(expected[3])
      assert info.dispatch == (number(expected[4]) != 0)
      let inputs = plan.roundInputs.value
      let groups = if f[11] == "-": newSeq[string](0) else: f[11].split(';') # Valid empty union.
      assert inputs.invocationServiceCount.value == groups.len
      assert uint64(inputs.invocationOperands.value.operandReportPrefix.value) == uint64(info.prefix)
      # Every service receives the exact selected report operands and its initial allowance, without transfers.
      for i in 0..<groups.len:
        let fields = groups[i].split(':')
        let service = inputs.invocationServiceAt(InvocationServiceIndex(i)).value
        assert uint32(service.service) == uint32(number(fields[0]))
        assert uint64(service.gas) == number(fields[1])
        assert service.transfers == 0
        let items = if fields[2] == "-": newSeq[string](0) else: fields[2].split(',') # Privilege-only service.
        assert service.operands == items.len
        # Exact C.2 equality verifies source identity, digest order and all success/error alternatives.
        for j in 0..<items.len:
          assert bytes(inputs.invocationInputAt(InvocationServiceIndex(i), InvocationInputIndex(
              j)).value) ==
            unhex(items[j]), f[0]
    inc total
  assert total == 670 and refused == 134

## Literal exact-fit and refusal tests isolate gas-domain arithmetic, prefix priority and each work ceiling.
proc boundaries(base: OwnedReport): InitialAccumulationRound =
  let empty = queue([])
  let noFree = privileges(@[])
  var config = cfg()
  config.blockGas = Gas(0)
  let stopped = planInitialAccumulation(empty, noFree, config).value
  assert not stopped.roundInfo.value.dispatch
  let zero = privileges(@[AlwaysAccumulate(service: ServiceIndex(9), gas: PrivilegeGas(0))])
  let active = planInitialAccumulation(empty, zero, config).value
  assert active.roundInfo.value.dispatch
  assert active.roundInputs.value.invocationServiceCount.value == 1
  # A rejected positive-cost report blocks the zero-cost report following it.
  let source = queue([reportFor(base, 0, [0'u64]), reportFor(base, 1, [10'u64]),
    reportFor(base, 0, [0'u64])])
  config.blockGas = Gas(9)
  assert uint64(planInitialAccumulation(source, noFree, config).value.roundInfo.value.prefix) == 1
  config.blockGas = Gas(10)
  assert uint64(planInitialAccumulation(source, noFree, config).value.roundInfo.value.prefix) == 3
  # Even a mathematical digest sum above uint64 simply makes its whole report unaffordable.
  let large = queue([reportFor(base, 0, [high(uint64), 1'u64])])
  config.blockGas = Gas(high(uint64))
  assert uint64(planInitialAccumulation(large, noFree, config).value.roundInfo.value.prefix) == 0
  let maximum = privileges(@[AlwaysAccumulate(service: ServiceIndex(9), gas: PrivilegeGas(high(uint64)))])
  assert uint64(planInitialAccumulation(empty, maximum, config).value.roundInfo.value.budget) ==
      high(uint64)
  config.reportGas = Gas(1)
  assert planInitialAccumulation(empty, maximum, config).error == AccumulationRoundError.GasOverflow
  let overflow = privileges(@[AlwaysAccumulate(service: ServiceIndex(8), gas: PrivilegeGas(high(
      uint64))),
    AlwaysAccumulate(service: ServiceIndex(9), gas: PrivilegeGas(1))])
  assert planInitialAccumulation(empty, overflow, cfg()).error == AccumulationRoundError.GasOverflow
  assert planInitialAccumulation(default(AccumulationQueuePlan), noFree, cfg()).error ==
      AccumulationRoundError.InvalidQueue
  assert planInitialAccumulation(empty, default(PrivilegeSnapshot), cfg()).error ==
      AccumulationRoundError.InvalidPrivileges
  assert planInitialAccumulation(empty, privileges(@[], 3), cfg()).error ==
      AccumulationRoundError.InvalidPrivileges
  # Bound all report traversal before scanning, and include a rejected report's inspected digest in the gas scan ceiling.
  for field in 0..<5:
    var limited = cfg()
    case field
    of 0: limited.operands.reports = ElementLimit(2) # Three source reports exceed the traversal policy.
    of 1: limited.operands.operands = ElementLimit(1) # Later inspected gas exceeds the work ceiling.
    of 2: limited.inputs.allowances = ElementLimit(0) # Zero allowance still consumes a dictionary row.
    of 3: limited.privileges.maxAlways = ElementLimit(0) # Parent dictionary has its own ceiling too.
    else: limited.inputs.services = ElementLimit(0) # No partial union may escape a late materialization refusal.
    assert planInitialAccumulation(source, zero, limited).error ==
        AccumulationRoundError.LimitExceeded
  config = cfg()
  config.operands.operands = ElementLimit(1)
  config.blockGas = Gas(0)
  assert planInitialAccumulation(source, noFree, config).error ==
      AccumulationRoundError.LimitExceeded
  let missing = default(InitialAccumulationRound)
  assert missing.roundInfo.error == AccumulationRoundError.Uninitialized
  assert missing.roundInputs.error == AccumulationRoundError.Uninitialized
  assert missing.roundPrivileges.error == AccumulationRoundError.Uninitialized
  assert default(BlockAccumulationRound).roundProjection.error ==
      AccumulationRoundError.Uninitialized
  assert default(BlockAccumulationRound).roundBlockQueue.error ==
      AccumulationRoundError.Uninitialized
  assert planBlockInitialAccumulation(default(BlockAccumulationQueue), cfg()).error ==
      AccumulationRoundError.InvalidQueue
  result = planInitialAccumulation(source, zero, cfg()).value

## Signed parent roots include the exact C(12) bytes; mutation after capture cannot change the bound plan.
proc boundCases(base: OwnedReport): PreparedAccumulationInputs =
  var chapter = entry(@[AlwaysAccumulate(service: ServiceIndex(99), gas: PrivilegeGas(5))])
  let context = authored(base, withAvailable = true, extra = @[chapter])
  let admission = planBlockReports(context.staged, context.older, config()).value
  let bound = planBlockAccumulationQueue(admission, queueConfig()).value
  let root = context.original.snapshot.value.commitment.root
  chapter.value[0] = chapter.value[0] xor 1
  let outcome = planBlockInitialAccumulation(bound, cfg())
  assert outcome.error == AccumulationRoundError.None
  let plan = outcome.value.roundProjection.value
  assert uint64(plan.roundInfo.value.allowanceGas) == 5
  assert uint64(plan.roundInfo.value.prefix) == 1
  assert uint32(privilegeInfo(plan.roundPrivileges.value).value.manager) == 77
  assert outcome.value.roundBlockQueue.value.accumulationAdmission.error ==
      AccumulationQueueError.None
  assert array[32, byte](context.original.snapshot.value.commitment.root) == array[32, byte](root)
  var wrong = cfg(3)
  assert planBlockInitialAccumulation(bound, wrong).error == AccumulationRoundError.InvalidConfig
  wrong = cfg()
  wrong.privileges.maxBytes = ByteLimit(chapter.value.len-1)
  assert planBlockInitialAccumulation(bound, wrong).error == AccumulationRoundError.LimitExceeded
  # Re-sign genuine parent roots for missing, malformed and trailing chapter failures rather than forging a bound owner.
  for mode in 0..<3:
    var extra: seq[StateEntry] = @[]
    if mode != 0:
      var damaged = entry(@[])
      if mode == 1: damaged.value.setLen(1) # Incomplete fixed role/assigner fields.
      else: damaged.value.add(0) # Valid prefix with an unauthorized suffix.
      extra.add(damaged)
    let badContext = authored(base, withAvailable = true, extra = extra)
    let badQueue = planBlockAccumulationQueue(planBlockReports(badContext.staged,
      badContext.older, config()).value, queueConfig()).value
    let error = planBlockInitialAccumulation(badQueue, cfg()).error
    assert error == (if mode == 0: AccumulationRoundError.MissingState
      else: AccumulationRoundError.InvalidPrivileges)
  result = plan.roundInputs.value

## Success and late refusal must release all acyclic storage after each complete planning call.
proc lifetime(base: OwnedReport) =
  let source = queue([reportFor(base, 0, [10'u64])])
  let free = privileges(@[])
  var limited = cfg()
  limited.inputs.services = ElementLimit(0)
  discard planInitialAccumulation(source, free, cfg())
  discard planInitialAccumulation(source, free, limited)
  let before = getOccupiedMem()
  # Repeated successful and refused preparations may not retain scratch or operand allocations.
  for i in 0..<1000:
    assert planInitialAccumulation(source, free, cfg()).error == AccumulationRoundError.None
    assert planInitialAccumulation(source, free, limited).error ==
        AccumulationRoundError.LimitExceeded
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_round", 1000, before, after)

## Run every assertion through Hastur; fixture/I/O failures remain unsuccessful executions.
proc main() {.raises.} =
  projections()
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for i in 0..<raw.len: wire[i] = byte(raw[i]) # Copy binary fixture octets without text encoding.
  let base = decodeOwnedReport(wire, 2).value
  let retained = boundaries(base)
  assert retained.roundInputs.value.invocationServiceCount.value > 0
  let inputs = boundCases(base)
  assert inputs.invocationServiceCount.value == 2
  assert bytes(inputs.invocationInputAt(InvocationServiceIndex(0), InvocationInputIndex(
      0)).value).len > 0
  lifetime(base)
  echo "PASS initial accumulation: gas prefix, parent privileges, complete inputs, bounds and ARC"
try:
  main() # Exercise the complete focused workload.
except:
  quit(2) # Unexpected I/O or exceptions must not report a passing suite.
