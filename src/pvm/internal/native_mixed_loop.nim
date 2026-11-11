# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Copied source and invocation receipts for a bounded native mixed self-loop.

import ../[machine, program]
import ./[jit_rules, native_ir, native_read_body, native_read_cycle]

const
  NativeMixedLoopCandidateLimit* = 8 ## Accepted source inventory and per-ticket refusals stay bounded.
  NativeMixedLoopReconstructionLimit* = 16 ## Cold source proof attempts per stream epoch, including refusals.
  NativeMixedLoopEntryLimit* = NativeMixedLoopCandidateLimit ## One arena preserves the ranked inventory's slot identities.
  NativeMixedLoopMinimum* = 3'u32 ## Ordered read, byte store and checked terminal.
  NativeMixedLoopVisitLimit* = 256'u32
  NativeMixedLoopVisitLimitOffset* = NativeCycleGasOffset
  NativeMixedLoopContextBytes* = NativeMixedLoopVisitLimitOffset+8
  NativeMixedLoopExitBit* = 0x80000000'u32

const
  NativeMixedLoopVisitMask = 0x1ff'u32
  NativeMixedLoopGuardShift* = 9
  NativeMixedLoopGuardMask = 0x3f'u32

func nativeMixedLoopStoreWidth*(opcode: byte): uint32 =
  ## The paid path admits relative U8 and absolute U32 Stores.
  case opcode
  of 120: 1'u32
  of 61: 4'u32
  else: 0'u32

type
  NativeMixedLoop* = object
    ## Copied immutable inputs, bound to a priced original block by the checked frame.
    header*, first*, terminal*, exitHeader*: uint32
    price*, epoch*: uint64
    span*, count*: uint8 ## Original source facts and physical operations, respectively.
    operations*: array[NativeReadFactLimit.int, NativeOperation]
    paidGuards*: uint32  ## Physical memory sites that can return an original paid continuation.
  NativeMixedLoopContext* = object
    ## Fresh true-length region borrows followed by a funded visit ceiling.
    read*: NativeReadContext
    writable*: array[2, NativeCycleWritable]
    dirty*: nil pointer
    dirtyWords*, visitLimit*: uint64
  NativeMixedLoopReceipt* = object
    ## Validated committed visits and the next original unpaid header.
    valid*: bool
    visits*, next*: uint32
    paid*: bool

func nativeMixedLoopPaidGuards*(proof: NativeMixedLoop): uint32 =
  ## Admit the source order Read, byte Store, Read, word Store and an infallible suffix.
  if proof.count < 5 or proof.count > uint8(NativeReadFactLimit): return 0
  var guards = 0'u32
  var stores = 0
  var read = false
  for index in 0..<int(proof.count)-1:
    let opcode = proof.operations[index].opcode
    let width = nativeMixedLoopStoreWidth(opcode)
    if width != 0:
      if not read or (stores == 0 and width != 1) or (stores == 1 and width != 4) or stores == 2:
        return 0
      inc stores
      read = false
      guards = guards or (1'u32 shl index)
    elif nativeReadOpcode(nativeReadEncodingOpcode(opcode)):
      if stores == 2: return 0
      read = true
      guards = guards or (1'u32 shl index)
    elif not supportedScalarOpcode(opcode): return 0
  if stores == 2: guards else: 0'u32

func complete*(proof: NativeMixedLoop): bool =
  ## Admit a transactional byte-store body or a sealed paid continuation body.
  let count = uint32(proof.count)
  let span = uint32(proof.span)
  if proof.epoch == 0 or count < NativeMixedLoopMinimum or count > span or
      span > NativeReadFactLimit or proof.terminal >= NativeEntryLimit or
      proof.header >= proof.terminal or proof.terminal-proof.header != count or
      proof.exitHeader >= NativeEntryLimit or proof.exitHeader in proof.header..proof.terminal or
      proof.first > high(uint32)-(span-1) or proof.operations[int(count)-1].opcode != 171:
    return false
  if proof.paidGuards != 0: return proof.paidGuards == nativeMixedLoopPaidGuards(proof)
  var read = false
  var store = false
  for index in 0..<int(count)-1:
    let opcode = proof.operations[index].opcode
    if opcode == 120:
      if store or not read: return false
      store = true
    elif nativeReadOpcode(nativeReadEncodingOpcode(opcode)):
      if store: return false
      read = true
    elif not supportedScalarOpcode(opcode): return false
  store

func nativeMixedLoopBudget*(span: uint8, price, gas, remaining: uint64): uint32 =
  ## Fund only complete original visits, including any folded noops.
  if span < uint8(NativeMixedLoopMinimum) or span > uint8(NativeReadFactLimit): return 0
  let bySteps = remaining div uint64(span)
  let cap = uint64(NativeMixedLoopVisitLimit)
  let funded = if bySteps < cap: bySteps else: cap
  if price != 0:
    let byGas = gas div price
    if byGas < funded: return uint32(byGas)
  uint32(funded)

func nativeMixedLoopReceipt*(proof: NativeMixedLoop, funded, raw: uint32,
    registers: RegisterFile): NativeMixedLoopReceipt =
  ## Refused work keeps its current header. A committed visit's last predicate must match its exit.
  result = default(NativeMixedLoopReceipt)
  if funded > NativeMixedLoopVisitLimit or
      proof.count < uint8(NativeMixedLoopMinimum) or proof.count > uint8(
          NativeReadFactLimit): return
  let leavesLoop = (raw and NativeMixedLoopExitBit) != 0
  var visits = raw and not NativeMixedLoopExitBit
  if proof.paidGuards != 0:
    const packed = NativeMixedLoopVisitMask or
      (NativeMixedLoopGuardMask shl NativeMixedLoopGuardShift) or NativeMixedLoopExitBit
    if funded == 0 or (raw and not packed) != 0: return
    visits = raw and NativeMixedLoopVisitMask
    let guard = (raw shr NativeMixedLoopGuardShift) and NativeMixedLoopGuardMask
    if guard != 0:
      if leavesLoop or visits >= funded or guard >= uint32(proof.count) or
          (proof.paidGuards and (1'u32 shl (guard-1))) == 0: return
      return NativeMixedLoopReceipt(valid: true, visits: visits, next: proof.header+guard, paid: true)
  if visits > funded: return
  if visits == 0:
    if leavesLoop: return
  else:
    let slots = proof.operations[int(proof.count)-1].slots
    if leavesLoop != (registers[slots.aIndex] == registers[slots.bIndex]): return
  result = NativeMixedLoopReceipt(valid: true, visits: visits,
    next: (if leavesLoop: proof.exitHeader else: proof.header))

type NativeMixedLoopSet* = object
  ## Ordered exact proofs share one auxiliary arena and one runtime credit.
  ## Occupancy bits identify slots only inside this complete source-bound set.
  ## Equal masks from different sets do not identify equal source or entry authority.
  count*: uint8
  proofs*: array[NativeMixedLoopEntryLimit, NativeMixedLoop]

func nativeMixedLoopDisjoint*(left, right: NativeMixedLoop): bool =
  ## Both bodies and their checked outside continuations keep independent patch ownership.
  if not left.complete or not right.complete or left.epoch != right.epoch: return false
  (uint64(left.first)+uint64(left.span) <= uint64(right.first) or
    uint64(right.first)+uint64(right.span) <= uint64(left.first)) and
    (left.terminal < right.header or right.terminal < left.header) and
    left.exitHeader notin right.header..right.terminal and
    right.exitHeader notin left.header..left.terminal

func complete*(set: NativeMixedLoopSet): bool =
  if set.count == 0 or set.count > uint8(NativeMixedLoopEntryLimit): return false
  for index in 0..<int(set.count):
    if not set.proofs[index].complete: return false
  for left in 0..<int(set.count):
    for right in left+1..<int(set.count):
      if not nativeMixedLoopDisjoint(set.proofs[left], set.proofs[right]): return false
  true

func singleNativeMixedLoop*(proof: NativeMixedLoop): NativeMixedLoopSet =
  result = default(NativeMixedLoopSet)
  result.count = 1
  result.proofs[0] = proof

func sameNativeMixedLoopSet*(left, right: NativeMixedLoopSet): bool =
  ## Compare active exact source proofs without inspecting unused inventory capacity.
  if left.count == 0 or left.count > uint8(NativeMixedLoopEntryLimit) or
      left.count != right.count: return false
  for index in 0..<int(left.count):
    if left.proofs[index] != right.proofs[index]: return false
  true
