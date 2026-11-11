# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prove when the ARM64 connected Read can borrow a descriptor window across roles.
## x86-64 retains the same invariant-base check at its lowering site to preserve
## the linked host layout observed in matched DOOM tick timing.

import ./[jit_rules, native_read_body, native_read_cycle]

func entryReadWindow*(cycle: NativeReadCycle): NativeReadWindow =
  ## Each emitted role must preserve the window's guest base lane. Native entry
  ## still proves the first descriptor covers all five qwords before borrowing
  ## the pointer. A pointer borrow retains no bytes across Stores or invocations.
  result = default(NativeReadWindow)
  let window = nativeReadWindow(cycle.read)
  if window.operations == 0: return
  let base = window.baseLane
  let word = cycle.word
  for index in 0..<cycle.read.len:
    # This copied body includes the separate StoreSetup's scalar writes.
    let op = cycle.read.operation(index)
    let destination = if nativeReadOpcode(nativeReadEncodingOpcode(op.opcode)): op.slots.aIndex
      else: op.slots.destinationIndex
    if destination == base: return
  if base in [word.baseLane, word.shiftLane, word.byteLane, cycle.tailLoad.slots.aIndex,
               cycle.tailStep.slots.destinationIndex, cycle.outer[0].slots.destinationIndex,
               cycle.outer[1].slots.destinationIndex]: return
  result = window
