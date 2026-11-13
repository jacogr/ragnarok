# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Source-bound static control flow for a bounded native graph. Original block prices and
## source attempts remain independent. Lowering can link only positive checked successors.
## Each native entry commits at most eight original reservations and returns their order.
## The checked bridge verifies this receipt before exposing a successor or resuming a paid
## memory operation. Fault handling and dynamic control remain with the checked stream.

import ./[jit_rules, native_ir, native_mixed_loop, native_read_body]

const
  NativeFusionTrainingFloor* = 524288'u64 ## Prior settled attempts before a sampling segment.
  NativeFusionBlockLimit* = 128           ## One ranked, runtime-owned graph.
  NativeFusionVisitLimit* = 8             ## One byte per reserved block in the returned path.
  NativeFusionImageLimit* = 128*1024      ## Total executable bytes in the optional arena.
  NativeFusionGasOffset* = NativeMixedLoopContextBytes
  NativeFusionQuotaOffset* = NativeFusionGasOffset+8
  NativeFusionPathOffset* = NativeFusionQuotaOffset+8
  NativeFusionPaidOffset* = NativeFusionPathOffset+8

type
  NativeFusionBlock* = object
    ## The source walk copies only verified non-noop body operations. Targets are
    ## [false, true]; a missing first target leaves the terminal to checked execution.
    header*, terminal*, first*, span*: uint32
    price*: uint64
    targets*: array[2, uint32]
    branch*: NativeOperation
    operations*: array[int(NativeReadFactLimit)-1, NativeOperation]
    guards*: uint32 ## Only these body nodes can be returned as paid refusals.
  NativeFusionContext* = object
    ## Common read/store descriptors with an independent exact gas/quota ledger.
    memory*: NativeMixedLoopContext
    gas*, remaining*, path*, paid*: uint64
  NativeFusionExit* = object
    ## A successful validation names the original header of the last paid block.
    valid*: bool
    paidHeader*, attempted*: uint32
    branches*: bool

func complete*(item: NativeFusionBlock): bool =
  ## Validate copied scalar geometry and all supported opcode and guard identities.
  if item.header >= item.terminal or item.terminal >= NativeEntryLimit or item.span == 0 or
      item.span > NativeReadFactLimit or item.terminal-item.header > item.span or
      item.first > high(uint32)-(item.span-1):
    return false
  let count = int(item.terminal-item.header)-1
  var guards = 0'u32
  for index in 0..<count:
    # Dynamic memory may decline at its original site after earlier effects.
    let op = item.operations[index].opcode
    if nativeMixedLoopStoreWidth(op) != 0 or nativeReadOpcode(nativeReadEncodingOpcode(op)):
      guards = guards or (1'u32 shl index)
    elif not supportedScalarOpcode(op):
      return false
  if guards != item.guards: return false
  let no = item.targets[0]
  let yes = item.targets[1]
  if no == NativeEntryFailure: return yes == NativeEntryFailure and count != 0
  if no >= NativeEntryLimit: return false
  if yes == NativeEntryFailure: return item.branch.opcode in [1'u8, 40]
  if yes >= NativeEntryLimit or item.branch.opcode notin {81'u8..90, 170..175}: return false
  if item.branch.opcode <= 90:
    # Immediate predicates use the same full-width sign extension as checked dispatch.
    let low = uint32(item.branch.immediate and 0xffffffff'u64)
    if cast[uint64](int64(cast[int32](low))) != item.branch.immediate: return false
  true

func nativeFusionExit*(blocks: openArray[NativeFusionBlock], entry, next: uint32,
    gas, quota: uint64, state: NativeFusionContext): NativeFusionExit =
  ## Consume the path backwards, checking each exact reservation and permitted edge.
  ## Last-predicate validation uses the committed register file at the frame bridge.
  result = default(NativeFusionExit)
  if state.paid > 1 or state.gas > gas or state.remaining > quota or
      quota-state.remaining > uint64(NativeFusionVisitLimit)*uint64(NativeReadFactLimit):
    return
  var path = state.path
  if path == 0:
    result.valid = state.paid == 0 and next == entry and state.gas == gas and state.remaining == quota
    return
  var successor = next
  var leftGas = gas
  var leftQuota = quota
  var last = true
  var completePath = false
  while path != 0:
    # A zero slot inside a nonempty path is invalid. Rank slots are one-based.
    let slot = int(path and 255)-1
    if slot < 0 or slot >= blocks.len: return
    let item {.cursor.} = blocks[slot]
    if item.span == 0 or item.span > NativeReadFactLimit or item.price > leftGas or uint64(
        item.span) > leftQuota: return
    leftGas -= item.price
    leftQuota -= uint64(item.span)
    if last and state.paid != 0:
      # An interior refusal names a certified memory guard. A paid terminal is
      # legal only when native lowering deliberately left the terminal checked.
      if next <= item.header or next > item.terminal: return
      if next == item.terminal:
        if item.targets[0] != NativeEntryFailure: return
      else:
        let position = next-item.header-1
        if position >= 32 or (item.guards and (1'u32 shl int(position))) == 0:
          return
      result.paidHeader = item.header+1
    else:
      if successor notin item.targets: return
      completePath = true
    successor = item.header
    last = false
    path = path shr 8
  if successor != entry or leftGas != state.gas or leftQuota != state.remaining:
    return default(NativeFusionExit)
  result.valid = true
  result.attempted = uint32(quota-leftQuota)
  result.branches = completePath
