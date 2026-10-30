# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded reusable pricing learns successful facts lazily for one immutable program and cycle policy.
## Handles share a private mutable memo identity; use exclusively, including synchronous nested calls.
import ../program
import ./gas

type
  GasMemoByteLimit* = distinct uint64 ## Bound the direct-address price payload before any allocation.
  GasMemoLimits* = object ## Local memory/work policy is independent of guest gas and program admission.
    bytes*: GasMemoByteLimit
    cycles*: GasCycleLimit
  GasMemoInfo* = object ## Copied observations expose neither mutable storage nor writable configuration.
    codeBytes*, payloadBytes*, pricedBlocks*: uint64
    cycleLimit*: GasCycleLimit
  GasMemoError* {.pure.} = enum ## Defaults and every refusal carry only their reason; no failed result owns a prefix.
    Uninitialized, None, InvalidProgram, LimitExceeded, InvalidStart, CycleLimitExceeded, NegativeBranchTarget
  GasMemoResult*[T] = object ## Successful handles/scalars are selectable only after inspecting their private discriminator.
    case status: GasMemoError
    of None:
      completed: T
    else:
      discard
  GasMemoData = ref object ## Source/configuration never change; private prices grow monotonically without retaining CPU/memory/callbacks.
    source: Program
    cycles: GasCycleLimit
    prices: seq[uint64]
    filled: uint64
  GasMemo* = object ## Copied handles share successful facts; rebinding one handle cannot replace another call's retained policy.
    data: nil GasMemoData

func error*[T](r: GasMemoResult[T]): GasMemoError =
  ## Inspect status without permitting caller retagging or payload forgery.
  r.status
func value*[T](r: GasMemoResult[T]): T {.inline, requires: r.status == GasMemoError.None.} =
  ## Return only the complete selected value; failed/default alternatives contain no successful payload.
  r.completed

proc newGasMemo*(source: Program, limits: GasMemoLimits): GasMemoResult[GasMemo] =
  ## Borrow for preflight, then retain the exact immutable owner without pricing unvisited blocks.
  let extent = codeLength(source)
  if extent.error != ProgramError.None:
    return GasMemoResult[GasMemo](status: GasMemoError.InvalidProgram)
  let length = extent.value
  if length == 0:
    return GasMemoResult[GasMemo](status: GasMemoError.InvalidProgram)
  if length > uint64(high(int)) div 8 or length > uint64(limits.bytes) div 8:
    return GasMemoResult[GasMemo](status: GasMemoError.LimitExceeded) # Prove allocation, conversion and payload multiplication first.
  GasMemoResult[GasMemo](status: GasMemoError.None, completed: GasMemo(data:
    GasMemoData(source: source, cycles: limits.cycles, prices: newSeq[uint64](int(length)), filled: 0)))

func matchesProgram*(memo: GasMemo, source: Program): bool =
  ## Exact identity prevents reuse across separately captured identical bytes or another decode profile.
  if memo.data == nil: return false
  let data = memo.data
  data.source == source
func programOf*(memo: GasMemo): GasMemoResult[Program] =
  ## A copied child remains valid after the last memo handle retires; defaults expose no fabricated source.
  if memo.data == nil: return GasMemoResult[Program](status: GasMemoError.InvalidProgram)
  let data = memo.data
  GasMemoResult[Program](status: GasMemoError.None, completed: data.source)
func gasMemoInfo*(memo: GasMemo): GasMemoResult[GasMemoInfo] =
  ## Observe bounded occupancy and immutable policy by value; earlier observations do not change as facts accumulate.
  if memo.data == nil: return GasMemoResult[GasMemoInfo](status: GasMemoError.InvalidProgram)
  let data = memo.data
  GasMemoResult[GasMemoInfo](status: GasMemoError.None, completed: GasMemoInfo(
    codeBytes: uint64(data.prices.len), payloadBytes: uint64(data.prices.len)*8,
    pricedBlocks: data.filled, cycleLimit: data.cycles))

proc price(data: GasMemoData, start: CodeAddress): GasMemoResult[BlockGas] =
  ## A non-null private owner stays stable across the pure simulator call; only successful positive prices may be retained.
  let pc = uint64(start)
  if pc >= uint64(data.prices.len):
    return GasMemoResult[BlockGas](status: GasMemoError.InvalidStart) # Full-width bounds precede native narrowing.
  let index = int(pc)
  let cached = data.prices[index]
  if cached != 0:
    return GasMemoResult[BlockGas](status: GasMemoError.None, completed: BlockGas(cached))
  let computed = blockGas(data.source, start, data.cycles)
  case computed.error
  of GasError.None:
    # Zero is the private absent marker; current normative whole-block prices are strictly positive.
    let cost = uint64(computed.value)
    if cost == 0: return GasMemoResult[BlockGas](status: GasMemoError.InvalidStart)
    if data.filled >= uint64(data.prices.len):
      return GasMemoResult[BlockGas](status: GasMemoError.InvalidProgram) # Defend the bounded counter before increment, even on an impossible inconsistent private table.
    data.prices[index] = cost
    inc data.filled
    GasMemoResult[BlockGas](status: GasMemoError.None, completed: computed.value)
  of GasError.CycleLimitExceeded:
    # Refused simulations retain no cost, occupancy change or partial pipeline state.
    GasMemoResult[BlockGas](status: GasMemoError.CycleLimitExceeded)
  of GasError.NegativeBranchTarget:
    # Preserve the historical pricing alternative; current approved wrapped-target pricing does not emit it.
    GasMemoResult[BlockGas](status: GasMemoError.NegativeBranchTarget)
  else:
    # Invalid/default pricing positions never become successful cached facts.
    GasMemoResult[BlockGas](status: GasMemoError.InvalidStart)

proc blockGas*(memo: GasMemo, start: CodeAddress): GasMemoResult[BlockGas] =
  ## Mirror the original exact block-start query; interior/operand addresses remain refused and execution selects containing starts.
  ## Updates may survive a later execution refusal, but contain no paid gas, CPU or memory progress.
  if memo.data == nil: return GasMemoResult[BlockGas](status: GasMemoError.InvalidProgram)
  let data {.cursor.} = memo.data # The caller retains the stable policy owner through this synchronous lookup.
  price(data, start)
