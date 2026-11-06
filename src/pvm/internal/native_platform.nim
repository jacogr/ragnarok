# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Thin machine lowering and OS executable-memory mechanics. Admission/lifecycle policy lives in native_pipeline.

import std/assertions
import ../machine
import ./native_ir
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

type NativeImage* = object ## Exclusive published pure image. The complete owning value moves between threads.
  handle: nil pointer
  offset: uint32
  bytesValue: uint64

proc `=copy`*(destination: var NativeImage, source: NativeImage) {.error.}
  ## Executable authority cannot be duplicated by copying its POD handle.
proc `=dup`*(source: NativeImage): NativeImage {.error.}
  ## Exactly one image owner releases the mapping.
proc `=wasMoved`*(image: var NativeImage) {.nodestroy, inline.} =
  ## Primitive move hooks do not clear raw pointers; disarm explicitly.
  image.handle = nil
  image.offset = 0
  image.bytesValue = 0
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

proc lowerNative*(span: NativeSpan): NativeImage =
  ## Called ONLY by the compiler worker: private emission, mapping and coherency finish before return.
  result = default(NativeImage)
  if not nativePlatformSupported() or span.len == 0: return
  when defined(pvmX86Jit) or defined(pvmArm64Jit):
    when defined(pvmX86Jit):
      var body = default(X86Block)
      for index in 0..<span.len:
        let op = span.operation(index)
        emitX86Operation(body, op.opcode, op.slots, op.immediate)
      var image = takeX86Instructions(body)
      image.add(0xc3'u8) # RET: pop caller's return RIP; pure leaf uses only SysV caller-saved registers.
      let count = image.len
    else:
      var body = default(ArmBlock)
      for index in 0..<span.len:
        let op = span.operation(index)
        emitArmOperation(body, op.opcode, op.slots, op.immediate)
      var image = armInstructions(body)
      image.add(0xd65f03c0'u32) # RET X30: return through caller's link register; no stack frame or saved registers.
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
    result = NativeImage(handle: handle, offset: uint32(offset), bytesValue: uint64(count))

proc enterNative*(image: NativeImage, registers: var RegisterFile) =
  ## Borrow only the current register file; a pure image must complete, and is never replayed after effects.
  assert image.handle != nil
  when defined(pvmX86Jit) or defined(pvmArm64Jit):
    assert arenaCall(image.handle, image.offset, addr registers[0]) == 1
