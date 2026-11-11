# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Copied certificate and checked receipt for a bounded three-header register loop.
##
## Both lowerers can reserve a complete round at the first header. A side exit
## refunds the gas and attempts of the unexecuted suffix. Entry at either later
## header and a failed whole-round reservation use the original per-header guards.

import ../machine
import ./native_ir

type
  NativeRingIndex* = range[0..2] ## Certificate order follows the three closed edges.
  NativeRingBlock* = object ## Complete original charged header, pure body and resolved branch.
    header*, first*, span*, yes*, no*: uint32
    price*: uint64
    body*: array[2, NativeOperation]
    branch*: NativeOperation
  NativeRegisterRing* = object ## Immutable copied worker input without program or invocation borrows.
    blocks*: array[NativeRingIndex, NativeRingBlock]
  NativeRingRoundBudget* = object ## Copied immediate costs for one complete pure round.
    enabled*: bool
    price*: uint32
    suffixPrices*: array[2, uint32]
  NativeRingContext* = object ## Two-borrow ABI with an unpaid rotating entry.
    gas*, remaining*: uint64
    visits*: array[NativeRingIndex, uint64]
    entry*: uint64

func complete*(ring: NativeRegisterRing): bool =
  ## Check the bounded original opcode shapes and one closed successor per block.
  const
    spans = [3'u32, 2, 3]
    firstOpcodes = [200'u8, 131, 151]
    secondOpcodes = [139'u8, 0, 152]
    branches = [82'u8, 88, 173]
  for index in 0..2:
    let item = ring.blocks[index]
    if item.span != spans[index] or item.header >= NativeEntryLimit or
        item.first > high(uint32)-item.span or item.body[0].opcode != firstOpcodes[index] or
        item.body[1].opcode != secondOpcodes[index] or item.branch.opcode != branches[index] or
        item.yes >= NativeEntryLimit or item.no >= NativeEntryLimit:
      return false
    let next = ring.blocks[(index+1) mod 3].header
    if (item.yes == next) == (item.no == next): return false
    let outside = if item.yes == next: item.no else: item.yes
    for other in 0..2:
      # The other edge resumes checked execution. The original source spans are disjoint.
      let peer = ring.blocks[other]
      if outside == peer.header: return false
      if other != index and (item.header == peer.header or
          (item.first <= peer.first and peer.first-item.first < item.span)):
        return false
    if index < 2:
      # Immediate branch operands are the checked sign extension of the encoded word.
      let low = uint32(item.branch.immediate and 0xffffffff'u64)
      if cast[uint64](int64(cast[int32](low))) != item.branch.immediate: return false
  true

const
  NativeRingRoundSpan* = 8'u32             ## Total original attempts in the certified three blocks.
  NativeRingRoundSuffixSpans* = [5'u32, 3] ## Attempts to refund after the first or second block.

func nativeRingRoundBudget*(ring: NativeRegisterRing): NativeRingRoundBudget =
  ## Require one shared 12-bit immediate ceiling for the total and both suffixes.
  ## Subtract from the ceiling to reject wide or overflowing totals before narrowing.
  ## A refusal preserves the ordinary guarded image.
  if not ring.complete: return default(NativeRingRoundBudget)
  const limit = 4095'u64
  var left = limit
  for item in ring.blocks:
    if item.price > left: return default(NativeRingRoundBudget)
    left -= item.price
  let price = uint32(limit-left)
  NativeRingRoundBudget(enabled: true, price: price,
    suffixPrices: [price-uint32(ring.blocks[0].price), uint32(ring.blocks[2].price)])

func successor(item: NativeRingBlock, registers: RegisterFile): uint32 =
  ## Validate the actual final predicate from its committed register checkpoint.
  let left = uint64(registers[item.branch.slots.aIndex])
  let taken = case item.branch.opcode
    of 82: left != item.branch.immediate
    of 88: cast[int64](left) <= cast[int64](item.branch.immediate)
    else: cast[int64](left) < cast[int64](uint64(registers[item.branch.slots.bIndex]))
  if taken: item.yes else: item.no

func validRingReceipt*(ring: NativeRegisterRing, entry: NativeRingIndex,
    destination: uint32, gas, remaining: uint64, context: NativeRingContext,
    registers: RegisterFile): bool =
  ## Require exact weighted debits, a connected prefix and a legitimate unpaid destination.
  if context.entry != uint64(entry) or context.gas > gas or context.remaining > remaining:
    return false
  var attempts = remaining-context.remaining
  var spent = gas-context.gas
  var total = 0'u64
  for index in 0..2:
    let item = ring.blocks[index]
    let visits = context.visits[index]
    if visits > attempts div uint64(item.span): return false
    if item.price != 0 and visits > spent div item.price: return false
    attempts -= visits*uint64(item.span)
    spent -= visits*item.price
    total += visits
  if attempts != 0 or spent != 0: return false
  let partial = int(total mod 3)
  for distance in 0..2:
    # A native path may only visit successive roles until its terminal edge or guard.
    let expected = total div 3 + uint64(ord(distance < partial))
    if context.visits[(int(entry)+distance) mod 3] != expected: return false
  let next = ring.blocks[(int(entry)+partial) mod 3]
  let blocked = context.remaining < uint64(next.span) or context.gas < next.price
  if total == 0: return blocked and destination == next.header
  let last = ring.blocks[(int(entry)+partial+2) mod 3]
  if destination != successor(last, registers): return false
  destination != next.header or blocked
