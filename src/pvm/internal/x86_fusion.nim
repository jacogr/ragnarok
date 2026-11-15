# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included by the x86 emitter beside the existing exact guarded memory operations.
## Every external entry loads the same graph-wide guest bank and exact budgets. Linked edges
## preserve those registers, the context borrow and the XMM7 visit count. The log append follows
## the horizon/gas/quota guards. All paid/unpaid returns share one commit/restore epilogue.
## Optional bounded same-kind memory groups share one true-view/dirty proof at their first source
## site. XMM9 retains the host pointer across scalar scratch use; it never survives a native call.

when declared(X86Block):
  type X86FusionEncoding* = object
    ## Edge coordinates name the rel32 operand. The internal entry skips the SysV prologue.
    bytes*: seq[byte]
    inner*: int
    edges*: array[2, int]
    table*: int ## rel32 operand for the immutable native header table; negative when unused.

  proc x86WindowPatch(code: var X86Block, at, target: int): bool =
    ## Patch a local staging displacement without consuming the enclosing label table.
    if at < 0 or at > code.bytes.len-4 or target < 0 or target > code.bytes.len: return false
    let delta = int64(target)-int64(at+4)
    if delta < -int64(NativeImageByteLimit) or delta > int64(NativeImageByteLimit): return false
    let value = cast[uint32](int32(delta))
    for index in 0..<4:
      code.bytes[at+index] = byte((value shr (index*8)) and 255)
    true

  proc x86WindowBranch(code: var X86Block, condition: byte): int =
    ## Reserve one local rel32 edge; zero selects an unconditional branch.
    if condition == 0: put(code, [0xe9'u8])
    else: put(code, [0x0f'u8, condition])
    result = code.bytes.len
    cycleWord(code, 0)

  proc x86WindowAddress(code: var X86Block, window: NativeMemoryWindow,
      access: X86FusionAccess): bool =
    ## EDX captures the original modulo-32 minimum before any source operation mutates its base.
    if window.absolute:
      put(code, [0xba'u8]) # MOV EDX,absolute32.
    else:
      if window.baseLane < 0 or window.baseLane > 12: return false
      readBodyBase(code, access, range[0..12](window.baseLane))
      put(code, [0x81'u8, 0xc2]) # ADD EDX,disp32 wraps the original address once.
    cycleWord(code, window.displacement)
    true

  proc x86WindowRegions(code: var X86Block, fixes: var seq[X86CycleFixup],
      window: NativeMemoryWindow, refusal: byte): bool =
    ## Accept only the first nonempty intersecting true-length view, declining partial overlap.
    ## RDX remains the virtual minimum; XMM9 retains the proved host pointer across scalar work.
    let writing = window.kind == NativeWindowKind.Write
    let regions = if writing: 2 else: 3
    let first = if writing: NativeCycleWritableOffset else: 0
    let stride = if writing: sizeof(NativeCycleWritable) else: sizeof(NativeReadRegion)
    var accepted = default(array[3, int])
    for region in 0..<regions:
      # Empty descriptors have no precedence; malformed nonempty nil views stay checked.
      let offset = first+region*stride
      readCycleContextOp(code, [0x49'u8, 0x8b, 0x82], offset)
      readCycleContextOp(code, [0x49'u8, 0x8b, 0x8a], offset+8)
      readCycleContextOp(code, [0x49'u8, 0x8b, 0xb2], offset+16)
      put(code, [0x48'u8, 0x85, 0xc9]) # TEST RCX,RCX checks true length.
      let empty = x86WindowBranch(code, 0x84)
      put(code, [0x48'u8, 0x85, 0xf6]) # TEST RSI,RSI checks the borrowed data.
      cycleEdge(code, fixes, 0x84, refusal)
      put(code, [0x48'u8, 0x39, 0xd0]) # CMP RAX,RDX checks a later start.
      let before = x86WindowBranch(code, 0x87)
      put(code, [0x49'u8, 0x89, 0xd0, 0x49, 0x29, 0xc0, 0x49, 0x39, 0xc8])
      let outside = x86WindowBranch(code, 0x83) # R8 is region-relative minimum; JAE skips it.
      put(code, [0x4c'u8, 0x29, 0xc1, 0x48, 0x81, 0xf9]) # SUB RCX,R8; CMP RCX,span.
      cycleWord(code, window.span)
      cycleEdge(code, fixes, 0x82, refusal)
      put(code, [0x49'u8, 0x01, 0xf0, 0x66, 0x4d, 0x0f, 0x6e, 0xc8])
      accepted[region] = x86WindowBranch(code, 0) # ADD R8,RSI; MOVQ XMM9,R8.
      let earlier = code.bytes.len
      put(code, [0x48'u8, 0x29, 0xd0, 0x48, 0x3d]) # SUB RAX,RDX; CMP RAX,span.
      cycleWord(code, window.span)
      cycleEdge(code, fixes, 0x82, refusal)
      let following = code.bytes.len
      if not x86WindowPatch(code, empty, following) or
          not x86WindowPatch(code, before, earlier) or
          not x86WindowPatch(code, outside, following): return false
    cycleEdge(code, fixes, 0, refusal)
    for region in 0..<regions:
      # Every successful proof bypasses later descriptors and the common refusal.
      if not x86WindowPatch(code, accepted[region], code.bytes.len): return false
    true

  proc x86FusionWindowGuard(code: var X86Block, fixes: var seq[X86CycleFixup],
      window: NativeMemoryWindow, refusal: byte, access: X86FusionAccess): bool =
    ## Prove bounds and already-dirty authority before the first original transfer.
    ## A failed whole-window proof returns paid at that site without moving any source effect.
    if not window.ready or window.span == 0 or window.span > 4096 or
        window.baseLane < 0 or window.baseLane > 12: return false
    if not x86WindowAddress(code, window, access): return false
    put(code, [0x81'u8, 0xfa]) # CMP EDX,65536 protects the low pages.
    cycleWord(code, 65536)
    cycleEdge(code, fixes, 0x82, refusal)
    put(code, [0x81'u8, 0xfa]) # CMP EDX,UINT32_MAX-span excludes wrap and the top byte.
    cycleWord(code, 0xffffffff'u32-window.span)
    cycleEdge(code, fixes, 0x87, refusal)
    if window.kind == NativeWindowKind.Write:
      # Dirty guards only read the bitmap. At most two pages can intersect a 4 KiB span.
      readCycleContextOp(code, [0x49'u8, 0x8b, 0xb2], NativeCycleDirtyOffset)
      put(code, [0x48'u8, 0x85, 0xf6])
      cycleEdge(code, fixes, 0x84, refusal)
      readCycleDirtyPage(code, fixes, refusal)
      put(code, [0x89'u8, 0xd0, 0x05]) # MOV EAX,EDX; ADD EAX,span-1.
      cycleWord(code, window.span-1)
      put(code, [0x31'u8, 0xd0, 0xa9]) # XOR EAX,EDX; TEST EAX,upper page bits.
      cycleWord(code, 0xfffff000'u32)
      let samePage = x86WindowBranch(code, 0x84)
      put(code, [0x81'u8, 0xc2]) # ADD EDX,span-1 selects the last byte's page.
      cycleWord(code, window.span-1)
      readCycleDirtyPage(code, fixes, refusal)
      if not x86WindowAddress(code, window, access): return false
      if not x86WindowPatch(code, samePage, code.bytes.len): return false
    x86WindowRegions(code, fixes, window, refusal)

  proc x86FusionWindowOperation(code: var X86Block, op: NativeOperation,
      window: NativeMemoryWindow, access: X86FusionAccess): bool =
    ## Preserve exact source width/sign and restore R8 after scalar emitters may clobber it.
    let encoding = nativeWindowOpcode(op.opcode)
    if encoding < 120 or encoding > 130: return false
    let width = indirectMemoryAccess(range[120..130](encoding)).width
    let delta = uint32(op.immediate and 0xffffffff'u64)-window.displacement
    if delta >= window.span or width > window.span-delta: return false
    put(code, [0x66'u8, 0x4d, 0x0f, 0x7e, 0xc8]) # MOVQ R8,XMM9.
    if encoding <= 123: readAccess(code, access, op.slots.aIndex, false)
    case encoding
    of 120: put(code, [0x41'u8, 0x88, 0x80])
    of 121: put(code, [0x66'u8, 0x41, 0x89, 0x80])
    of 122: put(code, [0x41'u8, 0x89, 0x80])
    of 123: put(code, [0x49'u8, 0x89, 0x80])
    of 124: put(code, [0x41'u8, 0x0f, 0xb6, 0x80])
    of 125: put(code, [0x49'u8, 0x0f, 0xbe, 0x80])
    of 126: put(code, [0x41'u8, 0x0f, 0xb7, 0x80])
    of 127: put(code, [0x49'u8, 0x0f, 0xbf, 0x80])
    of 128: put(code, [0x41'u8, 0x8b, 0x80])
    of 129: put(code, [0x49'u8, 0x63, 0x80])
    else: put(code, [0x49'u8, 0x8b, 0x80])
    cycleWord(code, delta)
    if encoding >= 124: writeAccess(code, access, op.slots.aIndex)
    true

  proc patchFusionEdge*(code: var X86FusionEncoding, edge, deltaBytes: int): bool =
    ## Store an arena-relative displacement measured from the rel32 operand.
    if edge notin 0..1 or deltaBytes < -NativeFusionImageLimit or
        deltaBytes > NativeFusionImageLimit: return false
    let at = code.edges[edge]
    if at < 0 or at > code.bytes.len-4: return false
    let relative = cast[uint32](int32(deltaBytes-4))
    for index in 0..<4:
      code.bytes[at+index] = byte((relative shr (index*8)) and 255)
    true

  proc patchFusionTable*(code: var X86FusionEncoding, deltaBytes: int): bool =
    ## RIP-relative addressing stays inside the bounded image; executable addresses never escape.
    if code.table < 0 or code.table > code.bytes.len-4 or
        deltaBytes < -NativeFusionImageLimit or deltaBytes > NativeFusionImageLimit: return false
    let value = cast[uint32](int32(deltaBytes-4))
    for index in 0..<4: code.bytes[code.table+index] = byte((value shr (index*8)) and 255)
    true

  proc x86FusionIndirect(code: var X86Block, fixes: var seq[X86CycleFixup],
      labels: var X86MixedLoopLabels, item: NativeFusionBlock, access: X86FusionAccess): int =
    ## Resolve only checked source tags and immutable internal entries before a load/jump mutation.
    ## RAX/RCX/RDX/RSI/R8 are scratch; XMM8 retains the wrapped pre-write address.
    let branch = item.branch
    readAccess(code, access, (if branch.opcode == 50: branch.slots.aIndex else: branch.slots.bIndex), false)
    put(code, [0x89'u8, 0xc0]) # MOV EAX,EAX discards the upper guest address word.
    if item.indirectDelta != 0:
      put(code, [0x05'u8]) # ADD EAX,delta32.
      cycleWord(code, item.indirectDelta)
    put(code, [0xa9'u8, 1, 0, 0, 0]) # TEST EAX,1.
    cycleEdge(code, fixes, 0x85, 1)
    put(code, [0x85'u8, 0xc0]) # TEST EAX,EAX.
    cycleEdge(code, fixes, 0x84, 1)
    put(code, [0x3d'u8]) # CMP EAX,halt sentinel.
    cycleWord(code, 0xffff0000'u32)
    cycleEdge(code, fixes, 0x84, 1)
    readCycleContextOp(code, [0x49'u8, 0x8b, 0xb2], NativeFusionJumpsOffset)
    put(code, [0x48'u8, 0x85, 0xf6]) # TEST RSI,RSI.
    cycleEdge(code, fixes, 0x84, 1)
    put(code, [0x89'u8, 0xc1, 0xd1, 0xe9, 0x8d, 0x51, 255, 0x81, 0xe2])
    cycleWord(code, uint32(DynamicJumpCacheMask)) # ECX is the full tag; EDX selects its host bucket.
    put(code, [0x48'u8, 0x8b, 0x14, 0xd6, 0x48, 0x89, 0xd6, 0x48, 0xc1, 0xee, 32, 0x39, 0xce])
    cycleEdge(code, fixes, 0x85, 1) # A mismatched tag never authorizes a native destination.
    put(code, [0x66'u8, 0x44, 0x0f, 0x6e, 0xc0, 0x89, 0xd0, 0x4c, 0x8d, 0x05])
    result = code.bytes.len
    cycleWord(code, 0) # LEA R8,[RIP+table] is patched after staging.
    put(code, [0x69'u8, 0xf0])
    cycleWord(code, 0x9e3779b9'u32)
    put(code, [0xc1'u8, 0xee, 23, 0xc1, 0xe6, 3]) # ESI hashes the header token to a byte offset.
    labels[3] = code.bytes.len
    put(code, [0x49'u8, 0x8b, 0x0c, 0x30, 0x85, 0xc9]) # Load entry, then test its low token first.
    cycleEdge(code, fixes, 0x84, 1)
    put(code, [0x39'u8, 0xc1])
    cycleEdge(code, fixes, 0x84, 2)
    put(code, [0x83'u8, 0xc6, 8, 0x81, 0xe6])
    cycleWord(code, 4095)
    cycleEdge(code, fixes, 0, 3)
    labels[2] = code.bytes.len
    put(code, [0x48'u8, 0xc1, 0xf9, 32, 0x4c, 0x01, 0xc1]) # Sign-extend delta; ADD RCX,R8.
    if branch.opcode == 180:
      immediate(code, 0xb8, item.indirectValue)
      writeAccess(code, access, branch.slots.aIndex)
    put(code, [0xff'u8, 0xe1]) # JMP RCX preserves the resident bank, original stack and budgets.

  proc x86FusionReturn(code: var X86Block, fixes: var seq[X86CycleFixup],
      next: uint32, paid: bool) =
    ## Select the checked continuation and mode before the common bank/ledger publication.
    readCycleContextOp(code, [0x49'u8, 0xc7, 0x82], NativeFusionPaidOffset)
    cycleWord(code, uint32(ord(paid)))
    put(code, [0xb8'u8]) # MOV EAX,checked continuation.
    cycleWord(code, next)
    cycleEdge(code, fixes, 0, 4) # One block-local epilogue owns every restoration path.

  proc encodeX86Fusion*(item: NativeFusionBlock, token: int,
      access: X86FusionAccess, useIndirect: bool): X86FusionEncoding =
    ## Reserve bounded buffers before emitting the source body or any fixup.
    const
      operationBytes = 240
      operationFixes = 16
      windowBytes = 512 # Includes both dirty guards, three views and the first transfer.
      returnBytes = 21
      epilogueBytes = 112
      unpaid = 0'u8
      noEdge = 1'u8
      yesEdge = 2'u8
      taken = 3'u8
      finish = 4'u8
      firstGuard = 5'u8
    result = default(X86FusionEncoding)
    if not item.complete or token < 1 or token > NativeFusionBlockLimit: return
    if item.indirect and not useIndirect and item.terminal == item.header+1: return
    let count = int(item.terminal-item.header)-1
    var code = default(X86Block)
    code.bytes = newSeqOfCap[byte](NativeImageByteLimit)
    if code.bytes.rawData == nil: return
    # Three reservation guards, three conditional/static edges and three return stubs
    # need nine fixed slots even for a predicate-only block; body guards include their own stubs.
    var fixes = newSeqOfCap[X86CycleFixup](count*operationFixes+(if useIndirect: 24 else: 10))
    if fixes.rawData == nil: return
    var labels = default(X86MixedLoopLabels)
    var nextLabel = firstGuard+byte(count)
    var table = -1
    beginX86Fusion(code, access)
    put(code, [0x49'u8, 0x89, 0xf2]) # MOV R10,RSI retains the call-local context.
    readCycleContextOp(code, [0x4d'u8, 0x8b, 0x8a], NativeFusionGasOffset) # MOV R9,[R10+gas].
    readCycleContextOp(code, [0x4d'u8, 0x8b, 0x9a], NativeFusionQuotaOffset) # MOV R11,[R10+quota].
    put(code, [0x66'u8, 0x0f, 0xef, 0xff]) # PXOR XMM7,XMM7 initializes the call-local count.
    if useIndirect: put(code, [0x66'u8, 0x45, 0x0f, 0xef, 0xc0]) # PXOR XMM8,XMM8 initializes private metadata.
    let inner = code.bytes.len
    put(code, [0x66'u8, 0x0f, 0x7e, 0xfe, 0x83, 0xfe, byte(
        NativeFusionVisitLimit)]) # MOVD ESI,XMM7; CMP ESI,horizon.
    cycleEdge(code, fixes, 0x83, unpaid)
    put(code, [0x49'u8, 0x83, 0xfb, byte(item.span)]) # CMP R11,span.
    cycleEdge(code, fixes, 0x82, unpaid)
    immediate(code, 0xb8, item.price)
    put(code, [0x49'u8, 0x39, 0xc1]) # CMP R9,RAX checks the original unsigned block price.
    cycleEdge(code, fixes, 0x82, unpaid)
    put(code, [0x49'u8, 0x29, 0xc1, 0x49, 0x83, 0xeb, byte(item.span)]) # SUB R9,RAX; SUB R11,span.
    put(code, [0x41'u8, 0xc6, 0x84, 0x32]) # MOV BYTE [R10+RSI+path],token.
    cycleWord(code, uint32(NativeFusionPathOffset))
    put(code, [byte(token), 0xff, 0xc6, 0x66, 0x0f, 0x6e, 0xfe]) # INC ESI; MOVD XMM7,ESI.
    var window = default(NativeMemoryWindow)
    for index in 0..<count:
      let op = item.operations[index]
      if nativeWindowOpcode(op.opcode) != 0 and index >= window.past:
        window = nativeMemoryWindow(item.operations, count, index)
        if window.ready and code.bytes.len > NativeImageByteLimit-windowBytes:
          # Optional geometry never removes ordinary lowering when the remaining entry is small.
          window = default(NativeMemoryWindow)
      if window.contains(index):
        if index == window.first:
          if not x86FusionWindowGuard(code, fixes, window, firstGuard+byte(index), access): return
        if code.bytes.len > NativeImageByteLimit-24 or
            not x86FusionWindowOperation(code, op, window, access): return
        continue
      if code.bytes.len > NativeImageByteLimit-operationBytes: return
      let width = nativeMixedLoopStoreWidth(op.opcode)
      let encoding = nativeReadEncodingOpcode(op.opcode)
      let guard = firstGuard+byte(index)
      if width != 0:
        mixedLoopStoreAccess(code, fixes, labels, op, byte(width), guard, nextLabel, access)
      elif nativeReadOpcode(encoding):
        mixedLoopLoadAccess(code, fixes, labels, op, encoding, guard, nextLabel, access)
      else:
        emitX86OperationAccess(code, access, op.opcode, op.slots, op.immediate)
    if code.bytes.len > NativeImageByteLimit-returnBytes*(3+countSetBits(
        item.guards))-epilogueBytes-64: return

    var edges = [-1, -1]
    if item.indirect and useIndirect:
      if code.bytes.len > NativeImageByteLimit-224-returnBytes*(2+countSetBits(
          item.guards))-epilogueBytes: return
      table = x86FusionIndirect(code, fixes, labels, item, access)
      labels[1] = code.bytes.len
      x86FusionReturn(code, fixes, item.terminal, true)
    elif item.targets[0] == NativeEntryFailure:
      x86FusionReturn(code, fixes, item.terminal, true)
    else:
      if item.branch.opcode == 80:
        let branch = item.branch
        immediate(code, 0xb8, branch.immediate)
        writeAccess(code, access, branch.slots.aIndex)
      if item.targets[1] != NativeEntryFailure:
        let branch = item.branch
        emitX86BranchAccess(code, access, branch.opcode, branch.slots, branch.immediate, 1, 0)
        put(code, [0x85'u8, 0xc0]) # TEST EAX,EAX.
        cycleEdge(code, fixes, 0x85, taken)
      cycleEdge(code, fixes, 0, noEdge)
      edges[0] = code.bytes.len-4
      if item.targets[1] != NativeEntryFailure:
        labels[int(taken)] = code.bytes.len
        cycleEdge(code, fixes, 0, yesEdge)
        edges[1] = code.bytes.len-4
      for edge in 0..1:
        if edges[edge] >= 0:
          labels[int(noEdge)+edge] = code.bytes.len
          x86FusionReturn(code, fixes, item.targets[edge], false)

    labels[int(unpaid)] = code.bytes.len
    x86FusionReturn(code, fixes, item.header, false)
    for index in 0..<count:
      if (item.guards and (1'u32 shl index)) != 0:
        labels[int(firstGuard)+index] = code.bytes.len
        x86FusionReturn(code, fixes, item.header+uint32(index)+1, true)
    labels[int(finish)] = code.bytes.len
    readCycleContextOp(code, [0x4d'u8, 0x89, 0x8a], NativeFusionGasOffset) # MOV [R10+gas],R9.
    readCycleContextOp(code, [0x4d'u8, 0x89, 0x9a], NativeFusionQuotaOffset) # MOV [R10+quota],R11.
    put(code, [0x66'u8, 0x0f, 0x7e, 0xfa]) # MOVD EDX,XMM7 returns the exact logged visit count.
    readCycleContextOp(code, [0x49'u8, 0x89, 0x92], NativeFusionVisitsOffset)
    if useIndirect:
      readCycleContextOp(code, [0x66'u8, 0x45, 0x0f, 0xd6, 0x82], NativeFusionAddressOffset)
    endX86Fusion(code, access)
    put(code, [0xc3'u8]) # RET after the complete checked state is published.
    if code.bytes.len > NativeImageByteLimit: return
    for fix in fixes:
      let target = labels[int(fix.target)]
      if target <= 0 or target >= code.bytes.len or fix.at < 0 or fix.at > code.bytes.len-4:
        return
      let relative = cast[uint32](int32(target-(fix.at+4)))
      for index in 0..<4:
        code.bytes[fix.at+index] = byte((relative shr (index*8)) and 255)
    result = X86FusionEncoding(bytes: takeX86Instructions(code), inner: inner, edges: edges, table: table)
