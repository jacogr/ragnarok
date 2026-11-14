# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included by the x86 emitter beside the existing exact guarded memory operations.
## Every external entry loads the same graph-wide guest bank and exact budgets. Linked edges
## preserve those registers, the context borrow and the XMM7 visit count. The log append follows
## the horizon/gas/quota guards. All paid/unpaid returns share one commit/restore epilogue.

when declared(X86Block):
  type X86FusionEncoding* = object
    ## Edge coordinates name the rel32 operand. The internal entry skips the SysV prologue.
    bytes*: seq[byte]
    inner*: int
    edges*: array[2, int]

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

  proc x86FusionReturn(code: var X86Block, fixes: var seq[X86CycleFixup],
      next: uint32, paid: bool) =
    ## Select the checked continuation and mode before the common bank/ledger publication.
    readCycleContextOp(code, [0x49'u8, 0xc7, 0x82], NativeFusionPaidOffset)
    cycleWord(code, uint32(ord(paid)))
    put(code, [0xb8'u8]) # MOV EAX,checked continuation.
    cycleWord(code, next)
    cycleEdge(code, fixes, 0, 4) # One block-local epilogue owns every restoration path.

  proc encodeX86Fusion*(item: NativeFusionBlock, token: int,
      access: X86FusionAccess): X86FusionEncoding =
    ## Reserve bounded buffers before emitting the source body or any fixup.
    const
      operationBytes = 240
      operationFixes = 16
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
    let count = int(item.terminal-item.header)-1
    var code = default(X86Block)
    code.bytes = newSeqOfCap[byte](NativeImageByteLimit)
    if code.bytes.rawData == nil: return
    # Three reservation guards, three conditional/static edges and three return stubs
    # need nine fixed slots even for a predicate-only block; body guards include their own stubs.
    var fixes = newSeqOfCap[X86CycleFixup](count*operationFixes+10)
    if fixes.rawData == nil: return
    var labels = default(X86MixedLoopLabels)
    var nextLabel = firstGuard+byte(count)
    beginX86Fusion(code, access)
    put(code, [0x49'u8, 0x89, 0xf2]) # MOV R10,RSI retains the call-local context.
    readCycleContextOp(code, [0x4d'u8, 0x8b, 0x8a], NativeFusionGasOffset) # MOV R9,[R10+gas].
    readCycleContextOp(code, [0x4d'u8, 0x8b, 0x9a], NativeFusionQuotaOffset) # MOV R11,[R10+quota].
    put(code, [0x66'u8, 0x0f, 0xef, 0xff]) # PXOR XMM7,XMM7 initializes the call-local count.
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
    for index in 0..<count:
      if code.bytes.len > NativeImageByteLimit-operationBytes: return
      let op = item.operations[index]
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
    if item.targets[0] == NativeEntryFailure:
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
    result = X86FusionEncoding(bytes: takeX86Instructions(code), inner: inner, edges: edges)
