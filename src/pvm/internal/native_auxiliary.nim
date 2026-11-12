# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Typed source requests for the runtime's single shared auxiliary image.
## An ordered slot names either an existing memory self-loop or one complete connected
## Read cycle. A cycle is one entry with its original Read-body ABI, not seven separately
## composable graph nodes. Exact ordered source proofs, primary ownership and published
## entry kinds together authorize entry; an occupancy mask or offset alone never does.
##
## The host lazily owns only the requested loop payloads and at most one cycle payload.
## Runtime storage retains one move-only request handle rather than eight maximum-size
## heterogeneous objects. While locked, the worker copies individual POD proofs into its
## own bounded plan. It never receives a managed ref/seq or an invocation memory borrow.
## The runtime must keep the request immutable until retirement and collect it on the
## host after worker/entry views finish; a parked retired request is still the sole owner.

import std/assertions
import ./[native_ir, native_mixed_loop, native_read_cycle]

const
  NativeAuxiliaryEntryLimit* = NativeMixedLoopEntryLimit
    ## One image preserves at most eight ranked source-slot identities.
  NativeAuxiliaryObservationLimit* = 15
    ## Seven cycle roles, its outside observation and at most seven loop observations.

type
  NativeAuxiliaryKind* {.pure.} = enum
    ## Each kind selects its own source validator, entry context and receipt contract.
    SelfLoop, ReadCycle
  NativeAuxiliaryBuildStatus* {.pure.} = enum
    ## Allocation refusal is retryable and must not poison source refusal tokens.
    Invalid, AllocationRefused, Ready
  NativeAuxiliarySlot = object
    ## Private ordered indirection never exposes an unchecked heterogeneous payload.
    kind: NativeAuxiliaryKind
    payload: uint8
  NativeAuxiliaryPlan* = object
    ## Worker/frame-local POD; a source epoch binds every active typed payload.
    count, loopCount: uint8
    hasCycle: bool
    epoch: uint64
    order: array[NativeAuxiliaryEntryLimit, NativeAuxiliarySlot]
    loops: array[NativeAuxiliaryEntryLimit, NativeMixedLoop]
    cycle: NativeReadCycle
  NativeAuxiliaryCycleData = ref object
    ## This optional allocation exists only for a request containing a cycle.
    proof: NativeReadCycle
  NativeAuxiliaryRequestData = ref object
    ## Host-only managed storage; every child is immutable after request construction.
    count: uint8
    epoch: uint64
    order: array[NativeAuxiliaryEntryLimit, NativeAuxiliarySlot]
    loops: seq[NativeMixedLoop]
    cycle: nil NativeAuxiliaryCycleData
  NativeAuxiliaryRequest* = object
    ## Exclusive host handle. Destruction is legal only after its runtime retires views.
    data: nil NativeAuxiliaryRequestData

proc `=copy`*(destination: var NativeAuxiliaryRequest,
    source: NativeAuxiliaryRequest) {.error.}
  ## A second owner could release a request while the worker or a lease still observes it.

proc `=dup`*(source: NativeAuxiliaryRequest): NativeAuxiliaryRequest {.error.}
  ## Queue handoff and host collection transfer the sole handle explicitly.

proc `=wasMoved`*(request: var NativeAuxiliaryRequest) {.nodestroy, inline.} =
  ## Delegate the managed child's move hook so the old handle no longer owns storage.
  `=wasMoved`(request.data)

proc `=destroy`*(request: var NativeAuxiliaryRequest) =
  ## The scheduler enforces host-only destruction after retirement or failed construction.
  `=destroy`(request.data)

func len*(plan: NativeAuxiliaryPlan): int =
  ## Return the bounded number of active ordered source slots.
  int(plan.count)

func sourceEpoch*(plan: NativeAuxiliaryPlan): uint64 =
  ## A source epoch is a comparison field, never independent executable authority.
  plan.epoch

func isEmpty*(request: NativeAuxiliaryRequest): bool =
  ## Empty handles own no payload and may receive a constructor or move handoff.
  request.data == nil

func kind*(plan: NativeAuxiliaryPlan, index: uint8): NativeAuxiliaryKind =
  ## A caller must first prove this index belongs to the complete active order.
  assert index < plan.count and index < uint8(NativeAuxiliaryEntryLimit)
  plan.order[int(index)].kind

func loopProof*(plan: var NativeAuxiliaryPlan, index: uint8): lent NativeMixedLoop =
  ## Borrow only from the caller's first argument after its active kind/index guards.
  assert index < plan.count and index < uint8(NativeAuxiliaryEntryLimit)
  let slot = plan.order[int(index)]
  assert slot.kind == NativeAuxiliaryKind.SelfLoop and slot.payload < plan.loopCount
  plan.loops[int(slot.payload)]

func cycleProof*(plan: var NativeAuxiliaryPlan, index: uint8): lent NativeReadCycle =
  ## A different ABI cannot access this payload merely by reusing its occupancy bit.
  assert index < plan.count and index < uint8(NativeAuxiliaryEntryLimit)
  assert plan.order[int(index)].kind == NativeAuxiliaryKind.ReadCycle and plan.hasCycle
  plan.cycle

func cycleTerminal(cycle: NativeReadCycle, role: NativeCycleRole): uint64 =
  ## Read and Setup own exact terminals. Tail's certified leading noop folds into
  ## its header just like Read's; the original four-fact debit remains unchanged.
  case role
  of NativeCycleRole.Read: uint64(cycle.read.info.terminal)
  of NativeCycleRole.StoreSetup: uint64(cycle.read.continuationInfo.terminal)
  of NativeCycleRole.Tail: uint64(cycle.layout.sites[role].header)+NativeCycleSpans[role]-1
  else: uint64(cycle.layout.sites[role].header)+NativeCycleSpans[role]

func cycleComplete(cycle: NativeReadCycle): bool =
  ## Structural bounds supplement, never replace, the checked frame's full source builder.
  if not cycle.read.complete or cycle.read.info.epoch == 0 or
      cycle.layout.outsideHeader >= NativeEntryLimit:
    return false
  let read = cycle.read.info
  let continuation = cycle.read.continuationInfo
  if cycle.layout.sites[NativeCycleRole.Read].header != read.header or
      cycle.layout.sites[NativeCycleRole.Read].first != read.first or
      cycle.layout.sites[NativeCycleRole.StoreSetup].header != continuation.header or
      cycle.layout.sites[NativeCycleRole.StoreSetup].price != continuation.price:
    return false
  for role in NativeCycleRole:
    # Original fact extents use widened arithmetic before any overlap comparison.
    let site = cycle.layout.sites[role]
    let span = NativeCycleSpans[role]
    let terminal = cycleTerminal(cycle, role)
    if site.header >= NativeEntryLimit or terminal <= uint64(site.header) or
        terminal >= uint64(NativeEntryLimit) or uint64(site.first)+span > uint64(high(uint32))+1:
      return false
    if uint64(cycle.layout.outsideHeader) in uint64(site.header)..terminal: return false
    if role == NativeCycleRole.Store and site.price > high(uint64) div NativeCycleGroupVisits:
      return false
    for earlier in NativeCycleRole:
      # Distinct original blocks cannot claim the same facts or an interior patch coordinate.
      if ord(earlier) >= ord(role): break
      let previous = cycle.layout.sites[earlier]
      let before = uint64(previous.first)+NativeCycleSpans[earlier] <= uint64(site.first)
      let after = uint64(site.first)+span <= uint64(previous.first)
      if not before and not after: return false
      if uint64(previous.header) <= terminal and
          cycleTerminal(cycle, earlier) >= uint64(site.header): return false
  true

func cycleLoopDisjoint(cycle: NativeReadCycle, loop: NativeMixedLoop): bool =
  ## The complete cycle footprint includes all roles and checked outside continuations.
  if not cycleComplete(cycle) or not loop.complete or cycle.read.info.epoch != loop.epoch:
    return false
  if cycle.layout.outsideHeader in loop.header..loop.terminal: return false
  for role in NativeCycleRole:
    # Original fact and cached handler intervals are independently source-bound.
    let site = cycle.layout.sites[role]
    let span = NativeCycleSpans[role]
    let before = uint64(site.first)+span <= uint64(loop.first)
    let after = uint64(loop.first)+uint64(loop.span) <= uint64(site.first)
    if not before and not after: return false
    let terminal = cycleTerminal(cycle, role)
    if uint64(loop.header) <= terminal and uint64(loop.terminal) >= uint64(site.header):
      return false
    if uint64(loop.exitHeader) in uint64(site.header)..terminal:
      return false
  true

func initNativeAuxiliaryPlan*(epoch: uint64): NativeAuxiliaryPlan =
  ## Empty plans retain their intended source epoch but are not complete requests.
  NativeAuxiliaryPlan(epoch: epoch)

proc add*(plan: var NativeAuxiliaryPlan, proof: NativeMixedLoop): bool =
  ## Append one already source-certified loop without changing the plan on refusal.
  if plan.count >= uint8(NativeAuxiliaryEntryLimit) or not proof.complete or
      proof.epoch != plan.epoch:
    return false
  for index in 0..<int(plan.loopCount):
    # Ordered source inventory and resident occupancy remain separate bounded concepts.
    if not nativeMixedLoopDisjoint(plan.loops[index], proof): return false
  if plan.hasCycle and not cycleLoopDisjoint(plan.cycle, proof): return false
  let payload = plan.loopCount
  plan.loops[int(payload)] = proof
  plan.order[int(plan.count)] = NativeAuxiliarySlot(kind: NativeAuxiliaryKind.SelfLoop,
      payload: payload)
  inc plan.loopCount
  inc plan.count
  true

proc add*(plan: var NativeAuxiliaryPlan, proof: NativeReadCycle): bool =
  ## A complete existing seven-role cycle occupies one typed slot and one payload.
  if plan.count >= uint8(NativeAuxiliaryEntryLimit) or plan.hasCycle or
      not cycleComplete(proof) or proof.read.info.epoch != plan.epoch:
    return false
  for index in 0..<int(plan.loopCount):
    # No cycle role may overlap another entry's original interval or patch ownership.
    if not cycleLoopDisjoint(proof, plan.loops[index]): return false
  plan.cycle = proof
  plan.hasCycle = true
  plan.order[int(plan.count)] = NativeAuxiliarySlot(kind: NativeAuxiliaryKind.ReadCycle)
  inc plan.count
  true

func complete*(plan: NativeAuxiliaryPlan): bool =
  ## Reject unbound, missing, duplicated or unused active payload mappings before allocation.
  if plan.epoch == 0 or plan.count == 0 or plan.count > uint8(NativeAuxiliaryEntryLimit) or
      int(plan.loopCount)+int(plan.hasCycle) != int(plan.count):
    return false
  var loops = 0'u8
  var cycle = false
  for index in 0..<int(plan.count):
    # Private construction normally guarantees this mapping; copied plans still validate fully.
    let slot = plan.order[index]
    case slot.kind
    of NativeAuxiliaryKind.SelfLoop:
      if slot.payload >= plan.loopCount: return false
      let bit = 1'u8 shl int(slot.payload)
      if (loops and bit) != 0: return false
      loops = loops or bit
      let proof {.cursor.} = plan.loops[int(slot.payload)]
      if proof.epoch != plan.epoch or not proof.complete: return false
    of NativeAuxiliaryKind.ReadCycle:
      if cycle or not plan.hasCycle or slot.payload != 0 or
          plan.cycle.read.info.epoch != plan.epoch or not cycleComplete(plan.cycle):
        return false
      cycle = true
  loops == uint8((1'u32 shl int(plan.loopCount))-1) and cycle == plan.hasCycle

proc newNativeAuxiliaryRequest*(plan: NativeAuxiliaryPlan,
    request: var NativeAuxiliaryRequest): NativeAuxiliaryBuildStatus =
  ## Construct actual payload sizes on the host before claiming a job or image credit.
  ## Nil ref destinations and short sequence allocations leave the output empty; callers
  ## distinguish retryable allocation refusal from source-invalid negative-cache entries.
  assert request.isEmpty
  if not plan.complete: return NativeAuxiliaryBuildStatus.Invalid
  var data: nil NativeAuxiliaryRequestData = NativeAuxiliaryRequestData(count: plan.count,
      epoch: plan.epoch, order: plan.order, loops: @[])
  if data == nil: return NativeAuxiliaryBuildStatus.AllocationRefused
  data.loops = newSeq[NativeMixedLoop](int(plan.loopCount))
  if data.loops.len != int(plan.loopCount): return NativeAuxiliaryBuildStatus.AllocationRefused
  for index in 0..<int(plan.loopCount):
    # Only POD elements cross into the private exact-length sequence.
    data.loops[index] = plan.loops[index]
  if plan.hasCycle:
    var cycle: nil NativeAuxiliaryCycleData = NativeAuxiliaryCycleData(proof: plan.cycle)
    if cycle == nil: return NativeAuxiliaryBuildStatus.AllocationRefused
    data.cycle = move(cycle)
  request.data = move(data)
  NativeAuxiliaryBuildStatus.Ready

proc copyNativeAuxiliaryPlan*(request: NativeAuxiliaryRequest,
    plan: var NativeAuxiliaryPlan): bool =
  ## While the runtime lock pins this immutable request, copy only POD into worker storage.
  ## The caller must not destroy/replace the handle until this call returns. No ref/seq
  ## copy, callback or pointer to a readonly parameter escapes the locked boundary.
  plan = default(NativeAuxiliaryPlan)
  let data {.cursor.} = request.data
  if data == nil or data.loops.len > NativeAuxiliaryEntryLimit: return false
  plan.count = data.count
  plan.epoch = data.epoch
  plan.order = data.order
  plan.loopCount = uint8(data.loops.len)
  for index in 0..<data.loops.len:
    # A cursor into the managed header never becomes another managed owner on the worker.
    plan.loops[index] = data.loops[index]
  let cycle {.cursor.} = data.cycle
  if cycle != nil:
    plan.hasCycle = true
    plan.cycle = cycle.proof
  plan.complete

func sameNativeAuxiliaryPlan*(request: NativeAuxiliaryRequest,
    plan: NativeAuxiliaryPlan): bool =
  ## Compare exact complete ordered typed source proofs under the request's runtime lock.
  let data {.cursor.} = request.data
  if data == nil or not plan.complete or data.count != plan.count or data.epoch != plan.epoch or
      data.loops.len != int(plan.loopCount) or (data.cycle != nil) != plan.hasCycle:
    return false
  for index in 0..<int(plan.count):
    # Equal occupancy bits do not hide a changed kind, source, payload or ordered slot.
    let slot = plan.order[index]
    if data.order[index] != slot: return false
    case slot.kind
    of NativeAuxiliaryKind.SelfLoop:
      if data.loops[int(slot.payload)] != plan.loops[int(slot.payload)]: return false
    of NativeAuxiliaryKind.ReadCycle:
      let cycle {.cursor.} = data.cycle
      if cycle == nil or not sameNativeReadCycle(cycle.proof, plan.cycle): return false
  true

proc nativeAuxiliaryPlan*(loops: NativeMixedLoopSet): NativeAuxiliaryPlan =
  ## Preserve the existing Read-primary source ranking without a second publisher.
  result = default(NativeAuxiliaryPlan)
  if not loops.complete: return
  result = initNativeAuxiliaryPlan(loops.proofs[0].epoch)
  for index in 0..<int(loops.count):
    # A refused source cannot leave a partially authoritative compatibility plan.
    if not result.add(loops.proofs[index]): return default(NativeAuxiliaryPlan)

func sameNativeAuxiliaryLoops*(request: NativeAuxiliaryRequest,
    loops: NativeMixedLoopSet): bool =
  ## Compare the existing loop-only order without materializing a second POD plan on every borrow.
  let data {.cursor.} = request.data
  if data == nil or loops.count == 0 or loops.count > uint8(NativeAuxiliaryEntryLimit) or
      data.count != loops.count or data.cycle != nil or data.loops.len != int(loops.count):
    return false
  for index in 0..<int(loops.count):
    # This compatibility path never grants a lease on a cycle entry with the same mask.
    if data.order[index] != NativeAuxiliarySlot(kind: NativeAuxiliaryKind.SelfLoop,
        payload: uint8(index)) or data.loops[index] != loops.proofs[index]: return false
  true
