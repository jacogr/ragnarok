# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Thin machine lowering and OS executable-memory mechanics. Admission/lifecycle policy lives in native_pipeline.

import std/assertions
import ../machine
import ./[native_ir, native_control]
import ./native_read_body
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

when NativeCheckedReadEnabled:
  func isReadBody*(image: NativeImage): bool =
    ## The installed ABI tag is meaningful only for a published image.
    image.ready and image.kind == NativeKind.CheckedReadBody

  proc lowerNativeReadBody*(body: NativeReadBody): NativeImage =
    ## Lower the copied certificate and publish it through the selected ARM64 arena.
    result = default(NativeImage)
    if not nativePlatformSupported() or not body.complete: return
    var words = armCheckedReadInstructions(body)
    let count = words.len
    if count == 0 or count > NativeImageByteLimit div 4: return
    let handle = createNativeArena()
    if handle == nil: return
    let offset = arenaPublish(handle, addr words[0], uint32(count))
    if offset < 0:
      arenaRelease(handle)
      return
    result = NativeImage(handle: handle, offset: uint32(offset), bytesValue: uint64(count)*4,
      kindValue: NativeKind.CheckedReadBody)

  proc enterNativeReadBody*(image: NativeImage, registers: var RegisterFile,
      context: var NativeReadContext): bool =
    ## A complete read body publishes registers once. A refused entry preserves the entire file.
    if not isReadBody(image): return false
    assert sizeof(NativeReadRegion) == 24 and sizeof(NativeReadContext) == 72
    let status = arenaRegion(image.handle, image.offset, addr registers[0], addr context)
    if status != NativeReadSuccess and status != NativeReadRefusal: abortNativeReceipt()
    status == NativeReadSuccess
