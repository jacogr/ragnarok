# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Check the shared receipt at the boundary where a native store cannot be replayed.

import std/[assertions, syncio]
import ../../../src/pvm/internal/native_read_cycle

const
  readHeader = 10'u32
  tailHeader = 40'u32
  outside = 99'u32
  layout = NativeCycleLayout(sites: [NativeCycleSite(header: readHeader, price: 60),
    NativeCycleSite(header: 20, price: 3), NativeCycleSite(header: 30, price: 7),
    NativeCycleSite(header: tailHeader, price: 11), NativeCycleSite(header: 50, price: 13),
    NativeCycleSite(header: 60, price: 3), NativeCycleSite(header: 70, price: 1)],
    outsideHeader: outside)

proc checkLayout() =
  ## Bind every emitter displacement to its actual field in the two-borrow ABI.
  var context = default(NativeCycleContext)
  let address = cast[uint64](addr context)
  assert sizeof(NativeCycleContext) == NativeCycleContextBytes
  assert sizeof(NativeCycleWritable) == 24
  assert cast[uint64](addr context.read) == address
  assert cast[uint64](addr context.writable) - address == uint64(NativeCycleWritableOffset)
  assert cast[uint64](addr context.dirty) - address == uint64(NativeCycleDirtyOffset)
  assert cast[uint64](addr context.dirtyWords) - address == uint64(NativeCycleDirtyWordsOffset)
  assert cast[uint64](addr context.gas) - address == uint64(NativeCycleGasOffset)
  assert cast[uint64](addr context.remaining) - address == uint64(NativeCycleRemainingOffset)
  assert cast[uint64](addr context.visits) - address == uint64(NativeCycleVisitsOffset)
  assert cast[uint64](addr context.lastCompleted) - address == uint64(NativeCycleLastOffset)
  assert cast[uint64](addr context.paidRead) - address == uint64(NativeCyclePaidReadOffset)

proc checkReceipt() =
  ## Check literal source-path histories across both invocation boundaries.
  # A declined first read preserves the prepaid block and both budgets.
  let first = NativeCycleContext(gas: 1000, remaining: 1000,
    lastCompleted: NativeCycleNoCompleted, paidRead: 1)
  assert validNativeCycleReceipt(layout, readHeader, 1000, 1000, first)
  assert not validNativeCycleReceipt(layout, tailHeader, 1000, 1000, first)

  # A completed setup before an unpaid store is straight-line progress.
  let afterSetup = NativeCycleContext(gas: 997, remaining: 996,
    visits: [1'u64, 1, 0, 0, 0, 0, 0], lastCompleted: uint64(ord(NativeCycleRole.StoreSetup)))
  assert validNativeCycleReceipt(layout, 30, 1000, 1000, afterSetup)
  assert not hasNativeCycleBackedge(afterSetup.visits)

  # Read, setup, four stores, then a guard miss before the unpaid tail load.
  var afterStore = NativeCycleContext(gas: 969, remaining: 976,
    visits: [1'u64, 1, 1, 0, 0, 0, 0], lastCompleted: uint64(ord(NativeCycleRole.Store)))
  assert validNativeCycleReceipt(layout, tailHeader, 1000, 1000, afterStore)
  assert not hasNativeCycleBackedge(afterStore.visits)
  assert not validNativeCycleReceipt(layout, outside, 1000, 1000, afterStore)
  afterStore.remaining = 975
  assert not validNativeCycleReceipt(layout, tailHeader, 1000, 1000, afterStore)

  # The tail can return to setup and run a second group before reaching another read.
  var round = NativeCycleContext(gas: 899, remaining: 939,
    visits: [1'u64, 2, 2, 2, 1, 1, 1], lastCompleted: uint64(ord(NativeCycleRole.Gate)))
  assert validNativeCycleReceipt(layout, readHeader, 1000, 1000, round)
  assert hasNativeCycleBackedge(round.visits)
  round.gas = 839
  round.remaining = 915
  round.paidRead = 1
  assert validNativeCycleReceipt(layout, readHeader, 1000, 1000, round)
  # The paid-read flag cannot turn an unpaid destination into a replay.
  assert not validNativeCycleReceipt(layout, 60, 1000, 1000, round)

  # A detached store self-cycle has plausible weighted totals and balanced local flow.
  let disconnected = NativeCycleContext(gas: 972, remaining: 980,
    visits: [1'u64, 0, 1, 0, 0, 0, 0], lastCompleted: uint64(ord(NativeCycleRole.Read)))
  assert not validNativeCycleReceipt(layout, 20, 1000, 1000, disconnected)

checkLayout()
checkReceipt()
echo "PASS native read cycle receipt"
