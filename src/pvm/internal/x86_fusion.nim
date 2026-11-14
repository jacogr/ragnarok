# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included by the x86 emitter beside the existing exact guarded memory operations.
## A linked edge preserves the same register-file borrow, context and path registers.

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

  proc x86FusionReturn(code: var X86Block, next: uint32, paid: bool) =
    ## Original gas and quota already live in the call context.
    readCycleContextOp(code, [0x4d'u8, 0x89, 0xa2], NativeFusionPathOffset)
    readCycleContextOp(code, [0x49'u8, 0xc7, 0x82], NativeFusionPaidOffset)
    cycleWord(code, uint32(ord(paid)))
    put(code, [0xb8'u8]) # MOV EAX,checked continuation.
    cycleWord(code, next)
    put(code, [0x41'u8, 0x5d, 0x41, 0x5c, 0xc3]) # POP R13; POP R12; RET.

  proc encodeX86Fusion*(item: NativeFusionBlock, token: int): X86FusionEncoding =
    ## Reserve bounded buffers before emitting the source body or any fixup.
    const
      operationBytes = 224
      operationFixes = 15
      returnBytes = 32
      unpaid = 0'u8
      noEdge = 1'u8
      yesEdge = 2'u8
      taken = 3'u8
      firstGuard = 4'u8
    result = default(X86FusionEncoding)
    if not item.complete or token < 1 or token > NativeFusionBlockLimit: return
    let count = int(item.terminal-item.header)-1
    var code = default(X86Block)
    code.bytes = newSeqOfCap[byte](NativeImageByteLimit)
    if code.bytes.rawData == nil: return
    var fixes = newSeqOfCap[X86CycleFixup](count*operationFixes+8)
    if fixes.rawData == nil: return
    var labels = default(X86MixedLoopLabels)
    var nextLabel = firstGuard+byte(count)
    let access = X86CanonicalAccess()

    put(code, [0x41'u8, 0x54, 0x41, 0x55]) # PUSH R12; PUSH R13.
    put(code, [0x49'u8, 0x89, 0xf2, 0x45, 0x31, 0xe4]) # MOV R10,RSI; XOR R12D,R12D.
    put(code, [0x41'u8, 0xbd]) # MOV R13D,visit limit.
    cycleWord(code, uint32(NativeFusionVisitLimit))
    let inner = code.bytes.len
    put(code, [0x45'u8, 0x85, 0xed]) # TEST R13D,R13D.
    cycleEdge(code, fixes, 0x84, unpaid)
    readCycleContextOp(code, [0x49'u8, 0x83, 0xba], NativeFusionQuotaOffset)
    put(code, [byte(item.span)]) # CMP [R10+quota],span.
    cycleEdge(code, fixes, 0x82, unpaid)
    immediate(code, 0xb8, item.price)
    readCycleContextOp(code, [0x49'u8, 0x39, 0x82], NativeFusionGasOffset)
    cycleEdge(code, fixes, 0x82, unpaid)
    readCycleContextOp(code, [0x49'u8, 0x29, 0x82], NativeFusionGasOffset)
    readCycleContextOp(code, [0x49'u8, 0x83, 0xaa], NativeFusionQuotaOffset)
    put(code, [byte(item.span)]) # SUB [R10+quota],span.
    put(code, [0x41'u8, 0xff, 0xcd, 0x49, 0xc1, 0xe4, 0x08]) # DEC R13D; SHL R12,8.
    put(code, [0x49'u8, 0x81, 0xcc]) # OR R12,token.
    cycleWord(code, uint32(token))
    for index in 0..<count:
      if code.bytes.len > NativeImageByteLimit-operationBytes: return
      let op = item.operations[index]
      let width = nativeMixedLoopStoreWidth(op.opcode)
      let encoding = nativeReadEncodingOpcode(op.opcode)
      let guard = firstGuard+byte(index)
      if width != 0:
        mixedLoopStore(code, fixes, labels, op, byte(width), guard, nextLabel)
      elif nativeReadOpcode(encoding):
        mixedLoopLoad(code, fixes, labels, op, encoding, guard, nextLabel)
      else:
        emitX86OperationAccess(code, access, op.opcode, op.slots, op.immediate)
    if code.bytes.len > NativeImageByteLimit-returnBytes*(3+countSetBits(item.guards))-64: return

    var edges = [-1, -1]
    if item.targets[0] == NativeEntryFailure:
      x86FusionReturn(code, item.terminal, true)
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
          x86FusionReturn(code, item.targets[edge], false)

    labels[int(unpaid)] = code.bytes.len
    x86FusionReturn(code, item.header, false)
    for index in 0..<count:
      if (item.guards and (1'u32 shl index)) != 0:
        labels[int(firstGuard)+index] = code.bytes.len
        x86FusionReturn(code, item.header+uint32(index)+1, true)
    for fix in fixes:
      let target = labels[int(fix.target)]
      if target <= 0 or target >= code.bytes.len or fix.at < 0 or fix.at > code.bytes.len-4:
        return
      let relative = cast[uint32](int32(target-(fix.at+4)))
      for index in 0..<4:
        code.bytes[fix.at+index] = byte((relative shr (index*8)) and 255)
    result = X86FusionEncoding(bytes: takeX86Instructions(code), inner: inner, edges: edges)
