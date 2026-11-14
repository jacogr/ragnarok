# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 checked handler-stream execution with invocation-owned regions and bounded preparation.
## Public immutable snapshot and host adapters live in pvm/step.
##
## A plan owns immutable source admission. Derived lazy catalogues belong to the
## exclusively leased frame/stream and fill complete blocks at stable source-global ordinals.
## The executable stream owns handlers,
## sealed operands, sites and stable offsets. A private frame owns mutable CPU,
## guest memory, budgets and callbacks. Restore and take move code-only state
## across calls. The executable cache retains no invocation pointers. Idle byte
## scratch has a separate lease and is restored before another invocation uses it.
## A refused frame buffer or restore delta produces a local allocation error.
## Extra writable runs allocate before their first store, with the whole guest
## access preflighted before allocating or modifying private bytes.
##
## Node and preparation-work refusals stay with the active frame. A prepared
## owner retains admitted entries and cumulative occupancy under the same ceilings.
## A refused stream allocation can interrupt emission after partial writes.
## Discard that catalogue and its native epoch before the next invocation.
##
## Snapshot publication returns a local refusal if dirty coordinates, page staging
## or replacement directory assembly fail. Host readiness is set only on success.
## Host suspension publishes an immutable observation. Resident deltas can resume
## the existing frame. Mapping or permission changes build a complete private
## replacement before swapping ownership, so refusal preserves the stopped frame.

import std/[assertions, bitops]
import ../[program, machine]
import ../gas/[gas, plan as gas_plan, memo as gas_memo]
import ./execution_types as oracle
import ./register_ops
import ./metadata_store
import ./native_pipeline
import ./[resident_bytes, resident_capture]
when NativeReadCycleEnabled:
  when defined(pvmMixedLoopWitness) or defined(pvmMixedLoopEntryWitness) or defined(pvmPaidMixedLoopWitness):
    import std/syncio
  import ./[native_mixed_loop, native_platform, native_fusion]
  from ./jit_rules import supportedScalarOpcode

  type
    FlatFusionSample = object
      ## Count a checked header under its one-based stream token.
      token, count: uint32
    FlatFusionSlot = object
      ## Segment-local map from original header to rank slot.
      token, index: uint32
    FlatFusionProbe = object
      ## One segment's sparse observation. No size depends on admitted source.
      down, seed, taken: uint32
      samples: array[1024, FlatFusionSample]

  type
    FlatMixedLoopSource = object
      ## Cold discovery retains only bounded source coordinates and their epoch.
      epoch: uint64
      chosen: array[NativeMixedLoopEntryLimit, uint32]
      count, checks, refused, chosenCount: uint8
      candidates: array[NativeMixedLoopCandidateLimit, uint32]
    FlatMixedLoopProbe = object
      ## Temporary checked terminal handlers count completed visits within this segment.
      count: int
      terminals, tokens: array[NativeMixedLoopCandidateLimit, uint32]
      visits: array[NativeMixedLoopCandidateLimit, uint64]
      spans: array[NativeMixedLoopCandidateLimit, uint8]
  when defined(pvmMixedLoopWitness):
    type FlatMixedArenaWitness = object
      entries, visits, refusals, paid, operations, branches, repeatedHeaders: uint64
  when defined(pvmPaidMixedLoopWitness):
    type
      FlatMixedPairMode* {.pure.} = enum
        Disabled, Checked, ByteOnly, PaidOnly, Both
      FlatMixedPairCounts = object
        entries, visits, refusals, paid, operations, branches, repeatedHeaders: uint64
        lastGuardPc, lastGuardOrdinal: uint32
      FlatMixedPairWitness = object
        proofs: array[2, NativeMixedLoop]
        images: array[2, nil ptr NativeImage]
        counts: array[2, FlatMixedPairCounts]

when defined(pvmArm64Jit) and not defined(pvmX86Jit) and
    defined(pvmArmMacroReceipt) and defined(pvmArmMacroStateTrace):
  from ./arm64_jit import ArmMacroState
when defined(pvmX86Jit):
  import ./x86_jit

when NativeCheckedReadEnabled:
  const
    ReadProbeSlots = 4                            ## Fixed ordinary call-local candidate capacity.
    ReadProbeWalkLimit = NativeReadProbeWalkLimit ## Whole-call certificate attempts.
    ReadProbeCapacity = when NativeReadCycleEnabled: ReadProbeSlots+1 else: ReadProbeSlots
  type
    ReadProbeCandidate = object ## Exact sealed terminal and its invocation-local evidence.
      pc, header, terminal, sourceFacts: uint32
      operations: int
      eligible: uint64
      resolved: bool
    ReadProbeState = object ## Scalar-only state carried across validated memory replacements.
      candidates: array[ReadProbeCapacity, ReadProbeCandidate]
      count, inspected: int
      epoch, segmentBudget: uint64
      priorWork: uint64
      observing, callActive, later: bool
      when NativeReadCycleEnabled:
        protectedTried, protectedInstalled, protectedActive, protectedCountable: bool
        protectedRemainingLimit: uint64

type FlatSourceRanks = ref object
  ## Immutable bitmap ranks preserve source-global ordinals without decoding every header again.
  words: seq[uint64]
  prefixes: seq[uint32]

type
  FlatFactLimit* = distinct uint64 ## Caller-selected decoded-fact admission policy, separate from guest gas.
  FlatNodeLimit* = distinct uint64 ## Ceiling on emitted header/operation nodes in one exclusive frame.
  FlatPreparationLimit* = distinct uint64 ## Total source span admitted for suffix emission plus containing-block pricing.
  FlatLimits* = object ## Copied local policies; later caller changes cannot change an admitted plan.
    codeBytes*: ProgramByteLimit
    facts*: FlatFactLimit
    jumps*: JumpCountLimit
    pages*: PageLimit
    nodes*: FlatNodeLimit
    preparation*: FlatPreparationLimit
  FlatError* {.pure.} = enum ## Local preparation refusals never masquerade as successful guest exits.
    Uninitialized, None, InvalidPolicy, InvalidProgram, CodeLimitExceeded,
    FactLimitExceeded, JumpLimitExceeded, PageLimitExceeded, StreamLimitExceeded,
      PreparationLimitExceeded, InvalidMemory, ResidentAllocationRefused, StreamAllocationRefused
  FlatResult*[T] = object ## Private alternatives publish only completely admitted owners.
    case status: FlatError
    of None: completed: T
    else: discard
  FlatArgs = object ## Exactly sixteen bytes: full immediate, secondary low word and genuine sealed register coordinates.
    x: uint64
    y: uint32
    slots: RegisterSlots
  FlatHandler = proc(f: var FlatFrame, off: uint32): uint32 {.nimcall, raises: [].}
  FlatNativePatch = object ## One exact installed slot and its original checked handler.
    offset: uint32
    checked, installed: nil FlatHandler
  FlatNativeInstallation = object ## At most three bridge patches belong to one full immutable image key.
    key: NativeImageKey
    patches: array[3, FlatNativePatch]
    count: byte
  FlatFact = object ## Stable source coordinates and suffix quotas, immutable after block admission.
    pc, next, sourceCount, priceIndex, nodeCount: uint32
    opcode: byte
    ending, fallthrough: bool
  FlatSourcePayload = object ## Temporary original operands and handler reconstructed only from the retained source.
    args: FlatArgs
    handler: nil FlatHandler
  FlatSourceInterval = object ## Bounded source coordinates and a captured charge, without complete-header authority.
    first, last, span: uint32
    price: uint64
  FlatTarget = object ## Only genuine jump-table and block-membership validation supplies positive target facts.
    pc: uint32
    valid: bool
  FlatPlan* = ref object ## Immutable admission, or a private derived catalogue owned by an exclusive frame/stream.
    source: Program
    facts: MetadataStore[FlatFact]
    # A materialized start stores its global ordinal plus one; operand and still-lazy PCs keep zero.
    factAt: MetadataStore[uint32]
    pricePcs: seq[CodeAddress]
    cycles: GasCycleLimit
    jumps: seq[FlatTarget]
    limits: FlatLimits         # Cold admission policy follows the existing hot plan fields.
    allowNative: bool          # Immutable cold policy; forced interpretation never creates native handlers.
    singleStep: bool # A bounded adapter plan owns one instruction and never enters whole-program emission.
    admission: nil FlatPlan    # Private cache catalogue points back to its immutable admission identity.
    admittedFacts: uint32      # Full validated source count is refused before any execution.
    codeBytes: uint32          # Logical PC extent remains known before a lazy map is allocated.
    ranks: nil FlatSourceRanks # Shared immutable source-global index, built once during admission.
    materialized: uint32       # Filled fact slots only; reserved array capacity is a separate cost.
  FlatRegion = object ## Extra regions read the containing immutable owner until their first complete store.
    first: uint64
    access: PageAccess
    size, sourceFirst: int # Logical bytes and genuine sorted source slot survive optional payload allocation.
    bytes: seq[byte] # Empty means baseline-backed; otherwise every logical byte is privately owned.
  FlatMemoryScratchData = object
    ## One exclusive idle byte lease; immutable baseline and dirty ordinals restore each new input completely.
    baseline: Memory
    pages: seq[PageDescription]
    roBase, rwBase, stackBase: uint64
    ro: seq[byte]
    rw: RWView
    stack: seq[byte]
    extra: seq[FlatRegion]
    dirty: seq[uint32]
    dirtyPages: seq[uint64] # Bitmap through the highest mapped page, at most 128 KiB.
    payloadBytes: uint64    # Logical baseline and private payload charged to the idle retention limit.
    rwStorage: RWStorage    # Cold exclusive backing follows its view through active and idle leases.
  FlatMemoryScratch* = ref FlatMemoryScratchData
  FlatDynamicOffsets = ref object ## Invocation-owned positive ordinal tags and stable offsets.
    slots: array[256, uint64]
  FlatFrame* = object ## One exclusive active execution; CPU, budgets, callbacks and borrowed native descriptors start afresh.
    plan: FlatPlan
    info*: MachineInfo
    reason*: oracle.StepError
    exit*: oracle.StepExit
    faultPage*: PageAddress
    hostCall*: oracle.HostCallId
    handlers: seq[FlatHandler]
    arguments: seq[FlatArgs]
    sites: seq[uint32]
    compiledForPc: MetadataStore[uint32]
    sourceMemory: Memory
    sourcePages: seq[PageDescription]
    roBase, rwBase, stackBase: uint64
    ro: seq[byte]
    rw: RWView
    stack: seq[byte]
    extra: seq[FlatRegion]
    remaining*: uint64
    reservation: uint32 # Raw source end, or a high-bit-tagged stable header resolved only on attempted exit.
    stoppedAt: uint32
    attemptedExit: bool
    barrier: uint32
    barrierFact: uint32
    savedHandler: nil FlatHandler
    dynamicOffsets: nil FlatDynamicOffsets
    hostSnapshot: Memory
    hostReady: bool
    hostSnapshotPc: CodeAddress
    fastResumes, fallbackResumes, hostCopiedPages: uint64
    dirtyPages: seq[uint64]                   # Absolute physical-page bits, bounded by the highest mapped page.
    dirtyIndices: seq[uint32] # Unique written pages; capacity is admitted with the mapping, never grown by a store.
    preparationFailure: FlatError # Rare admission state leaves all existing hot-frame coordinates unchanged.
    preparationUsed: uint64 # Cold source-span reservations persist with the emitted cache across resets/reentry.
    pricingPlan: GasPlan # Optional source-bound immutable prices, selected only during cold emission.
    pricingMemo: GasMemo                      # Optional caller-owned bounded price memo, never CPU or paid gas.
    when defined(pvmX86Jit) and defined(pvmX86CheckedStoreReceipt):
      x86CheckedStoreSelections, x86CheckedByteBlocks, x86CheckedWordGroups: uint64
    when NativeCheckedReadEnabled:
      readContext: NativeReadContext
      readContextReady: bool
      readProbe: ReadProbeState
    nativeSession*: NativeSession             # Prepared identity only; never passed to the compiler thread.
    nativeInstallation: FlatNativeInstallation
    nativeOriginal: nil FlatHandler
    prefixProbeOriginal: nil FlatHandler      # Invocation-local observer, restored before stream handback.
    prefixProbeHeader: uint32
    prefixProbeBodyOriginal: nil FlatHandler  # Exact scalar entry; headers alone do not prove it was reached.
    prefixProbeBody: uint32
    when NativeCheckedReadEnabled:
      nativeRingInstalled: bool               # Ready image rebound to this invocation's checked handlers.
    nativeEntry: uint32
    nativeInstalledEpoch: uint64
    pricingKind: byte # Zero dynamic, one complete plan, two lazy memo; no per-op pricing switch.
    rwStorage: RWStorage # Append cold ownership after existing fields; the hot RW view remains two words.
    when NativeReadCycleEnabled and (defined(pvmMixedLoopWitness) or defined(
        pvmMixedLoopEntryWitness)):
      mixedWitnessEntries, mixedWitnessVisits, mixedWitnessRefusals: uint64
    when defined(pvmMixedLoopEntryWitness) and NativeReadCycleEnabled:
      mixedWitnessProof: NativeMixedLoop
      mixedWitnessImage: nil ptr NativeImage
    when NativeReadCycleEnabled:
      bitmapCandidate: uint32                 # A single deferred cold-edge observation for this frame.
      mixedSource: FlatMixedLoopSource
      fusionImage: nil ptr NativeImage
      fusionBlocks: nil ptr seq[NativeFusionBlock]
      fusionReceipts: nil ptr NativeFusionReceipts
      fusionContext: nil ptr NativeFusionContext
      fusionSlots: nil ptr array[NativeFusionSlotLimit, FlatFusionSlot]
      mixedProbe: nil ptr FlatMixedLoopProbe
      mixedProofs: nil ptr NativeMixedLoopSet # Borrowed only inside the outlined frame segment.
      mixedImage: nil ptr NativeImage
      mixedMask: uint8
      when defined(pvmSharedAsyncWitness):
        mixedProbeWitness: bool
      when defined(pvmMixedLoopWitness):
        mixedArenaWitness: array[NativeMixedLoopEntryLimit, FlatMixedArenaWitness]
      when defined(pvmPaidMixedLoopWitness):
        mixedPairMode*: FlatMixedPairMode
        mixedPair: nil ptr FlatMixedPairWitness

proc `=copy`*(destination: var FlatFrame, source: FlatFrame) {.error.}
  ## Every profile rejects copying exclusive byte storage and any native children.

proc `=dup`*(source: FlatFrame): FlatFrame {.error.}
  ## Interpreted execution carries the same exclusive resident-owner contract as native execution.

proc `=wasMoved`*(frame: var FlatFrame) {.nodestroy, inline.} =
  ## Delegate every owning child and remove source views without retiring transferred storage.
  `=wasMoved`(frame.plan)
  `=wasMoved`(frame.handlers)
  `=wasMoved`(frame.arguments)
  `=wasMoved`(frame.sites)
  `=wasMoved`(frame.compiledForPc)
  `=wasMoved`(frame.sourceMemory)
  `=wasMoved`(frame.sourcePages)
  `=wasMoved`(frame.ro)
  `=wasMoved`(frame.stack)
  `=wasMoved`(frame.extra)
  `=wasMoved`(frame.dynamicOffsets)
  `=wasMoved`(frame.hostSnapshot)
  `=wasMoved`(frame.dirtyPages)
  `=wasMoved`(frame.dirtyIndices)
  `=wasMoved`(frame.pricingPlan)
  `=wasMoved`(frame.pricingMemo)
  `=wasMoved`(frame.nativeSession)
  frame.prefixProbeOriginal = nil
  frame.prefixProbeHeader = 0
  frame.prefixProbeBodyOriginal = nil
  frame.prefixProbeBody = 0
  `=wasMoved`(frame.rwStorage)
  frame.rw = default(RWView)
  when NativeCheckedReadEnabled:
    # A moved frame cannot retain a ready context into storage now owned elsewhere.
    frame.readContext = default(NativeReadContext)
    frame.readContextReady = false

proc `=copy`*(destination: var FlatResult[FlatFrame], source: FlatResult[FlatFrame]) {.error.}
  ## The success wrapper is itself noncopyable, independently of its exclusive child.

proc `=dup`*(source: FlatResult[FlatFrame]): FlatResult[FlatFrame] {.error.}
  ## Reject duplication of the actual successful frame result in every profile.

proc `=wasMoved`*(outcome: var FlatResult[FlatFrame]) {.nodestroy, inline.} =
  ## Initialization also calls this hook: select the payload-free neutral state without reading old storage.
  outcome.status = FlatError.Uninitialized

proc `=copy`*(destination: var FlatMemoryScratchData, source: FlatMemoryScratchData) {.error.}
  ## Reference-handle identity may be shared; the actual owning heap payload cannot be cloned.

proc `=dup`*(source: FlatMemoryScratchData): FlatMemoryScratchData {.error.}
  ## Reject a second independent owner of a retained resident mapping.

proc `=wasMoved`*(scratch: var FlatMemoryScratchData) {.nodestroy, inline.} =
  ## Disarm all moved children and the old view while preserving automatic complete destruction.
  `=wasMoved`(scratch.baseline)
  `=wasMoved`(scratch.pages)
  `=wasMoved`(scratch.ro)
  `=wasMoved`(scratch.stack)
  `=wasMoved`(scratch.extra)
  `=wasMoved`(scratch.dirty)
  `=wasMoved`(scratch.dirtyPages)
  `=wasMoved`(scratch.rwStorage)
  scratch.rw = default(RWView)
  scratch.payloadBytes = 0

proc clearFlatBorrowedMemory(f: var FlatFrame) {.inline.} =
  ## Manual child transfer needs the same view retirement as a whole-frame move.
  f.rw = default(RWView)
  when NativeCheckedReadEnabled:
    f.readContext = default(NativeReadContext)
    f.readContextReady = false

const flatStop = high(uint32)
  # Source ordinals fit the four-MiB program ceiling; emitted offsets stay below2^31.
  # The disjoint high bit defers a complete reservation's source lookup until an attempted exit.
const flatReservationHeaderFlag = 0x80000000'u32

func defaultFlatLimits*(): FlatLimits =
  ## Compatibility policy is finite; application callers should choose explicit deployment limits.
  FlatLimits(codeBytes: ProgramByteLimit(4194304), facts: FlatFactLimit(4194304),
    jumps: JumpCountLimit(1048576), pages: PageLimit(1048576), nodes: FlatNodeLimit(8388608),
        preparation: FlatPreparationLimit(67108864))

func error*[T](outcome: FlatResult[T]): FlatError =
  ## Inspect a default/refused result without exposing a partial owner.
  outcome.status

proc borrowFrame*(outcome: var FlatResult[FlatFrame]): var FlatFrame {.inline,
    requires: outcome.status == FlatError.None.} =
  ## Use the admitted frame in place while its enclosing result owns cleanup.
  outcome.completed

proc takeValue*[T](outcome: var FlatResult[T]): T {.inline, requires: outcome.status ==
    FlatError.None.} =
  ## Transfer an admitted owner once without deep-copying frame regions; consumed results lose success authority.
  result = move(outcome.completed)
  outcome = FlatResult[T](status: FlatError.Uninitialized)

func validFlatLimits(limits: FlatLimits): bool =
  ## Representation ceilings are checked before narrowing, indexing or allocating; zero budgets deliberately refuse work.
  uint64(limits.codeBytes) <= 4194304 and uint64(limits.facts) <= 4194304 and
    uint64(limits.jumps) <= 1048576 and uint32(limits.pages) <= 1048576 and
    uint64(limits.nodes) <= 2147483646

func preparationError*(frame: FlatFrame): FlatError =
  ## A stream-admission failure is sticky for this frame; no successful guest snapshot is claimed.
  frame.preparationFailure

func flatPreparationUnits*(frame: FlatFrame): uint64 =
  ## Copied cumulative source-span reservations; these are neither actual decoder visits nor CPU instructions/cycles.
  frame.preparationUsed

func flatSext32(x: uint32): uint64 {.inline.} =
  ## Preserve GP sign extension with unsigned bit operations.
  if (x and 0x80000000'u32) != 0: uint64(x) or 0xffffffff00000000'u64
  else: uint64(x)

proc flatConsiderNative(f: var FlatFrame, origin: uint32)
when NativeCheckedReadEnabled:
  proc discoverReadProbe(f: var FlatFrame, header, pc: uint32)
    ## Classify one bounded candidate without generating any native bytes.
  proc observeReadProbeHeader(f: var FlatFrame, header: uint32)
    ## Replacement discovery also sees cached checked headers under fixed whole-call budgets.

proc flatRestoreNativeInstallation(f: var FlatFrame) =
  ## Restore every old bridge and control field before source revalidation or physical retirement.
  when NativeCheckedReadEnabled:
    assert not f.readProbe.observing
  assert int(f.nativeInstallation.count) <= f.nativeInstallation.patches.len
  for index in 0..<int(f.nativeInstallation.count):
    let patch = f.nativeInstallation.patches[index]
    let checked = patch.checked
    let installed = patch.installed
    assert int(patch.offset) < f.handlers.len
    if checked != nil and installed != nil:
      assert f.handlers[int(patch.offset)] == installed
      f.handlers[int(patch.offset)] = checked
    else:
      # A default slot has no authority; only fully captured entries may be restored.
      assert false, "native installation contains an empty patch"
  f.nativeInstallation = default(FlatNativeInstallation)
  f.nativeOriginal = nil
  f.nativeEntry = 0
  f.nativeInstalledEpoch = 0
  when NativeCheckedReadEnabled:
    f.nativeRingInstalled = false
    f.readContext = default(NativeReadContext)
    f.readContextReady = false

proc flatInstallNativePatch(f: var FlatFrame, offset: uint32, selected: FlatHandler) =
  ## Capture an original once; repeated same-key installation never overwrites its checked fallback.
  let key = nativeInstalledKey(f.nativeSession)
  assert key.ticket != 0 and key.epoch == nativeEpoch(f.nativeSession)
  assert int(offset) < f.handlers.len
  if f.nativeInstallation.count != 0:
    assert f.nativeInstallation.key == key
  else:
    f.nativeInstallation.key = key
  for index in 0..<int(f.nativeInstallation.count):
    if f.nativeInstallation.patches[index].offset == offset:
      assert f.nativeInstallation.patches[index].installed == selected
      f.handlers[int(offset)] = selected
      return
  let count = int(f.nativeInstallation.count)
  assert count < f.nativeInstallation.patches.len
  f.nativeInstallation.patches[count] = FlatNativePatch(offset: offset,
    checked: f.handlers[int(offset)], installed: selected)
  f.nativeInstallation.count += 1'u8
  f.handlers[int(offset)] = selected

proc flatResolve(f: var FlatFrame, pc: uint32): uint32
  ## Cold lazy stream emission is forward-declared for target patching.

proc installFlatPrefixProbe(f: var FlatFrame)
  ## Bind the selected scalar entry and preserve its header's ordinary handoff after full emission.

proc restoreFlatPrefixProbe(f: var FlatFrame)
  ## Remove both invocation-local patches through the exact quota-predecessor rule.

func flatPlanIdentity(plan: FlatPlan): FlatPlan
  ## Dynamic targets use the admission owner's immutable table.

proc flatStopExit(f: var FlatFrame, off: uint32, kind: oracle.StepExit,
    attempted: bool = true): uint32 =
  ## Rare exits materialize the exact source PC; ordinary handlers never publish physical PCs.
  f.exit = kind
  f.stoppedAt = off
  f.attemptedExit = attempted
  let fact = f.plan.facts[int(f.sites[int(off)])]
  f.info.pc = if kind in [oracle.StepExit.Halt, oracle.StepExit.Panic]: CodeAddress(
      0) else: CodeAddress(fact.pc)
  flatStop

proc flatLocal(f: var FlatFrame, off: uint32, error: oracle.StepError): uint32 =
  ## A local refusal selects no successful snapshot; the caller restores any temporary budget barrier.
  f.reason = error
  if error != oracle.StepError.StepLimitExceeded:
    f.info.pc = CodeAddress(f.plan.facts[int(f.sites[int(off)])].pc)
  f.stoppedAt = off
  f.attemptedExit = false
  flatStop

proc flatBudget(f: var FlatFrame, off: uint32): uint32 =
  ## A partial reservation may stop on a folded no-op's original source fact.
  if uint64(f.barrierFact) >= uint64(f.plan.facts.len):
    f.reason = oracle.StepError.BackendFailure
    return flatStop
  f.info.pc = CodeAddress(f.plan.facts[int(f.barrierFact)].pc)
  flatLocal(f, off, oracle.StepError.StepLimitExceeded)

proc installFlatBudget(f: var FlatFrame, first, limit, fact: uint32): bool =
  ## Patch the first materialized node at or past the selected source attempt.
  ## Refuse inconsistent geometry before reading or changing the handler table.
  if f.barrier != flatStop or fact >= limit or uint64(limit) > uint64(f.plan.facts.len):
    return false
  var boundary = uint64(first)
  let extent = uint64(min(f.sites.len, f.handlers.len))
  while boundary < extent and f.sites[int(boundary)] < fact:
    inc boundary
  if boundary >= extent or f.sites[int(boundary)] >= limit: return false
  f.barrier = uint32(boundary)
  f.barrierFact = fact
  f.savedHandler = f.handlers[int(boundary)]
  f.handlers[int(boundary)] = flatBudget
  true

proc restoreFlatTemporaryHandler(f: var FlatFrame, node: uint32, temporary, original: FlatHandler) =
  ## A temporary owner can restore only the exact handler or saved quota predecessor.
  if uint64(node) >= uint64(f.handlers.len):
    f.reason = oracle.StepError.BackendFailure
    return
  if f.barrier == node:
    if f.handlers[int(node)] != flatBudget or f.savedHandler != temporary:
      f.reason = oracle.StepError.BackendFailure
      return
    f.savedHandler = original
  else:
    if f.handlers[int(node)] != temporary:
      f.reason = oracle.StepError.BackendFailure
      return
    f.handlers[int(node)] = original

template flatReserveImpl(f: var FlatFrame, off: uint32,
    observeProtected, observeLater: static[bool]) =
  ## Reserve a whole straight-line block once; a partial source budget changes one exclusive frame-owned handler temporarily.
  if f.remaining == 0:
    f.info.pc = CodeAddress(f.plan.facts[int(f.sites[int(off)])].pc)
    return flatLocal(f, off, oracle.StepError.StepLimitExceeded)
  let a = f.arguments[int(off)]
  if not f.info.blockCharged:
    if uint64(f.info.gas) < a.x: return flatStopExit(f, off, oracle.StepExit.OutOfGas, false)
    f.info.gas = MachineGas(uint64(f.info.gas)-a.x)
    f.info.blockCharged = true
  if f.remaining >= uint64(a.y):
    when NativeCheckedReadEnabled and observeLater:
      # Only the selected observing dispatcher reaches this complete ordinary reservation.
      observeReadProbeHeader(f, off)
    f.remaining-=uint64(a.y)
    # Whole-block exits are rare: retain its stable header instead of reading the source index on every entry.
    # Emitted offsets are below2^31; raw source ends are at most the four-MiB fact ceiling.
    f.reservation = off or flatReservationHeaderFlag
    when NativeReadCycleEnabled:
      when observeProtected:
        # This header owns disjoint complete reservations in one checked segment.
        if f.readProbe.protectedCountable and f.remaining <= f.readProbe.protectedRemainingLimit:
          inc f.readProbe.candidates[ReadProbeSlots].eligible
  else:
    # The paid source quota may land on a folded instruction inside this block.
    let start = f.sites[int(off)]
    if uint64(start)+uint64(a.y) > uint64(f.plan.facts.len) or
        not installFlatBudget(f, off+1, start+a.y, start+uint32(f.remaining)):
      f.reason = oracle.StepError.BackendFailure
      return flatStop
    f.remaining = 0
    f.reservation = f.barrierFact

template flatReserve(f: var FlatFrame, off: uint32) =
  ## Ordinary headers reserve without read observation.
  flatReserveImpl(f, off, false, false)

proc flatReserveHeader[ObserveLater: static[bool]](f: var FlatFrame,
    off: uint32): uint32 {.alwaysInline.} =
  ## Both dispatch modes reserve through the same checks before selecting a possibly patched body.
  flatReserveImpl(f, off, false, ObserveLater)
  off+1

proc flatCharge(f: var FlatFrame, off: uint32): uint32 =
  ## Ordinary headers retain their original indirect handoff after the shared complete reservation checks.
  flatReserve(f, off)
  # A successful entry consumes the next already sealed handler immediately; at most the existing
  # disjoint operation prefix adds a third call. Control transfers return offsets, never recurse.
  let next = off+1
  let selected = f.handlers[int(next)]
  selected(f, next)

proc flatPrefixProbe(f: var FlatFrame, off: uint32): uint32 =
  ## Keep adjacent specializations on original body nodes so they cannot bypass the scalar observer.
  let original = f.prefixProbeOriginal
  if original == nil or off != f.prefixProbeHeader:
    return flatLocal(f, off, oracle.StepError.BackendFailure)
  flatCharge(f, off)

proc flatPrefixBodyProbe(f: var FlatFrame, off: uint32): uint32 =
  ## Count only reaching and executing the candidate's exact scalar entry, after any earlier host.
  ## Segment settlement still discards work when a later instruction faults or otherwise refuses.
  let original = f.prefixProbeBodyOriginal
  if original == nil or off != f.prefixProbeBody:
    return flatLocal(f, off, oracle.StepError.BackendFailure)
  result = original(f, off)
  if f.reason == oracle.StepError.None and observeNativePrefix(f.nativeSession):
    restoreFlatPrefixProbe(f)

proc flatChargeFailure[Error: static[oracle.StepError]](f: var FlatFrame, off: uint32): uint32 =
  ## Preserve attempt-limit precedence and allow already-paid blocks past unused price failures.
  if f.remaining == 0:
    # Source-attempt exhaustion wins before a failed unused price on a newly reached header.
    f.info.pc = CodeAddress(f.plan.facts[int(f.sites[int(off)])].pc)
    return flatLocal(f, off, oracle.StepError.StepLimitExceeded)

  ## An already-paid resumed block may execute despite a failed unused pricing computation.
  if not f.info.blockCharged: return flatLocal(f, off, Error)
  flatCharge(f, off)

proc flatRegister[Code: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## This is our literal prepared-register worker on a sixteen-byte operand record and flat register file.
  let a = f.arguments[int(off)]
  var index: range[0..12] = 0
  var value = RegisterValue(0)
  if not computeRegisterOperands(a.slots, a.x, byte(Code), f.info.registers, index, value, Code):
    return flatLocal(f, off, oracle.StepError.UnsupportedInstruction)
  f.info.registers[index] = value
  off+1

proc flatRegisterPair[Code: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Master-style register-first prefix: the first mutation completes before the original checked second handler.
  let a = f.arguments[int(off)]
  var index: range[0..12] = 0
  var value = RegisterValue(0)
  if not computeRegisterOperands(a.slots, a.x, byte(Code), f.info.registers, index, value, Code):
    return flatLocal(f, off, oracle.StepError.UnsupportedInstruction)
  f.info.registers[index] = value
  let next = off+1
  let selected = f.handlers[int(next)]
  selected(f, next)

proc flatFusedRegisters[First, Second: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Execute two independently decoded register workers without a second indirect call; the original second node remains addressable.
  let a = f.arguments[int(off)]
  var index: range[0..12] = 0
  var value = RegisterValue(0)
  if not computeRegisterOperands(a.slots, a.x, byte(First), f.info.registers, index, value, First):
    return flatLocal(f, off, oracle.StepError.UnsupportedInstruction)
  f.info.registers[index] = value
  let next = off+1
  # A partial reservation still observes the original second-instruction boundary before reading or mutating its operands.
  if f.barrier == next: return flatBudget(f, next)
  let b = f.arguments[int(next)]
  if not computeRegisterOperands(b.slots, b.x, byte(Second), f.info.registers, index, value, Second):
    return flatLocal(f, next, oracle.StepError.UnsupportedInstruction)
  f.info.registers[index] = value
  next+1

func flatFusedRegisterHandler(first, second: byte): nil FlatHandler =
  ## These literal adjacent scalar pairs retain both original source nodes and the second-node barrier.
  if first == 151 and second == 152: flatFusedRegisters[151, 152]
  elif first == 200 and second == 139: flatFusedRegisters[200, 139]
  elif first == 149 and second == 149: flatFusedRegisters[149, 149]
  else: nil

func signedLess(a, b: uint64): bool =
  ## Compare unsigned register bits in signed order by flipping their sign bits.
  (a xor 0x8000000000000000'u64) < (b xor 0x8000000000000000'u64)

# Evaluate the condition against the original register file; decoding already saturated register IDs.
template branchConditionValue(indices: RegisterSlots, immediate: uint64, runtimeOpcode: byte,
    registers: RegisterFile, selectedOpcode: static[int]): bool =
  ## One shared comparison table expands into callers that need no out-of-line branch worker.
  block:
    let a = uint64(registers[indices.aIndex])
    let b = (if runtimeOpcode <= 90: immediate
      else: uint64(registers[indices.bIndex]))
    # Prepared handlers fix the comparison once; ordinary execution keeps its owned runtime opcode.
    let opcode = when selectedOpcode >= 0: byte(selectedOpcode) else: runtimeOpcode
    case opcode
    of 81, 170:
      # Equality has identical signed and unsigned interpretations.
      a == b
    of 82, 171:
      # Inequality also compares raw register bit patterns.
      a != b
    of 83, 172:
      # Unsigned strict lower bound.
      a < b
    of 84:
      # Unsigned inclusive lower bound.
      a <= b
    of 85, 174:
      # Unsigned inclusive upper bound.
      a >= b
    of 86:
      # Unsigned strict upper bound.
      a > b
    of 87, 173:
      # Signed strict lower bound.
      signedLess(a, b)
    of 88:
      # Signed inclusive lower bound.
      not signedLess(b, a)
    of 89, 175:
      # Signed inclusive upper bound.
      not signedLess(a, b)
    else:
      # The only remaining conditional opcode is signed greater-than immediate (90).
      signedLess(b, a)

func branchConditionOperands[SelectedOpcode: static[int]](indices: RegisterSlots,
    immediate: uint64, runtimeOpcode: byte, registers: RegisterFile): bool =
  ## Existing selected comparison workers retain the same shared original-register equation.
  branchConditionValue(indices, immediate, runtimeOpcode, registers, SelectedOpcode)

template flatBranchSelect(f: var FlatFrame, args: FlatArgs, Code: static[int],
    destination: var uint32) =
  ## Cached branch selection changes paid state only after preceding operations and uses copied sealed arms.
  block:
    f.info.blockCharged = false
    destination = if branchConditionValue(args.slots, flatSext32(uint32(args.x and 0xffffffff'u64)),
        byte(Code), f.info.registers, Code): uint32(args.x shr 32)
      else: args.y

proc flatReadSpan[W: static[int]](bytes: openArray[byte], at: int): uint64 {.inline.} =
  ## Complete bounds precede reads; the private initialized word never aliases the immutable source span.
  assert at >= 0 and bytes.len >= W and at <= bytes.len-W
  result = 0
  when W == 1:
    # Preserve the original byte worker; only wider selected reads use the transferred primitive.
    for i in 0..<W: result = result or (uint64(bytes[at+i]) shl(8*i))
  else:
    # Match master's little-endian, unaligned-safe scalar load after the unchanged region/permission checks.
    var endian = 1'u16
    var tag = default(array[2, byte])
    copyMem(addr tag[0], addr endian, 2)
    if tag[0] == 1:
      copyMem(addr result, unsafeAddr bytes[at], W)
    else:
      # Other host byte orders retain the original zero-extended little-endian byte equation.
      for i in 0..<W: result = result or (uint64(bytes[at+i]) shl(8*i))

proc flatWriteSpan[W: static[int]](bytes: var openArray[byte], at: int, value: uint64) {.inline.} =
  ## No bytes change until the complete selected region extent has passed.
  assert at >= 0 and bytes.len >= W and at <= bytes.len-W
  when W == 1:
    # Preserve the original byte worker literally; the transfer targets only multi-byte stores.
    for i in 0..<W: bytes[at+i] = byte((value shr (8*i)) and 255'u64)
  else:
    # Match master's endian-tested primitive: only admitted bytes copy from a disjoint initialized stack word.
    var endian = 1'u16
    var tag = default(array[2, byte])
    copyMem(addr tag[0], addr endian, 2)
    if tag[0] == 1:
      var word = value
      copyMem(addr bytes[at], addr word, W)
    else:
      # Other host byte orders retain the original portable little-endian equation.
      for i in 0..<W: bytes[at+i] = byte((value shr (8*i)) and 255'u64)

proc flatRead[W: static[int]](bytes: seq[byte], at: int): uint64 {.inline.} =
  ## Existing managed regions use the same checked little-endian byte equations.
  assert W > 0 and at >= 0 and bytes.len >= W and at <= bytes.len-W
  flatReadSpan[W](bytes.toOpenArray(at, at+W-1), 0)

proc flatRead[W: static[int]](bytes: RWView, at: int): uint64 {.inline.} =
  ## The cached RW pointer/length supplies a borrow without consulting its backing alternative.
  assert W > 0 and at >= 0 and bytes.len >= W and at <= bytes.len-W
  flatReadSpan[W](bytes.toOpenArray(at, at+W-1), 0)

proc flatWrite[W: static[int]](bytes: var seq[byte], at: int, value: uint64) {.inline.} =
  ## Retain complete preflight before exposing a nonempty managed scalar span.
  assert W > 0 and at >= 0 and bytes.len >= W and at <= bytes.len-W
  var span = bytes.toOpenArray(at, at+W-1)
  flatWriteSpan[W](span, 0, value)

proc flatWrite[W: static[int]](bytes: var RWView, at: int, value: uint64) {.inline.} =
  ## The complete RW extent, never an allocation tag, authorizes this synchronous store.
  assert W > 0 and at >= 0 and bytes.len >= W and at <= bytes.len-W
  var span = bytes.toOpenArray(at, at+W-1)
  flatWriteSpan[W](span, 0, value)

proc flatRememberPage(f: var FlatFrame, page: int) {.noinline.} =
  ## A first write records one admitted page; keep sequence bookkeeping outside repeated-store code.
  assert f.dirtyIndices.len < f.sourcePages.len
  f.dirtyIndices.add(uint32(page))
  let word = page shr 6
  assert word < f.dirtyPages.len
  f.dirtyPages[word] = f.dirtyPages[word] or (1'u64 shl (page and 63))

proc flatMarkStore[W: static[int]](f: var FlatFrame, address: uint64) {.alwaysInline.} =
  ## Mark only after complete store preflight; no allocation or guest-visible state changes occur here.
  assert address <= uint64(high(uint32))-uint64(W-1)
  let first = int(address shr 12)
  let word = first shr 6
  assert word < f.dirtyPages.len
  let mask = 1'u64 shl (first and 63)
  let before = f.dirtyPages[word]
  if (before and mask) == 0:
    # A dirty epoch needs one bit transition per page, even when the guest rewrites it repeatedly.
    flatRememberPage(f, first)
  when W > 1:
    # A scalar can span at most two pages; rejected cross-page stores never reach this helper.
    let last = int((address+uint64(W-1)) shr 12)
    if last != first:
      let lastWord = last shr 6
      assert lastWord < f.dirtyPages.len
      let lastMask = 1'u64 shl (last and 63)
      let lastBefore = f.dirtyPages[lastWord]
      if (lastBefore and lastMask) == 0:
        # The checked scalar may touch a second page in the same bitmap word or the following word.
        flatRememberPage(f, last)

proc flatClearDirty(f: var FlatFrame) =
  ## A successful host checkpoint or input reset makes private bytes equal their immutable base again.
  for page in f.dirtyIndices:
    # Several pages can share a word; repeated clearing is harmless and bounded by written pages.
    f.dirtyPages[int(page shr 6)] = 0
  f.dirtyIndices.setLen(0)

func flatDirty(f: FlatFrame, index: PageIndex): bool {.inline.} =
  ## Captured maps contain only 32-bit-addressable pages; unknown bitmap shapes retain full publication.
  let page = uint64(uint32(index))
  let word = page shr 6
  if word >= uint64(f.dirtyPages.len): return true
  (f.dirtyPages[int(word)] and (1'u64 shl int(page and 63))) != 0

proc flatTryCopySourcePage(memory: Memory, slot: int, expected: PageDescription,
    output: var openArray[byte]): bool =
  ## The retained mapping bounds this positional copy; matching metadata binds it to the same immutable owner.
  let copied = copyMemoryPage(memory, MemoryPageSlot(uint32(slot)), output)
  if copied.error != MachineError.None: return false
  let actual = copied.value
  actual.index == expected.index and actual.access == expected.access

proc flatCopySourcePage(memory: Memory, slot: int, expected: PageDescription,
    output: var openArray[byte]) =
  ## Existing reset and publication callers require a previously matched owner and layout.
  let copied = flatTryCopySourcePage(memory, slot, expected, output)
  assert copied

proc flatMaterializeStore[W: static[int]](f: var FlatFrame, address: uint64): oracle.StepError =
  ## Whole-store preflight has succeeded. Materialize a complete extra run
  ## before its first write. A refusal changes neither dirty bits nor guest bytes.
  for index in 0..<f.extra.len:
    let region {.cursor.} = f.extra[index]
    if address >= region.first and address-region.first < uint64(region.size):
      if region.access != PageAccess.ReadWrite or region.size < W or
          address-region.first > uint64(region.size-W):
        return oracle.StepError.InvalidMachine
      if region.bytes.len == 0:
        # The first write may need a managed allocation before any private bytes change.
        if region.size mod 4096 != 0: return oracle.StepError.InvalidMachine
        let pages = region.size div 4096
        if region.sourceFirst < 0 or region.sourceFirst > f.sourcePages.len-pages:
          return oracle.StepError.InvalidMachine
        var bytes = newSeqUninit[byte](region.size)
        # Managed refusal may return empty bytes; reject the actual extent before constructing any span.
        if bytes.len != region.size: return oracle.StepError.ResidentAllocationRefused
        for page in 0..<pages:
          # Fill the complete temporary from this frame's retained owner before installing any payload.
          let source = region.sourceFirst+page
          let offset = page*4096
          let expected = f.sourcePages[source]
          if expected.access != region.access or
              uint64(uint32(expected.index))*4096 != region.first+uint64(offset) or
              not flatTryCopySourcePage(f.sourceMemory, source, expected,
                bytes.toOpenArray(offset, offset+4095)):
            return oracle.StepError.InvalidMachine
        f.extra[index].bytes = move(bytes)
      elif region.bytes.len != region.size:
        # A retained payload must still cover the entire admitted run.
        return oracle.StepError.InvalidMachine
      return oracle.StepError.None
  oracle.StepError.None # The store uses one of the already resident primary runs.

proc flatByte(f: FlatFrame, address: uint64, baseline: byte): byte =
  ## The caller supplies a genuine checked scalar/page byte; logical membership selects any private overlay.
  if address >= f.stackBase and address-f.stackBase < uint64(f.stack.len): return f.stack[int(
      address-f.stackBase)]
  if address >= f.rwBase and address-f.rwBase < uint64(f.rw.len): return f.rw[int(address-f.rwBase)]
  if address >= f.roBase and address-f.roBase < uint64(f.ro.len): return f.ro[int(address-f.roBase)]
  for i in 0..<f.extra.len:
    let r {.cursor.} = f.extra[i]
    if address >= r.first and address-r.first < uint64(r.size):
      if r.bytes.len == 0: return baseline
      assert r.bytes.len == r.size
      return r.bytes[int(address-r.first)]
  assert false, "validated readable byte must belong to a captured private region"
  0

proc flatSetByte(f: var FlatFrame, address: uint64, value: byte) =
  ## Complete store preflight establishes writability across all involved regions before this helper mutates one byte.
  if address >= f.stackBase and address-f.stackBase < uint64(f.stack.len): f.stack[int(
      address-f.stackBase)] = value; return
  if address >= f.rwBase and address-f.rwBase < uint64(f.rw.len): f.rw[int(
      address-f.rwBase)] = value; return
  for i in 0..<f.extra.len:
    let r {.cursor.} = f.extra[i]
    if r.access == PageAccess.ReadWrite and address >= r.first and address-r.first < uint64(r.size):
      assert r.bytes.len == r.size # The whole store installed its complete payload before dirty marking.
      f.extra[i].bytes[int(address-r.first)] = value
      return
  assert false, "validated writable byte must belong to a captured writable region"

proc flatLoadSlow[W: static[int]](f: var FlatFrame, off: uint32, address: uint64,
    value: var uint64): bool =
  ## Canonical preflight provides baseline bytes; private overlays preserve later stores without repeating source reads.
  let checked = load(f.sourceMemory, MemoryAddress(address), AccessWidth(byte(W)))
  if checked.error != MachineError.None:
    if checked.error == MachineError.Fault:
      f.faultPage = checked.faultPage
      discard flatStopExit(f, off, oracle.StepExit.Fault)
    elif checked.error == MachineError.Panic: discard flatStopExit(f, off, oracle.StepExit.Panic)
    elif checked.error == MachineError.AmbiguousAccessOrder: discard flatLocal(f, off,
        oracle.StepError.AmbiguousAccessOrder)
    else: discard flatLocal(f, off, oracle.StepError.InvalidMachine)
    return false
  let baseline = uint64(checked.value)
  value = 0
  for i in 0..<W:
    # Each baseline lane is genuine even when only part of this load has a private overlay.
    let original = byte((baseline shr (8*i)) and 255'u64)
    value = value or (uint64(flatByte(f, address+uint64(i), original)) shl (8*i))
  true

proc flatStoreSlow[W: static[int]](f: var FlatFrame, off: uint32, address, value: uint64): bool =
  ## Exact read-only scalar preflight precedes dirty marking and every private byte mutation.
  let checked = writableScalar(f.sourceMemory, MemoryAddress(address), AccessWidth(byte(W)))
  if checked.error != MachineError.None:
    if checked.error == MachineError.Fault:
      f.faultPage = checked.faultPage
      discard flatStopExit(f, off, oracle.StepExit.Fault)
    elif checked.error == MachineError.Panic: discard flatStopExit(f, off, oracle.StepExit.Panic)
    elif checked.error == MachineError.AmbiguousAccessOrder: discard flatLocal(f, off,
        oracle.StepError.AmbiguousAccessOrder)
    else: discard flatLocal(f, off, oracle.StepError.InvalidMachine)
    return false
  let materialized = flatMaterializeStore[W](f, address)
  if materialized != oracle.StepError.None:
    discard flatLocal(f, off, materialized)
    return false
  flatMarkStore[W](f, address)
  for i in 0..<W: flatSetByte(f, address+uint64(i), byte((value shr (8*i)) and 255'u64))
  true

proc flatLoadFast[W: static[int]](f: var FlatFrame, off: uint32, address: uint64,
    value: var uint64): bool {.inline.} =
  ## Three-region fast selection keeps only address-dependent complete-extent checks on success.
  if address >= 65536'u64 and address <= uint64(high(uint32))-uint64(W):
    if address >= f.stackBase:
      let at = int(address-f.stackBase)
      if f.stack.len >= W and at <= f.stack.len-W: value = flatRead[W](f.stack, at); return true
    elif address >= f.rwBase:
      let at = int(address-f.rwBase)
      if f.rw.len >= W and at <= f.rw.len-W: value = flatRead[W](f.rw, at); return true
    elif address >= f.roBase:
      let at = int(address-f.roBase)
      if f.ro.len >= W and at <= f.ro.len-W: value = flatRead[W](f.ro, at); return true
  false

proc flatLoad[W: static[int]](f: var FlatFrame, off: uint32, address: uint64,
    value: var uint64): bool {.inline.} =
  ## Complete checked fallback remains available to existing source workers.
  if flatLoadFast[W](f, off, address, value): return true
  flatLoadSlow[W](f, off, address, value)

proc flatStore[W: static[int]](f: var FlatFrame, off: uint32, address,
    value: uint64): bool {.alwaysInline.} =
  ## Only captured writable/stack regions can satisfy a fast store; RO and fragmented boundaries retain full preflight.
  if address >= 65536'u64 and address <= uint64(high(uint32))-uint64(W):
    if address >= f.stackBase:
      let at = int(address-f.stackBase)
      if f.stack.len >= W and at <= f.stack.len-W:
        flatWrite[W](f.stack, at, value)
        flatMarkStore[W](f, address)
        return true
    elif address >= f.rwBase:
      let at = int(address-f.rwBase)
      if f.rw.len >= W and at <= f.rw.len-W:
        flatWrite[W](f.rw, at, value)
        flatMarkStore[W](f, address)
        return true
  flatStoreSlow[W](f, off, address, value)

proc flatMemoryCold[Width: static[int]; Loading, Signed, Indirect, ImmediateStore,
    Pair: static[bool]](f: var FlatFrame, off: uint32): uint32 {.noinline.}
  ## Keep only complete fallback outside hot workers; direct store callers remain eligible for inlining.

proc flatMemoryWorker[Width: static[int]; Loading, Signed, Indirect, ImmediateStore,
    Fast, Pair: static[bool]](f: var FlatFrame, off: uint32): uint32 =
  ## Shared selected access equation; only the cold load worker preserves state across full preflight.
  let a = f.arguments[int(off)]
  var base = 0'u64
  when Indirect:
    when Loading or not ImmediateStore: base = uint64(f.info.registers[a.slots.bIndex])
    else: base = uint64(f.info.registers[a.slots.aIndex])
  let address = (base+a.x) and 0xffffffff'u64
  when Loading:
    var value = 0'u64
    when Fast:
      if not flatLoadFast[Width](f, off, address, value):
        # Failed fast preflight has changed no CPU, bytes or attempt state; the complete worker owns every exit.
        return flatMemoryCold[Width, Loading, Signed, Indirect, ImmediateStore, Pair](f, off)
    else:
      if not flatLoad[Width](f, off, address, value): return flatStop
    when Signed:
      let bits = Width*8
      if (value and (1'u64 shl (bits-1))) != 0: value = value or (high(uint64) shl bits)
    f.info.registers[a.slots.aIndex] = RegisterValue(value)
  else:
    let value = when ImmediateStore: flatSext32(a.y) else: uint64(f.info.registers[a.slots.aIndex])
    if not flatStore[Width](f, off, address, value): return flatStop
  when Pair:
    # Source continuation is unchanged, including partial-budget barriers installed in the next slot.
    let next = off+1
    let selected = f.handlers[int(next)]
    selected(f, next)
  else:
    off+1

proc flatMemoryCold[Width: static[int]; Loading, Signed, Indirect, ImmediateStore,
    Pair: static[bool]](f: var FlatFrame, off: uint32): uint32 {.noinline.} =
  ## One full checked implementation preserves successful fragmented loads and exact terminal state.
  flatMemoryWorker[Width, Loading, Signed, Indirect, ImmediateStore, false, Pair](f, off)

proc flatCachedJump[Code: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Self-patched static nodes retain scalar executable offsets; load-and-jump writes before every exit.
  let a = f.arguments[int(off)]
  when Code == 80: f.info.registers[a.slots.aIndex] = RegisterValue(a.x)
  f.info.blockCharged = false
  a.y

proc flatResolutionFailure(f: var FlatFrame, off: uint32): uint32 =
  ## Invalid guest destinations panic; local policy exhaustion has no successful guest outcome.
  if f.preparationFailure != FlatError.None: return flatLocal(f, off,
      oracle.StepError.InvalidPreparedProgram)
  flatStopExit(f, off, oracle.StepExit.Panic)

when NativeReadCycleEnabled:
  proc observeFlatBitmap(f: var FlatFrame, root: uint32)
  proc installFlatBitmap(f: var FlatFrame, proof: NativeBitmapLoop)

proc flatJump[Code: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Resolve a source-owned sealed static target once and patch only this frame's private stream.
  let a = f.arguments[int(off)]
  when Code == 80: f.info.registers[a.slots.aIndex] = RegisterValue(a.x)
  let target = flatResolve(f, a.y)
  if target == flatStop: return flatResolutionFailure(f, off)
  f.arguments[int(off)].y = target
  let patched: FlatHandler = flatCachedJump[Code]
  f.handlers[int(off)] = patched
  when NativeReadCycleEnabled and Code == 40:
    # Observe only the cold backward edge of a complete read block with the bitmap source shape.
    let last = f.sites[int(off)]
    if f.bitmapCandidate == 0 and target < NativeEntryLimit and last >= 6 and
        f.plan.facts[int(last)-4].opcode == 130 and f.plan.facts[int(last)-6].opcode == 151 and
        f.plan.facts[int(last)-6].sourceCount == 7 and f.plan.facts[int(last)-6].pc > a.y and
        bitmapAdmissionEpoch(f.nativeSession) != 0:
      # The first trip can reach Read from a source suffix. The backedge may only now resolve Advance.
      f.bitmapCandidate = target+1
  f.info.blockCharged = false
  target

proc flatBranch[Code: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Conditions use our original-register comparison table; cached arms are already genuine executable offsets.
  let a = f.arguments[int(off)]
  var destination = flatStop
  flatBranchSelect(f, a, Code, destination)
  destination

when NativeReadCycleEnabled:
  proc observeFlatMixedLoop(f: var FlatFrame, pc, header, terminal: uint32)

proc flatUnresolvedBranch[Code: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Prepare both valid arms: resolve both valid arms, patch, then retry this synthetic preparation dispatch without a source attempt.
  let a = f.arguments[int(off)]
  let yes = flatResolve(f, uint32(a.x shr 32))
  let no = flatResolve(f, a.y)
  if yes == flatStop or no == flatStop: return flatResolutionFailure(f, off)
  f.arguments[int(off)].x = (a.x and 0xffffffff'u64) or (uint64(yes) shl 32)
  f.arguments[int(off)].y = no
  let patched: FlatHandler = flatBranch[Code]
  f.handlers[int(off)] = patched
  when NativeReadCycleEnabled and Code == 171:
    observeFlatMixedLoop(f, uint32(a.x shr 32), yes, off)
  off

proc flatFusedRegisterBranch[First, Branch: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Combine only a validated cached branch with its preceding arithmetic; both source nodes remain addressable.
  let a = f.arguments[int(off)]
  var index: range[0..12] = 0
  var value = RegisterValue(0)
  if not computeRegisterOperands(a.slots, a.x, byte(First), f.info.registers, index, value, First):
    return flatLocal(f, off, oracle.StepError.UnsupportedInstruction)
  f.info.registers[index] = value
  let next = off+1
  # The second source boundary must still stop before reading its operands or clearing the paid flag.
  if f.barrier == next: return flatBudget(f, next)
  let b = f.arguments[int(next)]
  f.info.blockCharged = false
  if branchConditionOperands[Branch](b.slots, flatSext32(uint32(b.x and 0xffffffff'u64)),
      byte(Branch), f.info.registers): uint32(b.x shr 32)
  else: b.y

proc flatRegisterBranchCold[First, Branch: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Original execution validates both branch arms after arithmetic; only a genuine cached branch enables fusion.
  let outcome = flatRegisterPair[First](f, off)
  let cached: FlatHandler = flatBranch[Branch]
  if f.handlers[int(off+1)] == cached:
    # Stable stream offsets survive target preparation and future resets; temporary budget handlers never qualify.
    let combined: FlatHandler = flatFusedRegisterBranch[First, Branch]
    f.handlers[int(off)] = combined
  outcome

template flatShapeRegister(f: var FlatFrame, off: uint32, Code: static[int]) =
  ## Expand the shared register equation inside a charged shape, without an out-of-line composed worker call.
  block:
    let a = f.arguments[int(off)]
    var index: range[0..12] = 0
    var value = RegisterValue(0)
    if not computeRegisterOperands(a.slots, a.x, byte(Code), f.info.registers, index, value, Code):
      return flatLocal(f, off, oracle.StepError.UnsupportedInstruction)
    f.info.registers[index] = value

template flatChargedStep(f: var FlatFrame, off: uint32, First, Second, Branch: static[int],
    destination: var uint32) =
  ## Execute one complete charged shape; failures and partial quotas return immediately from the containing interpreter loop.
  block:
    flatReserve(f, off)
    if f.barrier != flatStop:
      # Partial source quotas use the original addressable nodes and exact temporary boundary handler.
      let selected = f.handlers[int(off+1)]
      return selected(f, off+1)
    flatShapeRegister(f, off+1, First)
    when Second >= 0:
      # A full reservation permits the second original arithmetic operation; partial cases returned through ordinary nodes above.
      flatShapeRegister(f, off+2, Second)
    let branchOff = off+(when Second >= 0: 3'u32 else: 2'u32)
    let args = f.arguments[int(branchOff)]
    flatBranchSelect(f, args, Branch, destination)

when NativeCheckedReadEnabled:
  proc flatObserveNativeRing(f: var FlatFrame, first, middle, last: uint32): bool {.noinline.}
  proc flatTryNativeRing(f: var FlatFrame, header: uint32, destination: var uint32): bool

proc flatChargedShape[First, Second, Branch: static[int]; Ring: static[bool]](f: var FlatFrame,
    off: uint32): uint32 =
  ## Follow only exact positive cached shape links in a nonrecursive cycle; arbitrary exits return to ordinary dispatch.
  var current = off
  var destination = flatStop
  when NativeCheckedReadEnabled and Ring:
    if f.nativeRingInstalled and flatTryNativeRing(f, off, destination): return destination
  var middleOff = flatStop
  var lastOff = flatStop
  # Every logical block still performs its own complete gas and source-budget reservation.
  flatChargedStep(f, current, First, Second, Branch, destination)
  when First == 131:
    let middle: FlatHandler = flatChargedShape[151, 152, 173, Ring]
    if f.handlers[int(destination)] != middle: return destination
    middleOff = destination
    current = middleOff
    flatChargedStep(f, current, 151, 152, 173, destination)
    let last: FlatHandler = flatChargedShape[200, 139, 82, Ring]
    if f.handlers[int(destination)] != last: return destination
    lastOff = destination
    current = lastOff
    flatChargedStep(f, current, 200, 139, 82, destination)
  elif First == 200:
    let middle: FlatHandler = flatChargedShape[131, -1, 88, Ring]
    if f.handlers[int(destination)] != middle: return destination
    middleOff = destination
    current = middleOff
    flatChargedStep(f, current, 131, -1, 88, destination)
    let last: FlatHandler = flatChargedShape[151, 152, 173, Ring]
    if f.handlers[int(destination)] != last: return destination
    lastOff = destination
    current = lastOff
    flatChargedStep(f, current, 151, 152, 173, destination)
  else:
    let middle: FlatHandler = flatChargedShape[200, 139, 82, Ring]
    if f.handlers[int(destination)] != middle: return destination
    middleOff = destination
    current = middleOff
    flatChargedStep(f, current, 200, 139, 82, destination)
    let last: FlatHandler = flatChargedShape[131, -1, 88, Ring]
    if f.handlers[int(destination)] != last: return destination
    lastOff = destination
    current = lastOff
    flatChargedStep(f, current, 131, -1, 88, destination)
  # Only an actual closed round enables stable coordinates; a same-shaped but different record returns to normal dispatch.
  if destination != off: return destination
  let fixedMiddle = middleOff
  let fixedLast = lastOff
  when NativeCheckedReadEnabled and Ring:
    # Once the observed proof is copied, the original worker owns the remaining cold work.
    when First == 200:
      if flatObserveNativeRing(f, off, fixedMiddle, fixedLast): return off
    elif First == 131:
      if flatObserveNativeRing(f, fixedLast, off, fixedMiddle): return off
    else:
      if flatObserveNativeRing(f, fixedMiddle, fixedLast, off): return off
  while true:
    # Each block retains its charge/quota check. Any changed branch outcome exits before using a different record's operands.
    flatChargedStep(f, off, First, Second, Branch, destination)
    if destination != fixedMiddle: return destination
    when First == 131:
      flatChargedStep(f, fixedMiddle, 151, 152, 173, destination)
      if destination != fixedLast: return destination
      flatChargedStep(f, fixedLast, 200, 139, 82, destination)
    elif First == 200:
      flatChargedStep(f, fixedMiddle, 131, -1, 88, destination)
      if destination != fixedLast: return destination
      flatChargedStep(f, fixedLast, 151, 152, 173, destination)
    else:
      flatChargedStep(f, fixedMiddle, 200, 139, 82, destination)
      if destination != fixedLast: return destination
      flatChargedStep(f, fixedLast, 131, -1, 88, destination)
    if destination != off: return destination

proc flatChargedAdjacent[First: static[bool]](f: var FlatFrame, off: uint32): uint32 =
  ## Follow the matching peer only through original cached branches and checked bodies.
  let bodySpan = when First: 2'u32 else: 1'u32
  # A published native prefix owns its original body entry, even in the shared checked layout.
  if f.nativeEntry > off and f.nativeEntry-off <= bodySpan: return flatCharge(f, off)
  let peerHandler: FlatHandler = when First: flatChargedAdjacent[false] else: flatChargedAdjacent[true]
  var destination = flatStop
  when First:
    flatChargedStep(f, off, 149, 200, 170, destination)
  else:
    flatChargedStep(f, off, 132, -1, 81, destination)
  if f.handlers[int(destination)] != peerHandler: return destination
  # Let the peer execute its own native bridge through the same original entry.
  if f.nativeEntry > destination and f.nativeEntry-destination <= 3-bodySpan: return destination
  let peer = destination
  while true:
    # Every original block retains its reservation and exact paid/attempt checks.
    when First:
      flatChargedStep(f, peer, 132, -1, 81, destination)
      if destination != off: return destination
      flatChargedStep(f, off, 149, 200, 170, destination)
    else:
      flatChargedStep(f, peer, 149, 200, 170, destination)
      if destination != off: return destination
      flatChargedStep(f, off, 132, -1, 81, destination)
    if destination != peer: return destination

proc flatChargedShapeCold[First, Second, Branch: static[int]](f: var FlatFrame,
    off: uint32): uint32 =
  ## Preserve original first-use dispatch until the real terminal branch has validated and cached both arms.
  flatReserve(f, off)
  let selected = f.handlers[int(off+1)]
  let outcome = selected(f, off+1)
  let branchOff = off+(when Second >= 0: 3'u32 else: 2'u32)
  let cached: FlatHandler = flatBranch[Branch]
  if f.handlers[int(branchOff)] == cached:
    # Only positive cached capability enables a whole-block worker; no invalid or temporary handler qualifies.
    when First == 149:
      let checked: FlatHandler = flatChargedAdjacent[true]
      f.handlers[int(off)] = checked
    elif First == 132:
      let checked: FlatHandler = flatChargedAdjacent[false]
      f.handlers[int(off)] = checked
    else:
      let checked: FlatHandler = flatChargedShape[First, Second, Branch, false]
      when NativeCheckedReadEnabled:
        if nativeEpoch(f.nativeSession) != 0:
          let observed: FlatHandler = flatChargedShape[First, Second, Branch, true]
          f.handlers[int(off)] = observed
        else:
          f.handlers[int(off)] = checked
      else:
        f.handlers[int(off)] = checked
  outcome

proc flatChargedStoreLoop(f: var FlatFrame, off: uint32): uint32 =
  ## Keep this complete checked block resident while its genuine cached branch selects the same header.
  while true:
    # Every backedge retains its own complete gas and source-attempt reservation.
    flatReserve(f, off)
    if f.barrier != flatStop:
      # Partial budgets execute the original addressable prefix and its temporary barrier.
      let selected = f.handlers[int(off+1)]
      return selected(f, off+1)
    flatShapeRegister(f, off+1, 198)
    let stored = flatMemoryWorker[1, false, false, true, false, true, false](f, off+2)
    if stored == flatStop:
      # The original store retains prefix mutations, fault PC and the unattempted-reservation refund.
      return stored
    flatShapeRegister(f, off+3, 149)
    flatShapeRegister(f, off+4, 149)
    let args = f.arguments[int(off+5)]
    var destination = flatStop
    flatBranchSelect(f, args, 171, destination)
    when defined(pvmX86Jit) and defined(pvmX86CheckedStoreReceipt):
      inc f.x86CheckedByteBlocks
    if destination != off:
      # Changed branch outcomes return their real cached target to ordinary dispatch.
      return destination

func flatWordShape(f: FlatFrame, off: uint32): bool =
  ## Bind one byte extraction/store loop to five distinct source roles before selecting its word worker.
  let prefix = f.arguments[int(off+1)]
  let store = f.arguments[int(off+2)]
  let baseStep = f.arguments[int(off+3)]
  let shiftStep = f.arguments[int(off+4)]
  let branch = f.arguments[int(off+5)]
  let base = store.slots.bIndex
  let shift = prefix.slots.bIndex
  let roles = [prefix.slots.aIndex, shift, prefix.slots.destinationIndex, base, branch.slots.bIndex]
  for i in 0..<5:
    # Data, shift, byte destination, address and bound must not overwrite another live role.
    for j in i+1..<5:
      # Aliases retain the original checked loop instead of assuming a stable word or branch bound.
      if roles[i] == roles[j]: return false
  uint32(branch.x shr 32) == off and store.slots.aIndex == prefix.slots.destinationIndex and
    baseStep.slots.aIndex == base and baseStep.slots.bIndex == base and baseStep.x == 1 and
    shiftStep.slots.aIndex == shift and shiftStep.slots.bIndex == shift and shiftStep.x == 8 and
    branch.slots.aIndex == base

proc flatChargedWordLoop(f: var FlatFrame, off: uint32): uint32 =
  ## Replace four fully affordable, valid byte iterations with their equivalent checked word store.
  while f.remaining >= 20:
    # Four complete original blocks need twenty attempts and at most four nonoverflowing prices.
    let header = f.arguments[int(off)]
    if header.x > high(uint64) div 4:
      # Unknown large price combinations keep the original per-block affordability checks.
      break
    let charged = header.x*(if f.info.blockCharged: 3'u64 else: 4'u64)
    if uint64(f.info.gas) < charged:
      # The scalar path may still complete fewer blocks before its exact out-of-gas boundary.
      break
    let prefix = f.arguments[int(off+1)]
    let store = f.arguments[int(off+2)]
    let branch = f.arguments[int(off+5)]
    let shift = uint64(f.info.registers[prefix.slots.bIndex])
    let base = uint64(f.info.registers[store.slots.bIndex])
    let bound = uint64(f.info.registers[branch.slots.bIndex])
    if (shift and 31) != 0 or base > high(uint64)-4 or base+4 > bound:
      # Shifts 0/8/16/24 extract one low word; base+1..3 cannot equal the opcode 171 bound.
      # Wrapped or other loop coordinates retain the original != predicate and bytewise order.
      break
    let nextBase = base+4
    let address = (base+store.x) and 0xffffffff'u64
    if address < 65536 or address > uint64(high(uint32))-4:
      # Match the existing conservative four-byte fast-store extent; ambiguous/faulting spans stay scalar.
      break
    var valid = false
    if address >= f.stackBase:
      # The complete private stack extent has the same positive proof used by flatStore[4].
      valid = f.stack.len >= 4 and address-f.stackBase <= uint64(f.stack.len-4)
    elif address >= f.rwBase:
      # RO, fragmented and cross-permission layouts cannot qualify through this writable region.
      valid = f.rw.len >= 4 and address-f.rwBase <= uint64(f.rw.len-4)
    if not valid:
      # A bytewise prefix must remain observable before a later fault when the word extent is unavailable.
      break
    let word = uint64(f.info.registers[prefix.slots.aIndex]) and 0xffffffff'u64
    # No host/control exit or quota boundary can occur inside these four proven complete iterations.
    # The original checked store repeats the positive extent proof and owns dirty-page publication.
    let stored = flatStore[4](f, off+2, address, word)
    assert stored
    # Only a successful full extent permits the original twenty-attempt and four-block state projection.
    f.remaining-=20
    f.reservation = off or flatReservationHeaderFlag
    f.info.gas = MachineGas(uint64(f.info.gas)-charged)
    f.info.registers[prefix.slots.destinationIndex] = RegisterValue(word shr 24)
    f.info.registers[store.slots.bIndex] = RegisterValue(nextBase)
    f.info.registers[prefix.slots.bIndex] = RegisterValue(shift+32)
    when defined(pvmX86Jit) and defined(pvmX86CheckedStoreReceipt):
      inc f.x86CheckedWordGroups
    # The sealed true arm loops and the bound's distinct slot is unchanged by the batch.
    f.info.blockCharged = false
    if nextBase == bound: return branch.y
  # Every declined batch starts the untouched original checked loop, including its partial/fault behavior.
  flatChargedStoreLoop(f, off)

proc flatChargedStoreCold(f: var FlatFrame, off: uint32): uint32 =
  ## Retain ordinary checked dispatch until the terminal branch has validated both genuine arms.
  flatReserve(f, off)
  let selected = f.handlers[int(off+1)]
  let outcome = selected(f, off+1)
  let cached: FlatHandler = flatBranch[171]
  if f.barrier == flatStop and f.handlers[int(off+5)] == cached:
    # Partial barriers and unresolved/invalid branches never authorize the complete-loop worker.
    let args = f.arguments[int(off+5)]
    let yes = uint32(args.x shr 32)
    let no = args.y
    if (yes == off and no != off) or (no == off and yes != off):
      # Cache only source coordinates; no register, memory, gas or invocation pointer survives here.
      if flatWordShape(f, off):
        # Only this additional sealed dataflow permits four-byte projection inside the resident loop.
        f.handlers[int(off)] = flatChargedWordLoop
      else:
        # Other genuine five-operation self-loops keep their established checked per-iteration worker.
        f.handlers[int(off)] = flatChargedStoreLoop
      when defined(pvmX86Jit) and defined(pvmX86CheckedStoreReceipt):
        inc f.x86CheckedStoreSelections
  outcome

when defined(pvmX86Jit) and defined(pvmX86CheckedStoreReceipt):
  func flatX86CheckedStoreStatistics*(f: FlatFrame): array[3, uint64] =
    ## Receipt-only counts prove checked-loop installation and completed byte and word work.
    [f.x86CheckedStoreSelections, f.x86CheckedByteBlocks, f.x86CheckedWordGroups]

proc flatBadControl[Code: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Invalid destinations retain GP load mutations but never permit an unselected invalid conditional arm to escape validation.
  when Code == 80:
    let a = f.arguments[int(off)]
    f.info.registers[a.slots.aIndex] = RegisterValue(a.x)
  flatStopExit(f, off, oracle.StepExit.Panic)

proc flatDynamic[Code: static[int]; Single: static[bool]](f: var FlatFrame, off: uint32): uint32 =
  ## Full sentinel/alignment/table membership rules match our control worker, with predecoded dense target facts.
  let a = f.arguments[int(off)]
  let base = when Code == 50: uint64(f.info.registers[a.slots.aIndex]) else: uint64(
      f.info.registers[a.slots.bIndex])
  let delta = when Code == 50: a.x else: flatSext32(a.y)
  let address = (base+delta) and 0xffffffff'u64
  when Code == 180: f.info.registers[a.slots.aIndex] = RegisterValue(a.x)
  if address == 0xffff0000'u64: return flatStopExit(f, off, oracle.StepExit.Halt)
  if address == 0 or (address and 1) != 0: return flatStopExit(f, off, oracle.StepExit.Panic)
  let index = address div 2-1
  let slot = int(index and 255'u64)
  when not Single:
    # A one-step frame cannot reuse a cached target.
    let cache {.cursor.} = f.dynamicOffsets
    if cache != nil:
      let known = cache.slots[slot]
      if (known shr 32) == index+1:
        f.info.blockCharged = false
        return uint32(known and 0xffffffff'u64)-1
  var target = FlatTarget(pc: 0, valid: false)
  when Single:
    # A single instruction checks only its chosen original table ordinal; it never decodes the full table.
    let found = jumpTarget(f.plan.source, JumpIndex(index))
    if found.error != ProgramError.None: return flatStopExit(f, off, oracle.StepExit.Panic)
    let starts = basicBlockStart(f.plan.source, found.value)
    target = FlatTarget(pc: uint32(uint64(found.value) and 0xffffffff'u64),
      valid: starts.error == ProgramError.None and starts.value)
  else:
    # Ordinary prepared execution retains the qualified dense-table lookup without a runtime mode branch.
    let admitted = flatPlanIdentity(f.plan)
    if index >= uint64(admitted.jumps.len): return flatStopExit(f, off, oracle.StepExit.Panic)
    target = admitted.jumps[int(index)]
  if not target.valid: return flatStopExit(f, off, oracle.StepExit.Panic)
  let resolved = flatResolve(f, target.pc)
  if resolved == flatStop: return flatResolutionFailure(f, off)
  when not Single:
    # A refusal or halt never allocates. Only successful resolution can install a tag.
    let cache {.cursor.} = f.dynamicOffsets
    let tag = ((index+1) shl 32) or uint64(resolved+1)
    if cache == nil:
      let fresh: nil FlatDynamicOffsets = FlatDynamicOffsets(slots: default(array[256, uint64]))
      if fresh != nil:
        # The resolved offset is already valid. A refused optional cache leaves it usable.
        fresh.slots[slot] = tag
        f.dynamicOffsets = fresh
        when NativeReadCycleEnabled:
          # This frame owns the stable optional cache before the synchronous native borrow can see it.
          let context = f.fusionContext
          if context != nil: context[].jumps = addr fresh.slots
    else:
      cache.slots[slot] = tag
  f.info.blockCharged = false
  resolved

proc flatHost(f: var FlatFrame, off: uint32): uint32 =
  ## A genuine host exit is source-bound and preserves the sign-extended immediate in its complete register-width domain.
  f.hostCall = oracle.HostCallId(f.arguments[int(off)].x)
  flatStopExit(f, off, oracle.StepExit.Host)

proc flatTrap(f: var FlatFrame, off: uint32): uint32 =
  ## Recursive terminal normalization stays on the rare exit path.
  flatStopExit(f, off, oracle.StepExit.Panic)

proc flatNoop(f: var FlatFrame, off: uint32): uint32 =
  ## Available for isolated opcode witnesses; ordinary compilation folds unlikely while retaining source-budget facts.
  off+1

proc flatInvalid(f: var FlatFrame, off: uint32): uint32 =
  ## A missing successor for a nonterminator is a local invalid-machine refusal, not a fabricated guest trap.
  flatLocal(f, off, oracle.StepError.InvalidMachine)

func flatHandler(code: byte, valid, fallthrough: bool): nil FlatHandler {.inline.} =
  ## One canonical literal handler table is shared by ordinary preparation and specialized second-instruction selection.
  if not fallthrough and code notin {0'u8, 1'u8, 40'u8, 50'u8, 80'u8..90'u8, 170'u8..175'u8, 180'u8}:
    return flatInvalid
  case code
  of 0: flatTrap
  of 1: (if valid: flatJump[1] else: flatBadControl[1])
  of 2: flatNoop
  of 10: flatHost
  of 20: flatRegister[20]
  of 30: flatMemoryWorker[1, false, false, false, true, true, false]
  of 31: flatMemoryWorker[2, false, false, false, true, true, false]
  of 32: flatMemoryWorker[4, false, false, false, true, true, false]
  of 33: flatMemoryWorker[8, false, false, false, true, true, false]
  of 40: (if valid: flatJump[40] else: flatBadControl[40])
  of 50: flatDynamic[50, false]
  of 51: flatRegister[51]
  of 52: flatMemoryWorker[1, true, false, false, false, true, false]
  of 53: flatMemoryWorker[1, true, true, false, false, true, false]
  of 54: flatMemoryWorker[2, true, false, false, false, true, false]
  of 55: flatMemoryWorker[2, true, true, false, false, true, false]
  of 56: flatMemoryWorker[4, true, false, false, false, true, false]
  of 57: flatMemoryWorker[4, true, true, false, false, true, false]
  of 58: flatMemoryWorker[8, true, false, false, false, true, false]
  of 59: flatMemoryWorker[1, false, false, false, false, true, false]
  of 60: flatMemoryWorker[2, false, false, false, false, true, false]
  of 61: flatMemoryWorker[4, false, false, false, false, true, false]
  of 62: flatMemoryWorker[8, false, false, false, false, true, false]
  of 70: flatMemoryWorker[1, false, false, true, true, true, false]
  of 71: flatMemoryWorker[2, false, false, true, true, true, false]
  of 72: flatMemoryWorker[4, false, false, true, true, true, false]
  of 73: flatMemoryWorker[8, false, false, true, true, true, false]
  of 80: (if valid: flatJump[80] else: flatBadControl[80])
  of 81: (if valid and fallthrough: flatUnresolvedBranch[81] else: flatBadControl[81])
  of 82: (if valid and fallthrough: flatUnresolvedBranch[82] else: flatBadControl[82])
  of 83: (if valid and fallthrough: flatUnresolvedBranch[83] else: flatBadControl[83])
  of 84: (if valid and fallthrough: flatUnresolvedBranch[84] else: flatBadControl[84])
  of 85: (if valid and fallthrough: flatUnresolvedBranch[85] else: flatBadControl[85])
  of 86: (if valid and fallthrough: flatUnresolvedBranch[86] else: flatBadControl[86])
  of 87: (if valid and fallthrough: flatUnresolvedBranch[87] else: flatBadControl[87])
  of 88: (if valid and fallthrough: flatUnresolvedBranch[88] else: flatBadControl[88])
  of 89: (if valid and fallthrough: flatUnresolvedBranch[89] else: flatBadControl[89])
  of 90: (if valid and fallthrough: flatUnresolvedBranch[90] else: flatBadControl[90])
  of 100: flatRegister[100]
  of 101: flatRegister[101]
  of 102: flatRegister[102]
  of 103: flatRegister[103]
  of 104: flatRegister[104]
  of 105: flatRegister[105]
  of 106: flatRegister[106]
  of 107: flatRegister[107]
  of 108: flatRegister[108]
  of 109: flatRegister[109]
  of 110: flatRegister[110]
  of 120: flatMemoryWorker[1, false, false, true, false, true, false]
  of 121: flatMemoryWorker[2, false, false, true, false, true, false]
  of 122: flatMemoryWorker[4, false, false, true, false, true, false]
  of 123: flatMemoryWorker[8, false, false, true, false, true, false]
  of 124: flatMemoryWorker[1, true, false, true, false, true, false]
  of 125: flatMemoryWorker[1, true, true, true, false, true, false]
  of 126: flatMemoryWorker[2, true, false, true, false, true, false]
  of 127: flatMemoryWorker[2, true, true, true, false, true, false]
  of 128: flatMemoryWorker[4, true, false, true, false, true, false]
  of 129: flatMemoryWorker[4, true, true, true, false, true, false]
  of 130: flatMemoryWorker[8, true, false, true, false, true, false]
  of 131: flatRegister[131]
  of 132: flatRegister[132]
  of 133: flatRegister[133]
  of 134: flatRegister[134]
  of 135: flatRegister[135]
  of 136: flatRegister[136]
  of 137: flatRegister[137]
  of 138: flatRegister[138]
  of 139: flatRegister[139]
  of 140: flatRegister[140]
  of 141: flatRegister[141]
  of 142: flatRegister[142]
  of 143: flatRegister[143]
  of 144: flatRegister[144]
  of 145: flatRegister[145]
  of 146: flatRegister[146]
  of 147: flatRegister[147]
  of 148: flatRegister[148]
  of 149: flatRegister[149]
  of 150: flatRegister[150]
  of 151: flatRegister[151]
  of 152: flatRegister[152]
  of 153: flatRegister[153]
  of 154: flatRegister[154]
  of 155: flatRegister[155]
  of 156: flatRegister[156]
  of 157: flatRegister[157]
  of 158: flatRegister[158]
  of 159: flatRegister[159]
  of 160: flatRegister[160]
  of 161: flatRegister[161]
  of 170: (if valid and fallthrough: flatUnresolvedBranch[170] else: flatBadControl[170])
  of 171: (if valid and fallthrough: flatUnresolvedBranch[171] else: flatBadControl[171])
  of 172: (if valid and fallthrough: flatUnresolvedBranch[172] else: flatBadControl[172])
  of 173: (if valid and fallthrough: flatUnresolvedBranch[173] else: flatBadControl[173])
  of 174: (if valid and fallthrough: flatUnresolvedBranch[174] else: flatBadControl[174])
  of 175: (if valid and fallthrough: flatUnresolvedBranch[175] else: flatBadControl[175])
  of 180: flatDynamic[180, false]
  of 190: flatRegister[190]
  of 191: flatRegister[191]
  of 192: flatRegister[192]
  of 193: flatRegister[193]
  of 194: flatRegister[194]
  of 195: flatRegister[195]
  of 196: flatRegister[196]
  of 197: flatRegister[197]
  of 198: flatRegister[198]
  of 199: flatRegister[199]
  of 200: flatRegister[200]
  of 201: flatRegister[201]
  of 202: flatRegister[202]
  of 203: flatRegister[203]
  of 204: flatRegister[204]
  of 205: flatRegister[205]
  of 206: flatRegister[206]
  of 207: flatRegister[207]
  of 208: flatRegister[208]
  of 209: flatRegister[209]
  of 210: flatRegister[210]
  of 211: flatRegister[211]
  of 212: flatRegister[212]
  of 213: flatRegister[213]
  of 214: flatRegister[214]
  of 215: flatRegister[215]
  of 216: flatRegister[216]
  of 217: flatRegister[217]
  of 218: flatRegister[218]
  of 219: flatRegister[219]
  of 220: flatRegister[220]
  of 221: flatRegister[221]
  of 222: flatRegister[222]
  of 223: flatRegister[223]
  of 224: flatRegister[224]
  of 225: flatRegister[225]
  of 226: flatRegister[226]
  of 227: flatRegister[227]
  of 228: flatRegister[228]
  of 229: flatRegister[229]
  of 230: flatRegister[230]
  else: nil # Unsupported future opcodes never become guest traps or fabricated handlers.

func flatRegisterPairHandler(code: byte): nil FlatHandler =
  ## Only the complete existing register opcode set can provide a first-instruction prefix.
  case code
  of 20: flatRegisterPair[20]
  of 51: flatRegisterPair[51]
  of 100: flatRegisterPair[100]
  of 101: flatRegisterPair[101]
  of 102: flatRegisterPair[102]
  of 103: flatRegisterPair[103]
  of 104: flatRegisterPair[104]
  of 105: flatRegisterPair[105]
  of 106: flatRegisterPair[106]
  of 107: flatRegisterPair[107]
  of 108: flatRegisterPair[108]
  of 109: flatRegisterPair[109]
  of 110: flatRegisterPair[110]
  of 131: flatRegisterPair[131]
  of 132: flatRegisterPair[132]
  of 133: flatRegisterPair[133]
  of 134: flatRegisterPair[134]
  of 135: flatRegisterPair[135]
  of 136: flatRegisterPair[136]
  of 137: flatRegisterPair[137]
  of 138: flatRegisterPair[138]
  of 139: flatRegisterPair[139]
  of 140: flatRegisterPair[140]
  of 141: flatRegisterPair[141]
  of 142: flatRegisterPair[142]
  of 143: flatRegisterPair[143]
  of 144: flatRegisterPair[144]
  of 145: flatRegisterPair[145]
  of 146: flatRegisterPair[146]
  of 147: flatRegisterPair[147]
  of 148: flatRegisterPair[148]
  of 149: flatRegisterPair[149]
  of 150: flatRegisterPair[150]
  of 151: flatRegisterPair[151]
  of 152: flatRegisterPair[152]
  of 153: flatRegisterPair[153]
  of 154: flatRegisterPair[154]
  of 155: flatRegisterPair[155]
  of 156: flatRegisterPair[156]
  of 157: flatRegisterPair[157]
  of 158: flatRegisterPair[158]
  of 159: flatRegisterPair[159]
  of 160: flatRegisterPair[160]
  of 161: flatRegisterPair[161]
  of 190: flatRegisterPair[190]
  of 191: flatRegisterPair[191]
  of 192: flatRegisterPair[192]
  of 193: flatRegisterPair[193]
  of 194: flatRegisterPair[194]
  of 195: flatRegisterPair[195]
  of 196: flatRegisterPair[196]
  of 197: flatRegisterPair[197]
  of 198: flatRegisterPair[198]
  of 199: flatRegisterPair[199]
  of 200: flatRegisterPair[200]
  of 201: flatRegisterPair[201]
  of 202: flatRegisterPair[202]
  of 203: flatRegisterPair[203]
  of 204: flatRegisterPair[204]
  of 205: flatRegisterPair[205]
  of 206: flatRegisterPair[206]
  of 207: flatRegisterPair[207]
  of 208: flatRegisterPair[208]
  of 209: flatRegisterPair[209]
  of 210: flatRegisterPair[210]
  of 211: flatRegisterPair[211]
  of 212: flatRegisterPair[212]
  of 213: flatRegisterPair[213]
  of 214: flatRegisterPair[214]
  of 215: flatRegisterPair[215]
  of 216: flatRegisterPair[216]
  of 217: flatRegisterPair[217]
  of 218: flatRegisterPair[218]
  of 219: flatRegisterPair[219]
  of 220: flatRegisterPair[220]
  of 221: flatRegisterPair[221]
  of 222: flatRegisterPair[222]
  of 223: flatRegisterPair[223]
  of 224: flatRegisterPair[224]
  of 225: flatRegisterPair[225]
  of 226: flatRegisterPair[226]
  of 227: flatRegisterPair[227]
  of 228: flatRegisterPair[228]
  of 229: flatRegisterPair[229]
  of 230: flatRegisterPair[230]
  else: nil

func flatMemoryPairHandler(code: byte): nil FlatHandler =
  ## Only a successful first checked memory operation invokes the original second handler.
  case code
  of 30: flatMemoryWorker[1, false, false, false, true, true, true]
  of 31: flatMemoryWorker[2, false, false, false, true, true, true]
  of 32: flatMemoryWorker[4, false, false, false, true, true, true]
  of 33: flatMemoryWorker[8, false, false, false, true, true, true]
  of 52: flatMemoryWorker[1, true, false, false, false, true, true]
  of 53: flatMemoryWorker[1, true, true, false, false, true, true]
  of 54: flatMemoryWorker[2, true, false, false, false, true, true]
  of 55: flatMemoryWorker[2, true, true, false, false, true, true]
  of 56: flatMemoryWorker[4, true, false, false, false, true, true]
  of 57: flatMemoryWorker[4, true, true, false, false, true, true]
  of 58: flatMemoryWorker[8, true, false, false, false, true, true]
  of 59: flatMemoryWorker[1, false, false, false, false, true, true]
  of 60: flatMemoryWorker[2, false, false, false, false, true, true]
  of 61: flatMemoryWorker[4, false, false, false, false, true, true]
  of 62: flatMemoryWorker[8, false, false, false, false, true, true]
  of 70: flatMemoryWorker[1, false, false, true, true, true, true]
  of 71: flatMemoryWorker[2, false, false, true, true, true, true]
  of 72: flatMemoryWorker[4, false, false, true, true, true, true]
  of 73: flatMemoryWorker[8, false, false, true, true, true, true]
  of 120: flatMemoryWorker[1, false, false, true, false, true, true]
  of 121: flatMemoryWorker[2, false, false, true, false, true, true]
  of 122: flatMemoryWorker[4, false, false, true, false, true, true]
  of 123: flatMemoryWorker[8, false, false, true, false, true, true]
  of 124: flatMemoryWorker[1, true, false, true, false, true, true]
  of 125: flatMemoryWorker[1, true, true, true, false, true, true]
  of 126: flatMemoryWorker[2, true, false, true, false, true, true]
  of 127: flatMemoryWorker[2, true, true, true, false, true, true]
  of 128: flatMemoryWorker[4, true, false, true, false, true, true]
  of 129: flatMemoryWorker[4, true, true, true, false, true, true]
  of 130: flatMemoryWorker[8, true, false, true, false, true, true]
  else: nil

proc flatFact(decoded: ProgramResult[InstructionHeader], priceIndex: uint32): FlatFact =
  ## Retain the same eagerly validated source boundaries and logical admission units without rich payload storage.
  assert decoded.error == ProgramError.None
  let item = decoded.value
  let pc = uint64(item.address)
  assert pc <= uint64(high(uint32))-25
  FlatFact(pc: uint32(pc), next: uint32(pc+1+uint64(item.skip)), sourceCount: 0,
    priceIndex: priceIndex, opcode: item.opcode, ending: terminatesBlock(item.opcode),
    fallthrough: instructionHasFallthrough(decoded))

func flatSourcePayload(decoded: ProgramResult[Instruction]): FlatSourcePayload =
  ## Pack the original operands and target-dependent handler; mutable stream arguments never grant source facts.
  assert decoded.error == ProgramError.None
  let item = decoded.value
  let valid = instructionTargetStartsBlock(decoded)
  let fallthrough = instructionHasFallthrough(decoded)
  var args = FlatArgs(x: uint64(item.x), y: uint32(uint64(item.y) and 0xffffffff'u64),
      slots: instructionRegisters(decoded))
  case item.opcode
  of 1:
    # The fallthrough opcode uses the original marked successor as its destination.
    args.y = uint32(uint64(item.address)+1+uint64(item.skip))
  of 40, 80..90, 170..175:
    # Pack the original coordinates. The decoded validity selects the refusal handler for negative targets.
    let pc = uint64(item.address)
    let target = if item.displacement < 0:
        if uint64(-item.displacement) <= pc: pc-uint64(-item.displacement) else: 0'u64
      else: pc+uint64(item.displacement)
    if item.opcode in {40'u8, 80'u8}:
      args.y = uint32(target and 0xffffffff'u64)
    else:
      args.x = (args.x and 0xffffffff'u64) or ((target and 0xffffffff'u64) shl 32)
      args.y = uint32(pc+1+uint64(item.skip))
  else:
    discard # This handler consumes only the original decoded operands.
  FlatSourcePayload(args: args, handler: flatHandler(item.opcode, valid, fallthrough))

proc flatSourcePayload(plan: FlatPlan, fact: FlatFact): FlatSourcePayload =
  ## Query the exact immutable Program on the caller; no rich cache or source pointer reaches a worker.
  let decoded = instruction(plan.source, CodeAddress(uint64(fact.pc)))
  assert decoded.error == ProgramError.None
  let item = decoded.value
  assert item.opcode == fact.opcode and uint64(item.address)+1+uint64(item.skip) == uint64(fact.next)
  result = flatSourcePayload(decoded)
  if plan.singleStep:
    # Single-step dynamic transfers retain their bounded scalar-successor handlers.
    if fact.opcode == 50: result.handler = flatDynamic[50, true]
    elif fact.opcode == 180: result.handler = flatDynamic[180, true]

proc sourceRanks(source: Program, extent: uint64, count: uint32,
    ranks: var nil FlatSourceRanks): FlatError =
  ## Build one rank per 64 code bytes; only the validated marker bitmap is traversed.
  let words = int(extent div 64 + uint64(int(extent mod 64 != 0)))
  var masks = newSeqUninit[uint64](words)
  var prefixes = newSeqUninit[uint32](words)
  if masks.len != words or prefixes.len != words:
    return FlatError.PreparationLimitExceeded
  var slot = 0
  var seen = 0'u32
  for word in admissionMaskWords(source):
    # All set bits are genuine instruction starts, including in the zero-padded final group.
    let added = uint32(countSetBits(word))
    if slot >= words or seen > count or added > count-seen:
      return FlatError.InvalidProgram
    masks[slot] = word
    prefixes[slot] = seen
    seen += added
    inc slot
  if slot != words or seen != count: return FlatError.InvalidProgram
  let owner: nil FlatSourceRanks = FlatSourceRanks()
  if owner == nil: return FlatError.PreparationLimitExceeded
  owner.words = move(masks)
  owner.prefixes = move(prefixes)
  ranks = owner
  FlatError.None

func sourceOrdinal(ranks: FlatSourceRanks, pc: uint32): uint32 =
  ## Select a genuine zero-based ordinal; only block materialization uses rank arithmetic.
  let slot = int(pc div 64)
  let bit = 1'u64 shl int(pc mod 64)
  let word = ranks.words[slot]
  assert (word and bit) != 0
  ranks.prefixes[slot]+uint32(countSetBits(word and (bit-1)))

proc admitFlatPlan(source: Program, cycles: GasCycleLimit, limits: FlatLimits,
    extent: uint64, count: uint32, allowNative: bool): FlatResult[FlatPlan] =
  ## Admit all source/resource obligations now; derived facts belong to a later exclusive stream.
  if uint64(count) > uint64(limits.facts):
    return FlatResult[FlatPlan](status: FlatError.FactLimitExceeded)
  var ranks: nil FlatSourceRanks = nil
  let ranked = sourceRanks(source, extent, count, ranks)
  if ranked != FlatError.None: return FlatResult[FlatPlan](status: ranked)
  let admittedRanks = ranks
  if admittedRanks == nil: return FlatResult[FlatPlan](status: FlatError.PreparationLimitExceeded)
  let owner: nil FlatPlan = FlatPlan()
  if owner == nil: return FlatResult[FlatPlan](status: FlatError.PreparationLimitExceeded)
  owner.ranks = admittedRanks
  owner.source = source
  owner.limits = limits
  owner.cycles = cycles
  owner.allowNative = allowNative
  owner.admittedFacts = count
  owner.codeBytes = uint32(extent)
  var ordinal = 0'u64
  while true:
    # Jump-table membership remains eager and preserves fact-before-jump refusal precedence.
    let resolved = jumpTarget(source, JumpIndex(ordinal))
    if resolved.error != ProgramError.None: break
    if ordinal >= uint64(limits.jumps):
      return FlatResult[FlatPlan](status: FlatError.JumpLimitExceeded)
    let target = resolved.value
    let valid = basicBlockStart(source, target)
    owner.jumps.add(FlatTarget(pc: uint32(uint64(target) and 0xffffffff'u64),
      valid: valid.error == ProgramError.None and valid.value))
    if uint64(owner.jumps.len) != ordinal+1:
      return FlatResult[FlatPlan](status: FlatError.PreparationLimitExceeded)
    inc ordinal
  FlatResult[FlatPlan](status: FlatError.None, completed: owner)

func flatPlanIdentity(plan: FlatPlan): FlatPlan =
  ## Private derived catalogues never replace the immutable identity used for cache leasing.
  if plan == nil: return plan # Empty/default streams retain the original neutral identity.
  let original = plan.admission
  if original == nil: plan else: original

proc prepareFlatPlan*(source: Program, cycles: GasCycleLimit, limits: FlatLimits,
    allowNative: bool = true): FlatResult[FlatPlan] =
  ## Validate full-source resource obligations and jump membership before execution.
  ## Rank immutable opcode markers now; materialize complete block facts on first resolution.
  assert sizeof(FlatArgs) == 16
  when sizeof(pointer) == 8: assert sizeof(FlatFact) == 24
  if not validFlatLimits(limits): return FlatResult[FlatPlan](status: FlatError.InvalidPolicy)
  let extent = codeLength(source)
  if extent.error != ProgramError.None or extent.value == 0:
    return FlatResult[FlatPlan](status: FlatError.InvalidProgram)
  if extent.value > uint64(limits.codeBytes): return FlatResult[FlatPlan](
      status: FlatError.CodeLimitExceeded)
  let instructions = instructionCount(source)
  if instructions.error != ProgramError.None: return FlatResult[FlatPlan](
      status: FlatError.InvalidProgram)
  return admitFlatPlan(source, cycles, limits, extent.value, instructions.value, allowNative)

proc prepareSingleFlatPlan*(source: Program, pc: CodeAddress,
    cycles: GasCycleLimit): FlatResult[FlatPlan] =
  ## Admit exactly one genuine instruction; ordinary source/profile checks precede any mutable frame allocation.
  let limits = defaultFlatLimits()
  let extent = codeLength(source)
  if extent.error != ProgramError.None: return FlatResult[FlatPlan](
      status: FlatError.InvalidProgram)
  if extent.value > uint64(limits.codeBytes): return FlatResult[FlatPlan](
      status: FlatError.CodeLimitExceeded)
  let decoded = instructionHeader(source, pc)
  if decoded.error != ProgramError.None: return FlatResult[FlatPlan](
      status: FlatError.InvalidProgram)
  var fact = flatFact(decoded, 0)
  fact.sourceCount = 1
  fact.nodeCount = 1
  var facts = singletonMetadataStore(fact)
  if facts.len != 1: return FlatResult[FlatPlan](status: FlatError.StreamAllocationRefused)
  let owner: nil FlatPlan = FlatPlan(source: source, cycles: cycles, limits: limits,
    allowNative: false, singleStep: true)
  if owner == nil: return FlatResult[FlatPlan](status: FlatError.StreamAllocationRefused)
  owner.facts = move(facts)
  FlatResult[FlatPlan](status: FlatError.None, completed: owner)

proc newFlatPlan*(source: Program, cycles: GasCycleLimit): FlatPlan =
  ## Local witness convenience only; application admission uses prepareFlatPlan and checks its typed result.
  var prepared = prepareFlatPlan(source, cycles, defaultFlatLimits())
  assert prepared.error == FlatError.None
  takeValue(prepared)

proc flatEmit(f: var FlatFrame, handler: FlatHandler, args: FlatArgs, site: uint32): bool =
  ## Parallel contiguous arrays preserve a 24-byte handler/argument payload plus a source index for rare exits.
  let past = f.handlers.len+1
  f.handlers.add(handler)
  f.arguments.add(args)
  f.sites.add(site)
  if f.handlers.len == past and f.arguments.len == past and f.sites.len == past: return true
  f.preparationFailure = FlatError.StreamAllocationRefused
  false

proc flatPrice(f: var FlatFrame, start: CodeAddress, cost: var uint64): oracle.StepError =
  ## Query the selected exact-owner pricing policy only when preparing a previously unseen suffix.
  if f.pricingKind == 1:
    let price = blockGas(f.pricingPlan, start)
    if price.error != GasPlanError.None: return oracle.StepError.InvalidGasPlan
    cost = uint64(price.value)
    return oracle.StepError.None
  if f.pricingKind == 2:
    let price = blockGas(f.pricingMemo, start)
    case price.error
    of GasMemoError.None:
      cost = uint64(price.value)
      return oracle.StepError.None
    of GasMemoError.CycleLimitExceeded: return oracle.StepError.GasCycleLimitExceeded
    of GasMemoError.NegativeBranchTarget: return oracle.StepError.NegativeBranchTarget
    else: return oracle.StepError.InvalidGasMemo
  let price = blockGas(f.plan.source, start, f.plan.cycles)
  case price.error
  of GasError.None:
    cost = uint64(price.value)
    oracle.StepError.None
  of GasError.CycleLimitExceeded: oracle.StepError.GasCycleLimitExceeded
  of GasError.NegativeBranchTarget: oracle.StepError.NegativeBranchTarget
  else: oracle.StepError.InvalidMachine

proc flatMemoCharge(f: var FlatFrame, off: uint32): uint32 =
  ## Preparation alone must not populate a caller's lazy memo; only an attempted unpaid entry queries it.
  if f.remaining > 0 and not f.info.blockCharged:
    let fact = f.plan.facts[int(f.sites[int(off)])]
    var cost = 0'u64
    let priced = flatPrice(f, f.plan.pricePcs[int(fact.priceIndex)], cost)
    if priced != oracle.StepError.None: return flatLocal(f, off, priced)
    f.arguments[int(off)].x = cost
    f.handlers[int(off)] = flatCharge
  flatCharge(f, off)

proc flatSingleEnd(f: var FlatFrame, off: uint32): uint32 =
  ## A scalar successor publishes one completed source attempt without preparing its destination block.
  f.info.pc = CodeAddress(f.arguments[int(off)].x)
  f.reason = oracle.StepError.StepLimitExceeded
  f.stoppedAt = off
  f.attemptedExit = false
  flatStop

proc flatSingleResolve(f: var FlatFrame, pc: uint32): uint32 =
  ## At most two conditional arms add endpoint nodes; the same genuine target checks precede transfer.
  let decoded = instruction(f.plan.source, CodeAddress(uint64(pc)))
  if decoded.error != ProgramError.None: return flatStop
  assert f.handlers.len < 5
  let offset = uint32(f.handlers.len)
  if not flatEmit(f, flatSingleEnd, FlatArgs(x: uint64(pc), y: 0,
      slots: default(RegisterSlots)), 0): return flatStop
  offset

proc flatAdmitBlock(f: var FlatFrame, pc: uint32): bool =
  ## Materialize one complete containing block, giving every interior resume its original quotas.
  ## The cache exclusively owns this derived plan. The immutable admission owner stays untouched.
  ## Preserve global logical fact slots so native adjacency proofs keep their original index space.
  ## Allocate payload chunks only on writes; untouched blocks retain implicit zero metadata.
  ## A requested block, including a branch prelink, can be catalogued before emission is refused.
  let requested = instructionHeader(f.plan.source, CodeAddress(uint64(pc)))
  if requested.error != ProgramError.None: return false
  if f.plan.admission == nil:
    # Fork only on the first valid resolution; never let two frames mutate one admission catalogue.
    let original = f.plan
    var locations = initMetadataStore[uint32](int(original.codeBytes))
    var facts = initMetadataStore[FlatFact](int(original.admittedFacts))
    if locations.len != int(original.codeBytes) or facts.len != int(original.admittedFacts):
      f.preparationFailure = FlatError.StreamAllocationRefused
      return false
    let derived: nil FlatPlan = FlatPlan(source: original.source, limits: original.limits,
      cycles: original.cycles,
      allowNative: original.allowNative, singleStep: false,
      admission: original, admittedFacts: original.admittedFacts, codeBytes: original.codeBytes,
      ranks: original.ranks)
    if derived == nil:
      f.preparationFailure = FlatError.StreamAllocationRefused
      return false
    derived.factAt = move(locations)
    derived.facts = move(facts)
    f.plan = derived
  let owner = f.plan
  if owner.factAt[int(pc)] != 0: return true
  let containing = containingBlockStart(owner.source, CodeAddress(uint64(pc)))
  assert containing.error == ProgramError.None
  var at = uint64(containing.value)
  let ranks {.cursor.} = owner.ranks
  if ranks == nil:
    f.preparationFailure = FlatError.InvalidProgram
    return false
  let first = int(sourceOrdinal(ranks, uint32(at)))
  var past = first
  let priceIndex = uint32(owner.pricePcs.len)
  owner.pricePcs.add(containing.value)
  if uint64(owner.pricePcs.len) != uint64(priceIndex)+1:
    f.preparationFailure = FlatError.StreamAllocationRefused
    return false
  while true:
    # Immutable validation guarantees complete marked headers through the block terminator.
    assert at < uint64(owner.codeBytes) and owner.factAt[int(at)] == 0
    assert past < owner.facts.len and owner.materialized < owner.admittedFacts
    let decoded = instructionHeader(owner.source, CodeAddress(at))
    assert decoded.error == ProgramError.None
    let fact = flatFact(decoded, priceIndex)
    assert owner.facts[past].sourceCount == 0
    if not writeMetadata(owner.factAt, int(at), uint32(past+1)) or
        not writeMetadata(owner.facts, past, fact):
      f.preparationFailure = FlatError.StreamAllocationRefused
      return false
    inc past
    inc owner.materialized
    if fact.ending: break
    at = uint64(fact.next)
  var count = 0'u32
  var nodes = 0'u32
  var index = past
  while index > first:
    # Within-block ordinals stay contiguous and immutable after this complete publication.
    dec index
    inc count
    if owner.facts[index].opcode != 2: inc nodes
    var fact = owner.facts[index]
    fact.sourceCount = count
    fact.nodeCount = nodes
    if not writeMetadata(owner.facts, index, fact):
      f.preparationFailure = FlatError.StreamAllocationRefused
      return false
  assert owner.factAt[int(pc)] != 0
  true

proc flatResolve(f: var FlatFrame, pc: uint32): uint32 =
  ## Reuse admitted headers and keep offset links stable. For a new suffix, check
  ## the node ceiling and then the work ceiling before the first node or map write.
  ## Admission is atomic per suffix, including each arm of a conditional prelink.
  ## Interior resume can create a prepaid suffix header.
  if f.preparationFailure != FlatError.None: return flatStop
  if f.plan.singleStep: return flatSingleResolve(f, pc)
  if pc >= f.plan.codeBytes: return flatStop
  if f.compiledForPc.len > 0:
    let packed = f.compiledForPc[int(pc)]
    if packed != 0:
      let value = packed-1
      if (value and 0x80000000'u32) != 0: return value and 0x7fffffff'u32
  if not flatAdmitBlock(f, pc): return flatStop
  let packedStart = f.plan.factAt[int(pc)]
  if packedStart == 0: return flatStop
  let start = int(packedStart - 1)
  # The source catalogue is already populated. These quotas guard executable nodes and compiled-PC entries.
  let ceiling = uint64(f.plan.limits.nodes)
  let occupied = uint64(f.handlers.len)
  assert occupied <= ceiling
  let available = ceiling-occupied
  # Sealed non-noop suffix counts make admission constant-time, independently of guest source quotas.
  let required = 1'u64+uint64(f.plan.facts[start].nodeCount)
  if required > available:
    f.preparationFailure = FlatError.StreamLimitExceeded
    return flatStop
  # Node folding does not erase preparation cost: reserve both the emitted suffix span and its whole containing price span.
  let pricePc = f.plan.pricePcs[int(f.plan.facts[start].priceIndex)]
  let packedPrice = f.plan.factAt[int(uint64(pricePc))]
  assert packedPrice != 0
  let priceFact = int(packedPrice - 1)
  let neededWork = uint64(f.plan.facts[start].sourceCount)+uint64(f.plan.facts[
      priceFact].sourceCount)
  let workLimit = uint64(f.plan.limits.preparation)
  assert f.preparationUsed <= workLimit
  if neededWork > workLimit-f.preparationUsed:
    f.preparationFailure = FlatError.PreparationLimitExceeded
    return flatStop
  f.preparationUsed+=neededWork
  if f.compiledForPc.len == 0: f.compiledForPc = initMetadataStore[uint32](f.plan.factAt.len)
  if f.compiledForPc.len != f.plan.factAt.len:
    f.preparationFailure = FlatError.StreamAllocationRefused
    return flatStop
  let origin = uint32(f.handlers.len)
  var index = start
  var first = true
  # A fixed original node ends every short continuation chain, including unoptimized builds.
  var chainLimit = 4
  when defined(pvmX86Jit):
    if f.plan.allowNative: chainLimit = 2 # Keep the unmeasured x86 native fallback layout.
  var continuations = 0
  while index < f.plan.facts.len:
    let fact = f.plan.facts[index]
    let coordinate = uint32(f.handlers.len)
    let packed = f.compiledForPc[int(fact.pc)]
    if packed == 0 or ((packed-1) and 0x80000000'u32) == 0:
      # An overlapping suffix may replace an interior coordinate, never an already published complete entry header.
      let packed = (coordinate or (if first: 0x80000000'u32 else: 0'u32))+1
      if not writeMetadata(f.compiledForPc, int(fact.pc), packed):
        f.preparationFailure = FlatError.StreamAllocationRefused
        return flatStop
    if first:
      # Only a newly emitted header prices its genuine containing block. Its existing sealed charge/error node is the memo; interior suffixes may price once each.
      var charge: FlatHandler = flatCharge
      var needed = 0'u64
      if f.pricingKind == 2:
        # Even eagerly linked untaken branches must not create observable memo entries.
        charge = flatMemoCharge
      else:
        let priced = flatPrice(f, f.plan.pricePcs[int(fact.priceIndex)], needed)
        case priced
        of oracle.StepError.None:
          # Only these measured complete shapes specialize normal headers; folded prefixes and failed prices stay ordinary.
          if fact.sourceCount == 2 and index+1 < f.plan.facts.len and fact.opcode == 131 and
              f.plan.facts[index+1].opcode == 88:
            charge = flatChargedShapeCold[131, -1, 88]
          elif fact.sourceCount == 2 and index+1 < f.plan.facts.len and fact.opcode == 132 and
              f.plan.facts[index+1].opcode == 81 and not f.plan.allowNative:
            charge = flatChargedShapeCold[132, -1, 81]
          elif fact.sourceCount == 3 and index+2 < f.plan.facts.len:
            let second = f.plan.facts[index+1].opcode
            let last = f.plan.facts[index+2].opcode
            if fact.opcode == 200 and second == 139 and last == 82:
              charge = flatChargedShapeCold[200, 139, 82]
            elif fact.opcode == 151 and second == 152 and last == 173:
              charge = flatChargedShapeCold[151, 152, 173]
            elif fact.opcode == 149 and second == 200 and last == 170 and not f.plan.allowNative:
              charge = flatChargedShapeCold[149, 200, 170]
          elif fact.sourceCount == 5 and index+4 < f.plan.facts.len and f.pricingKind == 0:
            # Only this sealed adjacent shape is selected; native x86 has no store publisher for it.
            if fact.opcode == 198 and f.plan.facts[index+1].opcode == 120 and
                f.plan.facts[index+2].opcode == 149 and f.plan.facts[index+3].opcode == 149 and
                f.plan.facts[index+4].opcode == 171:
              when defined(pvmArm64Jit) and not defined(pvmX86Jit):
                # ARM native publication owns this store-loop entry; explicit interpretation keeps the checked worker.
                if not f.plan.allowNative:
                  charge = flatChargedStoreCold
              else:
                # X86 native and interpreted plans use the same source-proven checked word/store loop.
                charge = flatChargedStoreCold
        of oracle.StepError.GasCycleLimitExceeded: charge = flatChargeFailure[
            oracle.StepError.GasCycleLimitExceeded]
        of oracle.StepError.NegativeBranchTarget: charge = flatChargeFailure[
            oracle.StepError.NegativeBranchTarget]
        else: charge = flatChargeFailure[oracle.StepError.InvalidMachine]
      if not flatEmit(f, charge, FlatArgs(x: needed, y: fact.sourceCount,
          slots: default(RegisterSlots)), uint32(index)): return flatStop
      first = false
    let payload = flatSourcePayload(f.plan, fact)
    var selected = payload.handler
    assert selected != nil
    if fact.opcode != 2:
      # Bounded continuation prefixes stop at an original worker before the next chain begins.
      if continuations < chainLimit-1 and fact.fallthrough:
        let first = if isRegisterOpcode(fact.opcode): flatRegisterPairHandler(
            fact.opcode) else: flatMemoryPairHandler(fact.opcode)
        if first != nil:
          selected = first
          # Only these trace-selected adjacent genuine register opcodes fuse; folded noops and other families retain existing dispatch.
          if index+1 < f.plan.facts.len:
            let second = f.plan.facts[index+1].opcode
            let fused = flatFusedRegisterHandler(fact.opcode, second)
            if fused != nil: selected = fused
            elif fact.opcode == 131 and second == 88: selected = flatRegisterBranchCold[131, 88]
            elif fact.opcode == 131 and second == 83 and not f.plan.allowNative:
              # The ADD worker can fuse after resolution while the original branch node
              # remains addressable for partial attempts and shared native certification.
              selected = flatRegisterBranchCold[131, 83]
          inc continuations
        else: continuations = 0
      else: continuations = 0
      if selected != nil and not flatEmit(f, selected, payload.args, uint32(index)): return flatStop
    if fact.ending: break
    inc index
  flatConsiderNative(f, origin)
  when NativeCheckedReadEnabled:
    # Only a newly emitted canonical-looking noop block can reach bounded discovery.
    if f.readProbe.observing and f.plan.facts[start].opcode == 2 and
        f.plan.facts[start].sourceCount in 4'u32..NativeReadFactLimit and
        f.plan.facts[index].opcode == 1:
      discoverReadProbe(f, origin, pc)
  if f.prefixProbeOriginal == nil and nativePrefixObservation(f.nativeSession):
    installFlatPrefixProbe(f)
  origin

proc flatNativePure(f: var FlatFrame, off: uint32): uint32 =
  ## One shared control bridge: full paid original prefix first, fresh registers only, no native replay.
  let original = f.nativeOriginal
  if original == nil or off != f.nativeEntry:
    return flatLocal(f, off, oracle.StepError.BackendFailure)
  if f.pricingKind != 0 or f.barrier != flatStop or not f.info.blockCharged or
      not nativeSpanReady(f.nativeSession) or
      not matchesNativeImage(f.nativeSession, f.nativeInstallation.key, NativeKind.PurePrefix):
    return original(f, off)
  let span = nativeSpanInfo(f.nativeSession)
  if span.epoch != f.nativeInstalledEpoch: return original(f, off)
  var reservedEnd = f.reservation
  if (reservedEnd and flatReservationHeaderFlag) != 0:
    let header = reservedEnd and not flatReservationHeaderFlag
    reservedEnd = f.sites[int(header)]+f.arguments[int(header)].y
  if reservedEnd <= span.last: return original(f, off)
  if not runNativeSpan(f.nativeSession, f.info.registers):
    return flatLocal(f, off, oracle.StepError.BackendFailure)
  span.past

func flatSourceHeader(f: FlatFrame, header, pc: uint32): bool =
  ## Accept only a materialized original block header at this exact source PC.
  if header >= NativeEntryLimit or uint64(header) >= uint64(f.handlers.len) or
      uint64(header) >= uint64(f.sites.len) or uint64(pc) >= uint64(f.compiledForPc.len):
    return false
  if f.compiledForPc[int(pc)] != (header or flatReservationHeaderFlag)+1: return false
  let ordinal = f.sites[int(header)]
  if uint64(ordinal) >= uint64(f.plan.facts.len): return false
  let fact = f.plan.facts[int(ordinal)]
  fact.pc == pc and uint64(fact.priceIndex) < uint64(f.plan.pricePcs.len) and
    uint64(f.plan.pricePcs[int(fact.priceIndex)]) == uint64(pc)

func flatNativeHeader(f: FlatFrame, header, pc: uint32): bool =
  ## The single-header loop also requires the original ordinary charge worker.
  flatSourceHeader(f, header, pc) and f.handlers[int(header)] == flatCharge

when NativeCheckedReadEnabled:
  include ./handler_register_ring

proc flatLoopCertificate(f: FlatFrame, span: NativeSpanInfo): NativeLoopInfo =
  ## Check the one selected prefix against resolved source, without admitting or pricing another node.
  result = default(NativeLoopInfo)
  if f.plan == nil or f.plan.singleStep or f.pricingKind != 0 or
      f.preparationFailure != FlatError.None or span.epoch != nativeEpoch(f.nativeSession):
    return
  if span.len < NativeMinimumOperations or span.len >= NativeSpanOperations or span.entry == 0 or
      span.past >= NativeEntryLimit or span.past <= span.entry or
      span.past-span.entry != uint32(span.len) or span.last < span.first or
      span.last-span.first != uint32(span.len-1) or
      uint64(span.last)+1 >= uint64(f.plan.facts.len) or int(span.past) >= f.handlers.len or
      int(span.past) >= f.arguments.len or int(span.past) >= f.sites.len: return
  let header = span.entry-1
  let first = f.plan.facts[int(span.first)]
  let terminal = f.plan.facts[int(span.last)+1]
  let rightKind = case terminal.opcode
    of 83: NativeLoopRightKind.Immediate
    of 172: NativeLoopRightKind.Register
    else: return
  let branchHandler: FlatHandler = if rightKind == NativeLoopRightKind.Immediate:
    flatBranch[83]
  else:
    flatBranch[172]
  let sourceSpan = uint32(span.len)+1
  if not flatNativeHeader(f, header, first.pc) or f.sites[int(header)] != span.first or
      f.arguments[int(header)].y != sourceSpan or first.sourceCount != sourceSpan or
      f.sites[int(span.past)] != span.last+1 or not terminal.ending or
      terminal.priceIndex != first.priceIndex or f.handlers[int(span.past)] != branchHandler:
    return
  let branch = f.arguments[int(span.past)]
  let exitHeader = branch.y
  if uint32(branch.x shr 32) != header: return
  let terminalPayload = flatSourcePayload(f.plan, terminal)
  if uint32(terminalPayload.args.x shr 32) != first.pc or
      branch.slots != terminalPayload.args.slots or (branch.x and 0xffffffff'u64) !=
        (terminalPayload.args.x and 0xffffffff'u64) or
      (exitHeader >= header and exitHeader <= span.past) or
      not flatNativeHeader(f, exitHeader, terminalPayload.args.y): return
  for index in 0..<span.len:
    # Each original scalar fact has exactly one body node, with no folded or crossing instruction.
    let ordinal = span.first+uint32(index)
    let node = int(span.entry)+index
    let fact = f.plan.facts[int(ordinal)]
    let args = f.arguments[node]
    if f.sites[node] != ordinal or fact.ending or not fact.fallthrough or
        fact.priceIndex != first.priceIndex or fact.next != f.plan.facts[int(ordinal)+1].pc: return
    let payload = flatSourcePayload(f.plan, fact)
    if args.x != payload.args.x or args.slots != payload.args.slots or
        not matchesNativeOperation(f.nativeSession, index, fact.opcode, payload.args.slots,
          payload.args.x): return
  # The cached low word has been checked against the original branch fact.
  let immediate = if rightKind == NativeLoopRightKind.Immediate:
    flatSext32(uint32(branch.x and 0xffffffff'u64))
  else:
    0'u64
  result = NativeLoopInfo(header: header, exitHeader: exitHeader, sourceSpan: sourceSpan,
    price: f.arguments[int(header)].x, slots: branch.slots, rightKind: rightKind,
    rightImmediate: immediate)

proc flatPromoteNativeLoop(f: var FlatFrame) =
  ## Reconsider the same deferred prefix only after the checked segment has resolved its branch.
  if not nativePromotionOpen(f.nativeSession): return
  let loop = flatLoopCertificate(f, nativeSpanInfo(f.nativeSession))
  if loop.kind == NativeKind.ClosedRegisterLoop: promoteNativeLoop(f.nativeSession, loop)

proc flatNativeLoop(f: var FlatFrame, off: uint32): uint32 =
  ## The installed certificate is stable. Only an exact complete reservation authorizes first entry.
  let original = f.nativeOriginal
  if original == nil:
    return flatLocal(f, off, oracle.StepError.BackendFailure)
  if f.pricingKind != 0 or f.barrier != flatStop or not f.info.blockCharged or
      off != f.nativeEntry or not nativeSpanReady(f.nativeSession):
    return original(f, off)
  let loop = nativeLoopInfo(f.nativeSession)
  if loop.kind != NativeKind.ClosedRegisterLoop or
      not matchesNativeImage(f.nativeSession, f.nativeInstallation.key,
          NativeKind.ClosedRegisterLoop) or
      nativeEpoch(f.nativeSession) != f.nativeInstalledEpoch or off != loop.header+1 or
      f.reservation != (loop.header or flatReservationHeaderFlag) or
      f.handlers[int(loop.header)] != flatCharge or f.arguments[int(loop.header)].x != loop.price or
      f.arguments[int(loop.header)].y != loop.sourceSpan: return original(f, off)
  var context = NativeLoopContext(gas: uint64(f.info.gas), remaining: f.remaining, visits: 0)
  result = runNativeLoop(f.nativeSession, f.info.registers, context)
  if result == NativeEntryFailure: return flatLocal(f, off, oracle.StepError.BackendFailure)
  # The checked successor sees an unstarted block, including on a failed native next-visit guard.
  f.info.gas = MachineGas(context.gas)
  f.remaining = context.remaining
  f.info.blockCharged = false
  f.reservation = loop.header or flatReservationHeaderFlag

when NativeCheckedReadEnabled:
  proc installFlatReadBody(f: var FlatFrame, info: NativeReadBodyInfo)
when NativeReadCycleEnabled:
  proc installFlatReadCycle(f: var FlatFrame, info: NativeReadBodyInfo)

proc installNative(f: var FlatFrame) =
  ## Only the caller mutates its exclusively held stream; each image uses its own certificate.
  if f.pricingKind != 0: return
  if f.nativeInstallation.count != 0 and
      f.nativeInstallation.key != nativeInstalledKey(f.nativeSession):
    flatRestoreNativeInstallation(f)
  if f.nativeOriginal != nil: return
  when NativeReadCycleEnabled:
    let bitmap = nativeBitmapInfo(f.nativeSession)
    if bitmap.epoch != 0:
      installFlatBitmap(f, bitmap)
      return
    let cycle = nativeReadCycleInfo(f.nativeSession)
    if cycle.epoch != 0:
      installFlatReadCycle(f, cycle)
      return
  when NativeCheckedReadEnabled:
    let read = nativeReadInfo(f.nativeSession)
    if read.epoch != 0:
      installFlatReadBody(f, read)
      return
  when NativeCheckedReadEnabled:
    let ring = nativeRingInfo(f.nativeSession)
    if ring.blocks[0].span != 0:
      flatInstallNativeRing(f, ring)
      return
  if not nativeSpanReady(f.nativeSession): return
  let span = nativeSpanInfo(f.nativeSession)
  let candidate = nativeLoopInfo(f.nativeSession)
  if candidate.kind == NativeKind.ClosedRegisterLoop:
    let loop = flatLoopCertificate(f, span)
    if loop.sourceSpan != candidate.sourceSpan or loop.header != candidate.header or
        loop.exitHeader != candidate.exitHeader or loop.price != candidate.price or
        loop.slots != candidate.slots or loop.rightKind != candidate.rightKind or
        loop.rightImmediate != candidate.rightImmediate:
      invalidateNativeStream(f.nativeSession)
      return
    f.nativeOriginal = f.handlers[int(span.entry)]
    f.nativeEntry = span.entry
    f.nativeInstalledEpoch = span.epoch
    flatInstallNativePatch(f, span.entry, flatNativeLoop)
    return
  if span.epoch != nativeEpoch(f.nativeSession) or int(span.entry) >= f.handlers.len or
      int(span.past) >= f.handlers.len or span.past <= span.entry: return
  if f.sites[int(span.entry)] != span.first or f.sites[int(span.past)-1] != span.last: return
  if f.nativeOriginal == nil:
    if int(span.last) >= f.plan.facts.len: return
    var operation = 0
    for ordinal in span.first..span.last:
      let fact = f.plan.facts[int(ordinal)]
      # Folded noops remain original attempts but emit no register operation.
      if fact.opcode == 2: continue
      if fact.ending or not fact.fallthrough:
        invalidateNativeStream(f.nativeSession)
        return
      let payload = flatSourcePayload(f.plan, fact)
      if not matchesNativeOperation(f.nativeSession, operation, fact.opcode,
          payload.args.slots, payload.args.x):
        invalidateNativeStream(f.nativeSession)
        return
      inc operation
    if operation != span.len:
      invalidateNativeStream(f.nativeSession)
      return
    f.nativeOriginal = f.handlers[int(span.entry)]
    f.nativeEntry = span.entry
    f.nativeInstalledEpoch = span.epoch
    flatInstallNativePatch(f, span.entry, flatNativePure)

proc installFlatPrefixProbe(f: var FlatFrame) =
  ## Ordinary and adjacent-pair headers share the same reservation/body fallback.
  ## Defer their private specialization until two actual scalar entries; a host before the prefix buys no visit.
  ## The containing block must be fully materialized. No operand decode, admission or allocation is needed.
  if f.prefixProbeOriginal != nil or f.pricingKind != 0 or
      not nativePrefixObservation(f.nativeSession) or f.plan == nil: return
  let span = nativeSpanInfo(f.nativeSession)
  if uint64(span.first) >= uint64(f.plan.facts.len): return
  let header = nativePrefixHeader(f.nativeSession)
  if header >= span.entry or uint64(header) >= uint64(f.handlers.len) or
      uint64(header) >= uint64(f.sites.len) or uint64(header) >= uint64(f.arguments.len) or
      uint64(span.entry) >= uint64(f.handlers.len) or uint64(span.entry) >= uint64(f.sites.len) or
      uint64(span.entry) >= uint64(f.arguments.len) or f.sites[int(span.entry)] != span.first or
          f.barrier == span.entry: return
  let original = f.handlers[int(header)]
  if original != flatCharge:
    # Only these specialized workers promise the same original-body fallback as an ordinary header.
    let adjacentFirstCold: FlatHandler = flatChargedShapeCold[149, 200, 170]
    let adjacentSecondCold: FlatHandler = flatChargedShapeCold[132, -1, 81]
    let adjacentFirst: FlatHandler = flatChargedAdjacent[true]
    let adjacentSecond: FlatHandler = flatChargedAdjacent[false]
    if original != adjacentFirstCold and original != adjacentSecondCold and
        original != adjacentFirst and original != adjacentSecond: return
  let first = f.sites[int(header)]
  if first > span.first or uint64(first) >= uint64(f.plan.facts.len): return
  let fact = f.plan.facts[int(first)]
  if fact.priceIndex != f.plan.facts[int(span.first)].priceIndex or
      f.arguments[int(header)].y != fact.sourceCount or
      uint64(fact.pc) >= uint64(f.compiledForPc.len) or
      f.compiledForPc[int(fact.pc)] != (header or flatReservationHeaderFlag)+1: return
  f.prefixProbeHeader = header
  f.prefixProbeOriginal = original
  f.prefixProbeBody = span.entry
  f.prefixProbeBodyOriginal = f.handlers[int(span.entry)]
  f.handlers[int(header)] = flatPrefixProbe
  f.handlers[int(span.entry)] = flatPrefixBodyProbe

proc restoreFlatPrefixProbe(f: var FlatFrame) =
  ## Restore both exact predecessors before handback, including either slot's saved quota predecessor.
  let original = f.prefixProbeOriginal
  let body = f.prefixProbeBodyOriginal
  if original == nil and body == nil: return
  f.prefixProbeOriginal = nil
  f.prefixProbeBodyOriginal = nil
  if body != nil:
    restoreFlatTemporaryHandler(f, f.prefixProbeBody, flatPrefixBodyProbe, body)
  if original != nil:
    restoreFlatTemporaryHandler(f, f.prefixProbeHeader, flatPrefixProbe, original)

proc flatConsiderNative(f: var FlatFrame, origin: uint32) =
  ## Shared structural classification precedes any native cache/byte allocation and all ISA decisions.
  let epoch = nativeEpoch(f.nativeSession)
  if epoch == 0 or f.pricingKind != 0 or nativeSpanInfo(f.nativeSession).len != 0: return
  var index = max(origin, nativeScanStart(f.nativeSession))
  var header = NativeEntryFailure
  while int(index) < f.handlers.len and index < NativeEntryLimit:
    # Each retained emission has its own header, even when another suffix shares source facts.
    if uint64(index) >= uint64(f.sites.len): return
    let site = f.sites[int(index)]
    if uint64(site) >= uint64(f.plan.facts.len): return
    let pc = f.plan.facts[int(site)].pc
    if uint64(pc) < uint64(f.compiledForPc.len) and
        f.compiledForPc[int(pc)] == (index or flatReservationHeaderFlag)+1:
      header = index
    # Synthetic charge headers duplicate the next source site and never belong to a pure body.
    if int(index)+1 < f.sites.len and f.sites[int(index)] == f.sites[int(index)+1]:
      inc index
      continue
    var span = initNativeSpan(index, f.sites[int(index)], epoch)
    var at = index
    while int(at) < f.handlers.len and span.len < NativeSpanOperations:
      if int(at)+1 < f.sites.len and f.sites[int(at)] == f.sites[int(at)+1]: break
      let fact = f.plan.facts[int(f.sites[int(at)])]
      if fact.ending or not fact.fallthrough: break
      let payload = flatSourcePayload(f.plan, fact)
      if not span.add(fact.opcode, payload.args.slots, payload.args.x, f.sites[int(at)], at+1): break
      inc at
    if span.len >= NativeMinimumOperations and int(span.past) < f.handlers.len:
      considerNativeSpan(f.nativeSession, span, header)
      return
    index = if at > index: at else: index+1
  completeNativeScan(f.nativeSession, index)

proc settledNativeWork*(f: FlatFrame, supplied: uint64): uint64 =
  ## Initial conservative allowlist: normal checked halt/host excludes its attempted terminal instruction.
  ## Local errors, faults/panics/OOG and mixed native receipts contribute no speculative completion credit.
  if f.reason != oracle.StepError.None or f.exit notin {oracle.StepExit.Halt,
      oracle.StepExit.Host} or (not f.attemptedExit) or f.remaining > supplied: return 0
  let attempted = supplied-f.remaining
  if attempted == 0: return 0
  attempted-1

proc resetFlatFrame*(f: var FlatFrame, info: MachineInfo) =
  ## Restore input outside the execution clock, preserving the explicit reset boundary; cached code/links alone persist.
  flatClearDirty(f)
  f.hostReady = false
  f.hostSnapshot = default(Memory)
  f.info = info
  f.reason = oracle.StepError.None
  f.exit = oracle.StepExit.Continued
  f.faultPage = PageAddress(0)
  f.hostCall = oracle.HostCallId(0)
  let memory = f.sourceMemory
  for page in 0..<f.sourcePages.len:
    let image = f.sourcePages[page]
    if image.access == PageAccess.Inaccessible: continue
    let address = uint64(uint32(image.index))*4096
    if address >= f.stackBase and address-f.stackBase+4096 <= uint64(f.stack.len):
      let offset = int(address-f.stackBase)
      flatCopySourcePage(memory, page, image, f.stack.toOpenArray(offset, offset+4095))
    elif address >= f.rwBase and address-f.rwBase+4096 <= uint64(f.rw.len):
      let offset = int(address-f.rwBase)
      flatCopySourcePage(memory, page, image, f.rw.toOpenArray(offset, offset+4095))
    elif address >= f.roBase and address-f.roBase+4096 <= uint64(f.ro.len):
      let offset = int(address-f.roBase)
      flatCopySourcePage(memory, page, image, f.ro.toOpenArray(offset, offset+4095))
    else:
      var found = false
      for i in 0..<f.extra.len:
        let region {.cursor.} = f.extra[i]
        if address >= region.first and address-region.first+4096 <= uint64(region.size):
          if region.bytes.len != 0:
            # A baseline-backed extra is already restored through this immutable source owner.
            assert region.bytes.len == region.size
            let offset = int(address-region.first)
            flatCopySourcePage(memory, page, image,
              f.extra[i].bytes.toOpenArray(offset, offset+4095))
          found = true
          break
      assert found

proc flatFrameShell[reuseDirtyMetadata: static[bool]](plan: FlatPlan, memory: Memory,
    info: MachineInfo, pageCount, dirtyWordCount: int): FlatFrame =
  ## Both paths initialize every execution field afresh; the memory lease never supplies execution state.
  result = FlatFrame(plan: plan,
      preparationFailure: FlatError.None, preparationUsed: 0, hostSnapshot: default(Memory),
          hostReady: false,
    hostSnapshotPc: CodeAddress(0), fastResumes: 0, fallbackResumes: 0, hostCopiedPages: 0,
    # The admitted map bounds this bitmap; a later host remap rebuilds both capabilities together.
    dirtyPages: (when reuseDirtyMetadata: default(seq[uint64])
      else: (if dirtyWordCount == 0: @[] else: newSeq[uint64](dirtyWordCount))),
    dirtyIndices: (when reuseDirtyMetadata: default(seq[uint32])
      else: newSeqOfCap[uint32](pageCount)),
        info: info, reason: oracle.StepError.None,
    exit: oracle.StepExit.Continued,
    faultPage: PageAddress(0), hostCall: oracle.HostCallId(0), handlers: @[], arguments: @[],
        sites: @[],
    compiledForPc: default(MetadataStore[uint32]), sourceMemory: memory, sourcePages: @[],
    roBase: 0, rwBase: uint64(high(uint32)), stackBase: uint64(high(uint32)), ro: @[], rw: default(
        RWView), stack: @[], extra: @[], rwStorage: initRWStorage(),
    remaining: 0, reservation: 0, stoppedAt: 0, attemptedExit: false, barrier: flatStop,
        barrierFact: 0, savedHandler: nil)

proc flatRegionPast(images: openArray[PageDescription], first: int): int =
  ## Group only genuinely adjacent pages with equal permission before any region payload allocation.
  assert first >= 0 and first < images.len
  result = first+1
  while result < images.len and images[result].access == images[first].access and
      uint64(uint32(images[result].index)) == uint64(uint32(images[result-1].index))+1:
    inc result # The admitted description count bounds both metadata walks identically.

proc buildFlatFrame(plan: FlatPlan, images: var seq[PageDescription], info: MachineInfo,
    memory: Memory): FlatResult[FlatFrame] =
  ## Classify first, then construct one complete frame; failure owns no partial public payload.
  # Sorted genuine descriptions bound every physical bit, including RO and inaccessible observations.
  let dirtyWordCount = if images.len == 0: 0
    else: int((uint64(uint32(images[images.len-1].index)) shr 6)+1)
  var frame = flatFrameShell[false](plan, memory, info, images.len, dirtyWordCount)
  if frame.dirtyPages.len != dirtyWordCount or
      (images.len > 0 and frame.dirtyIndices.rawData == nil):
    return FlatResult[FlatFrame](status: FlatError.ResidentAllocationRefused)
  var firstRO = -1
  var firstRW = -1
  var lastRW = -1
  var ordinal = 0
  var first = 0
  while first < images.len:
    # Inaccessible descriptions never create a private allocation or native permission capability.
    if images[first].access == PageAccess.Inaccessible:
      inc first
      continue
    if images[first].access == PageAccess.ReadOnly and firstRO < 0: firstRO = ordinal
    if images[first].access == PageAccess.ReadWrite:
      if firstRW < 0: firstRW = ordinal
      lastRW = ordinal
    first = flatRegionPast(images, first)
    inc ordinal
  # Reserve exact value storage so building a region needs no separate ref allocation.
  var regions = newSeqOfCap[FlatRegion](ordinal)
  if ordinal > 0 and regions.rawData == nil:
    return FlatResult[FlatFrame](status: FlatError.ResidentAllocationRefused)
  var residentRW = false
  first = 0
  while first < images.len:
    let image = images[first]
    if image.access == PageAccess.Inaccessible:
      inc first
      continue
    let after = flatRegionPast(images, first)
    let pages = after-first
    if pages > high(int) div 4096:
      return FlatResult[FlatFrame](status: FlatError.ResidentAllocationRefused)
    let address = uint64(uint32(image.index))*4096
    if regions.len == firstRW:
      # Only this first RW run may allocate foreign storage, before any legacy byte seq exists.
      var captured = tryCaptureFreshZeroRW(memory, images, first, after)
      case captured.error
      of FreshRWStatus.Owned:
        var resident = resident_capture.takeOwned(captured)
        frame.rwStorage = takeResident(resident)
        residentRW = true
        regions.add(FlatRegion(first: address, access: image.access,
          size: pages*4096, sourceFirst: first, bytes: @[]))
      of FreshRWStatus.NotSelected:
        discard # The managed construction below owns the fallback.
      of FreshRWStatus.AllocationRefused:
        return FlatResult[FlatFrame](status: FlatError.ResidentAllocationRefused)
      else:
        return FlatResult[FlatFrame](status: FlatError.InvalidMemory)
      if residentRW:
        first = after
        continue
    if regions.len != firstRO and regions.len != firstRW and regions.len != lastRW:
      # Extras retain logical coordinates under the frame's immutable owner without allocating payload bytes.
      regions.add(FlatRegion(first: address, access: image.access,
        size: pages*4096, sourceFirst: first, bytes: @[]))
      first = after
      continue
    # Preserve eager primary allocation and complete fill before deriving any frame/native view.
    var region = FlatRegion(first: address, access: image.access,
      size: pages*4096, sourceFirst: first, bytes: newSeqUninit[byte](pages*4096))
    if region.bytes.len != region.size:
      return FlatResult[FlatFrame](status: FlatError.ResidentAllocationRefused)
    for page in first..<after:
      # All managed primary paths still restore complete pages before installing the final owner.
      let offset = (page-first)*4096
      if not flatTryCopySourcePage(memory, page, images[page],
          region.bytes.toOpenArray(offset, offset+4095)):
        return FlatResult[FlatFrame](status: FlatError.InvalidMemory)
    regions.add(move(region))
    first = after
  frame.sourcePages = move(images)
  # A sole writable run fills RW only; count its last-RW role once before reserving extra slots.
  let primaryCount = int(firstRO >= 0) + int(firstRW >= 0) +
    int(lastRW >= 0 and lastRW != firstRW)
  frame.extra = newSeqOfCap[FlatRegion](ordinal-primaryCount)
  if ordinal > primaryCount and frame.extra.rawData == nil:
    return FlatResult[FlatFrame](status: FlatError.ResidentAllocationRefused)
  for i in 0..<regions.len:
    # Preserve firstRO/firstRW/lastRW precedence, including a sole writable run remaining RW.
    var region = move(regions[i])
    if i == firstRO:
      frame.roBase = region.first
      frame.ro = move(region.bytes)
    elif i == firstRW:
      frame.rwBase = region.first
      if not residentRW: frame.rwStorage = takeManaged(region.bytes)
      frame.rw = borrowRW(frame.rwStorage) # Derive the borrow only after final owner installation.
    elif i == lastRW:
      frame.stackBase = region.first
      frame.stack = move(region.bytes)
    else: frame.extra.add(move(region))
  FlatResult[FlatFrame](status: FlatError.None, completed: move(frame))

proc prepareFlatMemoryFrame*(plan: FlatPlan, memory: Memory, info: MachineInfo): FlatResult[FlatFrame]
  ## The immutable memory-owner constructor is also used by captured page-image inputs.

proc prepareFlatFrame*(plan: FlatPlan, images: openArray[PageImage], info: MachineInfo): FlatResult[FlatFrame] =
  ## Validate complete page admission before private region copies; a refusal contains no partial frame.
  if uint64(images.len) > uint64(uint32(plan.limits.pages)):
    return FlatResult[FlatFrame](status: FlatError.PageLimitExceeded)
  let memory = captureMemory(images, plan.limits.pages)
  if memory.error != MachineError.None: return FlatResult[FlatFrame](
      status: FlatError.InvalidMemory)
  prepareFlatMemoryFrame(plan, memory.value, info)

proc newFlatFrame*(plan: FlatPlan, images: openArray[PageImage], info: MachineInfo): FlatFrame =
  ## Local witness convenience only; application admission uses prepareFlatFrame and checks its typed result.
  var prepared = prepareFlatFrame(plan, images, info)
  assert prepared.error == FlatError.None
  takeValue(prepared)

func flatSourceIntervalAt(f: FlatFrame, header, maxSpan: uint32,
    found: var FlatSourceInterval): bool =
  ## A successful interval ends at a source terminal; identity, interiors and child proofs stay with callers.
  if uint64(header) >= uint64(f.handlers.len) or uint64(header) >= uint64(f.sites.len) or
      uint64(header) >= uint64(f.arguments.len): return false
  let first = f.sites[int(header)]
  let span = f.arguments[int(header)].y
  if span == 0 or span > maxSpan or uint64(first)+uint64(span) > uint64(f.plan.facts.len):
    return false
  let last = first+(span-1)
  if not f.plan.facts[int(last)].ending: return false
  # Failure leaves the output untouched; this value does not certify any handler or priced-block identity.
  found = FlatSourceInterval(first: first, last: last, span: span,
    price: f.arguments[int(header)].x)
  true

include ./handler_trace_source
when NativeReadCycleEnabled:
  include ./handler_bitmap_loop
when NativeCheckedReadEnabled:
  when NativeReadCycleEnabled:
    proc buildFlatReadCycle(f: FlatFrame, read: NativeReadBody): NativeReadCycle
  include ./handler_read_body
  when NativeReadCycleEnabled:
    include ./handler_mixed_loop
    include ./handler_read_cycle
    include ./handler_fusion
  include ./read_admission_probe

when defined(pvmArmMacroReceipt) or defined(pvmX86MemoryCycleSealWitness):
  func flatSourceIntervalProof*(f: FlatFrame, pc, maxSpan: uint32,
      fields: var array[5, uint64]): bool =
    ## Read only an already captured complete entry; this adapter's map proof is not the interval's contract.
    if uint64(pc) >= uint64(f.compiledForPc.len): return false
    let packed = f.compiledForPc[int(pc)]
    if packed == 0: return false
    let entry = packed-1
    if (entry and 0x80000000'u32) == 0: return false
    let header = entry and 0x7fffffff'u32
    var source = default(FlatSourceInterval)
    if not flatSourceIntervalAt(f, header, maxSpan, source): return false
    fields = [uint64(header), uint64(source.first), uint64(source.last), uint64(source.span),
      source.price]
    true

when defined(pvmX86Jit):
  func flatX86CachedBranch(f: FlatFrame, offset: uint32): bool =
    ## Exact original worker identity certifies that both scalar destinations passed checked source/target admission.
    let opcode = f.plan.facts[int(f.sites[int(offset)])].opcode
    case opcode
    of 81: f.handlers[int(offset)] == flatBranch[81]
    of 82: f.handlers[int(offset)] == flatBranch[82]
    of 83: f.handlers[int(offset)] == flatBranch[83]
    of 84: f.handlers[int(offset)] == flatBranch[84]
    of 85: f.handlers[int(offset)] == flatBranch[85]
    of 86: f.handlers[int(offset)] == flatBranch[86]
    of 87: f.handlers[int(offset)] == flatBranch[87]
    of 88: f.handlers[int(offset)] == flatBranch[88]
    of 89: f.handlers[int(offset)] == flatBranch[89]
    of 90: f.handlers[int(offset)] == flatBranch[90]
    of 170: f.handlers[int(offset)] == flatBranch[170]
    of 171: f.handlers[int(offset)] == flatBranch[171]
    of 172: f.handlers[int(offset)] == flatBranch[172]
    of 173: f.handlers[int(offset)] == flatBranch[173]
    of 174: f.handlers[int(offset)] == flatBranch[174]
    of 175: f.handlers[int(offset)] == flatBranch[175]
    else: false

  func flatX86RegionStatistics*(f: FlatFrame): array[2, uint64] =
    ## The checked stream has no private x86 region owner. Raw regions report through their own JIT.
    default(array[2, uint64])

  when defined(pvmX86Jit):
    func flatX86CompleteSource(f: FlatFrame, pc: uint32,
        found: var X86MemoryCycleHeader): bool =
      ## Recheck one published basic-block header, its original priced span and every emitted site.
      found = default(X86MemoryCycleHeader)
      var header = 0'u32
      var source = default(FlatSourceInterval)
      if not flatCompleteOriginalHeader(f, pc, 65, header, source): return false
      let ordinal = source.first
      let last = source.last
      var summary = default(FlatSourceSummary)
      if not flatWalkCompleteSource(f, header, source, summary): return false
      let handler = f.handlers[int(header)]
      let kind = if handler == flatCharge: X86MemoryCycleHandlerKind.Ordinary
        elif handler == flatChargedWordLoop: X86MemoryCycleHandlerKind.CheckedWord
        else: X86MemoryCycleHandlerKind.Other
      found = X86MemoryCycleHeader(pc: pc, header: header, ordinal: ordinal, span: source.span,
        terminal: summary.terminal, price: source.price,
        opcode: f.plan.facts[int(last)].opcode, kind: kind)
      true

    func flatX86CompleteTarget(f: FlatFrame, offset: uint32,
        found: var X86MemoryCycleHeader): bool =
      ## A cached arm must name the exact current complete header, never an interior or stale site.
      found = default(X86MemoryCycleHeader)
      if int(offset) >= f.sites.len: return false
      let ordinal = f.sites[int(offset)]
      if int(ordinal) >= f.plan.facts.len: return false
      let pc = f.plan.facts[int(ordinal)].pc
      flatX86CompleteSource(f, pc, found) and found.header == offset

    func flatX86SealMemoryCycle*(f: FlatFrame, prefixPc: uint32,
        candidate: var X86MemoryCycleCandidate): bool =
      ## Prove the narrow three-block source graph without reading guest values or changing a cache.
      candidate = default(X86MemoryCycleCandidate)
      # This is a source-only seal. A stopped paid frame may publish code because the worker
      # retains the original handler for every paid or partial-budget reentry.
      # The publisher separately requires an executable owner, even when this source is valid.
      if not f.plan.allowNative or f.plan.singleStep or f.preparationFailure != FlatError.None or
          f.pricingKind != 0 or f.barrier != flatStop:
        return false
      var prefix = default(X86MemoryCycleHeader)
      if not flatX86CompleteSource(f, prefixPc, prefix): return false
      if prefix.kind != X86MemoryCycleHandlerKind.Ordinary or prefix.opcode != 1 or
          f.handlers[int(prefix.terminal)] != flatCachedJump[1]: return false
      var dirty = default(X86MemoryCycleHeader)
      if not flatX86CompleteTarget(f, f.arguments[int(prefix.terminal)].y, dirty): return false
      if prefix.header == dirty.header or dirty.span != 5 or dirty.opcode != 171 or
          dirty.kind != X86MemoryCycleHandlerKind.CheckedWord or
          not flatX86CachedBranch(f, dirty.terminal): return false
      for i in 0..<5:
        if f.plan.facts[int(dirty.ordinal)+i].opcode != [198'u8, 120, 149, 149, 171][i]:
          return false
      if not flatWordShape(f, dirty.header): return false
      let dirtyArms = f.arguments[int(dirty.terminal)]
      if uint32(dirtyArms.x shr 32) != dirty.header: return false
      dirty.yes = dirty.header
      var tail = default(X86MemoryCycleHeader)
      if not flatX86CompleteTarget(f, dirtyArms.y, tail): return false
      if tail.header == prefix.header or tail.header == dirty.header or
          tail.kind != X86MemoryCycleHandlerKind.Ordinary or tail.opcode != 173 or
          not flatX86CachedBranch(f, tail.terminal): return false
      var prefixOps = default(array[4, uint32])
      var prefixCount = 0
      for at in prefix.ordinal..<prefix.ordinal+prefix.span:
        if f.plan.facts[int(at)].opcode != 2:
          if prefixCount >= prefixOps.len: return false
          prefixOps[prefixCount] = at
          inc prefixCount
      if prefixCount != 4 or f.plan.facts[int(prefixOps[0])].opcode != 51 or
          f.plan.facts[int(prefixOps[1])].opcode != 200 or
          f.plan.facts[int(prefixOps[2])].opcode != 149 or
          f.plan.facts[int(prefixOps[3])].opcode != 1: return false
      var tailOps = default(array[3, uint32])
      var tailCount = 0
      for at in tail.ordinal..<tail.ordinal+tail.span:
        if f.plan.facts[int(at)].opcode != 2:
          if tailCount >= tailOps.len: return false
          tailOps[tailCount] = at
          inc tailCount
      if tailCount != 3 or f.plan.facts[int(tailOps[0])].opcode notin {52'u8..58} or
          f.plan.facts[int(tailOps[1])].opcode != 131 or
          f.plan.facts[int(tailOps[2])].opcode != 173: return false
      let tailArms = f.arguments[int(tail.terminal)]
      if uint32(tailArms.x shr 32) != prefix.header: return false
      tail.yes = prefix.header
      var outside = default(X86MemoryCycleHeader)
      if not flatX86CompleteTarget(f, tailArms.y, outside): return false
      if outside.header == prefix.header or outside.header == dirty.header or
          outside.header == tail.header or outside.kind != X86MemoryCycleHandlerKind.Ordinary:
        return false
      dirty.no = tail.header
      tail.no = outside.header
      prefix.yes = dirty.header
      let pLoad = f.arguments[int(prefix.header+1)]
      let pBound = f.arguments[int(prefix.header+2)]
      let pStep = f.arguments[int(prefix.header+3)]
      let dExtract = f.arguments[int(dirty.header+1)]
      let dStore = f.arguments[int(dirty.header+2)]
      let dBranch = f.arguments[int(dirty.terminal)]
      let tRead = f.arguments[int(tail.header+1)]
      let tStep = f.arguments[int(tail.header+2)]
      let tBranch = f.arguments[int(tail.terminal)]
      let data = dExtract.slots.aIndex
      let shift = dExtract.slots.bIndex
      let extracted = dExtract.slots.destinationIndex
      let base = dStore.slots.bIndex
      let bound = dBranch.slots.bIndex
      let length = pBound.slots.bIndex
      let counter = tBranch.slots.aIndex
      let readResult = tRead.slots.aIndex
      let roles = [data, shift, extracted, base, bound, length, counter, readResult]
      for i in 0..<roles.len:
        for j in i+1..<roles.len:
          if roles[i] == roles[j]: return false
      if pLoad.slots.destinationIndex != shift or pBound.slots.aIndex != base or
          pBound.slots.destinationIndex != bound or pStep.slots.bIndex != bound or
          pStep.slots.destinationIndex != bound or pStep.x != 1 or
          tStep.slots.bIndex != counter or tStep.slots.destinationIndex != counter or
          tStep.x != 1 or tBranch.slots.bIndex != readResult: return false
      let readOpcode = f.plan.facts[int(tailOps[0])].opcode
      let width = case readOpcode
        of 52, 53: 1'u8
        of 54, 55: 2'u8
        of 56, 57: 4'u8
        else: 8'u8
      candidate = X86MemoryCycleCandidate(prefix: prefix, dirty: dirty, tail: tail,
        outside: outside, readOrdinal: tailOps[0], readImmediate: tRead.x,
        storeDisplacement: dStore.x, initialShift: pLoad.x,
        readOpcode: readOpcode, readWidth: width,
        data: byte(data), shift: byte(shift), extracted: byte(extracted), base: byte(base),
        bound: byte(bound), length: byte(length), counter: byte(counter),
        readResult: byte(readResult))
      true

    when defined(pvmX86Jit):
      func flatX86WideReadBlock(f: FlatFrame, header: uint32,
          cycle: X86MemoryCycleCandidate, found: var X86MemoryCycleHeader,
          operations, loads: var uint32): bool =
        ## A complete original block contains only speculative reads and pure scalar operations.
        found = default(X86MemoryCycleHeader)
        operations = 0
        loads = 0
        if not flatX86CompleteTarget(f, header, found) or
            found.kind != X86MemoryCycleHandlerKind.Ordinary or
            found.opcode != 1 or found.span < 4 or found.span > 65 or
            f.handlers[int(found.terminal)] != flatCachedJump[1] or
            f.arguments[int(found.terminal)].y != cycle.prefix.header:
          return false
        if f.plan.facts[int(found.ordinal)].opcode != 2 or
            f.plan.facts[int(found.ordinal)+1].opcode notin
              {52'u8..58'u8, 124'u8..130'u8}:
          return false
        for ordinal in found.ordinal+1..<found.ordinal+found.span-1:
          let fact = f.plan.facts[int(ordinal)]
          if fact.opcode == 2 or fact.ending or not fact.fallthrough:
            return false
          if fact.opcode in {52'u8..58'u8, 124'u8..130'u8}:
            inc loads
          elif not supportedX86Opcode(fact.opcode):
            return false
          inc operations
        operations >= 4 and operations <= 64 and loads >= 2 and loads <= 16

      func flatX86WideBranch(f: FlatFrame, header: uint32,
          guard: X86MemoryCycleHeader, cycle: X86MemoryCycleCandidate,
          found, readBlock: var X86MemoryCycleHeader,
          operations, loads: var uint32): bool =
        ## Both cached arms are positive source targets; exactly one returns to the outer guard.
        found = default(X86MemoryCycleHeader)
        readBlock = default(X86MemoryCycleHeader)
        operations = 0
        loads = 0
        if not flatX86CompleteTarget(f, header, found) or
            found.kind != X86MemoryCycleHandlerKind.Ordinary or found.span != 1 or
            found.opcode != 88 or not flatX86CachedBranch(f, found.terminal):
          return false
        let arms = f.arguments[int(found.terminal)]
        let yes = uint32(arms.x shr 32)
        let no = arms.y
        if yes == no or (yes == guard.header) == (no == guard.header): return false
        let readHeader = if yes == guard.header: no else: yes
        if not flatX86WideReadBlock(f, readHeader, cycle, readBlock, operations, loads):
          return false
        found.yes = yes
        found.no = no
        true

      func flatX86SealWideCycle*(f: FlatFrame, prefixPc: uint32,
          candidate: var X86WideCycleCandidate): bool =
        ## Derive seven current complete blocks from positive cached edges, never from a fixture PC.
        candidate = default(X86WideCycleCandidate)
        var cycle = default(X86MemoryCycleCandidate)
        if not flatX86SealMemoryCycle(f, prefixPc, cycle): return false
        let outside = cycle.outside
        if outside.kind != X86MemoryCycleHandlerKind.Ordinary or outside.span != 1 or
            outside.opcode != 40 or
            f.handlers[int(outside.terminal)] != flatCachedJump[40]: return false
        var guard = default(X86MemoryCycleHeader)
        if not flatX86CompleteTarget(f, f.arguments[int(outside.terminal)].y, guard) or
            guard.span != 3 or guard.opcode != 81 or
            guard.kind != X86MemoryCycleHandlerKind.Ordinary or
            not flatX86CachedBranch(f, guard.terminal): return false
        for index, opcode in [131'u8, 149, 81]:
          if f.plan.facts[int(guard.ordinal)+index].opcode != opcode: return false
        let arms = f.arguments[int(guard.terminal)]
        let yes = uint32(arms.x shr 32)
        let no = arms.y
        if yes == no: return false
        var branch = default(X86MemoryCycleHeader)
        var readBlock = default(X86MemoryCycleHeader)
        var rare = default(X86MemoryCycleHeader)
        var operations = 0'u32
        var loads = 0'u32
        var found = 0
        for target in [yes, no]:
          var trialBranch = default(X86MemoryCycleHeader)
          var trialRead = default(X86MemoryCycleHeader)
          var trialOperations = 0'u32
          var trialLoads = 0'u32
          if flatX86WideBranch(f, target, guard, cycle, trialBranch, trialRead,
              trialOperations, trialLoads):
            inc found
            branch = trialBranch
            readBlock = trialRead
            operations = trialOperations
            loads = trialLoads
        if found != 1: return false
        let rareTarget = if yes == branch.header: no else: yes
        if not flatX86CompleteTarget(f, rareTarget, rare): return false
        guard.yes = yes
        guard.no = no
        let headers = [cycle.prefix.header, cycle.dirty.header, cycle.tail.header,
          outside.header, guard.header, branch.header, readBlock.header]
        for index in 0..<headers.len:
          if headers[index] == rare.header: return false
          for earlier in 0..<index:
            if headers[index] == headers[earlier]: return false
        candidate = X86WideCycleCandidate(cycle: cycle, loopGuard: guard,
          loopBranch: branch, readBlock: readBlock, rare: rare,
          readOperations: operations, readLoads: loads)
        true

      proc flatX86WideEmission(f: FlatFrame, candidate: X86WideCycleCandidate,
          emission: var X86WideEmission): bool =
        ## Copy only the sealed source operands; generated code receives no frame reference.
        emission = default(X86WideEmission)
        emission.prefix = flatX86CycleEmission(f, candidate.cycle)
        let guard = candidate.loopGuard
        if guard.span != 3 or guard.terminal != guard.header+3: return false
        for index in 0..<2:
          let fact = f.plan.facts[int(guard.ordinal)+index]
          if not supportedX86Opcode(fact.opcode): return false
          let payload = flatSourcePayload(f.plan, fact)
          emission.guardOperations[index] = X86WideOperation(opcode: fact.opcode,
            slots: payload.args.slots, immediate: payload.args.x)
        let guardBranch = f.arguments[int(guard.terminal)]
        emission.guardBranch = guardBranch.slots
        emission.guardImmediate = flatSext32(uint32(guardBranch.x and 0xffffffff'u64))
        let loopBranch = f.arguments[int(candidate.loopBranch.terminal)]
        emission.loopBranch = loopBranch.slots
        emission.loopImmediate = flatSext32(uint32(loopBranch.x and 0xffffffff'u64))
        var count = 0'u32
        for current in candidate.readBlock.header+1..<candidate.readBlock.terminal:
          if int(current) >= f.sites.len: return false
          let fact = f.plan.facts[int(f.sites[int(current)])]
          if fact.opcode notin {52'u8..58'u8, 124'u8..130'u8} and
              not supportedX86Opcode(fact.opcode): return false
          if count >= uint32(emission.readOperations.len): return false
          let payload = flatSourcePayload(f.plan, fact)
          emission.readOperations[int(count)] = X86WideOperation(opcode: fact.opcode,
            slots: payload.args.slots, immediate: payload.args.x)
          inc count
        if count != candidate.readOperations: return false
        emission.readCount = count
        true

    when defined(pvmX86MemoryCycleSealWitness):
      func flatX86CompleteTargetWitness*(f: FlatFrame, offset: uint32): bool =
        ## Recheck an observed scalar destination without resolving it or changing its source owner.
        var found = default(X86MemoryCycleHeader)
        flatX86CompleteTarget(f, offset, found)

      func flatX86InteriorSourceWitness*(f: FlatFrame, pc: uint32): bool =
        ## A present interior coordinate has no complete-header authority for a source seal.
        if int(pc) >= f.compiledForPc.len: return false
        let packed = f.compiledForPc[int(pc)]
        packed != 0 and ((packed-1) and 0x80000000'u32) == 0

      func flatX86UncachedTailWitness*(f: FlatFrame, pc: uint32): bool =
        ## A complete tail may exist before its original conditional acquires both cached arms.
        var tail = default(X86MemoryCycleHeader)
        flatX86CompleteSource(f, pc, tail) and not flatX86CachedBranch(f, tail.terminal)

      proc flatX86BarrierRefusalWitness*(f: var FlatFrame, prefixPc: uint32): bool =
        ## A test-only idle barrier proves refusal and restores the exact original frame scalar.
        let original = f.barrier
        f.barrier = 0
        var candidate = default(X86MemoryCycleCandidate)
        result = not flatX86SealMemoryCycle(f, prefixPc, candidate)
        f.barrier = original

  when defined(pvmX86Jit):
    proc flatX86CycleAbort() {.cdecl, importc: "abort", header: "stdlib.h".}
      ## An impossible post-native receipt cannot be rolled back or replayed through checked code.

    proc flatX86CycleReadRegionSpan(first: uint64, bytes: openArray[byte], address: uint64,
        width: uint8, memory: var X86CycleMemory) =
      ## A current private region supplies one clipped address interval, or no native read capability.
      if bytes.len == 0 or first > uint64(high(uint32))+1 or
          uint64(bytes.len) > uint64(high(uint32))+1-first: return
      let ending = first+uint64(bytes.len)
      if address < first or address > high(uint64)-uint64(width) or
          address+uint64(width) > ending: return
      memory.readPtr = addr bytes[0]
      memory.readFirst = first
      memory.readEnd = ending

    proc flatX86CycleWriteRegionSpan(first: uint64, bytes: openArray[byte], address: uint64,
        memory: var X86CycleMemory) =
      ## One complete writable four-byte extent is selected before any native store can occur.
      if bytes.len < 4 or first > uint64(high(uint32))+1 or
          uint64(bytes.len) > uint64(high(uint32))+1-first: return
      let ending = first+uint64(bytes.len)
      if address < first or address > high(uint64)-4 or address+4 > ending: return
      memory.writePtr = addr bytes[0]
      memory.writeFirst = first
      memory.writeEnd = ending

    proc flatX86CycleReadRegion(first: uint64, bytes: var seq[byte], address: uint64,
        width: uint8, memory: var X86CycleMemory) =
      ## Managed callers retain the original checked descriptor worker.
      flatX86CycleReadRegionSpan(first, bytes, address, width, memory)

    proc flatX86CycleReadRegion(first: uint64, bytes: RWView, address: uint64,
        width: uint8, memory: var X86CycleMemory) =
      ## Reborrow only the live RW allocation for this synchronous native call.
      if bytes.len == 0: return
      flatX86CycleReadRegionSpan(first, bytes.toOpenArray(0, bytes.len-1), address, width, memory)

    proc flatX86CycleWriteRegion(first: uint64, bytes: var seq[byte], address: uint64,
        memory: var X86CycleMemory) =
      ## Managed write descriptors keep the unchanged complete four-byte guard.
      flatX86CycleWriteRegionSpan(first, bytes, address, memory)

    proc flatX86CycleWriteRegion(first: uint64, bytes: RWView, address: uint64,
        memory: var X86CycleMemory) =
      ## Empty/moved views supply no native writable capability.
      if bytes.len == 0: return
      flatX86CycleWriteRegionSpan(first, bytes.toOpenArray(0, bytes.len-1), address, memory)

    proc flatX86CycleMemory(f: var FlatFrame, candidate: X86MemoryCycleCandidate):
        X86CycleMemory =
      ## Reborrow private memory on each call; no pointer follows the cache through a move or host remap.
      result = default(X86CycleMemory)
      if candidate.base > 12: return
      let base = uint64(f.info.registers[range[0..12](candidate.base)])
      let writeAddress = (base+candidate.storeDisplacement) and 0xffffffff'u64
      flatX86CycleWriteRegion(f.stackBase, f.stack, writeAddress, result)
      if result.writePtr == nil:
        flatX86CycleWriteRegion(f.rwBase, f.rw, writeAddress, result)
      let readAddress = candidate.readImmediate and 0xffffffff'u64
      flatX86CycleReadRegion(f.stackBase, f.stack, readAddress, candidate.readWidth, result)
      if result.readPtr == nil:
        flatX86CycleReadRegion(f.rwBase, f.rw, readAddress, candidate.readWidth, result)
      if result.readPtr == nil:
        flatX86CycleReadRegion(f.roBase, f.ro, readAddress, candidate.readWidth, result)
      assert f.dirtyPages.len <= int(high(uint32))
      result.dirtyWords = uint32(f.dirtyPages.len)

    func flatX86CycleReceiptValid(candidate: X86MemoryCycleCandidate, startGas,
        startAttempts: uint64, state: X86CycleState, next: uint32): bool =
      ## Validate every equation and allowed completed/next edge before publishing frame bookkeeping.
      if state.reserved != 0 or state.gas > startGas or state.attempts > startAttempts or
          (state.exitKind != 1 and state.exitKind != 2): return false
      let spentGas = startGas-state.gas
      let spentAttempts = startAttempts-state.attempts
      if state.wordGroups > high(uint64) div 4 or
          state.visits[1] != state.wordGroups*4: return false
      let spans = [candidate.prefix.span, candidate.dirty.span, candidate.tail.span]
      let prices = [candidate.prefix.price, candidate.dirty.price, candidate.tail.price]
      var countedGas = 0'u64
      var countedAttempts = 0'u64
      var visitsTotal = 0'u64
      for index in 0..<3:
        let visits = state.visits[index]
        let span = uint64(spans[index])
        let price = prices[index]
        if span == 0 or visits > (spentAttempts-countedAttempts) div span: return false
        countedAttempts += visits*span
        if price != 0:
          if visits > (spentGas-countedGas) div price: return false
          countedGas += visits*price
        if visits > high(uint64)-visitsTotal: return false
        visitsTotal += visits
      if countedGas != spentGas or countedAttempts != spentAttempts or
          (state.lastCompleted == high(uint32)) != (visitsTotal == 0): return false
      # Every tail follows one completed word group, and every prefix follows one tail.
      if state.visits[2] > state.wordGroups or state.visits[0] > state.visits[2] or
          state.visits[2]-state.visits[0] > 1: return false
      let openTail = state.visits[2]-state.visits[0]
      # A dirty completion after a prefix needs a fresh group, even when earlier counts balance.
      if state.lastCompleted == candidate.dirty.header and
          state.wordGroups <= state.visits[0]: return false
      if state.exitKind == 2:
        return openTail == 1 and next == candidate.outside.header and
          state.lastCompleted == candidate.tail.header and state.visits[2] > 0
      if next == candidate.dirty.header:
        return openTail == 0 and (state.lastCompleted == high(uint32) or
          (state.lastCompleted == candidate.dirty.header and state.visits[1] > 0) or
          (state.lastCompleted == candidate.prefix.header and state.visits[0] > 0))
      if next == candidate.tail.header:
        return openTail == 0 and state.lastCompleted == candidate.dirty.header and
          state.visits[1] > 0
      if next == candidate.prefix.header:
        return openTail == 1 and state.lastCompleted == candidate.tail.header and
          state.visits[2] > 0
      false

    func flatX86CycleEmission(f: FlatFrame, candidate: X86MemoryCycleCandidate):
        X86CycleEmission =
      ## Copy only the original sealed operand slots used by the arithmetic/branch emitter.
      X86CycleEmission(
        prefixLoad: f.arguments[int(candidate.prefix.header+1)].slots,
        prefixBound: f.arguments[int(candidate.prefix.header+2)].slots,
        prefixStep: f.arguments[int(candidate.prefix.header+3)].slots,
        dirtyBranch: f.arguments[int(candidate.dirty.terminal)].slots,
        tailStep: f.arguments[int(candidate.tail.header+2)].slots,
        tailBranch: f.arguments[int(candidate.tail.terminal)].slots)

    when defined(pvmX86WideParentRefusalWitness):
      func flatX86WideReceiptValid(candidate: X86WideCycleCandidate, startGas,
          startAttempts: uint64, state: X86WideState, next: uint32): bool =
        ## Exact charged/completed equations include a speculative read charged before replay.
        let cycle = state.cycle
        let outsideVisits = state.outerVisits[0]
        let guardVisits = state.outerVisits[1]
        let branchVisits = state.outerVisits[2]
        let readVisits = state.outerVisits[3]
        if cycle.reserved != 0 or cycle.gas > startGas or
            cycle.attempts > startAttempts or
            (cycle.exitKind != 1 and cycle.exitKind != 2 and cycle.exitKind != 3) or
            cycle.wordGroups > high(uint64) div 4 or
            cycle.visits[1] != cycle.wordGroups*4 or
            cycle.visits[2] > cycle.wordGroups or
            cycle.visits[0] < state.childCalls or
            state.childCalls > readVisits or
            readVisits-state.childCalls > 1 or
            outsideVisits > state.childCalls or
            state.childCalls-outsideVisits > 1 or
            readVisits > branchVisits or
            guardVisits > branchVisits: return false
        # Branch chooses either guard directly or read→child→outside→guard.
        # Only one branch/read/child segment can remain open at a return.
        let openBranches = branchVisits-guardVisits
        if openBranches > 1 or readVisits-outsideVisits > openBranches:
          return false
        if cycle.visits[2] > high(uint64)-state.childCalls: return false
        let childTails = cycle.visits[2]+state.childCalls
        if cycle.visits[0] > childTails: return false
        let openTails = childTails-cycle.visits[0]
        if openTails < state.outerVisits[0] or
            openTails-state.outerVisits[0] > 1:
          return false
        let spans = [candidate.cycle.prefix.span, candidate.cycle.dirty.span,
          candidate.cycle.tail.span, candidate.cycle.outside.span,
          candidate.loopGuard.span, candidate.loopBranch.span,
          candidate.readBlock.span]
        let prices = [candidate.cycle.prefix.price, candidate.cycle.dirty.price,
          candidate.cycle.tail.price, candidate.cycle.outside.price,
          candidate.loopGuard.price, candidate.loopBranch.price,
          candidate.readBlock.price]
        let visits = [cycle.visits[0], cycle.visits[1], cycle.visits[2],
          state.outerVisits[0], state.outerVisits[1], state.outerVisits[2],
          state.outerVisits[3]]
        var countedGas = 0'u64
        var countedAttempts = 0'u64
        var completed = 0'u64
        for index in 0..<visits.len:
          let count = visits[index]
          if count > high(uint64)-completed: return false
          completed += count
          if count > 0 and uint64(spans[index]) > high(uint64) div count:
            return false
          let attempts = count*uint64(spans[index])
          if attempts > high(uint64)-countedAttempts: return false
          countedAttempts += attempts
          if prices[index] != 0 and count > high(uint64) div prices[index]:
            return false
          let gas = count*prices[index]
          if gas > high(uint64)-countedGas: return false
          countedGas += gas
        if cycle.exitKind == 3:
          if countedAttempts > high(uint64)-uint64(candidate.readBlock.span) or
              countedGas > high(uint64)-candidate.readBlock.price: return false
          countedAttempts += uint64(candidate.readBlock.span)
          countedGas += candidate.readBlock.price
        if countedGas != startGas-cycle.gas or
            countedAttempts != startAttempts-cycle.attempts or
            (cycle.lastCompleted == high(uint32)) != (completed == 0): return false
        let known = [candidate.cycle.prefix.header, candidate.cycle.dirty.header,
          candidate.cycle.tail.header, candidate.cycle.outside.header,
          candidate.loopGuard.header, candidate.loopBranch.header,
          candidate.readBlock.header]
        if completed > 0 and cycle.lastCompleted notin known: return false
        if cycle.exitKind == 2:
          return next == candidate.rare.header and
            cycle.lastCompleted == candidate.loopGuard.header and
            openBranches == 0 and readVisits == outsideVisits
        if cycle.exitKind == 3:
          return next == candidate.readBlock.header+1 and
            cycle.lastCompleted == candidate.loopBranch.header and
            state.childCalls == readVisits and openBranches == 1 and
            readVisits == outsideVisits
        if next == candidate.loopBranch.header:
          return openBranches == 0 and readVisits == outsideVisits
        if next == candidate.loopGuard.header or
            next == candidate.readBlock.header:
          return openBranches == 1 and readVisits == outsideVisits
        if next in [candidate.cycle.prefix.header, candidate.cycle.dirty.header,
            candidate.cycle.tail.header, candidate.cycle.outside.header]:
          return openBranches == 1 and readVisits-outsideVisits == 1
        false

    proc flatX86MemoryCycleImageProof*(f: FlatFrame, prefixPc: uint32,
        image: var seq[byte]): bool =
      ## A private witness can inspect exact generated bytes without publishing or executing x86.
      image = @[]
      var candidate = default(X86MemoryCycleCandidate)
      if not flatX86SealMemoryCycle(f, prefixPc, candidate): return false
      buildX86MemoryCycleImage(candidate, flatX86CycleEmission(f, candidate), image)

    when defined(pvmX86WideParentRefusalWitness):
      proc flatX86WideSourceProof*(f: FlatFrame, prefixPc: uint32,
          candidate: var X86WideCycleCandidate, emission: var X86WideEmission): bool =
        ## Give the direct backend witness the exact checked graph and copied operands.
        flatX86SealWideCycle(f, prefixPc, candidate) and flatX86WideEmission(f, candidate, emission)

      func flatX86WideReceiptProof*(candidate: X86WideCycleCandidate, gas, attempts: uint64,
          state: X86WideState, next: uint32): bool =
        ## Validate a typed native completion without installing a frame handler.
        flatX86WideReceiptValid(candidate, gas, attempts, state, next)

    func flatX86CycleBoundaryProof*(f: FlatFrame): array[7, uint64] =
      ## Private literals can inspect the exact unstarted/paid/refund bookkeeping after fallback.
      [f.remaining, uint64(f.reservation), uint64(f.stoppedAt),
        uint64(if f.attemptedExit: 1 else: 0),
        uint64(if f.info.blockCharged: 1 else: 0), uint64(f.dirtyIndices.len),
        (if f.dirtyPages.len == 0: 0'u64 else: f.dirtyPages[0])]

    proc flatX86CycleDescriptorProof*(f: var FlatFrame,
        candidate: X86MemoryCycleCandidate): array[7, uint64] =
      ## Report only the fresh descriptor ranges, never its borrowed invocation pointers.
      let memory = flatX86CycleMemory(f, candidate)
      [uint64(if memory.readPtr == nil: 0 else: 1), memory.readFirst,
        memory.readEnd, uint64(if memory.writePtr == nil: 0 else: 1),
        memory.writeFirst, memory.writeEnd, uint64(memory.dirtyWords)]

    func flatX86CycleReceiptProof*(candidate: X86MemoryCycleCandidate, startGas,
        startAttempts: uint64, state: X86CycleState, next: uint32): bool =
      ## A positive and corrupted synthetic ledger exercise the same production validator.
      flatX86CycleReceiptValid(candidate, startGas, startAttempts, state, next)

    proc flatX86CycleRequireReceiptProof*(candidate: X86MemoryCycleCandidate, startGas,
        startAttempts: uint64, state: X86CycleState, next: uint32) =
      ## A child process must observe unconditional abort on a corrupted post-native receipt.
      if not flatX86CycleReceiptValid(candidate, startGas, startAttempts, state, next):
        flatX86CycleAbort()

when defined(pvmArm64Jit) and not defined(pvmX86Jit):
  func flatArmRegionStatistics*(f: FlatFrame): array[2, uint64] =
    ## Unbound checked witnesses own no legacy connected image.
    default(array[2, uint64])

  func flatArmDirtyLoopStatistics*(f: FlatFrame): array[3, uint64] =
    ## Raw dirty-loop receipts belong to the direct backend owner.
    default(array[3, uint64])

  func flatArmMixedStatistics*(f: FlatFrame): array[4, uint64] =
    ## Raw mixed-region receipts belong to the direct backend owner.
    default(array[4, uint64])

  func flatArmMixedGroupStatistics*(f: FlatFrame): array[3, uint64] =
    ## Unbound checked witnesses retain no legacy publication or guard activity.
    default(array[3, uint64])

  func flatArmDirtyWordGroups*(f: FlatFrame): uint64 =
    ## Unbound checked witnesses perform no legacy native word groups.
    0'u64

  when defined(pvmArmMacroReceipt):
    func flatArmMacroStatistics*(f: FlatFrame): array[7, uint64] =
      ## Checked macro histories have no private image or activity.
      default(array[7, uint64])

    func flatArmMacroResidentActive*(f: FlatFrame): bool =
      ## A checked frame owns no resident macro image.
      false

    func flatArmMacroImageWords*(f: FlatFrame): uint32 =
      ## A checked frame owns no emitted macro words.
      0'u32

    when defined(pvmArmMacroStateTrace):
      func flatArmMacroLastState*(f: FlatFrame): ArmMacroState =
        ## A checked frame has no native macro return state.
        default(ArmMacroState)

  func flatArmMemoryCycleStatistics*(f: FlatFrame): array[6, uint64] =
    ## Raw cycle activity is observed through the separate direct owner.
    default(array[6, uint64])

  func flatArmResidentMemoryCycleActive*(f: FlatFrame): bool =
    ## A checked frame owns no resident memory-cycle image.
    false

  func flatArmStatistics*(f: FlatFrame): array[5, uint64] =
    ## Private frame counters are empty. Prepared execution reports through the shared owner.
    default(array[5, uint64])

  func flatArmControlStatistics*(f: FlatFrame): array[2, uint64] =
    ## Unbound frame probes have no native branch or header entries.
    default(array[2, uint64])

proc flatResumePaid(f: var FlatFrame, body: uint32, start: int): uint32 =
  ## A real paid resume reserves only its original suffix. Refuse a stale cached
  ## coordinate before using it as either a handler or a source fact.
  if not f.info.blockCharged or f.remaining == 0 or f.barrier != flatStop or
      start < 0 or start >= f.plan.facts.len or
      uint64(body) >= uint64(min(f.handlers.len, f.sites.len)):
    f.reason = oracle.StepError.BackendFailure
    return flatStop
  let count = f.plan.facts[start].sourceCount
  let past = uint64(start)+uint64(count)
  let site = uint64(f.sites[int(body)])
  if count == 0 or past > uint64(f.plan.facts.len) or site < uint64(start) or site >= past:
    f.reason = oracle.StepError.BackendFailure
    return flatStop
  let reserved = min(f.remaining, uint64(count))
  let stop = uint32(start)+uint32(reserved)
  if reserved < uint64(count) and not installFlatBudget(f, body, uint32(past), stop):
    f.reason = oracle.StepError.BackendFailure
    return flatStop
  f.remaining-=reserved
  f.reservation = stop
  body

template flatDispatchLoop(f: var FlatFrame, entry: uint32, ObserveLater: static[bool],
    SampleFusion: static[bool] = false, fusionProbe: untyped = nil) =
  ## The checked loop is shared by the ordinary and observed segments. Only the latter can discover.
  var node = entry
  while node != flatStop:
    assert int(node) < f.handlers.len
    let selected = f.handlers[int(node)]
    if selected == flatCharge:
      when SampleFusion: observeFlatFusion(fusionProbe, node)
      # Preserve temporary barriers: select the first operation only after complete reservation/patching.
      when ObserveLater:
        node = flatReserveHeader[true](f, node)
      else:
        node = flatReserveHeader[false](f, node)
      if node != flatStop:
        let body = f.handlers[int(node)]
        node = body(f, node)
    else:
      # Specialized charged/native/failure workers retain their existing entry and complete fallback behavior.
      node = selected(f, node)

when NativeCheckedReadEnabled:
  proc runFlatObservedLoop(f: var FlatFrame, entry: uint32) {.noinline.} =
    ## The armed segment selects this loop once. Read certificates require the ordinary charge
    ## identity; fused shapes cannot nominate, and the protected slot already owns its observation.
    flatDispatchLoop(f, entry, true)

template flatDispatchSegment(f: var FlatFrame, entry: uint32) =
  when NativeCheckedReadEnabled:
    if f.readProbe.observing and f.readProbe.later:
      runFlatObservedLoop(f, entry)
    else:
      flatDispatchLoop(f, entry, false)
  else:
    flatDispatchLoop(f, entry, false)

when NativeReadCycleEnabled:
  proc runFlatFusionSegment(f: var FlatFrame, entry: uint32) {.noinline.} =
    ## Rebind the exact optional lease once per segment. Keep every other route
    ## and the original checked worker for every linked block.
    let borrowed = borrowNativeFusion(f.nativeSession)
    let image = borrowed.image
    let blocks = borrowed.blocks
    if image == nil or blocks == nil:
      if nativeFusionTraining(f.nativeSession) and f.remaining >= NativeFusionTrainingFloor:
        markNativeFusionSampled(f.nativeSession)
        var probe = FlatFusionProbe(down: 1, seed: 0x9e3779b9'u32)
        flatDispatchLoop(f, entry, false, true, probe)
        if f.reason == oracle.StepError.None and f.exit == oracle.StepExit.Halt:
          offerFlatFusion(f, probe)
      else:
        flatDispatchSegment(f, entry)
      return
    defer: returnNativeMixedLoop(f.nativeSession)
    if blocks[].len > NativeFusionBlockLimit:
      flatDispatchSegment(f, entry)
      return
    var patches = default(array[NativeFusionBlockLimit, uint32])
    var slots = default(array[NativeFusionSlotLimit, FlatFusionSlot])
    var count = 0
    for slot in 0..<blocks[].len:
      if not nativeFusionEntry(image[], slot): continue
      let header = blocks[][slot].header
      if header >= uint32(f.handlers.len) or f.handlers[int(header)] != flatCharge:
        # A conflict anywhere in the graph prevents all linked entries from acquiring authority.
        flatDispatchSegment(f, entry)
        return
      if not nativeFusionDispatchEntry(image[], slot): continue
      let token = header+1
      var at = nativeFusionSlot(token)
      while slots[at].token != 0: at = (at+1) and (NativeFusionSlotLimit-1)
      slots[at] = FlatFusionSlot(token: token, index: uint32(slot))
      patches[count] = header
      inc count
    if count == 0:
      flatDispatchSegment(f, entry)
      return
    var context = NativeFusionContext(memory: NativeMixedLoopContext(
      read: [initNativeReadRegion(f.stackBase, f.stack), flatRWReadRegion(f.rwBase, f.rw),
        initNativeReadRegion(f.roBase, f.ro)],
      writable: [NativeCycleWritable(first: f.stackBase, length: uint64(f.stack.len)),
        NativeCycleWritable(first: f.rwBase, length: uint64(f.rw.len))],
      dirtyWords: uint64(f.dirtyPages.len)))
    if f.stack.len > 0: context.memory.writable[0].data = addr f.stack[0]
    if f.rw.len > 0: context.memory.writable[1].data = addr f.rw[0]
    if f.dirtyPages.len > 0: context.memory.dirty = addr f.dirtyPages[0]
    let dynamicOffsets = f.dynamicOffsets
    if dynamicOffsets != nil: context.jumps = addr dynamicOffsets.slots
    f.fusionImage = image
    # Source paths may repeat while this image and its graph are exclusively borrowed.
    var receipts = default(NativeFusionReceipts)
    f.fusionBlocks = blocks
    f.fusionReceipts = addr receipts
    f.fusionContext = addr context
    f.fusionSlots = addr slots
    for index in 0..<count: f.handlers[int(patches[index])] = flatFusionEntry
    defer:
      for index in 0..<count: f.handlers[int(patches[index])] = flatCharge
      f.fusionContext = nil
      f.fusionSlots = nil
      f.fusionBlocks = nil
      f.fusionReceipts = nil
      f.fusionImage = nil
    flatDispatchSegment(f, entry)

  proc flatProbeMixedLoop(f: var FlatFrame, terminal: uint32): uint32 =
    ## A completed original BNE counts one full checked visit, including folded source facts.
    let probe = f.mixedProbe
    assert probe != nil
    var index = 0
    while index < probe[].count and probe[].terminals[index] != terminal: inc index
    assert index < probe[].count
    result = flatBranch[171](f, terminal)
    if f.reason == oracle.StepError.None: inc probe[].visits[index]

  proc runFlatMixedProbeSegment(f: var FlatFrame, entry: uint32) {.noinline.} =
    ## Rank actual complete checked work across this callback-free segment, bounded by its public quota.
    var probe = default(FlatMixedLoopProbe)
    let source = f.mixedSource
    for index in 0..<int(source.count):
      if (source.refused and (1'u8 shl index)) != 0: continue
      let token = source.candidates[index]
      let proof = buildFlatMixedLoop(f, token-1, source.epoch)
      if not proof.complete or not mixedLoopDisjoint(f.nativeSession, proof): continue
      let slot = probe.count
      probe.terminals[slot] = proof.terminal
      probe.tokens[slot] = token
      probe.spans[slot] = proof.span
      inc probe.count
    if probe.count == 0:
      flatDispatchSegment(f, entry)
      return
    f.mixedProbe = addr probe
    for index in 0..<probe.count: f.handlers[int(probe.terminals[index])] = flatProbeMixedLoop
    defer:
      f.mixedProbe = nil
      for index in 0..<probe.count:
        restoreFlatTemporaryHandler(f, probe.terminals[index], flatProbeMixedLoop, flatBranch[171])
      if f.reason == oracle.StepError.None and nativeInvocationUsed(f.nativeSession):
        var selected = default(NativeMixedLoopSet)
        var chosenTokens = default(array[NativeMixedLoopEntryLimit, uint32])
        var considered = 0'u8
        when defined(pvmMixedLoopWitness):
          var selectedWork = default(array[NativeMixedLoopEntryLimit, uint64])
        while selected.count < uint8(NativeMixedLoopEntryLimit):
          var best = -1
          var bestWork = NativeInvocationFloor-1
          for index in 0..<probe.count:
            if (considered and (1'u8 shl index)) != 0: continue
            let work = probe.visits[index]*uint64(probe.spans[index])
            if work > bestWork:
              best = index
              bestWork = work
          if best < 0: break
          considered = considered or (1'u8 shl best)
          let proof = buildFlatMixedLoop(f, probe.tokens[best]-1, source.epoch)
          if not proof.complete: continue
          var disjoint = true
          for index in 0..<int(selected.count):
            if not nativeMixedLoopDisjoint(selected.proofs[index], proof): disjoint = false
          if not disjoint: continue
          let slot = int(selected.count)
          selected.proofs[slot] = proof
          chosenTokens[slot] = probe.tokens[best]
          when defined(pvmMixedLoopWitness): selectedWork[slot] = bestWork
          inc selected.count
        if selected.count != 0 and offerNativeMixedLoops(f.nativeSession, selected):
          f.mixedSource.chosen = chosenTokens
          f.mixedSource.chosenCount = selected.count
          when defined(pvmMixedLoopWitness):
            for index in 0..<int(selected.count):
              let proof = selected.proofs[index]
              echo "MIXED_ARENA_CHOICE,", index, ",", chosenTokens[index]-1, ",", selectedWork[
                  index],
                ",", proof.span, ",", proof.price, ",", proof.paidGuards
    flatDispatchSegment(f, entry)

  proc runFlatMixedLoopSegment(f: var FlatFrame, entry: uint32) {.noinline.} =
    ## Reconstruct exact selected proofs and borrow their shared immutable arena once.
    let source = f.mixedSource
    if source.chosenCount != 0:
      var requested = default(NativeMixedLoopSet)
      requested.count = source.chosenCount
      for index in 0..<int(source.chosenCount):
        requested.proofs[index] = buildFlatMixedLoop(f, source.chosen[index]-1, source.epoch)
      if requested.complete:
        let borrowed = borrowFlatMixedLoopSegment(f, addr requested)
        if f.mixedImage != nil:
          defer: returnFlatMixedLoopSegment(f)
          flatDispatchSegment(f, entry)
          return
        if borrowed.refusedMask != 0:
          for index in 0..<int(source.chosenCount):
            if (borrowed.refusedMask and (1'u8 shl index)) == 0: continue
            for candidate in 0..<int(source.count):
              if source.candidates[candidate] == source.chosen[index]:
                f.mixedSource.refused = f.mixedSource.refused or (1'u8 shl candidate)
          f.mixedSource.chosenCount = 0
        elif not borrowed.settled or borrowed.pending:
          flatDispatchSegment(f, entry)
          return
    runFlatMixedProbeSegment(f, entry)

  when defined(pvmPaidMixedLoopWitness):
    proc runFlatMixedPairSegment(f: var FlatFrame, entry: uint32) =
      ## Privately install both disjoint entries in the same already linked checked frame.
      ## The shared Read owner and its ordinary worker keep their original lease.
      if not mixedLoopPrimaryReady(f.nativeSession):
        flatDispatchSegment(f, entry)
        return
      let epoch = nativeEpoch(f.nativeSession)
      var pair = default(FlatMixedPairWitness)
      pair.proofs[0] = buildFlatMixedLoop(f, 469077, epoch)
      pair.proofs[1] = buildFlatMixedLoop(f, 467872, epoch, allowPaid = true)
      let byteLoop {.cursor.} = pair.proofs[0]
      let paidLoop {.cursor.} = pair.proofs[1]
      if not byteLoop.complete or not paidLoop.complete or paidLoop.paidGuards == 0 or
          not mixedLoopDisjoint(f.nativeSession, byteLoop) or
          not mixedLoopDisjoint(f.nativeSession, paidLoop):
        flatDispatchSegment(f, entry)
        return
      assert paidLoop.first+uint32(paidLoop.span) <= byteLoop.first
      assert paidLoop.exitHeader notin byteLoop.header..byteLoop.terminal
      assert byteLoop.exitHeader notin paidLoop.header..paidLoop.terminal
      assert paidLoop.terminal < byteLoop.header or byteLoop.terminal < paidLoop.header
      var byteImage = default(NativeImage)
      var paidImage = default(NativeImage)
      var refused = false
      if f.mixedPairMode in {FlatMixedPairMode.ByteOnly, FlatMixedPairMode.Both}:
        byteImage = lowerNativeMixedLoop(byteLoop, refused)
        assert byteImage.ready and not refused
        pair.images[0] = addr byteImage
      if f.mixedPairMode in {FlatMixedPairMode.PaidOnly, FlatMixedPairMode.Both}:
        paidImage = lowerNativeMixedLoop(paidLoop, refused)
        assert paidImage.ready and not refused
        pair.images[1] = addr paidImage
      assert f.mixedPair == nil
      f.mixedPair = addr pair
      for index in 0..1:
        if pair.images[index] != nil:
          let header = pair.proofs[index].header
          assert f.handlers[int(header)] == flatCharge
          f.handlers[int(header)] = flatMixedPairEntry
      defer:
        for index in 0..1:
          if pair.images[index] != nil:
            let header = pair.proofs[index].header
            restoreFlatTemporaryHandler(f, header, flatMixedPairEntry, flatCharge)
        f.mixedPair = nil
        let first = pair.counts[0]
        let second = pair.counts[1]
        if first.entries != 0 or second.entries != 0:
          echo "MIXED_PAIR_SEGMENT,", first.entries, ",", first.visits, ",", first.refusals,
            ",", first.paid, ",", first.operations, ",", first.branches, ",", first.repeatedHeaders,
            ",", second.entries, ",", second.visits, ",", second.refusals, ",", second.paid,
            ",", second.operations, ",", second.branches, ",", second.repeatedHeaders
      flatDispatchSegment(f, entry)

  template dispatchPreparedMixed(f: var FlatFrame, offset: uint32) =
    template ordinary() =
      if f.mixedSource.count != 0 and f.mixedSource.epoch == nativeEpoch(f.nativeSession) and
          mixedLoopPrimaryReady(f.nativeSession):
        runFlatMixedLoopSegment(f, offset)
      elif not f.readProbe.observing and f.pricingKind == 0 and f.remaining >= NativeInvocationFloor:
        if nativeFusionAvailable(f.nativeSession): runFlatFusionSegment(f, offset)
        else: flatDispatchSegment(f, offset)
      else:
        flatDispatchSegment(f, offset)
    template selected() =
      when defined(pvmPaidMixedLoopWitness):
        if f.mixedPairMode != FlatMixedPairMode.Disabled:
          runFlatMixedPairSegment(f, offset)
        else:
          ordinary()
      else:
        ordinary()
    when defined(pvmSharedAsyncWitness):
      if f.mixedProbeWitness:
        runFlatMixedProbeSegment(f, offset)
      else:
        selected()
    else:
      selected()

when NativeCheckedReadEnabled and defined(pvmSharedAsyncWitness):
  var loseQuotaPredecessor {.threadvar.}: bool

  proc loseNextQuotaProbePredecessor*() =
    ## Inject a missing quota predecessor at a terminal still owned by the Read observer.
    loseQuotaPredecessor = true

proc runFlat*(f: var FlatFrame, limit: uint64) =
  ## The offset-returning dispatch reserves attempts at complete headers or actual paid cached-body entries.
  ## A zero budget returns StepLimitExceeded before the frame's preparation failure
  ## can return InvalidPreparedProgram. Local refusals produce no guest snapshot.
  ## A cold bitmap backedge stays with the exclusive cached stream across short calls.
  ## The first segment with enough settled work consumes it for a source proof.
  defer: restoreFlatPrefixProbe(f)
  f.hostReady = false
  f.hostSnapshot = default(Memory)
  f.remaining = limit
  f.reason = oracle.StepError.None
  f.exit = oracle.StepExit.Continued
  f.barrier = flatStop
  f.savedHandler = nil
  f.attemptedExit = false
  if limit == 0:
    f.reason = oracle.StepError.StepLimitExceeded
    return
  if f.plan == nil:
    f.reason = oracle.StepError.InvalidMachine
    return
  if f.plan.singleStep:
    # Bounded adapter plans carry no whole-program maps and cannot authorize an ordinary invocation.
    f.reason = oracle.StepError.InvalidPreparedProgram
    return
  if f.preparationFailure != FlatError.None:
    f.reason = oracle.StepError.InvalidPreparedProgram
    return
  let cache {.cursor.} = f.dynamicOffsets
  if cache != nil:
    # A resumed segment starts with empty tags and may reuse its existing private allocation.
    cache.slots = default(array[256, uint64])
  let pc = uint32(uint64(f.info.pc) and 0xffffffff'u64)
  var offset = flatStop
  if f.info.blockCharged and uint64(pc) < uint64(f.plan.factAt.len) and f.compiledForPc.len > 0:
    # Only real entry/resumption may reserve a paid interior body; branch prelinking keeps the original resolver.
    let packed = f.compiledForPc[int(pc)]
    if packed != 0:
      let target = packed-1
      if (target and 0x80000000'u32) != 0:
        # A complete entry still executes its ordinary header, including any existing native/header accounting.
        offset = target and 0x7fffffff'u32
      else:
        # The original admitted body has every source operation already; neither emission nor pricing is needed.
        let start = int(f.plan.factAt[int(pc)]) - 1
        offset = flatResumePaid(f, target, start)
        if offset == flatStop: return
  if offset == flatStop:
    # Unpaid, missing and invalid entries retain their existing admission, pricing and refusal order.
    offset = flatResolve(f, pc)
  if offset == flatStop:
    f.reason = if f.preparationFailure == FlatError.None: oracle.StepError.InvalidMachine else: oracle.StepError.InvalidPreparedProgram
    return
  if f.prefixProbeOriginal == nil and nativePrefixObservation(f.nativeSession):
    installFlatPrefixProbe(f)
  when NativeReadCycleEnabled:
    dispatchPreparedMixed(f, offset)
  else:
    flatDispatchSegment(f, offset)
  restoreFlatPrefixProbe(f)
  if f.barrier != flatStop:
    when NativeCheckedReadEnabled and defined(pvmSharedAsyncWitness):
      if loseQuotaPredecessor:
        loseQuotaPredecessor = false
        f.readProbe.observing = true
        f.readProbe.count = 1
        f.readProbe.candidates[0].terminal = f.barrier
        f.savedHandler = nil
    let saved = f.savedHandler
    if saved == nil or uint64(f.barrier) >= uint64(f.handlers.len) or
        f.handlers[int(f.barrier)] != flatBudget:
      f.reason = oracle.StepError.BackendFailure
    else:
      f.handlers[int(f.barrier)] = saved
    f.barrier = flatStop
    f.savedHandler = nil
  # A damaged stream cannot be scanned for promotion or returned to the owner.
  if f.reason == oracle.StepError.BackendFailure: return
  if f.reason == oracle.StepError.None and f.attemptedExit:
    let sourceFact = f.sites[int(f.stoppedAt)]
    var reservedEnd = f.reservation
    if (reservedEnd and flatReservationHeaderFlag) != 0:
      # Only the final attempted exit needs its exact source end; stream coordinates remain owned and stable.
      let header = reservedEnd and not flatReservationHeaderFlag
      reservedEnd = f.sites[int(header)]+f.arguments[int(header)].y
    if reservedEnd > sourceFact+1:
      f.remaining+=uint64(reservedEnd-sourceFact-1)
  when NativeReadCycleEnabled:
    # Boundary classifiers require the original handler identity, including on exit edges.
    settleProtectedReadSegment(f)
    if f.bitmapCandidate != 0 and settledNativeWork(f, limit) >= NativeInvocationFloor:
      let root = f.bitmapCandidate-1
      f.bitmapCandidate = 0
      observeFlatBitmap(f, root)
  flatPromoteNativeLoop(f)

when defined(pvmMixedLoopEntryWitness) and NativeReadCycleEnabled:
  proc witnessFlatMixedLoopEntry*(program: Program, pc: uint32) =
    ## Exercise the native entry and its original checked fallbacks from the same prepared owner.
    let cycles = GasCycleLimit(100000)
    var prepared = prepareFlatPlan(program, cycles, defaultFlatLimits(), false)
    assert prepared.error == FlatError.None
    let plan = takeValue(prepared)
    let price = blockGas(program, CodeAddress(uint64(pc)), cycles)
    assert price.error == GasError.None and uint64(price.value) > 0
    let blockPrice = uint64(price.value)
    const readAddress = 0x10000'u64
    const writeAddress = 0x11000'u64
    var readable = PageImage(index: PageIndex(uint32(readAddress shr 12)),
      access: PageAccess.ReadOnly, bytes: default(array[4096, byte]))
    readable.bytes[0] = 0x24
    let writable = PageImage(index: PageIndex(uint32(writeAddress shr 12)),
      access: PageAccess.ReadWrite, bytes: default(array[4096, byte]))

    for scenario in 0..8:
      var pages = @[readable, writable]
      if scenario == 7: pages = @[writable]
      let paid = scenario == 6
      let gas = case scenario
        of 4: blockPrice-1
        of 5: blockPrice
        else: 1000000'u64
      let quota = case scenario
        of 2: 14'u64
        of 3: 16'u64
        else: 50'u64
      var info = MachineInfo(pc: CodeAddress(uint64(pc)), gas: MachineGas(gas),
        blockCharged: paid, registers: default(RegisterFile))
      info.registers[0] = RegisterValue(0x35)
      info.registers[5] = RegisterValue(if scenario == 8: writeAddress+4095 else: writeAddress)
      info.registers[6] = RegisterValue(readAddress)
      info.registers[7] = RegisterValue(1)
      info.registers[12] = RegisterValue(3)
      var native = newFlatFrame(plan, pages, info)
      var checked = newFlatFrame(plan, pages, info)
      for frame in [addr native, addr checked]:
        let header = flatResolve(frame[], pc)
        assert header != flatStop
        var source = default(FlatSourceInterval)
        var walk = default(FlatSourceSummary)
        assert flatSourceIntervalAt(frame[], header, NativeReadFactLimit, source)
        assert flatWalkCompleteSource(frame[], header, source, walk)
        assert flatUnresolvedBranch[171](frame[], walk.terminal) == walk.terminal
        if scenario != 0: flatMarkStore[1](frame[], writeAddress)
      let proof = buildFlatMixedLoop(native, pc, 1)
      assert proof.complete and proof.price == blockPrice
      var refused = false
      var image = lowerNativeMixedLoop(proof, refused)
      assert image.ready and not refused
      native.mixedWitnessProof = proof
      native.mixedWitnessImage = addr image
      native.handlers[int(proof.header)] = flatMixedLoopEntryWitness
      runFlat(native, quota)
      runFlat(checked, quota)
      native.mixedWitnessImage = nil
      assert native.info == checked.info and native.reason == checked.reason and
        native.exit == checked.exit and uint64(native.faultPage) == uint64(checked.faultPage)
      assert native.remaining == checked.remaining and native.reservation == checked.reservation
      assert native.stoppedAt == checked.stoppedAt and native.attemptedExit == checked.attemptedExit
      assert native.dirtyPages == checked.dirtyPages and native.dirtyIndices == checked.dirtyIndices
      assert native.rw.len == checked.rw.len
      for index in 0..<native.rw.len: assert native.rw[index] == checked.rw[index]
      let visits = [2'u64, 3, 0, 1, 0, 1, 2, 0, 1]
      let refusals = [1'u64, 0, 0, 0, 0, 0, 0, 1, 1]
      assert native.mixedWitnessVisits == visits[scenario]
      assert native.mixedWitnessRefusals == refusals[scenario]
      echo "MIXED_LOOP_ENTRY,", scenario, ",", native.mixedWitnessVisits, ",",
        native.mixedWitnessRefusals, ",", uint64(native.faultPage)

proc runFlatSingle*(f: var FlatFrame) =
  ## Reuse the ordinary charge and opcode workers with one source fact and scalar successor endpoints.
  assert f.plan.singleStep and f.plan.facts.len == 1
  assert f.handlers.len == 0 and f.arguments.len == 0 and f.sites.len == 0
  f.remaining = 1
  f.reason = oracle.StepError.None
  f.exit = oracle.StepExit.Continued
  let fact = f.plan.facts[0]
  var cost = 0'u64
  if not f.info.blockCharged:
    # Prepaid stepping does not query an unused price; unpaid entry still charges the genuine containing block.
    let start = containingBlockStart(f.plan.source, CodeAddress(uint64(fact.pc)))
    if start.error != ProgramError.None:
      f.reason = oracle.StepError.InvalidMachine
      return
    let priced = flatPrice(f, start.value, cost)
    if priced != oracle.StepError.None:
      f.reason = priced
      return
  let payload = flatSourcePayload(f.plan, fact)
  let selected = payload.handler
  assert selected != nil
  if not flatEmit(f, flatCharge, FlatArgs(x: cost, y: 1, slots: default(RegisterSlots)), 0) or
      (selected != nil and not flatEmit(f, selected, payload.args, 0)) or
      not flatEmit(f, flatSingleEnd, FlatArgs(x: uint64(fact.next), y: 0,
        slots: default(RegisterSlots)), 0):
    f.reason = oracle.StepError.InvalidPreparedProgram
    return
  var offset = 0'u32
  while offset != flatStop:
    assert int(offset) < f.handlers.len
    let handler = f.handlers[int(offset)]
    offset = handler(f, offset)

func flatPublicationError(error: MachineError): oracle.StepError =
  ## Publication failures carry no committed memory, CPU or gas.
  if error == MachineError.None: oracle.StepError.None
  elif error == MachineError.LimitExceeded: oracle.StepError.ResidentAllocationRefused
  else: oracle.StepError.InvalidMachine

proc flatCollectPage(f: FlatFrame, page: int, batch: var ResidentReplacementBatch): oracle.StepError =
  ## Writing original bytes back still publishes no replacement or mutable source alias.
  let description = f.sourcePages[page]
  if description.access != PageAccess.ReadWrite: return oracle.StepError.InvalidMachine
  let sourceSlot = MemoryPageSlot(uint32(page))
  let address = uint64(uint32(description.index))*4096
  if address >= f.stackBase and address-f.stackBase+4096 <= uint64(f.stack.len):
    let offset = int(address-f.stackBase)
    return flatPublicationError(stageResidentPage(batch, sourceSlot, description,
      f.stack.toOpenArray(offset, offset+4095)))
  if address >= f.rwBase and address-f.rwBase+4096 <= uint64(f.rw.len):
    let offset = int(address-f.rwBase)
    return flatPublicationError(stageResidentPage(batch, sourceSlot, description,
      f.rw.toOpenArray(offset, offset+4095)))
  for slot in 0..<f.extra.len:
    let region {.cursor.} = f.extra[slot]
    if region.access == PageAccess.ReadWrite and address >= region.first and
        address-region.first+4096 <= uint64(region.size):
      if region.bytes.len != region.size: return oracle.StepError.InvalidMachine
      let offset = int(address-region.first)
      return flatPublicationError(stageResidentPage(batch, sourceSlot, description,
        region.bytes.toOpenArray(offset, offset+4095)))
  oracle.StepError.InvalidMachine # Every dirty page needs a complete writable payload.

proc siftDirtyIndices(indices: var openArray[uint32], start, count: int) =
  ## Restore a max heap over the active prefix without allocating.
  var root = start
  while root < count div 2:
    var child = root*2+1
    if child+1 < count and indices[child] < indices[child+1]: inc child
    if indices[root] >= indices[child]: return
    swap(indices[root], indices[child])
    root = child

proc sortDirtyIndices(indices: var openArray[uint32]) =
  ## Dirty ordinals are unique. In-place heapsort retains bounded worst-case work.
  var start = indices.len div 2
  while start > 0:
    dec start
    siftDirtyIndices(indices, start, indices.len)
  var count = indices.len
  while count > 1:
    dec count
    swap(indices[0], indices[count])
    siftDirtyIndices(indices, 0, count)

proc tryFlatMemorySnapshot*(f: FlatFrame, snapshot: var Memory): oracle.StepError =
  ## Publish only dirty pages while preserving immutable ownership and sorted replacement order.
  if f.dirtyIndices.len == 0:
    # An untouched epoch has exactly its existing immutable bytes, permissions and local ceiling.
    snapshot = f.sourceMemory
    return oracle.StepError.None
  var batch = beginResidentReplacements(f.sourceMemory)
  if f.dirtyIndices.len < f.sourcePages.len div 8:
    # Sparse writes sort only their copied ordinals; publication never mutates the epoch's membership.
    var indices = newSeq[uint32](f.dirtyIndices.len)
    if indices.len != f.dirtyIndices.len: return oracle.StepError.ResidentAllocationRefused
    for index in 0..<indices.len: indices[index] = f.dirtyIndices[index]
    sortDirtyIndices(indices)
    var start = 0
    for index in indices:
      # A successful store proves membership; binary search skips the untouched portion of a large map.
      var low = start
      var high = f.sourcePages.len
      while low < high:
        let middle = low+(high-low) div 2
        if uint32(f.sourcePages[middle].index) < index: low = middle+1
        else: high = middle
      if low >= f.sourcePages.len or uint32(f.sourcePages[low].index) != index:
        return oracle.StepError.InvalidMachine
      let collected = flatCollectPage(f, low, batch)
      if collected != oracle.StepError.None: return collected
      start = low+1
  else:
    # Dense writes retain the original linear walk instead of sorting nearly the entire mapping.
    for page in 0..<f.sourcePages.len:
      if flatDirty(f, f.sourcePages[page].index):
        let collected = flatCollectPage(f, page, batch)
        if collected != oracle.StepError.None: return collected
  # Share untouched blocks and publish only after all resident pages have been accepted.
  let updated = finishResidentReplacements(batch)
  if updated.error != MachineError.None: return flatPublicationError(updated.error)
  snapshot = updated.value
  oracle.StepError.None

proc flatMemorySnapshot*(f: FlatFrame): Memory =
  ## Witness convenience. The public stepping adapter checks the typed outcome.
  result = default(Memory)
  let observed = tryFlatMemorySnapshot(f, result)
  assert observed == oracle.StepError.None

proc tryObserveFlatHostMemory*(f: var FlatFrame, snapshot: var Memory): oracle.StepError =
  ## Bind a host stop only after the complete observation succeeds.
  if f.reason != oracle.StepError.None or f.exit != oracle.StepExit.Host:
    return oracle.StepError.InvalidHostSuspension
  let observed = tryFlatMemorySnapshot(f, snapshot)
  if observed != oracle.StepError.None: return observed
  f.hostSnapshot = snapshot
  f.hostSnapshotPc = f.info.pc
  f.hostReady = true
  oracle.StepError.None

proc observeFlatHostMemory*(f: var FlatFrame): Memory =
  ## Witness convenience. Public callbacks receive only a successful observation.
  result = default(Memory)
  let observed = tryObserveFlatHostMemory(f, result)
  assert observed == oracle.StepError.None

proc readFlatHost32*(f: FlatFrame, address: MemoryAddress, limit: MemoryByteLimit,
    output: var array[32, byte]): MachineError =
  ## Copy a natural host range at the stopped PC, including unpublished guest stores.
  ## The immutable mapping supplies permissions and clean bytes. Dirty resident slices are
  ## copied into private temporary storage before the complete fixed result is exposed.
  if not f.hostReady or f.reason != oracle.StepError.None or f.exit != oracle.StepExit.Host or
      f.info.pc != f.hostSnapshotPc:
    return MachineError.InvalidOwner
  var bytes = default(array[32, byte])
  let checked = readBytesInto(f.sourceMemory, address, bytes, limit)
  if checked.error != MachineError.None: return checked.error
  let start = uint64(address)
  var copied = 0
  while copied < bytes.len:
    let physical = start+uint64(copied) # Complete preflight bounded the whole natural interval.
    let count = min(bytes.len-copied, 4096-int(physical mod 4096))
    if flatDirty(f, PageIndex(uint32(physical div 4096))):
      if physical >= f.stackBase and physical-f.stackBase+uint64(count) <= uint64(f.stack.len):
        copyMem(addr bytes[copied], unsafeAddr f.stack[int(physical-f.stackBase)], count)
      elif physical >= f.rwBase and physical-f.rwBase+uint64(count) <= uint64(f.rw.len):
        copyMem(addr bytes[copied], unsafeAddr f.rw[int(physical-f.rwBase)], count)
      else:
        var resident = false
        for slot in 0..<f.extra.len:
          let region {.cursor.} = f.extra[slot]
          if region.access == PageAccess.ReadWrite and physical >= region.first and
              physical-region.first+uint64(count) <= uint64(region.bytes.len):
            copyMem(addr bytes[copied], unsafeAddr region.bytes[int(physical-region.first)], count)
            resident = true
            break
        if not resident: return MachineError.InvalidOwner # A dirty page must have resident bytes.
    copied += count
  output = bytes
  MachineError.None

proc observeFlatHostScalars*(f: var FlatFrame): MachineInfo =
  ## Bind a genuine host stop without publishing memory; the callback receives only copied CPU state.
  assert f.reason == oracle.StepError.None and f.exit == oracle.StepExit.Host
  f.hostSnapshot = default(Memory)
  f.hostSnapshotPc = f.info.pc
  f.hostReady = true
  f.info

func flatNodes*(f: FlatFrame): int =
  ## A copied observation reports stream size without exposing mutable cache arrays.
  f.handlers.len

proc checkFlatSource*(f: FlatFrame, expected: openArray[PageImage]) =
  ## An independently captured caller witness checks every immutable baseline byte outside execution.
  assert expected.len == f.sourcePages.len
  for slot in 0..<expected.len:
    # The witness belongs to the caller, never to production frame storage or its resident buffers.
    let description = f.sourcePages[slot]
    assert description.index == expected[slot].index and description.access == expected[slot].access
    let original = pageImage(f.sourceMemory, description.index)
    assert original.error == MachineError.None and original.value.access == expected[
        slot].access and
      original.value.bytes == expected[slot].bytes

proc checkFlatReference*(f: FlatFrame, expected: string, offset: int = 120) =
  ## Compare all current bytes and permissions against the independent complete reference outside clocks.
  assert expected.len == offset+f.sourcePages.len*4096
  for page in 0..<f.sourcePages.len:
    let description = f.sourcePages[page]
    let source = pageImage(f.sourceMemory, description.index)
    assert source.error == MachineError.None
    let image = source.value
    assert image.access == description.access
    for at in 0..<4096:
      # Inaccessible bytes have no resident region and remain solely in their immutable source page.
      let current = if description.access == PageAccess.Inaccessible: image.bytes[at]
        else: flatByte(f, uint64(uint32(description.index))*4096+uint64(at), image.bytes[at])
      assert current == byte(expected[offset+page*4096+at])

proc prepareFlatMemoryFrame*(plan: FlatPlan, memory: Memory, info: MachineInfo): FlatResult[FlatFrame] =
  ## A validated immutable Memory already owns checked page capabilities; retain it instead of recapturing them.
  let count = memoryPageCount(memory)
  if count.error != MachineError.None: return FlatResult[FlatFrame](status: FlatError.InvalidMemory)
  if uint32(count.value) > uint32(plan.limits.pages):
    return FlatResult[FlatFrame](status: FlatError.PageLimitExceeded)
  var layout = memoryLayout(memory)
  if layout.error == MachineError.AllocationRefused:
    return FlatResult[FlatFrame](status: FlatError.ResidentAllocationRefused)
  if layout.error != MachineError.None: return FlatResult[FlatFrame](
      status: FlatError.InvalidMemory)
  var retained = machine.takeValue(layout)
  buildFlatFrame(plan, retained, info, memory)

proc flatCommitMemoryReplacement(f: var FlatFrame, replacement: var FlatFrame) =
  ## Both callers fully validate a fresh same-plan frame before moving the code-only cache and policies.
  when NativeCheckedReadEnabled:
    # The prior segment always restores its terminal handlers before any host transition.
    assert not f.readProbe.observing
    replacement.readProbe = f.readProbe
    replacement.nativeRingInstalled = f.nativeRingInstalled
  replacement.preparationFailure = f.preparationFailure
  replacement.preparationUsed = f.preparationUsed
  replacement.pricingPlan = f.pricingPlan
  replacement.pricingMemo = f.pricingMemo
  replacement.pricingKind = f.pricingKind
  replacement.plan = move(f.plan)
  replacement.handlers = move(f.handlers)
  replacement.arguments = move(f.arguments)
  replacement.sites = move(f.sites)
  replacement.compiledForPc = move(f.compiledForPc)
  replacement.nativeSession = move(f.nativeSession)
  replacement.nativeInstallation = f.nativeInstallation
  replacement.nativeOriginal = f.nativeOriginal
  replacement.nativeEntry = f.nativeEntry
  replacement.nativeInstalledEpoch = f.nativeInstalledEpoch
  when NativeReadCycleEnabled:
    assert f.mixedImage == nil
    replacement.mixedSource = f.mixedSource
  f = move(replacement)

proc replaceFlatMemoryChecked*(f: var FlatFrame, images: openArray[PageImage],
    info: MachineInfo): FlatError =
  ## Trusted observation/reentry replaces memory capabilities wholesale; code cache offsets never retain memory or register owners.
  var prepared = prepareFlatFrame(f.plan, images, info)
  if prepared.error != FlatError.None: return prepared.error
  var replacement = takeValue(prepared)
  flatCommitMemoryReplacement(f, replacement)
  FlatError.None

proc flatReplaceMemoryOwner(f: var FlatFrame, memory: Memory,
    info: MachineInfo): FlatError {.noinline.} =
  ## Keep complete Frame construction off resident host resumes; commit only a fully admitted owner.
  var prepared = prepareFlatMemoryFrame(f.plan, memory, info)
  if prepared.error != FlatError.None: return prepared.error
  var replacement = takeValue(prepared)
  flatCommitMemoryReplacement(f, replacement)
  FlatError.None

proc replaceFlatMemory*(f: var FlatFrame, images: openArray[PageImage], info: MachineInfo) =
  ## Local witness convenience only; the checked boundary preserves a refused frame intact.
  let error = replaceFlatMemoryChecked(f, images, info)
  assert error == FlatError.None

proc resumeFlatHost*(f: var FlatFrame, images: openArray[PageImage], gas: MachineGas,
    registers: RegisterFile) =
  ## The decoder-owned successor, not host-supplied PC/charged metadata, resumes an already paid block.
  assert f.reason == oracle.StepError.None and f.exit == oracle.StepExit.Host
  let pc = uint64(f.info.pc)
  assert pc < uint64(f.plan.factAt.len)
  let packed = f.plan.factAt[int(pc)]
  assert packed != 0
  let at = int(packed - 1)
  var info = f.info
  info.pc = CodeAddress(f.plan.facts[at].next)
  info.gas = gas
  info.registers = registers
  replaceFlatMemory(f, images, info)

proc flatHostPage(f: var FlatFrame, posterior: Memory, slot: MemoryPageSlot,
    apply: bool, copiedPages: var uint64): bool =
  ## Valid destination and physical copy count are distinct; preflight never changes bytes or the count.
  let page = int(uint32(slot))
  let description = f.sourcePages[page]
  if description.access != PageAccess.ReadWrite: return false
  let address = uint64(uint32(description.index))*4096
  if address >= f.stackBase and address-f.stackBase+4096 <= uint64(f.stack.len):
    let offset = int(address-f.stackBase)
    if apply:
      flatCopySourcePage(posterior, page, description, f.stack.toOpenArray(offset, offset+4095))
      inc copiedPages
    return true
  if address >= f.rwBase and address-f.rwBase+4096 <= uint64(f.rw.len):
    let offset = int(address-f.rwBase)
    if apply:
      flatCopySourcePage(posterior, page, description, f.rw.toOpenArray(offset, offset+4095))
      inc copiedPages
    return true
  for i in 0..<f.extra.len:
    # Fragmented mappings retain their own immutable access metadata and full-span checks.
    let region {.cursor.} = f.extra[i]
    if region.access == PageAccess.ReadWrite and address >= region.first and
        address-region.first+4096 <= uint64(region.size):
      assert region.bytes.len == 0 or region.bytes.len == region.size
      if apply and region.bytes.len != 0:
        # Baseline-backed extras accept the changed owner without allocating or physically copying bytes.
        let offset = int(address-region.first)
        flatCopySourcePage(posterior, page, description,
          f.extra[i].bytes.toOpenArray(offset, offset+4095))
        inc copiedPages
      return true
  false

template requireFlatHostFact(f: FlatFrame, fact: var int) =
  ## Bind both host observations to the original stopped node and its immutable source PC.
  if f.reason != oracle.StepError.None or f.exit != oracle.StepExit.Host or not f.hostReady or
      f.info.pc != f.hostSnapshotPc or not f.info.blockCharged or uint64(f.info.gasDeficit) != 0:
    return oracle.StepError.InvalidHostSuspension
  if f.plan.singleStep or int(f.stoppedAt) >= f.sites.len:
    return oracle.StepError.InvalidHostSuspension
  fact = int(f.sites[int(f.stoppedAt)])
  if uint64(f.info.pc) != uint64(f.plan.facts[fact].pc):
    return oracle.StepError.InvalidHostSuspension

func flatHostContinuation(f: FlatFrame, gas: MachineGas, registers: RegisterFile,
    info: var MachineInfo): oracle.StepError {.noinline.} =
  ## Keep the owned CPU stage separate from the mutable memory transaction.
  var fact = 0
  requireFlatHostFact(f, fact)
  info = f.info
  info.pc = CodeAddress(f.plan.facts[fact].next)
  info.gas = gas
  info.registers = registers
  oracle.StepError.None

template resetFlatHostSegment(f: var FlatFrame) =
  ## Finish the validated continuation and retire its stopped observation.
  f.reason = oracle.StepError.None
  f.exit = oracle.StepExit.Continued
  f.faultPage = PageAddress(0)
  f.hostCall = oracle.HostCallId(0)
  f.remaining = 0
  f.reservation = 0
  f.stoppedAt = 0
  f.attemptedExit = false
  f.barrier = flatStop
  f.barrierFact = 0
  f.savedHandler = nil
  # The next runFlat entry applies the same paid-interior and jump-cache rules for either capability.
  f.hostReady = false
  f.hostSnapshot = default(Memory)
  inc f.fastResumes

proc flatCommitHostContinuation(f: var FlatFrame, info: MachineInfo) =
  ## Publish the CPU state staged for the completed owned-memory transaction.
  f.info = info
  resetFlatHostSegment(f)

proc resumeFlatHostScalars*(f: var FlatFrame, gas: MachineGas,
    registers: RegisterFile): oracle.StepError =
  ## Commit the scalar reply while retaining dirty membership against the old baseline.
  var fact = 0
  requireFlatHostFact(f, fact)
  let nextPc = CodeAddress(f.plan.facts[fact].next)
  f.info.pc = nextPc
  f.info.gas = gas
  f.info.registers = registers
  resetFlatHostSegment(f)
  oracle.StepError.None

proc resumeFlatHostMemory*(f: var FlatFrame, posterior: Memory, gas: MachineGas,
    registers: RegisterFile): oracle.StepError =
  ## The host supplies immutable posterior memory and scalar CPU changes, never a successor PC/paid flag.
  ## Refused responses leave the complete stopped invocation and observation usable for repair/retry.
  var info = default(MachineInfo)
  let checked = flatHostContinuation(f, gas, registers, info)
  if checked != oracle.StepError.None: return checked
  # Reject oversized host mappings before extracting changed pages or allocating replacement storage.
  let count = memoryPageCount(posterior)
  if count.error != MachineError.None or uint32(count.value) > uint32(f.plan.limits.pages):
    return oracle.StepError.InvalidHostResponse
  var delta = changedMemoryPageSlots(f.hostSnapshot, posterior)
  if delta.error == MachineError.AllocationRefused:
    return oracle.StepError.ResidentAllocationRefused
  if delta.error == MachineError.InvalidOwner: return oracle.StepError.InvalidHostResponse
  var replace = delta.error != MachineError.None
  if not replace:
    let changes = machine.takeValue(delta)
    var copiedPages = 0'u64
    for i in 0..<changes.len:
      # Complete preflight precedes the first host-byte mutation; unusual capabilities take the slow path.
      if not flatHostPage(f, posterior, changes[i], false, copiedPages): replace = true
    if not replace:
      for i in 0..<changes.len:
        let applied = flatHostPage(f, posterior, changes[i], true, copiedPages)
        assert applied
      f.sourceMemory = posterior
      flatClearDirty(f)
      flatCommitHostContinuation(f, info)
      f.hostCopiedPages+=copiedPages
      return oracle.StepError.None
  # Mapping/permission/RO replacement rebuilds all capabilities from a genuine validated snapshot.
  let fast = f.fastResumes
  let fallbacks = f.fallbackResumes
  let pages = f.hostCopiedPages
  let replacementError = flatReplaceMemoryOwner(f, posterior, info)
  if replacementError != FlatError.None:
    if replacementError == FlatError.ResidentAllocationRefused:
      return oracle.StepError.ResidentAllocationRefused
    return oracle.StepError.InvalidHostResponse
  f.fastResumes = fast
  f.fallbackResumes = fallbacks+1
  f.hostCopiedPages = pages
  oracle.StepError.None

func flatHostStats*(f: FlatFrame): array[3, uint64] =
  ## Copied diagnostic counters: resident resumes, full mapping replacements, copied host pages.
  [f.fastResumes, f.fallbackResumes, f.hostCopiedPages]

type FlatStream* = object
  ## A reusable exclusive cache retains program coordinates/handlers and counters, never CPU or memory.
  handlers: seq[FlatHandler]
  arguments: seq[FlatArgs]
  sites: seq[uint32]
  compiledForPc: MetadataStore[uint32]
  sourcePlan: nil FlatPlan # Exact source, emission and default-cycle owner for every build.
  nativeOriginal: nil FlatHandler
  nativeInstallation: FlatNativeInstallation
  nativeEntry: uint32
  nativeInstalledEpoch: uint64
  when NativeReadCycleEnabled:
    bitmapCandidate: uint32
    mixedSource: FlatMixedLoopSource
  pricingKind: byte        # Nondefault sealed headers require fresh emission when leased to another frame.
  failure: FlatError
  preparation: uint64
  catalogue: nil FlatPlan  # Exclusive derived metadata moves together with stable handler site ordinals.

proc `=copy`*(destination: var FlatStream, source: FlatStream) {.error.}
  ## Reject copying exclusive native resources or a privately mutable lazy catalogue.

proc `=dup`*(source: FlatStream): FlatStream {.error.}
  ## Reject duplication of exclusive native resources or a privately mutable lazy catalogue.

proc takeFlatStream*(f: var FlatFrame): FlatStream =
  ## Return the exclusive cache to the prepared owner with its admitted entries,
  ## cumulative preparation usage and native restoration state. Generated leaves
  ## retain no invocation pointers. A pending bitmap observation moves with its
  ## original stream coordinates and is discarded with the stream on repricing.
  ## Omit node and preparation-work refusals from the saved cache so a fresh frame
  ## can use those entries. The active frame keeps its failure.
  if f.preparationFailure == FlatError.StreamAllocationRefused:
    # A partial catalogue or node sequence cannot be leased again. Invalidate
    # its source epoch before another invocation can install its native image.
    invalidateNativeStream(f.nativeSession)
    result = default(FlatStream)
    result.preparation = f.preparationUsed
    return
  let savedFailure = if f.preparationFailure in {FlatError.StreamLimitExceeded,
      FlatError.PreparationLimitExceeded}: FlatError.Uninitialized else: f.preparationFailure
  result = FlatStream(handlers: move(f.handlers), arguments: move(f.arguments), sites: move(f.sites),
    compiledForPc: move(f.compiledForPc), sourcePlan: f.plan, pricingKind: f.pricingKind,
    failure: savedFailure,
    preparation: f.preparationUsed, nativeOriginal: f.nativeOriginal, nativeEntry: f.nativeEntry,
    nativeInstalledEpoch: f.nativeInstalledEpoch, nativeInstallation: f.nativeInstallation)
  let original = flatPlanIdentity(f.plan)
  result.sourcePlan = original
  if f.plan != nil and f.plan.admission != nil:
    result.catalogue = move(f.plan)
    f.plan = original # The emptied frame cannot retain mutable metadata now leased to the stream.
  when NativeReadCycleEnabled:
    assert f.mixedImage == nil and f.mixedProofs == nil and f.mixedMask == 0
    when defined(pvmPaidMixedLoopWitness): assert f.mixedPair == nil
    result.bitmapCandidate = f.bitmapCandidate
    f.bitmapCandidate = 0
    result.mixedSource = f.mixedSource
    f.mixedSource = default(FlatMixedLoopSource)

proc restoreFlatStream*(f: var FlatFrame, stream: var FlatStream) =
  ## Restore an executable stream only for the exact immutable plan.
  ## Sealed prices and errors belong to their emitting policy. If either side uses
  ## complete-plan or memo pricing, discard the stream and reemit under the new
  ## frame's policy. This also preserves stricter cycle limits on a fresh memo.
  ## An absent saved failure leaves the receiving frame's status intact, including
  ## a sticky refusal on a same-frame restore. A fresh frame can use the admitted
  ## entries. Any new suffix must fit the remaining node and preparation-work quota.
  let identity = flatPlanIdentity(f.plan)
  if stream.sourcePlan != nil and stream.sourcePlan != identity:
    # Refuse before consuming another owner's price, executable capability or scalar coordinates.
    f.preparationFailure = FlatError.InvalidProgram
    return
  if f.pricingKind != 0 or stream.pricingKind != 0:
    # A sealed charge/error or native header belongs to its original pricing policy. Reemit under the
    # newly selected policy rather than borrowing an unproven price or retaining another policy owner.
    invalidateNativeStream(f.nativeSession)
    stream = default(FlatStream)
    return
  let catalogue = stream.catalogue
  if catalogue != nil:
    # Narrow the optional retained owner before handing off its sole mutable capability.
    f.plan = catalogue
    stream.catalogue = nil
  stream.sourcePlan = nil
  f.handlers = move(stream.handlers)
  f.arguments = move(stream.arguments)
  f.sites = move(stream.sites)
  f.compiledForPc = move(stream.compiledForPc)
  if stream.failure != FlatError.Uninitialized: f.preparationFailure = stream.failure
  f.preparationUsed = stream.preparation
  f.nativeOriginal = stream.nativeOriginal
  f.nativeEntry = stream.nativeEntry
  f.nativeInstalledEpoch = stream.nativeInstalledEpoch
  f.nativeInstallation = stream.nativeInstallation
  when NativeReadCycleEnabled:
    f.bitmapCandidate = stream.bitmapCandidate
    stream.bitmapCandidate = 0
    f.mixedSource = stream.mixedSource
    stream.mixedSource = default(FlatMixedLoopSource)
  flatConsiderNative(f, 0) # Reconsider prior cached code after transient registration capacity becomes available.
  when NativeCheckedReadEnabled:
    # Restored original facts authorize a deferred read retry without discovering another candidate.
    validateFlatReadNomination(f)
  installNative(f)

when defined(pvmArm64Jit) or defined(pvmX86Jit):
  func streamNativeStatistics*(stream: FlatStream): array[7, uint64] =
    ## Private stream counters are empty. Prepared execution reports through the shared owner.
    default(array[7, uint64])

when defined(pvmX86Jit):
  func flatX86Statistics*(frame: FlatFrame): array[5, uint64] =
    ## Unbound witness frames retain checked execution without a private executable cache.
    default(array[5, uint64])

  func flatX86ControlStatistics*(frame: FlatFrame): array[2, uint64] =
    ## Unbound frame probes have no native branch or header entries.
    default(array[2, uint64])

when defined(pvmArm64JitOwnerReceipt):
  func streamArmStatistics*(stream: FlatStream): array[7, uint64] =
    ## Preserve the existing diagnostic API over the same copied cold observation.
    streamNativeStatistics(stream)

when defined(pvmArmMacroReceipt):
  func streamArmMacroStatistics*(stream: FlatStream): array[7, uint64] =
    ## A checked stream retains no private macro image or activity.
    default(array[7, uint64])

  func streamArmMacroResidentActive*(stream: FlatStream): bool =
    ## A checked stream retains no resident macro image.
    false

func streamNodes*(stream: FlatStream): uint64 =
  ## Copied logical occupancy exposes neither mutable arrays nor retained invocation state.
  uint64(stream.handlers.len)

func streamPreparation*(stream: FlatStream): uint64 =
  ## The bounded preparation allowance survives every lease, including local refusal.
  stream.preparation

func planFacts*(plan: FlatPlan): uint64 =
  ## Report the full admitted source count; lazy materialization never changes its resource obligation.
  if not plan.singleStep: return uint64(plan.admittedFacts)
  uint64(plan.facts.len)

func metadataPayloadBytes*(frame: FlatFrame): uint64 =
  ## Copied allocated fact/map payload excludes directory and executable-handler storage.
  ## A default or moved frame owns no metadata.
  if frame.plan == nil: return 0
  uint64(allocatedElements(frame.plan.facts))*uint64(sizeof(FlatFact)) +
    uint64(allocatedElements(frame.plan.factAt)+allocatedElements(frame.compiledForPc))*4

func materializedFacts*(frame: FlatFrame): uint64 =
  ## Copied occupancy reports only blocks requested by resolution, including branch prelinks.
  if frame.plan == nil: 0'u64 else: uint64(frame.plan.materialized)

func materializedOrdinal*(frame: FlatFrame, pc: CodeAddress): uint32 =
  ## Copied global ordinal tag; zero means this instruction has no materialized fact.
  if frame.plan == nil or uint64(pc) >= uint64(frame.plan.factAt.len): return 0
  frame.plan.factAt[int(uint64(pc))]

func materializedFacts*(stream: FlatStream): uint64 =
  ## Observe the saved catalogue without exporting its mutable owner or coordinates.
  let catalogue = stream.catalogue
  if catalogue == nil: 0'u64 else: uint64(catalogue.materialized)

func flatScratchSlot(pages: seq[PageDescription], physical: uint32): int =
  ## Resolve a retained dirty page against the sorted mapping.
  var low = 0
  var high = pages.len
  while low < high:
    let middle = low+(high-low) div 2
    if uint32(pages[middle].index) < physical: low = middle+1
    else: high = middle
  if low < pages.len and uint32(pages[low].index) == physical: low else: -1

proc flatRestoreScratchPage(f: var FlatFrame, page: int): bool =
  ## Copy a genuine source page to its private backing, or refuse an inconsistent retained span.
  let description = f.sourcePages[page]
  if description.access == PageAccess.Inaccessible: return true
  let address = uint64(uint32(description.index))*4096
  if address >= f.stackBase and address-f.stackBase+4096 <= uint64(f.stack.len):
    let offset = int(address-f.stackBase)
    return flatTryCopySourcePage(f.sourceMemory, page, description, f.stack.toOpenArray(offset, offset+4095))
  if address >= f.rwBase and address-f.rwBase+4096 <= uint64(f.rw.len):
    let offset = int(address-f.rwBase)
    return flatTryCopySourcePage(f.sourceMemory, page, description, f.rw.toOpenArray(offset, offset+4095))
  if address >= f.roBase and address-f.roBase+4096 <= uint64(f.ro.len):
    let offset = int(address-f.roBase)
    return flatTryCopySourcePage(f.sourceMemory, page, description, f.ro.toOpenArray(offset, offset+4095))
  for index in 0..<f.extra.len:
    let region {.cursor.} = f.extra[index]
    if address >= region.first and address-region.first+4096 <= uint64(region.size):
      # Lazy extras already use the incoming baseline.
      if region.bytes.len == 0: return true
      if region.bytes.len != region.size: return false
      let offset = int(address-region.first)
      return flatTryCopySourcePage(f.sourceMemory, page, description,
        f.extra[index].bytes.toOpenArray(offset, offset+4095))
  false

proc prepareReusedFlatMemoryFrame*(plan: FlatPlan, memory: Memory, info: MachineInfo,
    scratch: var nil FlatMemoryScratch, reused: var bool): FlatResult[FlatFrame] =
  ## Admission and full map/access equality precede reuse; mismatches discard the old idle allocation.
  reused = false
  if scratch == nil: return prepareFlatMemoryFrame(plan, memory, info)
  let count = memoryPageCount(memory)
  if count.error != MachineError.None: return FlatResult[FlatFrame](status: FlatError.InvalidMemory)
  if uint32(count.value) > uint32(plan.limits.pages):
    return FlatResult[FlatFrame](status: FlatError.PageLimitExceeded)
  var held = move(scratch)
  if held == nil: return prepareFlatMemoryFrame(plan, memory, info)
  var delta = changedMemoryPageSlots(held.baseline, memory)
  if delta.error == MachineError.AllocationRefused:
    scratch = move(held)
    return FlatResult[FlatFrame](status: FlatError.ResidentAllocationRefused)
  if delta.error != MachineError.None or uint64(held.pages.len) != uint64(uint32(count.value)) or
      held.dirty.len > held.pages.len:
    held = nil
    return prepareFlatMemoryFrame(plan, memory, info)
  let words = if held.pages.len == 0: 0'u64
    else: (uint64(uint32(held.pages[held.pages.len-1].index)) shr 6)+1
  if uint64(held.dirtyPages.len) != words:
    held = nil
    return prepareFlatMemoryFrame(plan, memory, info)
  block restore:
    let changes = machine.takeValue(delta)
    var frame = flatFrameShell[true](plan, memory, info, held.pages.len, 0)
    frame.sourcePages = move(held.pages)
    frame.roBase = held.roBase
    frame.rwBase = held.rwBase
    frame.stackBase = held.stackBase
    frame.ro = move(held.ro)
    frame.rwStorage = move(held.rwStorage)
    frame.rw = borrowRW(frame.rwStorage)
    held.rw = default(RWView) # Manual payload transfer retires the old heap cell's borrowed authority.
    frame.stack = move(held.stack)
    frame.extra = move(held.extra)
    frame.dirtyPages = move(held.dirtyPages)
    frame.dirtyIndices = move(held.dirty)
    for index in 0..<changes.len:
      let slot = uint64(uint32(changes[index]))
      if slot >= uint64(frame.sourcePages.len): break restore
      let page = int(slot)
      let physical = uint64(uint32(frame.sourcePages[page].index))
      let word = physical shr 6
      # A marked page is restored by the dirty-list pass below. Leftover bits reject reuse.
      if (word >= uint64(frame.dirtyPages.len) or
          (frame.dirtyPages[int(word)] and (1'u64 shl int(physical and 63))) == 0) and
          not flatRestoreScratchPage(frame, page):
        break restore
    for index in 0..<frame.dirtyIndices.len:
      # A restored page consumes its bit. A duplicate ordinal cannot claim it twice.
      let physical = frame.dirtyIndices[index]
      let page = flatScratchSlot(frame.sourcePages, physical)
      let word = uint64(physical shr 6)
      let mask = 1'u64 shl int(physical and 63)
      if page < 0 or frame.sourcePages[page].access != PageAccess.ReadWrite or
          word >= uint64(frame.dirtyPages.len) or
          (frame.dirtyPages[int(word)] and mask) == 0 or
          not flatRestoreScratchPage(frame, page):
        break restore
      frame.dirtyPages[int(word)] = frame.dirtyPages[int(word)] and not mask
    for index in 0..<frame.dirtyPages.len:
      if frame.dirtyPages[index] != 0: break restore
    frame.dirtyIndices.setLen(0)
    reused = true
    return FlatResult[FlatFrame](status: FlatError.None, completed: move(frame))
  # The private frame retired when the restore block exited. Re-admit from the immutable input.
  held = nil
  prepareFlatMemoryFrame(plan, memory, info)

proc takeFlatMemoryScratch*(f: var FlatFrame, payloadLimit: uint64): nil FlatMemoryScratch =
  ## Retain only bounded private payload plus one immutable baseline; zero disables retention.
  if payloadLimit == 0: return nil
  var bytes = uint64(f.ro.len)+uint64(f.rw.len)+uint64(f.stack.len)
  for region in f.extra:
    # Charge complete logical extents even when an untouched extra has no private payload yet.
    bytes += uint64(region.size)
  if bytes == 0: return nil
  let total = bytes+uint64(f.sourcePages.len)*4096
  if total > payloadLimit: return nil
  let scratch: nil FlatMemoryScratch = FlatMemoryScratch()
  if scratch == nil: return nil # Optional retention leaves the frame in charge of cleanup.
  scratch.baseline = f.sourceMemory
  scratch.pages = move(f.sourcePages)
  scratch.roBase = f.roBase
  scratch.rwBase = f.rwBase
  scratch.stackBase = f.stackBase
  scratch.ro = move(f.ro)
  scratch.stack = move(f.stack)
  scratch.extra = move(f.extra)
  scratch.dirty = move(f.dirtyIndices)
  scratch.dirtyPages = move(f.dirtyPages)
  scratch.payloadBytes = total
  scratch.rwStorage = move(f.rwStorage)
  scratch.rw = borrowRW(scratch.rwStorage)
  clearFlatBorrowedMemory(f) # Child moves do not invoke the whole-frame move hook.
  scratch

when defined(pvmResidentWitness):
  type ScratchDirtyDamage* {.pure.} = enum
    Unmapped, Duplicate, Omitted

  proc invalidateLastScratchDirtyPage*(scratch: FlatMemoryScratch, damage: ScratchDirtyDamage) =
    ## Damage the list while preserving the original bitmap.
    assert scratch.dirty.len > 1
    case damage
    of Unmapped: scratch.dirty[scratch.dirty.len-1] = high(uint32)
    of Duplicate: scratch.dirty[scratch.dirty.len-1] = scratch.dirty[0]
    of Omitted: scratch.dirty.setLen(scratch.dirty.len-1)

  func residentFrameRWInfo*(frame: FlatFrame): array[3, uint64] =
    ## Test-only lengths distinguish a retired view from storage still owned by an active or idle lease.
    [uint64(frame.rw.len), logicalBytes(frame.rwStorage), mappedBytes(frame.rwStorage)]

func flatMemoryScratchPayload*(scratch: nil FlatMemoryScratch): uint64 =
  ## Copied logical payload occupancy excludes allocator overhead and remains zero without an idle lease.
  if scratch == nil: 0'u64 else: scratch.payloadBytes

proc selectFlatPrices*(f: var FlatFrame, plan: GasPlan, memo: GasMemo): oracle.StepError =
  ## Complete and lazy policy owners must match the exact immutable program before cache restore or emission.
  if gasPlanInfo(plan).error == GasPlanError.None:
    if not matchesProgram(plan, f.plan.source): return oracle.StepError.InvalidGasPlan
    if f.handlers.len != 0: return oracle.StepError.InvalidPreparedProgram
    f.pricingPlan = plan
    f.pricingKind = 1
  elif gasMemoInfo(memo).error == GasMemoError.None:
    if not matchesProgram(memo, f.plan.source): return oracle.StepError.InvalidGasMemo
    if f.handlers.len != 0: return oracle.StepError.InvalidPreparedProgram
    f.pricingMemo = memo
    f.pricingKind = 2
  oracle.StepError.None

when NativeReadCycleEnabled and defined(pvmPaidMixedLoopWitness):
  include ./handler_mixed_pair_witness

when NativeReadCycleEnabled and defined(pvmSharedAsyncWitness):
  proc witnessFlatMixedProbeBarrier*(program: Program, pc: uint32) =
    ## Stop immediately before a profiled BNE, retain its stream, and resume the exact paid source PC.
    let cycles = GasCycleLimit(100000)
    var admitted = prepareFlatPlan(program, cycles, defaultFlatLimits(), false)
    assert admitted.error == FlatError.None
    let plan = takeValue(admitted)
    let read = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly)
    let write = PageImage(index: PageIndex(17), access: PageAccess.ReadWrite)
    var info = MachineInfo(pc: CodeAddress(uint64(pc)), gas: MachineGas(1000000))
    info.registers[5] = RegisterValue(17*4096)
    info.registers[6] = RegisterValue(16*4096)
    info.registers[12] = RegisterValue(1)
    var observed = newFlatFrame(plan, [read, write], info)
    var checked = newFlatFrame(plan, [read, write], info)
    var header, terminal = 0'u32
    for frame in [addr observed, addr checked]:
      header = flatResolve(frame[], pc)
      assert header != flatStop
      var source = default(FlatSourceInterval)
      var walk = default(FlatSourceSummary)
      assert flatSourceIntervalAt(frame[], header, NativeReadFactLimit, source)
      assert flatWalkCompleteSource(frame[], header, source, walk)
      terminal = walk.terminal
      assert flatUnresolvedBranch[171](frame[], terminal) == terminal
    # Stale coordinates must not patch a neighboring worker or replay a paid suffix.
    let charge = observed.handlers[int(header)]
    let terminalSite = observed.sites[int(terminal)]
    assert not installFlatBudget(observed, uint32(observed.handlers.len),
      terminalSite+1, terminalSite)
    assert not installFlatBudget(observed, header, terminalSite, terminalSite)
    assert observed.barrier == flatStop and observed.savedHandler == nil
    assert observed.handlers[int(header)] == charge
    observed.info.blockCharged = true
    observed.remaining = 1
    assert flatResumePaid(observed, uint32(observed.handlers.len), int(terminalSite)) == flatStop
    assert observed.reason == oracle.StepError.BackendFailure
    assert observed.remaining == 1 and observed.barrier == flatStop
    observed.info.blockCharged = false
    observed.reason = oracle.StepError.None
    let proof = buildFlatMixedLoop(observed, pc, 1)
    assert proof.complete
    observed.mixedSource.epoch = 1
    observed.mixedSource.count = 1
    observed.mixedSource.candidates[0] = pc+1
    observed.mixedProbeWitness = true
    let quota = uint64(proof.span)-1
    runFlat(observed, quota)
    runFlat(checked, quota)
    assert observed.reason == oracle.StepError.StepLimitExceeded and observed.reason == checked.reason
    assert observed.info == checked.info and observed.info.blockCharged
    # The active frame owns materialized facts; the original admission plan stays immutable.
    assert observed.info.pc == CodeAddress(uint64(observed.plan.facts[int(proof.first)+int(
        proof.span)-1].pc))
    assert observed.mixedProbe == nil and observed.barrier == flatStop and observed.savedHandler == nil
    assert observed.handlers[int(terminal)] == flatBranch[171]
    assert observed.remaining == checked.remaining and observed.dirtyPages == checked.dirtyPages
    assert observed.dirtyIndices == checked.dirtyIndices
    let snapshot = flatMemorySnapshot(observed)
    let reference = flatMemorySnapshot(checked)
    var fresh = prepareFlatMemoryFrame(plan, snapshot, observed.info)
    var baseline = prepareFlatMemoryFrame(plan, reference, checked.info)
    assert fresh.error == FlatError.None and baseline.error == FlatError.None
    var resumed = takeValue(fresh)
    var compared = takeValue(baseline)
    var retained = takeFlatStream(observed)
    var control = takeFlatStream(checked)
    restoreFlatStream(resumed, retained)
    restoreFlatStream(compared, control)
    runFlat(resumed, 1)
    runFlat(compared, 1)
    assert resumed.mixedProbe == nil and resumed.reason == compared.reason
    assert resumed.info == compared.info and resumed.remaining == compared.remaining
    assert resumed.reservation == compared.reservation and resumed.stoppedAt == compared.stoppedAt
    assert resumed.dirtyPages == compared.dirtyPages and resumed.dirtyIndices ==
        compared.dirtyIndices

when NativeReadCycleEnabled and defined(pvmMixedLoopEntryWitness):
  proc witnessFlatFusedMixedLoopEntry*(program: Program, pc: uint32) =
    ## Compare every original node, including a step barrier between the two fused scalar operations.
    let cycles = GasCycleLimit(100000)
    var admitted = prepareFlatPlan(program, cycles, defaultFlatLimits(), false)
    assert admitted.error == FlatError.None
    let plan = takeValue(admitted)
    let price = blockGas(program, CodeAddress(uint64(pc)), cycles)
    assert price.error == GasError.None and uint64(price.value) > 0
    let read = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly)
    let write = PageImage(index: PageIndex(17), access: PageAccess.ReadWrite)
    for scenario in 0..5:
      let quota = case scenario
        of 1: 4'u64
        of 2: 12'u64
        of 3: 13'u64
        else: 27'u64
      var info = MachineInfo(pc: CodeAddress(uint64(pc)), gas: MachineGas(
        if scenario == 4: uint64(price.value)-1 else: 1000000'u64))
      info.registers[0] = RegisterValue(0x35)
      info.registers[5] = RegisterValue(17*4096)
      info.registers[6] = RegisterValue(16*4096)
      info.registers[12] = RegisterValue(17*4096+2)
      var native = newFlatFrame(plan, [read, write], info)
      var checked = newFlatFrame(plan, [read, write], info)
      for frame in [addr native, addr checked]:
        let header = flatResolve(frame[], pc)
        assert header != flatStop
        var source = default(FlatSourceInterval)
        var walk = default(FlatSourceSummary)
        assert flatSourceIntervalAt(frame[], header, NativeReadFactLimit, source)
        assert flatWalkCompleteSource(frame[], header, source, walk)
        assert flatUnresolvedBranch[171](frame[], walk.terminal) == walk.terminal
        if scenario != 5: flatMarkStore[1](frame[], 17'u64*4096)
      let proof = buildFlatMixedLoop(native, pc, 1)
      assert proof.complete and proof.span == 13 and proof.count == 12
      var refused = false
      var image = lowerNativeMixedLoop(proof, refused)
      assert image.ready and not refused
      native.mixedWitnessProof = proof
      native.mixedWitnessImage = addr image
      native.handlers[int(proof.header)] = flatMixedLoopEntryWitness
      runFlat(native, quota)
      runFlat(checked, quota)
      native.mixedWitnessImage = nil
      assert native.info == checked.info and native.reason == checked.reason and native.exit == checked.exit
      assert native.remaining == checked.remaining and native.reservation == checked.reservation
      assert native.stoppedAt == checked.stoppedAt and native.attemptedExit == checked.attemptedExit
      assert uint64(native.faultPage) == uint64(checked.faultPage)
      assert native.dirtyPages == checked.dirtyPages and native.dirtyIndices == checked.dirtyIndices
      assert native.rw.len == checked.rw.len
      for index in 0..<native.rw.len: assert native.rw[index] == checked.rw[index]
      let expected = [2'u64, 0, 0, 1, 0, 1]
      assert native.mixedWitnessVisits == expected[scenario]
      if scenario == 1:
        assert native.reason == oracle.StepError.StepLimitExceeded and native.info.blockCharged
        # Resolve the original instruction in this frame's private block catalogue.
        assert uint64(native.info.pc) == uint64(native.plan.facts[int(proof.first)+4].pc)
      echo "MIXED_FUSED_ENTRY,", pc, ",", scenario, ",", native.mixedWitnessVisits

when NativeReadCycleEnabled and defined(pvmMixedLoopWitness):
  proc seedFlatMixedDirtyPages*(frame: var FlatFrame, addresses: openArray[uint64]) =
    ## Private continuation controls establish checked dirty bookkeeping without changing source bytes.
    for address in addresses:
      let access = writableScalar(frame.sourceMemory, MemoryAddress(address), AccessWidth(1))
      assert access.error == MachineError.None
      flatMaterializeStore[1](frame, address)
      flatMarkStore[1](frame, address)
