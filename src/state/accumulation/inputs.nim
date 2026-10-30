# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 accpar/accone: bounded invocation inputs from explicit round context.
## Exposes immutable service/input access, transfer-before-operand ordering and checked gas sums.
## This projection neither executes services nor certifies caller-supplied transfers or privileges.

import std/algorithm
import ../../codec/[bounded, composite]
import ../../codec/work/digest as work_digest
import ../../codec/c2_records
import ../../codec/state/privileges as state_privileges
import ./operands as accumulation_operands

type
  InvocationServiceIndex* = distinct uint64 ## Invocation service position is distinct from protocol service IDs and operand-group ordinals.
  InvocationInputIndex* = distinct uint64 ## Input position addresses one service's transfer/operand concatenation only.
  AccumulationInputConfig* = object ## Independent local ceilings bound input descriptors, allowance traversal and resulting services.
    inputs*, allowances*, services*: ElementLimit
  AccumulationInputError* {.pure.} = enum ## Failed/default results expose no partially prepared services or gas budget.
    Uninitialized, None, InvalidConfig, InvalidOperands, InvalidAllowances, LimitExceeded,
    GasOverflow, InvalidIndex
  InvocationInput* = object ## Private selected input carries only its active copied transfer or immutable operand owner.
    case inputKind: AccumulationKind
    of Transfer:
      transferValue: DeferredTransfer # Fixed fields are independent of the caller's array.
    of Operand:
      operandValue: OwnedOperand      # Immutable acyclic owner retains its payload bytes.
  InvocationServiceInfo* = object ## Copied service metadata includes the complete mathematical gas sum and both input counts.
    service*: ServiceIndex
    gas*: Gas
    transfers*, operands*: int
  ## Private sortable row records exact source order; allowance-only rows have no input.
  InputRow = object
    service: ServiceIndex
    gas: uint64
    category, order, group, member: int
  ## Private service storage is published only after every count, dictionary and gas sum succeeds.
  InvocationGroup = object
    info: InvocationServiceInfo
    inputs: seq[InvocationInput]
  ## Acyclic owner retains exact report-prefix provenance and complete immutable input groups.
  InputData = ref object
    source: PreparedAccumulationOperands
    groups: seq[InvocationGroup]
  PreparedAccumulationInputs* = object ## A prepared round is not evidence of execution, consumed gas or posterior state publication.
    data: nil InputData
  AccumulationInputResult*[T] = object ## Only successful results carry complete payloads, protected by selected-success contracts.
    case status: AccumulationInputError
    of None:
      completed: T # No externally writable discriminator or payload.
    else:
      discard      # A failure never carries default success metadata.

func error*[T](outcome: AccumulationInputResult[T]): AccumulationInputError =
  ## Inspect failure without exposing writable result storage.
  outcome.status

func value*[T](outcome: AccumulationInputResult[T]): T {.inline,
    requires: outcome.status == AccumulationInputError.None.} =
  ## Extract only selected success, preserving runtime and compiler guard enforcement.
  outcome.completed

func kind*(input: InvocationInput): AccumulationKind =
  ## Inspect the actual C.2 alternative before accessing its payload.
  input.inputKind

func transfer*(input: InvocationInput): DeferredTransfer {.requires: input.inputKind ==
    AccumulationKind.Transfer.} =
  ## Copy a transfer only after selecting the transfer alternative.
  input.transferValue

func operand*(input: InvocationInput): OwnedOperand {.requires: input.inputKind ==
    AccumulationKind.Operand.} =
  ## Retain an operand only after selecting the operand alternative.
  input.operandValue

func compareRow(a, b: InputRow): int =
  ## Sort numeric service IDs, then transfers, operands and allowance rows, retaining source ordinals.
  if uint32(a.service) < uint32(b.service): return -1 # Numeric service enumeration.
  if uint32(a.service) > uint32(b.service): return 1 # Larger service follows.
  if a.category < b.category: return -1 # Transfers precede report operands.
  if a.category > b.category: return 1 # Allowance rows carry no input.
  if a.order < b.order: return -1 # Preserve original per-category sequence.
  if a.order > b.order: return 1 # Do not rely on sorting stability.
  0

func sameAccumulationInputs*(left, right: PreparedAccumulationInputs): bool =
  ## Compare initialized preparation owners without traversing their input contents.
  ## Copies match; defaults and independently prepared equal contents do not.
  left.data != nil and left.data == right.data

proc invocationServiceCount*(plan: PreparedAccumulationInputs): AccumulationInputResult[int] =
  ## Count complete invocation groups; default handles cannot masquerade as valid empty rounds.
  let data = plan.data
  if data == nil: return AccumulationInputResult[int](
      status: AccumulationInputError.Uninitialized) # No validated storage.
  AccumulationInputResult[int](status: AccumulationInputError.None, completed: data.groups.len)

proc invocationOperands*(plan: PreparedAccumulationInputs): AccumulationInputResult[
    PreparedAccumulationOperands] =
  ## Retain the exact report-prefix source independently of the invocation handle.
  let data = plan.data
  if data == nil: return AccumulationInputResult[PreparedAccumulationOperands](
      status: AccumulationInputError.Uninitialized) # No fabricated report prefix.
  AccumulationInputResult[PreparedAccumulationOperands](status: AccumulationInputError.None,
    completed: data.source)

proc invocationServiceAt*(plan: PreparedAccumulationInputs,
    index: InvocationServiceIndex): AccumulationInputResult[InvocationServiceInfo] =
  ## Read copied service gas/counts after proving its ordinal fits before native conversion.
  let data = plan.data
  if data == nil: return AccumulationInputResult[InvocationServiceInfo](
      status: AccumulationInputError.Uninitialized) # No default metadata.
  if uint64(index) >= uint64(data.groups.len): return AccumulationInputResult[
      InvocationServiceInfo](status: AccumulationInputError.InvalidIndex) # Prove access before narrowing.
  AccumulationInputResult[InvocationServiceInfo](status: AccumulationInputError.None,
    completed: data.groups[int(uint64(index))].info)

proc invocationInputAt*(plan: PreparedAccumulationInputs, service: InvocationServiceIndex,
    index: InvocationInputIndex): AccumulationInputResult[InvocationInput] =
  ## Copy or retain one selected input; neither its parent handle nor caller arrays must stay alive.
  let data = plan.data
  if data == nil: return AccumulationInputResult[InvocationInput](
      status: AccumulationInputError.Uninitialized) # No fabricated input.
  if uint64(service) >= uint64(data.groups.len): return AccumulationInputResult[InvocationInput](
      status: AccumulationInputError.InvalidIndex) # Check outer index first.
  let group = data.groups[int(uint64(service))]
  if uint64(index) >= uint64(group.inputs.len): return AccumulationInputResult[InvocationInput](
      status: AccumulationInputError.InvalidIndex) # Check inner index before narrowing.
  AccumulationInputResult[InvocationInput](status: AccumulationInputError.None,
    completed: group.inputs[int(uint64(index))])

proc prepareAccumulationInputs*(source: PreparedAccumulationOperands,
    transfers: openArray[DeferredTransfer], allowances: openArray[AlwaysAccumulate],
    config: AccumulationInputConfig): AccumulationInputResult[PreparedAccumulationInputs] =
  ## Prepare one explicit round's accone inputs. Allowances must be a numeric sorted unique dictionary;
  ## pass C(12)'s always pairs for the initial round and an empty array for subsequent accseq rounds.
  ## Borrow arrays synchronously, copy transfers, retain operand owners; reject gas sums outside GP gas=N_64.
  ## Refuse atomically without returning partially accumulated gas or earlier services.
  template fail(reason: AccumulationInputError) =
    return AccumulationInputResult[PreparedAccumulationInputs](status: reason)
  let maxRows = uint64(high(int) div sizeof(InputRow))
  if uint64(config.inputs) > maxRows or uint64(config.allowances) > maxRows-uint64(config.inputs) or
      uint64(config.services) > uint64(high(int) div sizeof(InvocationGroup)) or
      uint64(config.inputs) > uint64(high(int) div sizeof(InvocationInput)):
    fail(AccumulationInputError.InvalidConfig) # Prove combined descriptor/native storage extents.
  let count = source.operandServiceCount
  if count.error != AccumulationOperandError.None:
    fail(AccumulationInputError.InvalidOperands) # Default source is not a valid empty round.
  if uint64(transfers.len) > uint64(config.inputs) or uint64(allowances.len) > uint64(
      config.allowances):
    fail(AccumulationInputError.LimitExceeded) # Bound both external traversals before allocation.
  var inputCount = uint64(transfers.len)
  # Group count bounds traversal even when the supplied service budget is smaller than report-only work.
  if uint64(count.value) > uint64(config.services):
    fail(AccumulationInputError.LimitExceeded) # Union cannot contain fewer than report groups.
  # Prove the complete input count before creating any descriptors.
  for i in 0..<count.value:
    let group = source.operandServiceAt(OperandServiceIndex(i)).value
    if uint64(group.operands) > uint64(config.inputs)-inputCount:
      fail(AccumulationInputError.LimitExceeded) # No wrapped input sum.
    inputCount += uint64(group.operands)
  # Reject duplicate/out-of-order dictionary keys rather than inventing a conflict-resolution policy.
  for i in 1..<allowances.len:
    if uint32(allowances[i-1].service) >= uint32(allowances[i].service):
      fail(AccumulationInputError.InvalidAllowances) # Same canonical order as the C(12) codec.
  var rows: seq[InputRow] = @[]
  # Transfer order is global source order, filtered only by destination service.
  for i in 0..<transfers.len:
    rows.add(InputRow(service: transfers[i].destination, gas: uint64(transfers[i].gas),
      category: 0, order: i, group: 0, member: i))
  # Prior preparation already established report/digest order and immutable operand validity.
  for i in 0..<count.value:
    let group = source.operandServiceAt(OperandServiceIndex(i)).value
    # Each report operand contributes its accumulation gas, including all work-error alternatives.
    for j in 0..<group.operands:
      let item = source.serviceOperandAt(OperandServiceIndex(i), ServiceOperandIndex(j)).value
      rows.add(InputRow(service: group.service, gas: uint64(operandInfo(item).value.gas),
        category: 1, order: j, group: i, member: j))
  # Zero allowances still introduce always-accumulate services with empty input sequences.
  for i in 0..<allowances.len:
    rows.add(InputRow(service: allowances[i].service, gas: uint64(allowances[i].gas),
      category: 2, order: i, group: 0, member: 0))
  rows.sort(compareRow)
  var groups: seq[InvocationGroup] = @[]
  # Preflight every service sum before materializing its input sequence.
  for row in rows:
    if groups.len == 0 or uint32(groups[^1].info.service) != uint32(row.service):
      if uint64(groups.len) >= uint64(config.services):
        fail(AccumulationInputError.LimitExceeded) # Bound a late union-only service too.
      groups.add(InvocationGroup(info: InvocationServiceInfo(service: row.service, gas: Gas(0),
        transfers: 0, operands: 0), inputs: @[])) # Publish nothing until the whole projection succeeds.
    let previous = uint64(groups[^1].info.gas)
    if row.gas > high(uint64)-previous:
      fail(AccumulationInputError.GasOverflow) # GP natural addition must not silently wrap or saturate.
    groups[^1].info.gas = Gas(previous+row.gas)
  var groupIndex = 0
  # Materialization copies only fixed transfers and immutable handles; no payload bytes are duplicated.
  for row in rows:
    if uint32(groups[groupIndex].info.service) != uint32(row.service):
      inc groupIndex # Sorted descriptors advance to the next already validated service.
    case row.category
    of 0:
      groups[groupIndex].inputs.add(InvocationInput(inputKind: AccumulationKind.Transfer,
        transferValue: transfers[row.member])) # Preserve complete source/destination/balance/memo/gas.
      inc groups[groupIndex].info.transfers
    of 1:
      groups[groupIndex].inputs.add(InvocationInput(inputKind: AccumulationKind.Operand,
        operandValue: source.serviceOperandAt(OperandServiceIndex(row.group),
          ServiceOperandIndex(row.member)).value)) # Retain the exact earlier C.2 operand owner.
      inc groups[groupIndex].info.operands
    else:
      discard # Allowance rows affect membership and gas, never the invocation input sequence.
  AccumulationInputResult[PreparedAccumulationInputs](status: AccumulationInputError.None,
    completed: PreparedAccumulationInputs(data: InputData(source: source, groups: groups)))
