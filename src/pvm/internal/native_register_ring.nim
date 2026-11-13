# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Copied certificates and checked receipts for bounded register loops.
##
## Both lowerers can reserve a complete round at the first header. A side exit
## refunds the gas and attempts of the unexecuted suffix. Entry at either later
## header and a failed whole-round reservation use the original per-header guards.

import ../machine
import ./native_ir

type
  NativeRingIndex* = range[0..2] ## Certificate order follows the closed edges.
  NativeRingBlock* = object ## Complete original charged header, pure body and resolved branch.
    header*, first*, span*, yes*, no*: uint32
    price*: uint64
    body*: array[2, NativeOperation]
    branch*: NativeOperation
  NativeRegisterRing* = object ## Immutable copied worker input without program or invocation borrows.
    blocks*: array[NativeRingIndex, NativeRingBlock] ## x86 pairs leave the third slot empty.
  NativeRingRoundBudget* = object ## Copied immediate costs for one complete pure round.
    enabled*: bool
    price*: uint32
    suffixPrices*: array[2, uint32]
  NativeRingContext* = object ## Two-borrow ABI with an unpaid rotating entry.
    gas*, remaining*: uint64
    visits*: array[NativeRingIndex, uint64]
    entry*: uint64

func nativeRingBlockCount*(ring: NativeRegisterRing): int {.inline.} =
  ## Two x86 blocks share the existing mailbox and receipt layout; the unused slot must be empty.
  when defined(pvmX86Jit) and NativeCheckedReadEnabled:
    if ring.blocks[2].span == 0: return 2
  3

func complete*(ring: NativeRegisterRing): bool =
  ## Check the bounded original opcode shapes and one closed successor per block.
  const
    spans = [3'u32, 2, 3]
    firstOpcodes = [200'u8, 131, 151]
    secondOpcodes = [139'u8, 0, 152]
    branches = [82'u8, 88, 173]
    pairFirstOpcodes = [149'u8, 132]
    pairSecondOpcodes = [200'u8, 0]
    pairBranches = [170'u8, 81]
  let count = nativeRingBlockCount(ring)
  if count == 2 and ring.blocks[2] != default(NativeRingBlock): return false
  for index in 0..<count:
    let item = ring.blocks[index]
    if item.span != spans[index] or item.header >= NativeEntryLimit or
        item.first > high(uint32)-item.span or item.yes >= NativeEntryLimit or
        item.no >= NativeEntryLimit:
      return false
    if count == 2:
      # The pair supports only the measured pure bodies and their original equality branches.
      if item.body[0].opcode != pairFirstOpcodes[index] or
          item.body[1].opcode != pairSecondOpcodes[index] or
          item.branch.opcode != pairBranches[index]:
        return false
    elif item.body[0].opcode != firstOpcodes[index] or
        item.body[1].opcode != secondOpcodes[index] or item.branch.opcode != branches[index]:
      return false
    let next = ring.blocks[(index+1) mod count].header
    if (item.yes == next) == (item.no == next): return false
    let outside = if item.yes == next: item.no else: item.yes
    for other in 0..<count:
      # The other edge resumes checked execution. The original source spans are disjoint.
      let peer = ring.blocks[other]
      if outside == peer.header: return false
      if other != index and (item.header == peer.header or
          (item.first <= peer.first and peer.first-item.first < item.span)):
        return false
    if item.branch.opcode <= 90:
      # Immediate branch operands are the checked sign extension of the encoded word.
      let low = uint32(item.branch.immediate and 0xffffffff'u64)
      if cast[uint64](int64(cast[int32](low))) != item.branch.immediate: return false
  true

func matchesNativeRingShiftPair*(first, second: NativeOperation): bool =
  ## A whole admitted C block may hide the first shift only if the second overwrites it.
  ## The copied slots already account for saturated source register encodings.
  first.opcode == 151 and second.opcode == 152 and
    first.slots.destinationIndex == second.slots.bIndex and
    first.slots.destinationIndex == second.slots.destinationIndex and
    (first.immediate and 63) == (second.immediate and 63)

const
  NativeRingRoundSpan* = 8'u32             ## Total original attempts in the certified three blocks.
  NativeRingRoundSuffixSpans* = [5'u32, 3] ## Attempts to refund after the first or second block.

func nativeRingRoundBudget*(ring: NativeRegisterRing): NativeRingRoundBudget =
  ## Require one shared 12-bit immediate ceiling for the total and both suffixes.
  ## Subtract from the ceiling to reject wide or overflowing totals before narrowing.
  ## A refusal preserves the ordinary guarded image.
  if nativeRingBlockCount(ring) != 3 or not ring.complete: return default(NativeRingRoundBudget)
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
    of 81: left == item.branch.immediate
    of 170: left == uint64(registers[item.branch.slots.bIndex])
    of 82: left != item.branch.immediate
    of 88: cast[int64](left) <= cast[int64](item.branch.immediate)
    else: cast[int64](left) < cast[int64](uint64(registers[item.branch.slots.bIndex]))
  if taken: item.yes else: item.no

func validRingReceipt*(ring: NativeRegisterRing, entry: NativeRingIndex,
    destination: uint32, gas, remaining: uint64, context: NativeRingContext,
    registers: RegisterFile): bool =
  ## Require exact weighted debits, a connected prefix and a legitimate unpaid destination.
  let count = nativeRingBlockCount(ring)
  if int(entry) >= count or (count == 2 and context.visits[2] != 0) or
      context.entry != uint64(entry) or context.gas > gas or context.remaining > remaining:
    return false
  var attempts = remaining-context.remaining
  var spent = gas-context.gas
  var total = 0'u64
  for index in 0..<count:
    let item = ring.blocks[index]
    let visits = context.visits[index]
    if visits > attempts div uint64(item.span): return false
    if item.price != 0 and visits > spent div item.price: return false
    attempts -= visits*uint64(item.span)
    spent -= visits*item.price
    total += visits
  if attempts != 0 or spent != 0: return false
  let partial = int(total mod uint64(count))
  for distance in 0..<count:
    # A native path may only visit successive roles until its terminal edge or guard.
    let expected = total div uint64(count) + uint64(ord(distance < partial))
    if context.visits[(int(entry)+distance) mod count] != expected: return false
  let next = ring.blocks[(int(entry)+partial) mod count]
  let blocked = context.remaining < uint64(next.span) or context.gas < next.price
  if total == 0: return blocked and destination == next.header
  let last = ring.blocks[(int(entry)+partial+count-1) mod count]
  if destination != successor(last, registers): return false
  destination != next.header or blocked
