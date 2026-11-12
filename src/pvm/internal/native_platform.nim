# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Platform lowering and OS mechanics; native_pipeline owns scheduling and admission.
## One immutable auxiliary arena holds bounded self-loops; general graphs remain checked.
## Its 4096-byte cap yields target-dependent subsets; failed publication releases it whole.

import std/assertions
import ../machine
import ./[native_ir, native_control]
import ./[native_read_body, native_register_ring]
when NativeReadCycleEnabled:
  import ./native_read_cycle
  import ./native_mixed_loop
when defined(pvmX86Jit):
  import ./x86_jit
elif defined(pvmArm64Jit):
  import ./arm64_jit

when defined(pvmX86Jit):
  proc arenaCreate(): nil pointer {.cdecl, importc: "pvm_x86_arena_create", header: "x86_memory.h".}
    ## Create the maintained platform arena; only the compiler worker calls this path.
  proc arenaRelease(handle: nil pointer) {.cdecl, importc: "pvm_x86_arena_destroy",
      header: "x86_memory.h".}
    ## Release the sole owned mapping; no invocation may retain an active image borrow.
  proc arenaPublish(handle: nil pointer, bytes: pointer, count: uint32): int32 {.cdecl,
      importc: "pvm_x86_arena_publish", header: "x86_memory.h".}
    ## Complete writes/coherency before the shared mailbox can publish Ready.
  proc arenaCall(handle: nil pointer, offset: uint32, registers: pointer): cint {.cdecl,
      importc: "pvm_x86_arena_call", header: "x86_memory.h".}
    ## Register-only invocation ABI returns a checked completion status.
  proc arenaRegion(handle: nil pointer, offset: uint32, registers, context: pointer): uint32 {.
      cdecl, importc: "pvm_x86_arena_region", header: "x86_memory.h".}
    ## Two transient borrows and a returned stream coordinate.
elif defined(pvmArm64Jit):
  proc arenaCreate(): nil pointer {.cdecl, importc: "pvm_arm64_arena_create",
      header: "arm64_memory.h".}
    ## Create the maintained platform arena; only the compiler worker calls this path.
  proc arenaRelease(handle: nil pointer) {.cdecl, importc: "pvm_arm64_arena_destroy",
      header: "arm64_memory.h".}
    ## Release the sole owned mapping; no invocation may retain an active image borrow.
  proc arenaPublish(handle: nil pointer, words: pointer, count: uint32): int32 {.cdecl,
      importc: "pvm_arm64_arena_publish", header: "arm64_memory.h".}
    ## Complete writes/coherency before the shared mailbox can publish Ready.
  proc arenaCall(handle: nil pointer, offset: uint32, registers: pointer): cint {.cdecl,
      importc: "pvm_arm64_arena_call", header: "arm64_memory.h".}
    ## Register-only invocation ABI returns a checked completion status.
  proc arenaRegion(handle: nil pointer, offset: uint32, registers, context: pointer): uint32 {.
      cdecl, importc: "pvm_arm64_arena_region", header: "arm64_memory.h".}
    ## Two transient borrows and a returned stream coordinate.

proc abortNativeReceipt*() {.cdecl, importc: "abort", header: "<stdlib.h>", noreturn.}
  ## Internal ABI/receipt failure cannot unwind into guest replay or publish a partial snapshot.

type NativeImage* = object ## Exclusive published image with its exact call ABI.
  handle: nil pointer
  offset: uint32
  bytesValue: uint64
  kindValue: NativeKind
  when NativeReadCycleEnabled:
    mixedOffsets, mixedLengths: array[NativeMixedLoopEntryLimit, uint32]
    mixedEntries: uint8
  when NativeCheckedReadEnabled:
    ringValue: NativeRegisterRing

proc `=copy`*(destination: var NativeImage, source: NativeImage) {.error.}
  ## Executable authority cannot be duplicated by copying its POD handle.

proc `=dup`*(source: NativeImage): NativeImage {.error.}
  ## Exactly one image owner releases the mapping.

proc `=wasMoved`*(image: var NativeImage) {.nodestroy, inline.} =
  ## Primitive move hooks do not clear raw pointers; disarm explicitly.
  image.handle = nil
  image.offset = 0
  image.bytesValue = 0
  image.kindValue = NativeKind.PurePrefix
  when NativeReadCycleEnabled:
    image.mixedOffsets = default(array[NativeMixedLoopEntryLimit, uint32])
    image.mixedLengths = default(array[NativeMixedLoopEntryLimit, uint32])
    image.mixedEntries = 0
  when NativeCheckedReadEnabled:
    image.ringValue = default(NativeRegisterRing)

proc `=destroy`*(image: NativeImage) =
  ## Default, failed and moved-from images own no executable storage.
  when defined(pvmX86Jit) or defined(pvmArm64Jit):
    if image.handle != nil: arenaRelease(image.handle)

func nativePlatformSupported*(): bool =
  ## Declarative host capability only; there is no ISA-specific scheduling or profit rule.
  when defined(pvmX86Jit): defined(amd64) and defined(linux)
  elif defined(pvmArm64Jit): defined(arm64) and (defined(linux) or defined(macosx))
  else: false

when defined(pvmX86Jit) or defined(pvmArm64Jit):
  proc createNativeArena(): nil pointer =
    ## Inject only the selected ISA's existing allocation refusal; capability and worker startup stay real.
    when defined(pvmX86Jit):
      # Preserve the normal C constructor unless this x86 profile explicitly refuses executable storage.
      when defined(pvmX86JitRefuse): nil
      else: arenaCreate()
    else:
      # ARM refusal has the same empty-image contract and does not affect an x86-selected profile.
      when defined(pvmArm64JitRefuse): nil
      else: arenaCreate()

func ready*(image: NativeImage): bool =
  ## Only a fully published image has callable authority.
  image.handle != nil

func codeBytes*(image: NativeImage): uint64 =
  ## Copied occupancy; one platform arena also reserves its maintained one-MiB backing allocation.
  image.bytesValue

func kind*(image: NativeImage): NativeKind =
  ## The image tag must match the owner certificate before calling the selected ABI.
  image.kindValue

proc lowerNative*(span: NativeSpan): NativeImage =
  ## Called ONLY by the compiler worker: private emission, mapping and coherency finish before return.
  result = default(NativeImage)
  if not nativePlatformSupported() or span.len == 0: return
  when defined(pvmX86Jit) or defined(pvmArm64Jit):
    let loop = span.loopInfo
    when defined(pvmX86Jit):
      var image: seq[byte] = @[]
      if loop.kind == NativeKind.ClosedRegisterLoop:
        image = encodeX86Loop(span, loopControl(loop))
      else:
        # ARM/x86 gap: ARM's ArmBlock keeps guest lanes resident across this pure span;
        # this x86 path still uses canonical array access per operation. Revisit residency
        # here while retaining the common opcode subset and exact source accounting.
        var body = default(X86Block)
        for index in 0..<span.len:
          let op = span.operation(index)
          emitX86Operation(body, op.opcode, op.slots, op.immediate)
        image = takeX86Instructions(body)
        image.add(0xc3'u8) # RET: pop caller's return RIP; pure leaf uses SysV caller-saved registers.
      let count = image.len
    else:
      var image: seq[uint32] = @[]
      if loop.kind == NativeKind.ClosedRegisterLoop:
        image = encodeArmLoop(span, loopControl(loop))
      else:
        var body = default(ArmBlock)
        for index in 0..<span.len:
          let op = span.operation(index)
          emitArmOperation(body, op.opcode, op.slots, op.immediate)
        image = armInstructions(body)
        image.add(0xd65f03c0'u32) # RET X30: return via link register without a stack frame.
      if image.len > NativeImageByteLimit div 4: return # Prove multiplication before computing byte extent.
      let count = image.len*4
    # Both adapters report into the same common complete-image byte ceiling.
    if count == 0 or count > NativeImageByteLimit: return
    let handle = createNativeArena()
    if handle == nil: return
    let offset = arenaPublish(handle, addr image[0], uint32(image.len))
    if offset < 0:
      arenaRelease(handle)
      return
    result = NativeImage(handle: handle, offset: uint32(offset), bytesValue: uint64(count),
      kindValue: loop.kind)

proc enterNative*(image: NativeImage, registers: var RegisterFile) =
  ## Borrow only the current register file; a pure image must complete, and is never replayed after effects.
  assert image.handle != nil and image.kind == NativeKind.PurePrefix
  when defined(pvmX86Jit) or defined(pvmArm64Jit):
    assert arenaCall(image.handle, image.offset, addr registers[0]) == 1

proc enterNativeLoop*(image: NativeImage, registers: var RegisterFile,
    context: var NativeLoopContext): uint32 =
  ## The region wrapper borrows two buffers for this call only.
  assert sizeof(RegisterFile) == 104 and sizeof(NativeLoopContext) == 24
  if image.handle == nil or image.kind != NativeKind.ClosedRegisterLoop: abortNativeReceipt()
  when defined(pvmX86Jit) or defined(pvmArm64Jit):
    arenaRegion(image.handle, image.offset, addr registers[0], addr context)
  else:
    abortNativeReceipt()

proc lowerNativeRegisterRing*(ring: NativeRegisterRing): NativeImage =
  ## Validate and publish one bounded pure image in the selected platform arena.
  result = default(NativeImage)
  if not nativePlatformSupported() or not ring.complete: return
  when defined(pvmX86Jit) or defined(pvmArm64Jit):
    when defined(pvmX86Jit):
      var encoded = encodeX86RegisterRing(ring)
      const unitBytes = 1
    else:
      var encoded = encodeArmRegisterRing(ring)
      const unitBytes = 4
    let count = encoded.len
    if count == 0 or count > NativeImageByteLimit div unitBytes: return
    let handle = createNativeArena()
    if handle == nil: return
    let offset = arenaPublish(handle, addr encoded[0], uint32(count))
    if offset < 0:
      arenaRelease(handle)
      return
    result = NativeImage(handle: handle, offset: uint32(offset), bytesValue: uint64(
        count*unitBytes),
      kindValue: NativeKind.RegisterRing)
    when NativeCheckedReadEnabled:
      result.ringValue = ring

func nativeRegisterRingCertificate*(image: NativeImage): NativeRegisterRing =
  ## Only the published image owns the exact certificate used by its entry receipt.
  when NativeCheckedReadEnabled:
    if image.ready and image.kind == NativeKind.RegisterRing: return image.ringValue
  default(NativeRegisterRing)

func nativeRegisterRingRotation*(image: NativeImage, header: uint32): uint64 =
  ## Select the bound entry without copying the full certificate on the execution path.
  when NativeCheckedReadEnabled:
    if image.ready and image.kind == NativeKind.RegisterRing:
      for index in 0..2:
        if image.ringValue.blocks[index].header == header: return uint64(index)
  high(uint64)

when NativeCheckedReadEnabled and defined(pvmX86Jit) and defined(pvmX86ResidentProof):
  proc ringAbiNative(handle: nil pointer, offset: uint32,
      registers, context: pointer): uint64 {.cdecl, importc: "pvm_x86_ring_abi_proof",
      header: "x86_resident_access_proof.h".}
    ## The private proof checks actual SysV preservation without changing the Ring receipt.

proc enterNativeRegisterRing*(image: NativeImage, registers: var RegisterFile,
    context: var NativeRingContext): uint32 =
  ## Validate rotation before borrowing state and verify the complete receipt before returning.
  assert sizeof(RegisterFile) == 104 and sizeof(NativeRingContext) == 48
  if not image.ready or image.kind != NativeKind.RegisterRing or
      context.entry > 2 or context.visits != [0'u64, 0, 0]:
    abortNativeReceipt()
  when NativeCheckedReadEnabled:
    let entry = NativeRingIndex(context.entry)
    let gas = context.gas
    let remaining = context.remaining
    when defined(pvmX86Jit) and defined(pvmX86ResidentProof):
      # The maintained x86 matrix enters the real published image through the ABI canary.
      let tagged = ringAbiNative(image.handle, image.offset, addr registers[0], addr context)
      assert tagged shr 32 == 1
      result = uint32(tagged and 0xffffffff'u64)
    else:
      result = arenaRegion(image.handle, image.offset, addr registers[0], addr context)
    if not validRingReceipt(image.ringValue, entry, result, gas, remaining, context, registers):
      abortNativeReceipt()
  else:
    abortNativeReceipt()

when NativeCheckedReadEnabled:
  func isReadBody*(image: NativeImage): bool =
    ## The installed ABI tag is meaningful only for a published image.
    image.ready and image.kind == NativeKind.CheckedReadBody

  proc lowerNativeReadBody*(body: NativeReadBody): NativeImage =
    ## Publish one checked read leaf through the selected arena and preserve the shared image tag.
    result = default(NativeImage)
    if not nativePlatformSupported() or not body.complete: return
    when defined(pvmX86Jit):
      # The x86 arena accepts a byte stream and its byte count.
      var encoded = x86CheckedReadInstructions(body)
      const unitBytes = 1
    else:
      # The ARM64 arena retains its original word stream and word count.
      var encoded = armCheckedReadInstructions(body)
      const unitBytes = 4
    let count = encoded.len
    if count == 0 or count > NativeImageByteLimit div unitBytes: return
    let handle = createNativeArena()
    if handle == nil: return
    let offset = arenaPublish(handle, addr encoded[0], uint32(count))
    if offset < 0:
      arenaRelease(handle)
      return
    result = NativeImage(handle: handle, offset: uint32(offset),
      bytesValue: uint64(count)*uint64(unitBytes), kindValue: NativeKind.CheckedReadBody)

  when defined(pvmX86Jit) and defined(pvmX86ResidentProof):
    proc checkedReadAbiNative(handle: nil pointer, offset: uint32,
        registers, context: pointer): uint64 {.cdecl, importc: "pvm_x86_checked_read_abi_proof",
        header: "x86_resident_access_proof.h".}

    proc enterNativeReadBodyAbiProof*(image: NativeImage, registers: var RegisterFile,
        context: var NativeReadContext): bool {.noinline.} =
      ## Check all six saved hardware registers around the actual two-borrow ABI.
      assert isReadBody(image)
      assert sizeof(NativeReadRegion) == 24 and sizeof(NativeReadContext) == 72
      let tagged = checkedReadAbiNative(image.handle, image.offset, addr registers[0], addr context)
      assert tagged shr 32 == 1
      let status = uint32(tagged and 0xffffffff'u64)
      assert status == NativeReadSuccess or status == NativeReadRefusal
      status == NativeReadSuccess

  proc enterNativeReadBody*(image: NativeImage, registers: var RegisterFile,
      context: var NativeReadContext): bool =
    ## A complete read body publishes registers once. A refused entry preserves the entire file.
    if not isReadBody(image): return false
    assert sizeof(NativeReadRegion) == 24 and sizeof(NativeReadContext) == 72
    let status = arenaRegion(image.handle, image.offset, addr registers[0], addr context)
    if status != NativeReadSuccess and status != NativeReadRefusal: abortNativeReceipt()
    status == NativeReadSuccess

when NativeReadCycleEnabled:
  proc lowerNativeMixedLoops*(candidates: NativeMixedLoopSet, refused: var uint8,
      pairRefused: var bool): NativeImage =
    ## Publish accepted source slots into one immutable arena before returning its owner.
    ## Individual bad encodings set refusal bits. An aggregate size refusal skips
    ## that ranked leaf and sets only pairRefused; later leaves still fit greedily.
    ## Allocation or append failures release the whole arena and remain retryable.
    ## Encoding lengths and alignment depend on the target ISA: identical admitted
    ## source sets can occupy different subsets under the same byte cap. Original
    ## rank indices remain stable; a skipped leaf does not prevent later smaller
    ## leaves from fitting. Only the returned occupancy mask authorizes entry.
    result = default(NativeImage)
    refused = 0
    pairRefused = false
    if candidates.count == 0 or candidates.count > uint8(NativeMixedLoopEntryLimit): return
    if not candidates.complete:
      refused = uint8((1'u32 shl int(candidates.count))-1)
      return
    when defined(pvmX86Jit):
      const unitBytes = 1
      const alignment = 16
      var encodings = default(array[NativeMixedLoopEntryLimit, seq[byte]])
    else:
      const unitBytes = 4
      const alignment = 4
      var encodings = default(array[NativeMixedLoopEntryLimit, seq[uint32]])
    var offsets = default(array[NativeMixedLoopEntryLimit, uint32])
    var lengths = default(array[NativeMixedLoopEntryLimit, uint32])
    var entries = 0'u8
    var used = 0
    for index in 0..<int(candidates.count):
      let proof {.cursor.} = candidates.proofs[index]
      template operations: untyped = proof.operations.toOpenArray(0, int(proof.count)-1)
      when defined(pvmX86Jit):
        encodings[index] = if proof.paidGuards != 0:
            x86PaidMixedLoopInstructions(operations, proof.paidGuards)
          else: x86MixedLoopInstructions(operations)
      else:
        encodings[index] = if proof.paidGuards != 0:
            armPaidMixedLoopInstructions(operations, proof.paidGuards)
          else: armMixedLoopInstructions(operations)
      let count = encodings[index].len
      if count == 0 or count > NativeImageByteLimit div unitBytes:
        refused = refused or (1'u8 shl index)
      else:
        # Both multiplication and alignment stay bounded before arithmetic or narrowing.
        let length = count*unitBytes
        let offset = (used+alignment-1) and not (alignment-1)
        if offset > NativeImageByteLimit-length:
          pairRefused = true
        else:
          offsets[index] = uint32(offset)
          lengths[index] = uint32(length)
          entries = entries or (1'u8 shl index)
          used = offset+length
    if entries == 0: return
    let handle = createNativeArena()
    if handle == nil: return
    for index in 0..<int(candidates.count):
      if (entries and (1'u8 shl index)) != 0:
        let count = uint32(encodings[index].len)
        let offset = arenaPublish(handle, addr encodings[index][0], count)
        if offset < 0:
          # The image is usable only after every accepted leaf has been published.
          arenaRelease(handle)
          return
        assert uint32(offset) == offsets[index]
    result = NativeImage(handle: handle, bytesValue: uint64(used),
      kindValue: NativeKind.MixedSelfLoop, mixedOffsets: offsets,
      mixedLengths: lengths, mixedEntries: entries)

  proc lowerNativeMixedLoop*(proof: NativeMixedLoop, refused: var bool): NativeImage =
    ## Preserve the one-leaf caller contract through the shared immutable publisher.
    let candidates = singleNativeMixedLoop(proof)
    var failures = 0'u8
    var pairRefused = false
    result = lowerNativeMixedLoops(candidates, failures, pairRefused)
    refused = (failures and 1) != 0

  func nativeMixedLoopEntries*(image: NativeImage): uint8 =
    ## Zero denotes an absent image. Occupied bits retain the original ranked proof slots.
    if image.ready and image.kind == NativeKind.MixedSelfLoop: image.mixedEntries
    else: 0'u8

  when defined(pvmMixedLoopWitness):
    func witnessNativeMixedLoopGeometry*(image: NativeImage, index: uint8): tuple[offset,
        length: uint32] =
      ## Copied byte coordinates identify one occupied proof slot without granting a new image borrow.
      assert index < uint8(NativeMixedLoopEntryLimit) and
        (nativeMixedLoopEntries(image) and (1'u8 shl int(index))) != 0
      (offset: image.mixedOffsets[int(index)], length: image.mixedLengths[int(index)])

  proc enterNativeMixedLoopAt*(image: NativeImage, index: uint8, registers: var RegisterFile,
      context: var NativeMixedLoopContext): uint32 =
    ## Enter only a published slot under the shared image borrow and its exact certificate.
    ## Entry offsets are immutable after publication. Both buffers remain invocation-local.
    assert sizeof(NativeMixedLoopContext) == NativeMixedLoopContextBytes and
      sizeof(RegisterFile) == 104
    if index >= uint8(NativeMixedLoopEntryLimit) or (nativeMixedLoopEntries(image) and (
        1'u8 shl int(index))) == 0:
      abortNativeReceipt()
    let offset = image.mixedOffsets[int(index)]
    assert uint64(offset)+uint64(image.mixedLengths[int(index)]) <= image.codeBytes
    arenaRegion(image.handle, offset, addr registers[0], addr context)

  proc enterNativeMixedLoop*(image: NativeImage, registers: var RegisterFile,
      context: var NativeMixedLoopContext): uint32 =
    ## The runtime lease owns the image while this call borrows only the active frame.
    enterNativeMixedLoopAt(image, 0, registers, context)

  proc lowerNativeReadCycle*(cycle: NativeReadCycle): NativeImage =
    ## Publish one complete region under its own ABI and image size limit.
    ## The lowerers retain their original probes when the Store proof exceeds the
    ## ceiling. Publication checks the complete image again, including the return.
    result = default(NativeImage)
    if not nativePlatformSupported() or not cycle.read.complete: return
    when defined(pvmX86Jit):
      var encoded = x86ReadCycleInstructions(cycle)
      const unitBytes = 1
    else:
      var encoded = armReadCycleInstructions(cycle)
      const unitBytes = 4
    let count = encoded.len
    if count == 0 or count > NativeImageByteLimit div unitBytes: return
    let handle = createNativeArena()
    if handle == nil: return
    let offset = arenaPublish(handle, addr encoded[0], uint32(count))
    if offset < 0:
      arenaRelease(handle)
      return
    result = NativeImage(handle: handle, offset: uint32(offset),
      bytesValue: uint64(count) * uint64(unitBytes), kindValue: NativeKind.ConnectedReadCycle)

  proc enterNativeReadCycle*(image: NativeImage, registers: var RegisterFile,
      context: var NativeCycleContext): uint32 =
    ## The region borrows the same private memory and register file for this call alone.
    assert sizeof(NativeCycleContext) == NativeCycleContextBytes and sizeof(RegisterFile) == 104
    if not image.ready or image.kind != NativeKind.ConnectedReadCycle: abortNativeReceipt()
    arenaRegion(image.handle, image.offset, addr registers[0], addr context)

  when defined(pvmX86Jit) and defined(pvmX86ResidentProof):
    proc enterNativeReadCycleAbiProof*(image: NativeImage, registers: var RegisterFile,
        context: var NativeCycleContext): uint32 =
      ## Check all six SysV preserved registers around the actual connected entry.
      assert sizeof(NativeCycleContext) == NativeCycleContextBytes and sizeof(RegisterFile) == 104
      if not image.ready or image.kind != NativeKind.ConnectedReadCycle: abortNativeReceipt()
      let tagged = checkedReadAbiNative(image.handle, image.offset, addr registers[0], addr context)
      assert tagged shr 32 == 1
      uint32(tagged and 0xffffffff'u64)

    when defined(pvmReadCycleCreditWitness):
      proc copyReadCycleRx(handle: nil pointer, offset: uint32,
          output: ptr byte, count: uint32): cint {.cdecl,
          importc: "pvm_x86_resident_copy_proof", header: "x86_resident_access_proof.h".}
        ## Reuse the existing checked copy from the published executable alias.

      proc enterNativeReadCycleAbiProof*(image: NativeImage, registers: var RegisterFile,
          context: var NativeCycleContext, expected: openArray[byte]): uint32 =
        ## Verify the exact published bytes before entering that same owner with the SysV sentinel.
        assert image.ready and image.kind == NativeKind.ConnectedReadCycle
        assert expected.len > 0 and expected.len <= NativeImageByteLimit
        assert uint64(expected.len) == image.codeBytes
        var actual = default(array[NativeImageByteLimit, byte])
        assert copyReadCycleRx(image.handle, image.offset, addr actual[0], uint32(expected.len)) == 1
        for index in 0..<expected.len:
          # No native call happens until the complete executable extent matches the emission.
          assert actual[index] == expected[index]
        enterNativeReadCycleAbiProof(image, registers, context)
