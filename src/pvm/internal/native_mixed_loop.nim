# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Copied source and invocation receipts for a bounded native mixed self-loop.

import ../[machine, program]
import ./[jit_rules, native_ir, native_read_body, native_read_cycle]

const
  NativeMixedLoopCandidateLimit* = 8 ## Bounded source checks and per-ticket deterministic refusals.
  NativeMixedLoopMinimum* = 3'u32    ## Ordered read, byte store and checked terminal.
  NativeMixedLoopVisitLimit* = 256'u32
  NativeMixedLoopVisitLimitOffset* = NativeCycleGasOffset
  NativeMixedLoopContextBytes* = NativeMixedLoopVisitLimitOffset+8
  NativeMixedLoopExitBit* = 0x80000000'u32

type
  NativeMixedLoop* = object
    ## Copied immutable inputs, bound to a priced original block by the checked frame.
    header*, first*, terminal*, exitHeader*: uint32
    price*, epoch*: uint64
    span*, count*: uint8 ## Original source facts and physical operations, respectively.
    operations*: array[NativeReadFactLimit.int, NativeOperation]
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

func complete*(proof: NativeMixedLoop): bool =
  ## Only one ordered byte store separates a guarded prefix from an infallible suffix.
  let count = uint32(proof.count)
  let span = uint32(proof.span)
  if proof.epoch == 0 or count < NativeMixedLoopMinimum or count > span or
      span > NativeReadFactLimit or proof.terminal >= NativeEntryLimit or
      proof.header >= proof.terminal or proof.terminal-proof.header != count or
      proof.exitHeader >= NativeEntryLimit or proof.exitHeader in proof.header..proof.terminal or
      proof.first > high(uint32)-(span-1) or proof.operations[int(count)-1].opcode != 171:
    return false
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
  let visits = raw and not NativeMixedLoopExitBit
  if funded > NativeMixedLoopVisitLimit or visits > funded or
      proof.count < uint8(NativeMixedLoopMinimum) or proof.count > uint8(
          NativeReadFactLimit): return
  let leavesLoop = (raw and NativeMixedLoopExitBit) != 0
  if visits == 0:
    if leavesLoop: return
  else:
    let slots = proof.operations[int(proof.count)-1].slots
    if leavesLoop != (registers[slots.aIndex] == registers[slots.bIndex]): return
  result = NativeMixedLoopReceipt(valid: true, visits: visits,
    next: (if leavesLoop: proof.exitHeader else: proof.header))
