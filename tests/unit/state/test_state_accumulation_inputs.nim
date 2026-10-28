# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native accpar/accone input preparation tests: independent contexts, exact bytes, gas and limits.
## Hastur main replays published/authored report projections and exercises ownership and ARC release.

# @@Verification={"arc": "accumulation_inputs_arc_release"}

import std/assertions
import std/envvars
import std/strutils
import std/parseutils
import std/syncio
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_operands as state_accumulation_operands
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/header as codec_header
import ../../../src/codec/work_digest as codec_work_digest
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/c2_records as codec_c2_records
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../../src/codec/state_privileges as codec_state_privileges
import ../../support/state_report_context
import ../../support/testing_arc_evidence

## Finite independent local ceilings cover input descriptors, allowance rows and union services.
proc cfg(): AccumulationInputConfig =
  AccumulationInputConfig(inputs: ElementLimit(20000), allowances: ElementLimit(1000),
    services: ElementLimit(20000))

## Existing operand preparation owns payload budgets independently of this retained-handle projection.
proc operandConfig(): AccumulationOperandConfig =
  AccumulationOperandConfig(reports: ElementLimit(1000), operands: ElementLimit(16000),
    services: ElementLimit(16000), totalBytes: ByteLimit(10000000), totalBlobBytes: ByteLimit(
        10000000),
    operand: OperandLimits(outputBytes: ByteLimit(100000), authBytes: ByteLimit(100000),
      totalBlobBytes: ByteLimit(200000), maxBytes: ByteLimit(1000000)))

## Match the explicit queue epoch/core profile carried by each independent fixture row.
proc queueConfig(cores = 2'u64, slots = 12'u64): AccumulationQueueConfig =
  AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(cores),
    epochSlots: EpochSlots(slots), perSlot: ElementLimit(10000), totalItems: ElementLimit(10000),
    perDependencies: ElementLimit(80000), totalDependencies: ElementLimit(80000),
    reportBytes: ByteLimit(1000000), maxBytes: ByteLimit(10000000)),
    items: ElementLimit(10000), dependencies: ElementLimit(80000))

## Parse trusted decimal fixture transport without narrowing full-width gas to a signed native integer.
proc number(text: string): uint64 =
  var value = 0'u64
  assert parseBiggestUInt(text, value) == text.len
  value

## Valid empty report preparation is distinct from an uninitialized source handle.
proc empty(): PreparedAccumulationOperands =
  let queue = planAccumulationQueues([], newSeq[byte](12), newSeq[byte](12), HeaderSlot(0),
    queueConfig()).value
  prepareAccumulationOperands(queue, AccumulationReportPrefix(0), operandConfig()).value

## Encode a copied transfer or retained operand to compare every field against independent complete C.2 bytes.
proc bytes(input: InvocationInput): seq[byte] =
  case input.kind
  of AccumulationKind.Transfer:
    result = newSeq[byte](154) # Standalone transfer includes its actual C.2 discriminator.
    assert encodeTransfer(input.transfer, ByteLimit(154), result).value == result.len
  of AccumulationKind.Operand:
    let owner = input.operand # Select before retaining the active payload owner.
    result = newSeq[byte](operandInfo(owner).value.consumed)
    assert encodeOwnedOperand(owner, operandConfig().operand, result).value == result.len

## Independent arbitrary-precision oracle determines complete groups, ordering, bytes and overflow verdicts.
proc projections() {.raises.} =
  var total = 0
  var refused = 0
  var retained: seq[InvocationInput] = @[]
  # Each row retains the original source queue and an explicitly selected report prefix.
  for line in readFile(getEnv("RAGNAROK_ACCUMULATION_INPUTS")).splitLines:
    if line.len == 0: continue # Ignore the final transport newline only.
    let f = line.splitWhitespace
    var reports: seq[OwnedReport] = @[]
    if f[6] != "-":
      for raw in f[6].split(','):
        reports.add(decodeOwnedReport(unhex(raw), number(f[1])).value) # Unchanged full report bytes.
    let queue = planAccumulationQueues(reports, unhex(f[4]), unhex(f[5]), HeaderSlot(number(f[3])),
      queueConfig(number(f[1]), number(f[2]))).value
    let source = prepareAccumulationOperands(queue, AccumulationReportPrefix(number(f[7])),
      operandConfig()).value
    var transfers: seq[DeferredTransfer] = @[]
    if f[8] != "-":
      for raw in f[8].split(','):
        transfers.add(decodeTransfer(unhex(raw), ByteLimit(154)).value.value) # Fixed copied transfers.
    var allowances: seq[AlwaysAccumulate] = @[]
    if f[9] != "-":
      for raw in f[9].split(','):
        let fields = raw.split(':') # Trusted sorted dictionary transport.
        allowances.add(AlwaysAccumulate(service: ServiceIndex(uint32(number(fields[0]))),
          gas: PrivilegeGas(number(fields[1]))))
    let outcome = prepareAccumulationInputs(source, transfers, allowances, cfg())
    if f[10] == "overflow":
      assert outcome.error == AccumulationInputError.GasOverflow, f[0] # Never accept a wrapped mathematical sum.
      inc refused
    else:
      assert outcome.error == AccumulationInputError.None, f[0] & " " & $outcome.error # Complete contexts only.
      let owner = outcome.value
      let groups = if f[10] == "-": newSeq[string](0) else: f[10].split(';') # Explicit valid empty union.
      assert owner.invocationServiceCount.value == groups.len
      assert uint64(owner.invocationOperands.value.operandReportPrefix.value) == number(f[7])
      var inputs = 0
      # Every whole C.2 input must match, including source/destination, memo, errors and traces.
      for i in 0..<groups.len:
        let expected = groups[i].split(':')
        let info = owner.invocationServiceAt(InvocationServiceIndex(i)).value
        let items = if expected[3] == "-": newSeq[string](0) else: expected[3].split(
            ',') # Allowance-only service.
        assert uint32(info.service) == uint32(number(expected[0]))
        assert uint64(info.gas) == number(expected[1])
        assert info.transfers == int(number(expected[2]))
        assert info.transfers+info.operands == items.len
        inputs += items.len
        # Exact sequence equality also detects interleaved transfers or reordering within either category.
        for j in 0..<items.len:
          let input = owner.invocationInputAt(InvocationServiceIndex(i), InvocationInputIndex(j)).value
          assert bytes(input) == unhex(items[j]), f[0] & " " & $i & " " & $j
          if input.kind == AccumulationKind.Operand and j == info.transfers:
            retained.add(input) # Retain a child past every source queue and invocation owner in this row.
      var exact = AccumulationInputConfig(inputs: ElementLimit(inputs),
        allowances: ElementLimit(allowances.len), services: ElementLimit(groups.len))
      assert prepareAccumulationInputs(source, transfers, allowances, exact).error ==
          AccumulationInputError.None
      # Each independent complete-context budget refuses one below the exact required extent.
      for field in 0..<3:
        var limited = exact
        case field
        of 0:
          if inputs == 0: continue # No valid negative budget for a genuinely empty input list.
          limited.inputs = ElementLimit(inputs-1)
        of 1:
          if allowances.len == 0: continue # Empty round dictionary needs no allowance capacity.
          limited.allowances = ElementLimit(allowances.len-1)
        else:
          if groups.len == 0: continue # Empty service union needs no service capacity.
          limited.services = ElementLimit(groups.len-1)
        assert prepareAccumulationInputs(source, transfers, allowances, limited).error ==
          AccumulationInputError.LimitExceeded
    inc total
  assert total == 146 and refused > 0 and refused < total
  assert retained.len > 0
  # All per-row source/plan handles have left scope; extracted children still own complete payload wire.
  for input in retained:
    assert input.kind == AccumulationKind.Operand and bytes(input).len > 129

## Literal transfer/filter/dictionary boundaries do not depend on the fixture generator or report oracle.
proc boundaries(): InvocationInput =
  let source = empty()
  assert prepareAccumulationInputs(source, [], [], default(
      AccumulationInputConfig)).value.invocationServiceCount.value == 0
  var transfers = @[
    DeferredTransfer(source: ServiceIndex(9), destination: ServiceIndex(42), gas: Gas(7),
      amount: TransferBalance(high(uint64)), memo: TransferMemo(default(array[128, byte]))),
    DeferredTransfer(source: ServiceIndex(42), destination: ServiceIndex(0), gas: Gas(3)),
    DeferredTransfer(source: ServiceIndex(1), destination: ServiceIndex(42), gas: Gas(11))]
  var memo = default(array[128, byte])
  memo[127] = 99
  transfers[0].memo = TransferMemo(memo)
  var allowances = @[AlwaysAccumulate(service: ServiceIndex(42), gas: PrivilegeGas(13)),
    AlwaysAccumulate(service: ServiceIndex(high(uint32)), gas: PrivilegeGas(0))]
  let owner = prepareAccumulationInputs(source, transfers, allowances, cfg()).value
  assert owner.invocationServiceCount.value == 3
  assert uint32(owner.invocationServiceAt(InvocationServiceIndex(0)).value.service) == 0
  let info = owner.invocationServiceAt(InvocationServiceIndex(1)).value
  assert uint32(info.service) == 42 and uint64(info.gas) == 31 and info.transfers == 2 and
      info.operands == 0
  let last = owner.invocationServiceAt(InvocationServiceIndex(2)).value
  assert uint32(last.service) == high(uint32) and uint64(last.gas) == 0 and last.transfers == 0
  result = owner.invocationInputAt(InvocationServiceIndex(1), InvocationInputIndex(0)).value
  assert result.kind == AccumulationKind.Transfer
  assert uint32(result.transfer.source) == 9 and uint64(result.transfer.amount) == high(uint64)
  assert array[128, byte](result.transfer.memo)[127] == 99
  transfers[0].destination = ServiceIndex(7)
  transfers[0].memo = TransferMemo(default(array[128, byte]))
  allowances[0].gas = PrivilegeGas(0) # Mutating caller storage cannot change already validated metadata.
  assert uint64(owner.invocationServiceAt(InvocationServiceIndex(1)).value.gas) == 31
  assert array[128, byte](owner.invocationInputAt(InvocationServiceIndex(1), InvocationInputIndex(
      0)).value.transfer.memo)[127] == 99
  assert prepareAccumulationInputs(source, [], [allowances[0], allowances[0]], cfg()).error ==
      AccumulationInputError.InvalidAllowances
  assert prepareAccumulationInputs(source, [], [allowances[1], allowances[0]], cfg()).error ==
      AccumulationInputError.InvalidAllowances
  let maximum = [AlwaysAccumulate(service: ServiceIndex(42), gas: PrivilegeGas(high(uint64)))]
  assert uint64(prepareAccumulationInputs(source, [], maximum, cfg()).value.invocationServiceAt(
      InvocationServiceIndex(0)).value.gas) == high(uint64)
  transfers[0].destination = ServiceIndex(42)
  assert prepareAccumulationInputs(source, transfers, maximum, cfg()).error ==
      AccumulationInputError.GasOverflow
  transfers[0].gas = Gas(high(uint64))
  transfers[2].gas = Gas(1)
  assert prepareAccumulationInputs(source, transfers, [], cfg()).error ==
      AccumulationInputError.GasOverflow
  assert prepareAccumulationInputs(default(PreparedAccumulationOperands), [], [], cfg()).error ==
      AccumulationInputError.InvalidOperands
  # Every native extent proof must precede allocation, even when source work is empty.
  for field in 0..<3:
    var oversized = cfg()
    case field
    of 0: oversized.inputs = ElementLimit(high(uint64)) # Input storage/descriptor extent.
    of 1: oversized.allowances = ElementLimit(high(uint64)) # Combined descriptor extent.
    else: oversized.services = ElementLimit(high(uint64)) # Service storage extent.
    assert prepareAccumulationInputs(source, [], [], oversized).error ==
        AccumulationInputError.InvalidConfig
  let missing = default(PreparedAccumulationInputs)
  assert missing.invocationServiceCount.error == AccumulationInputError.Uninitialized
  assert missing.invocationOperands.error == AccumulationInputError.Uninitialized
  assert missing.invocationServiceAt(InvocationServiceIndex(0)).error ==
      AccumulationInputError.Uninitialized
  assert missing.invocationInputAt(InvocationServiceIndex(0), InvocationInputIndex(0)).error ==
      AccumulationInputError.Uninitialized
  assert owner.invocationServiceAt(InvocationServiceIndex(high(uint64))).error ==
      AccumulationInputError.InvalidIndex
  assert owner.invocationInputAt(InvocationServiceIndex(high(uint64)), InvocationInputIndex(
      0)).error == AccumulationInputError.InvalidIndex
  assert owner.invocationInputAt(InvocationServiceIndex(0), InvocationInputIndex(high(
      uint64))).error == AccumulationInputError.InvalidIndex
  assert owner.invocationInputAt(InvocationServiceIndex(2), InvocationInputIndex(0)).error ==
      AccumulationInputError.InvalidIndex

## Success and late gas refusal must release all descriptor/group/owner allocations under ARC.
proc lifetime() =
  let source = empty()
  let transfers = [DeferredTransfer(destination: ServiceIndex(42), gas: Gas(1))]
  let allowances = [AlwaysAccumulate(service: ServiceIndex(42), gas: PrivilegeGas(high(uint64)))]
  discard prepareAccumulationInputs(source, transfers, [], cfg()) # Warm deterministic runtime paths.
  discard prepareAccumulationInputs(source, transfers, allowances, cfg()) # Warm refusal too.
  let before = getOccupiedMem()
  # Each iteration constructs a complete owner and a fully refused overflowing context.
  for i in 0..<1000:
    assert prepareAccumulationInputs(source, transfers, [], cfg()).error ==
        AccumulationInputError.None
    assert prepareAccumulationInputs(source, transfers, allowances, cfg()).error ==
        AccumulationInputError.GasOverflow
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_accumulation_inputs", 1000, before, after)

## Run native verdicts through the standard Hastur entry point; fixture failures cannot become success.
proc main() {.raises.} =
  projections()
  let retained = boundaries()
  assert array[128, byte](retained.transfer.memo)[127] == 99 # All source arrays and parent handles left scope.
  lifetime()
  echo "PASS accumulation inputs: service union, ordered transfers/operands, checked gas, limits and ARC"
try:
  main() # Execute the complete focused suite.
except:
  quit(2) # Missing transport and unexpected exceptions remain test failures.
