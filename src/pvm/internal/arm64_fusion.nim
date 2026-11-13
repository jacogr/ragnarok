# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included by the ARM64 emitter. Retain the complete guest bank and exact path
## across source-checked edges. Standalone source audits import an empty fragment.

when declared(ArmBlock):
  type ArmFusionEncoding* = object
    ## A standalone entry and its in-arena continuation use the same resident bank.
    words*: seq[uint32]
    inner*: int
    edges*: array[2, int]

  proc armFusionBranchWord(words: var seq[uint32], at, delta: int): bool =
    ## Resolve one unconditional edge relative to its instruction, within the arena cap.
    if at < 0 or at >= words.len or delta < -33554432 or delta >= 33554432: return false
    words[at] = 0x14000000'u32 or (uint32(delta) and 0x3ffffff'u32)
    true

  proc patchFusionEdge*(code: var ArmFusionEncoding, edge, deltaBytes: int): bool =
    ## Leave the local checked return intact if a linked target is unavailable.
    if edge notin 0..1 or deltaBytes mod 4 != 0: return false
    armFusionBranchWord(code.words, code.edges[edge], deltaBytes div 4)

  proc armFusionReturn(words: var seq[uint32], next: uint32, paid: bool) =
    ## The common exit commits original lanes and restores the host's saved registers.
    for slot in 0..12:
      cycleStore(words, uint32(slot+4), 19, uint32(slot*8))
    cycleStore(words, 21, 20, uint32(NativeFusionGasOffset))
    cycleStore(words, 22, 20, uint32(NativeFusionQuotaOffset))
    cycleStore(words, 24, 20, uint32(NativeFusionPathOffset))
    armCompactImmediate(words, 1, uint64(ord(paid)))
    cycleStore(words, 1, 20, uint32(NativeFusionPaidOffset))
    armCompactImmediate(words, 0, uint64(next))
    words.add(0xa94053f3'u32) # LDP X19,X20,[SP].
    words.add(0xa9415bf5'u32) # LDP X21,X22,[SP,#16].
    words.add(0xa94263f7'u32) # LDP X23,X24,[SP,#32].
    words.add(0x9100c3ff'u32) # ADD SP,SP,#48.
    words.add(0xd65f03c0'u32) # RET.

  proc encodeArmFusion*(item: NativeFusionBlock, token: int): ArmFusionEncoding =
    ## Reserve checked capacities before reusing the existing mixed memory and scalar emitters.
    const capacity = NativeImageByteLimit div 4
    const operationWords = 64
    const returnWords = 28
    const unpaid = 0
    result = default(ArmFusionEncoding)
    if not item.complete or token < 1 or token > NativeFusionBlockLimit: return
    let count = int(item.terminal-item.header)-1
    var words = newSeqOfCap[uint32](capacity)
    if words.rawData == nil: return
    var fixes = newSeqOfCap[ArmMemoryCycleFixup](count*11+8)
    if fixes.rawData == nil: return
    var scratch = default(ArmReadSpan)
    scratch.body = newArmRegionBody()
    scratch.body.words = newSeqOfCap[uint32](operationWords)
    scratch.body.terminal = newSeqOfCap[uint32](5)
    scratch.guards = newSeqOfCap[ArmReadGuard](1)
    if scratch.body.words.rawData == nil or scratch.body.terminal.rawData == nil or
        scratch.guards.rawData == nil: return

    words.add(0xd100c3ff'u32) # SUB SP,SP,#48.
    words.add(0xa90053f3'u32) # STP X19,X20,[SP].
    words.add(0xa9015bf5'u32) # STP X21,X22,[SP,#16].
    words.add(0xa90263f7'u32) # STP X23,X24,[SP,#32].
    cycleMove(words, 19, 0)
    cycleMove(words, 20, 1)
    cycleLoad(words, 21, 20, uint32(NativeFusionGasOffset))
    cycleLoad(words, 22, 20, uint32(NativeFusionQuotaOffset))
    words.add(0xd2800117'u32) # MOV X23,#8.
    words.add(0xd2800018'u32) # MOV X24,#0.
    for slot in 0..12:
      cycleLoad(words, uint32(slot+4), 19, uint32(slot*8))
    let inner = words.len
    cycleCompareImmediate(words, 23, 0)
    cycleEdge(words, fixes, unpaid, 0)
    cycleCompareImmediate(words, 22, item.span)
    cycleEdge(words, fixes, unpaid, 3)
    cyclePriceGuard(words, fixes, item.price, unpaid)
    cyclePriceChange(words, item.price)
    cycleAddImmediate(words, 22, 22, item.span, true)
    cycleAddImmediate(words, 23, 23, 1, true)
    words.add(0xd378df18'u32) # LSL X24,X24,#8.
    cycleAddImmediate(words, 24, 24, uint32(token))
    for index in 0..<count:
      if words.len > capacity-operationWords: return
      let op = item.operations[index]
      let width = nativeMixedLoopStoreWidth(op.opcode)
      if width != 0:
        armPaidLoopStore(words, fixes, op, index+1)
      else:
        scratch.body.words.shrink(0)
        scratch.body.reads = 0
        scratch.body.writes = 0
        let encoding = nativeReadEncodingOpcode(op.opcode)
        if encoding >= 124 and encoding <= 130:
          scratch.guards.shrink(0)
          emitArmCheckedRead(scratch, op.slots, uint32(op.immediate and 0xffffffff'u64),
            range[124..130](encoding), encoding != op.opcode)
          appendArmCycleRead(words, fixes, scratch, index+1)
        else:
          emitArmOperation(scratch.body, op.opcode, op.slots, op.immediate)
          for word in scratch.body.words: words.add(word)
    if words.len > capacity-returnWords*(3+countSetBits(item.guards))-8: return

    var edges = [-1, -1]
    if item.targets[0] == NativeEntryFailure:
      armFusionReturn(words, item.terminal, true)
    else:
      if item.targets[1] != NativeEntryFailure:
        let branch = item.branch
        let condition = armBranchCompare(scratch.body, branch.opcode,
          branch.slots.aIndex, branch.slots.bIndex, branch.immediate)
        for word in scratch.body.terminal: words.add(word)
        words.add(0x54000040'u32 or condition) # B.cond over the false edge.
      for edge in 0..1:
        if item.targets[edge] != NativeEntryFailure:
          edges[edge] = words.len
          words.add(0)
      for edge in 0..1:
        if edges[edge] >= 0:
          if not armFusionBranchWord(words, edges[edge], words.len-edges[edge]): return
          armFusionReturn(words, item.targets[edge], false)

    var labels = default(array[int(NativeReadFactLimit), int])
    labels[unpaid] = words.len
    armFusionReturn(words, item.header, false)
    for index in 0..<count:
      if (item.guards and (1'u32 shl index)) != 0:
        labels[index+1] = words.len
        armFusionReturn(words, item.header+uint32(index)+1, true)
    if words.len <= capacity and armMacroPatch(words, fixes, labels):
      result = ArmFusionEncoding(words: move(words), inner: inner*4, edges: edges)
