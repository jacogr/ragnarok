# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable complete block prices bound to one captured program and one local cycle policy.
import ./[program, gas]

type
  GasPlanByteLimit* = distinct uint64 ## Bound the private direct-address payload before allocation.
  GasPlanBlockLimit* = distinct uint64 ## Bound the number of independent pipeline simulations.
  GasPlanLimits* = object ## Caller work/memory policy is separate from guest gas and source-code admissibility.
    blocks*: GasPlanBlockLimit
    bytes*: GasPlanByteLimit
    cycles*: GasCycleLimit
  GasPlanInfo* = object ## Copied resource observations expose no mutable table or source storage.
    codeBytes*, blockCount*, payloadBytes*: uint64
    cycleLimit*: GasCycleLimit
  GasPlanError* {.pure.} = enum ## Every refusal carries only its reason; zero/default never denotes a plan.
    Uninitialized, None, InvalidProgram, LimitExceeded, CycleLimitExceeded, InvalidStart
  GasPlanResult*[T] = object ## Only successful alternatives carry a complete immutable handle/value.
    case status: GasPlanError
    of None:
      completed: T
    else:
      discard
  GasPlanData = ref object ## No back-reference from the immutable program can form an ownership cycle.
    source: Program
    prices: seq[uint64]
    info: GasPlanInfo
  GasPlan* = object ## Copied handles share immutable successful facts, never invocation CPU/memory or callbacks.
    data: nil GasPlanData

func error*[T](r: GasPlanResult[T]): GasPlanError =
  ## Inspect status without exposing its discriminator for caller mutation.
  r.status
func value*[T](r: GasPlanResult[T]): T {.inline, requires: r.status == GasPlanError.None.} =
  ## Copy only a selected complete value; failed/default results contain no payload.
  r.completed

proc newGasPlan*(source: Program, limits: GasPlanLimits): GasPlanResult[GasPlan] =
  ## Borrow during preparation, then retain the exact immutable program only after complete successful pricing.
  let extent = codeLength(source)
  if extent.error != ProgramError.None:
    return GasPlanResult[GasPlan](status: GasPlanError.InvalidProgram)
  let length = extent.value
  if length == 0:
    return GasPlanResult[GasPlan](status: GasPlanError.InvalidProgram)
  if length > uint64(high(int)) div 8 or length > uint64(limits.bytes) div 8:
    return GasPlanResult[GasPlan](status: GasPlanError.LimitExceeded) # Prove native allocation and multiplication bounds first.
  if uint64(limits.blocks) == 0:
    return GasPlanResult[GasPlan](status: GasPlanError.LimitExceeded) # Every nonempty admitted program has an initial block.
  var prices = newSeq[uint64](int(length))
  var pc = 0'u64
  var blocks = 0'u64
  var atStart = true
  while pc < length:
    # A genuine decoded successor enumerates the same immutable marked chain used by source admission.
    let decoded = instruction(source, CodeAddress(pc))
    if decoded.error != ProgramError.None:
      return GasPlanResult[GasPlan](status: GasPlanError.InvalidProgram)
    if atStart:
      if blocks == uint64(limits.blocks):
        return GasPlanResult[GasPlan](status: GasPlanError.LimitExceeded)
      let priced = blockGas(source, CodeAddress(pc), limits.cycles)
      if priced.error == GasError.CycleLimitExceeded:
        return GasPlanResult[GasPlan](status: GasPlanError.CycleLimitExceeded)
      if priced.error != GasError.None:
        return GasPlanResult[GasPlan](status: GasPlanError.InvalidProgram)
      let cost = uint64(priced.value)
      if cost == 0:
        return GasPlanResult[GasPlan](status: GasPlanError.InvalidProgram) # Successful normative prices are positive; zero remains an absent-start marker.
      prices[int(pc)] = cost
      inc blocks
    let item = decoded.value
    let advance = 1'u64+uint64(item.skip)
    if advance > length-pc:
      return GasPlanResult[GasPlan](status: GasPlanError.InvalidProgram)
    pc += advance
    atStart = terminatesBlock(item.opcode)
  GasPlanResult[GasPlan](status: GasPlanError.None, completed: GasPlan(data:
    GasPlanData(source: source, prices: prices, info: GasPlanInfo(codeBytes: length,
      blockCount: blocks, payloadBytes: length*8, cycleLimit: limits.cycles))))

func matchesProgram*(plan: GasPlan, source: Program): bool =
  ## Exact owner identity prevents reuse across separately captured bytes or raw/JAM profiles.
  if plan.data == nil: return false
  let data = plan.data
  data.source == source

func programOf*(plan: GasPlan): GasPlanResult[Program] =
  ## Retain the original immutable child independently of the plan; a default handle exposes no fabricated owner.
  if plan.data == nil: return GasPlanResult[Program](status: GasPlanError.InvalidProgram)
  let data = plan.data
  GasPlanResult[Program](status: GasPlanError.None, completed: data.source)

func gasPlanInfo*(plan: GasPlan): GasPlanResult[GasPlanInfo] =
  ## A default owner has no fabricated zero statistics or configuration.
  if plan.data == nil: return GasPlanResult[GasPlanInfo](status: GasPlanError.InvalidProgram)
  let data = plan.data
  GasPlanResult[GasPlanInfo](status: GasPlanError.None, completed: data.info)

func blockGas*(plan: GasPlan, start: CodeAddress): GasPlanResult[BlockGas] =
  ## Select only an exact priced block start; full-width addresses are checked before narrowing.
  if plan.data == nil: return GasPlanResult[BlockGas](status: GasPlanError.InvalidProgram)
  let data = plan.data
  let pc = uint64(start)
  if pc >= uint64(data.prices.len): return GasPlanResult[BlockGas](
      status: GasPlanError.InvalidStart)
  let price = data.prices[int(pc)]
  if price == 0: return GasPlanResult[BlockGas](status: GasPlanError.InvalidStart)
  GasPlanResult[BlockGas](status: GasPlanError.None, completed: BlockGas(price))
