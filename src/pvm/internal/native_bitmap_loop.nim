# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Copied certificate and unpaid continuation receipt for a five-block bitmap scan.

import ../[machine, program]
import ./native_ir

type
  BitmapBlock* {.pure.} = enum ## Original block roles, independent of guest and stream addresses.
    Advance, Parity, Midpoint, Index, Read
  BitmapExit* {.pure.} = enum ## Checked edges outside the native route.
    End, Reset, Trap
  NativeBitmapSite* = object ## A complete original priced block and its cached checked header.
    header*, first*: uint32
    price*: uint64
  NativeBitmapLoop* = object ## POD copied to the worker. Invocation addresses stay in the frame.
    epoch*: uint64
    sites*: array[BitmapBlock, NativeBitmapSite]
    exits*: array[BitmapExit, uint32]
    operations*: array[16, NativeOperation]
  NativeBitmapContext* = object ## Fresh two-borrow ABI. Every return is an unpaid checked header.
    gas*, remaining*: uint64
    visits*: array[BitmapBlock, uint64]
    last*: uint64
    base*, length*: uint64
    bytes*: nil ptr byte

const
  BitmapSpans* = [3'u64, 2, 2, 2, 7]
  BitmapOpcodes* = [149'u8, 200, 170, 132, 81, 152, 174, 152, 174,
    151, 200, 130, 133, 208, 132, 40]
  BitmapFixupCount* = 27 ## Ten budget guards, four read guards, five transfers and eight return stubs.
  BitmapNoCompleted* = 5'u64
  BitmapBaseOffset* = 64'u32
  BitmapLengthOffset* = 72'u32
  BitmapPointerOffset* = 80'u32
  BitmapContextBytes* = 88

func complete*(loop: NativeBitmapLoop): bool =
  ## Admit only the decoded aliasing and immediates implemented by both bitmap lowerers.
  if loop.epoch == 0: return false
  for role in BitmapBlock:
    let item = loop.sites[role]
    let span = uint32(BitmapSpans[ord(role)])
    if item.header >= NativeEntryLimit-span or item.first > high(uint32)-span or item.price == 0:
      return false
    for other in BitmapBlock:
      if other == role: continue
      let peer = loop.sites[other]
      if (peer.header >= item.header and peer.header-item.header <= span) or
          (peer.first >= item.first and peer.first-item.first < span): return false
    for side in BitmapExit:
      let target = loop.exits[side]
      if target >= NativeEntryLimit or
          (target >= item.header and target-item.header <= span): return false
  for index in 0..<BitmapOpcodes.len:
    if loop.operations[index].opcode != BitmapOpcodes[index]: return false
  template ops: untyped = loop.operations
  ops[0].slots.destinationIndex == 11 and ops[0].slots.bIndex == 11 and ops[0].immediate == 1 and
    ops[1].slots.destinationIndex == 5 and ops[1].slots.aIndex == 5 and ops[1].slots.bIndex == 12 and
    ops[2].slots.aIndex == 7 and ops[2].slots.bIndex == 11 and
    ops[3].slots.destinationIndex == 12 and ops[3].slots.bIndex == 11 and ops[3].immediate == 1 and
    ops[4].slots.aIndex == 12 and ops[4].immediate == 0 and
    ops[5].slots.destinationIndex == 12 and ops[5].slots.bIndex == 11 and ops[5].immediate == 1 and
    ops[6].slots.aIndex == 12 and ops[6].slots.bIndex == 10 and
    ops[7].slots.destinationIndex == 6 and ops[7].slots.bIndex == 11 and ops[7].immediate == 7 and
    ops[8].slots.aIndex == 6 and ops[8].slots.bIndex == 9 and
    ops[9].slots.destinationIndex == 6 and ops[9].slots.bIndex == 6 and ops[9].immediate == 3 and
    ops[10].slots.destinationIndex == 6 and ops[10].slots.aIndex == 6 and ops[10].slots.bIndex == 8 and
    ops[11].slots.aIndex == 6 and ops[11].slots.bIndex == 6 and ops[11].immediate == 0 and
    ops[12].slots.destinationIndex == 6 and ops[12].slots.bIndex == 6 and ops[12].immediate == high(
        uint64) and
    ops[13].slots.destinationIndex == 12 and ops[13].slots.aIndex == 6 and ops[13].slots.bIndex == 12 and
    ops[14].slots.destinationIndex == 12 and ops[14].slots.bIndex == 12 and ops[14].immediate == 1

func bitmapAddress*(registers: RegisterFile): uint64 =
  ## Match the original low-32-bit effective address after the shift and addition.
  ((uint64(registers[6]) shl 3)+uint64(registers[8])) and 0xffffffff'u64

func bitmapReadable*(context: NativeBitmapContext, registers: RegisterFile): bool =
  ## Refuse before reserving or changing registers when the entire word is outside the borrow.
  let address = bitmapAddress(registers)
  context.bytes != nil and address >= 65536 and address <= 0xfffffff7'u64 and
    address >= context.base and context.length >= 8 and address-context.base <= context.length-8

func validBitmapReceipt*(loop: NativeBitmapLoop, destination: uint32,
    gas, remaining: uint64, context: NativeBitmapContext, registers: RegisterFile): bool =
  ## Require a connected history and exact weighted debits before checked execution resumes.
  const A = BitmapBlock.Advance
  const P = BitmapBlock.Parity
  const M = BitmapBlock.Midpoint
  const I = BitmapBlock.Index
  const R = BitmapBlock.Read
  if context.gas > gas or context.remaining > remaining or context.last > BitmapNoCompleted:
    return false
  var attempts = remaining-context.remaining
  var spent = gas-context.gas
  for role in BitmapBlock:
    let span = BitmapSpans[ord(role)]
    let price = loop.sites[role].price
    let count = context.visits[role]
    if price == 0 or count > attempts div span or count > spent div price: return false
    attempts -= count*span
    spent -= count*price
  if attempts != 0 or spent != 0: return false
  if context.last == BitmapNoCompleted:
    return context.gas == gas and context.remaining == remaining and
      destination == loop.sites[A].header and (remaining < BitmapSpans[ord(A)] or gas < loop.sites[A].price)
  let last = BitmapBlock(context.last)
  if context.visits[A] == 0 or context.visits[last] == 0: return false
  var incoming = context.visits
  var outgoing = context.visits
  dec incoming[A]
  dec outgoing[last]
  # Advance enters Parity. Parity splits between the Advance backedge and the forward spine.
  # Midpoint and Index each have only one internal successor. Read returns to Advance.
  if outgoing[A] != incoming[P] or incoming[M] > outgoing[P] or
      outgoing[M] != incoming[I] or outgoing[I] != incoming[R] or
      outgoing[P]-incoming[M] > incoming[A] or
      outgoing[R] != incoming[A]-(outgoing[P]-incoming[M]): return false
  let next = case last
    of A:
      if registers[7] == registers[11]: return destination == loop.exits[BitmapExit.End]
      P
    of P:
      if uint64(registers[12]) == 0: A else: M
    of M:
      if uint64(registers[12]) >= uint64(registers[10]):
        return destination == loop.exits[BitmapExit.Reset]
      I
    of I:
      if uint64(registers[6]) >= uint64(registers[9]):
        return destination == loop.exits[BitmapExit.Trap]
      R
    of R: A
  destination == loop.sites[next].header and
    (context.remaining < BitmapSpans[ord(next)] or context.gas < loop.sites[next].price or
      (next == R and not bitmapReadable(context, registers)))
