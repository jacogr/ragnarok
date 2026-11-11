# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Copied read-cycle input and the receipt shared by the ARM and x86 lowerers.
##
## ARM64 checks and debits each new role in native budget registers. Eligible x86-64 images
## use conservative role credits and reconstruct exact gas and attempt balances before return.
## Exhausted credits and images without credits use the exact role guards.
##
## Both reuse the checked first Read reservation and leave Store and Tail preflight refusals
## unpaid. A Read guard miss restores only that Read's staged registers and keeps its reservation
## paid and earlier stores committed. The shared receipt checks exact debits and the continuation.

import ../[machine, program]
import ./[native_ir, native_read_body]

export native_ir.NativeReadCycleEnabled

type
  NativeCycleRole* {.pure.} = enum ## The seven roles of the certified route, independent of guest PCs.
    Read, StoreSetup, Store, Tail, Jump, Outer, Gate
  NativeCycleSite* = object ## An original complete block and its resolved checked header.
    header*, first*: uint32
    price*: uint64
  NativeCycleLayout* = object ## The source geometry shared by lowering and receipt validation.
    sites*: array[NativeCycleRole, NativeCycleSite]
    outsideHeader*: uint32
  NativeCycleWord* = object ## Five distinct lanes and a displacement from the checked word proof.
    valueLane*, shiftLane*, byteLane*, baseLane*, boundLane*: range[0..12]
    displacement*: uint64
  NativeReadCycle* = object ## Copied operations and geometry. The worker receives no frame borrow.
    read*: NativeReadBody
    layout*: NativeCycleLayout
    word*: NativeCycleWord
    tailLoad*, tailStep*, tailBranch*: NativeOperation
    outer*: array[3, NativeOperation]
    gate*: NativeOperation
  NativeCycleWritable* = object ## A true-length borrow from a live private writable allocation.
    first*, length*: uint64
    data*: nil pointer
  NativeCycleVisits* = array[NativeCycleRole, uint64] ## Store counts four-visit groups; all others count blocks.
  NativeCycleContext* = object ## Two-borrow native ABI. The extra writable extents exist only during entry.
    read*: NativeReadContext
    writable*: array[2, NativeCycleWritable]
    dirty*: nil pointer
    dirtyWords*: uint64
    gas*, remaining*: uint64
    visits*: NativeCycleVisits
    lastCompleted*, paidRead*: uint64

const
  NativeCycleSpans*: array[NativeCycleRole, uint64] = [24'u64, 4, 5, 4, 1, 3, 1]
  NativeCycleGroupVisits* = 4'u64
  NativeCycleNoCompleted* = 7'u64
  NativeCycleWritableOffset* = 72
  NativeCycleDirtyOffset* = 120
  NativeCycleDirtyWordsOffset* = 128
  NativeCycleGasOffset* = 136
  NativeCycleRemainingOffset* = 144
  NativeCycleVisitsOffset* = 152
  NativeCycleLastOffset* = 208
  NativeCyclePaidReadOffset* = 216
  NativeCycleContextBytes* = 224

func hasNativeCycleBackedge*(visits: NativeCycleVisits): bool =
  ## A repeated role completed after a native backedge. One store group is one emitted visit.
  for count in visits:
    if count > 1: return true
  false

func nativeCycleTargets*(layout: NativeCycleLayout, role: NativeCycleRole): array[2, uint32] =
  ## Return the original true and false headers; unconditional blocks use the same target twice.
  let sites = layout.sites
  case role
  of NativeCycleRole.Read: [sites[NativeCycleRole.StoreSetup].header, sites[
      NativeCycleRole.StoreSetup].header]
  of NativeCycleRole.StoreSetup: [sites[NativeCycleRole.Store].header, sites[
      NativeCycleRole.Store].header]
  of NativeCycleRole.Store: [sites[NativeCycleRole.Store].header, sites[
      NativeCycleRole.Tail].header]
  of NativeCycleRole.Tail: [sites[NativeCycleRole.StoreSetup].header, sites[
      NativeCycleRole.Jump].header]
  of NativeCycleRole.Jump: [sites[NativeCycleRole.Outer].header, sites[
      NativeCycleRole.Outer].header]
  of NativeCycleRole.Outer: [layout.outsideHeader, sites[NativeCycleRole.Gate].header]
  of NativeCycleRole.Gate: [sites[NativeCycleRole.Outer].header, sites[NativeCycleRole.Read].header]

func sameNativeReadCycle*(left, right: NativeReadCycle): bool =
  ## A restored stream must reproduce every copied operand and source coordinate.
  left.read.sameReadBody(right.read) and left.layout == right.layout and left.word == right.word and
    left.tailLoad == right.tailLoad and left.tailStep == right.tailStep and
    left.tailBranch == right.tailBranch and left.outer == right.outer and left.gate == right.gate

func nativeCycleSuccessor*(cycle: NativeReadCycle, role: NativeCycleRole,
    registers: RegisterFile): uint32 =
  ## Validate the last completed predicate against the published register checkpoint.
  let targets = nativeCycleTargets(cycle.layout, role)
  const sign = 0x8000000000000000'u64
  case role
  of NativeCycleRole.Store:
    if registers[cycle.word.baseLane] != registers[cycle.word.boundLane]: targets[0]
    else: targets[1]
  of NativeCycleRole.Tail:
    let a = uint64(registers[cycle.tailBranch.slots.aIndex])
    let b = uint64(registers[cycle.tailBranch.slots.bIndex])
    if (a xor sign) < (b xor sign): targets[0] else: targets[1]
  of NativeCycleRole.Outer:
    let a = uint64(registers[cycle.outer[2].slots.aIndex])
    if a == cycle.outer[2].immediate: targets[0] else: targets[1]
  of NativeCycleRole.Gate:
    let a = uint64(registers[cycle.gate.slots.aIndex])
    if (a xor sign) <= (cycle.gate.immediate xor sign): targets[0] else: targets[1]
  else:
    # The three unconditional roles have one certified successor.
    targets[0]

func cycleSpend(left: var uint64, visits, price: uint64): bool =
  ## Subtract one weighted count after proving the product fits the remaining delta.
  if price == 0: return true
  if visits > left div price: return false
  left -= visits * price
  true

func cycleConnected(visits: NativeCycleVisits, last: NativeCycleRole): bool =
  ## Derive edge counts between completed units from flow balance at each certified role.
  const R = NativeCycleRole.Read
  const P = NativeCycleRole.StoreSetup
  const S = NativeCycleRole.Store
  const T = NativeCycleRole.Tail
  const J = NativeCycleRole.Jump
  const O = NativeCycleRole.Outer
  const G = NativeCycleRole.Gate
  if visits[R] == 0 or visits[last] == 0: return false
  var incoming = visits
  var outgoing = visits
  dec incoming[R]
  dec outgoing[last]
  if outgoing[R] > incoming[P] or incoming[T] > outgoing[S] or
      incoming[R] > outgoing[G] or outgoing[J] > incoming[O]: return false
  let tailToSetup = incoming[P] - outgoing[R]
  let storeToStore = outgoing[S] - incoming[T]
  let gateToOuter = outgoing[G] - incoming[R]
  if tailToSetup > outgoing[T] or outgoing[T] - tailToSetup != incoming[J] or
      storeToStore > incoming[S] or incoming[S] - storeToStore != outgoing[P] or
      incoming[O] - outgoing[J] != gateToOuter or outgoing[O] != incoming[G]: return false
  # The only route to a role's first visit is the forward spine. Backedges cannot establish
  # reachability, even when a disconnected cycle balances its own incoming and outgoing counts.
  (visits[P] == 0 or outgoing[R] != 0) and
    (visits[S] == 0 or outgoing[P] != 0) and
    (visits[T] == 0 or incoming[T] != 0) and
    (visits[J] == 0 or incoming[J] != 0) and
    (visits[O] == 0 or outgoing[J] != 0) and
    (visits[G] == 0 or incoming[G] != 0)

func validNativeCycleReceipt*(layout: NativeCycleLayout, destination: uint32,
    gas, remaining: uint64, context: NativeCycleContext): bool =
  ## Check the exact consumed reservations and the topology of the committed path.
  if context.gas > gas or context.remaining > remaining or context.paidRead > 1 or
      context.lastCompleted > NativeCycleNoCompleted: return false
  let paidRead = context.paidRead == 1
  let readHeader = layout.sites[NativeCycleRole.Read].header
  if paidRead and destination != readHeader: return false
  if context.lastCompleted == NativeCycleNoCompleted:
    # A first-read guard miss preserves the original paid reservation and all invocation state.
    return paidRead and context.visits == default(NativeCycleVisits) and
      context.gas == gas and context.remaining == remaining
  let last = NativeCycleRole(context.lastCompleted)
  let targets = nativeCycleTargets(layout, last)
  if destination != targets[0] and destination != targets[1]: return false
  if not cycleConnected(context.visits, last): return false
  var attempts = remaining - context.remaining
  var spent = gas - context.gas
  for role in NativeCycleRole:
    # The first read was paid by the checked header. A later paid read miss replaces that credit.
    var units = context.visits[role]
    var span = NativeCycleSpans[role]
    var price = layout.sites[role].price
    if role == NativeCycleRole.Read and not paidRead: dec units
    if role == NativeCycleRole.Store:
      # Native grouping commits four whole original byte iterations as one checked-equivalent unit.
      if price > high(uint64) div NativeCycleGroupVisits: return false
      span *= NativeCycleGroupVisits
      price *= NativeCycleGroupVisits
    if not cycleSpend(attempts, units, span) or not cycleSpend(spent, units, price): return false
  attempts == 0 and spent == 0
