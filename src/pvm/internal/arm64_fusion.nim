# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included by the ARM64 emitter. Retain the complete guest bank and exact path
## across source-checked edges. X23 bounds visits and X24 appends one token to call-local
## history after a successful reservation. Standalone source audits import an empty fragment.

when declared(ArmBlock):
  type ArmFusionEncoding* = object
    ## A standalone entry and its in-arena continuation use the same resident bank.
    words*: seq[uint32]
    inner*: int
    edges*: array[2, int]
    table*: int ## Byte coordinate of ADR; negative when no indirect lookup is emitted.

  proc armFusionBranchWord(words: var seq[uint32], at, delta: int): bool =
    ## Resolve one unconditional edge relative to its instruction, within the arena cap.
    if at < 0 or at >= words.len or delta < -33554432 or delta >= 33554432: return false
    words[at] = 0x14000000'u32 or (uint32(delta) and 0x3ffffff'u32)
    true

  proc patchFusionEdge*(code: var ArmFusionEncoding, edge, deltaBytes: int): bool =
    ## Leave the local checked return intact if a linked target is unavailable.
    if edge notin 0..1 or deltaBytes mod 4 != 0: return false
    armFusionBranchWord(code.words, code.edges[edge], deltaBytes div 4)

  proc patchFusionTable*(code: var ArmFusionEncoding, deltaBytes: int): bool =
    ## ADR binds only this immutable image's table, within the signed21-bit PC-relative range.
    if code.table < 0 or code.table mod 4 != 0 or code.table div 4 >= code.words.len or
        deltaBytes < -1048576 or deltaBytes > 1048575: return false
    let value = cast[uint32](int32(deltaBytes)) and 0x1fffff'u32
    code.words[code.table div 4] = 0x10000002'u32 or ((value and 3) shl 29) or ((value shr 2) shl 5)
    true

  proc armFusionIndirect(words: var seq[uint32], fixes: var seq[ArmMemoryCycleFixup],
      labels: var array[int(NativeReadFactLimit)+3, int], item: NativeFusionBlock,
      refusal, probe, found: int): int =
    ## Guard a checked cache tag before probing immutable source-authorized native entries.
    ## X0..X3/X17 are scratch; D17 retains the pre-write address across later bodies.
    let branch = item.branch
    let base = uint32(if branch.opcode == 50: branch.slots.aIndex else: branch.slots.bIndex)+4
    words.add(0x2a0003e0'u32 or (base shl 16)) # MOV W0,Wbase discards the high guest address bits.
    if item.indirectDelta != 0:
      armCompactImmediate(words, 1, uint64(item.indirectDelta))
      words.add(0x0b010000'u32) # ADD W0,W0,W1 wraps modulo2^32.
    words.add(0x7200001f'u32) # TST W0,#1.
    cycleEdge(words, fixes, refusal, 1)
    cycleCompareImmediate(words, 0, 0)
    cycleEdge(words, fixes, refusal, 0)
    armCompactImmediate(words, 1, 0xffff0000'u64)
    cycleCompare(words, 0, 1, true)
    cycleEdge(words, fixes, refusal, 0)
    cycleLoad(words, 2, 20, uint32(NativeFusionJumpsOffset))
    cycleCompareImmediate(words, 2, 0)
    cycleEdge(words, fixes, refusal, 0)
    words.add(0x53017c01'u32) # LSR W1,W0,#1 gives the nonzero source jump-table tag.
    words.add(0x51000423'u32) # SUB W3,W1,#1.
    words.add(0x12001c63'u32) # AND W3,W3,#255.
    words.add(0xf8637843'u32) # LDR X3,[X2,X3,LSL#3].
    words.add(0xd360fc62'u32) # LSR X2,X3,#32.
    cycleCompare(words, 2, 1, true)
    cycleEdge(words, fixes, refusal, 1)
    words.add(0x2a0303f1'u32) # MOV W17,W3 retains the checked header token.
    words.add(0x9e670011'u32) # FMOV D17,X0 captures the original address before an aliased load.
    result = words.len*4
    words.add(0x10000002'u32) # ADR X2,immutable_table is patched after staging.
    armCompactImmediate(words, 1, 0x9e3779b9'u64)
    words.add(0x1b017e21'u32) # MUL W1,W17,W1.
    words.add(0x53177c21'u32) # LSR W1,W1,#23.
    words.add(0xd37df021'u32) # LSL X1,X1,#3.
    labels[probe] = words.len
    words.add(0xf8616843'u32) # LDR X3,[X2,X1].
    cycleCompareImmediate(words, 3, 0) # Low token zero denotes an empty slot, independent of its upper offset.
    # Use a word comparison because the upper half of an occupied entry is a signed relative offset.
    words[words.len-1] = 0x7100007f'u32 # CMP W3,#0.
    cycleEdge(words, fixes, refusal, 0)
    cycleCompare(words, 3, 17, true)
    cycleEdge(words, fixes, found, 0)
    words.add(0x11002021'u32) # ADD W1,W1,#8.
    words.add(0x12002c21'u32) # AND W1,W1,#4095 keeps every probe inside the fixed table.
    cycleEdge(words, fixes, probe, 16)
    labels[found] = words.len
    words.add(0x9360fc63'u32) # ASR X3,X3,#32 sign-extends the image-relative entry displacement.
    words.add(0x8b030043'u32) # ADD X3,X2,X3 derives only an internal entry address.
    if branch.opcode == 180:
      armCompactImmediate(words, uint32(branch.slots.aIndex)+4, item.indirectValue)
    words.add(0xd61f0060'u32) # BR X3 preserves the resident bank, budgets and original host return.

  proc armFusionReturn(words: var seq[uint32], next: uint32, paid, useIndirect: bool) =
    ## The common exit commits original lanes and restores the host's saved registers.
    for slot in 0..12:
      cycleStore(words, uint32(slot+4), 19, uint32(slot*8))
    cycleStore(words, 21, 20, uint32(NativeFusionGasOffset))
    cycleStore(words, 22, 20, uint32(NativeFusionQuotaOffset))
    armCompactImmediate(words, 1, uint64(NativeFusionVisitLimit))
    cycleAddRegister(words, 1, 1, 23, true)
    cycleStore(words, 1, 20, uint32(NativeFusionVisitsOffset))
    armCompactImmediate(words, 1, uint64(ord(paid)))
    cycleStore(words, 1, 20, uint32(NativeFusionPaidOffset))
    if useIndirect:
      words.add(0xfd000291'u32 or ((uint32(NativeFusionAddressOffset) div 8) shl 10)) # STR D17,[X20,address].
    armCompactImmediate(words, 0, uint64(next))
    words.add(0xa94053f3'u32) # LDP X19,X20,[SP].
    words.add(0xa9415bf5'u32) # LDP X21,X22,[SP,#16].
    words.add(0xa94263f7'u32) # LDP X23,X24,[SP,#32].
    words.add(0x9100c3ff'u32) # ADD SP,SP,#48.
    words.add(0xd65f03c0'u32) # RET.

  proc encodeArmFusion*(item: NativeFusionBlock, token: int, useIndirect: bool): ArmFusionEncoding =
    ## Reserve checked capacities before reusing the existing mixed memory and scalar emitters.
    const capacity = NativeImageByteLimit div 4
    const operationWords = 64
    let returnWords = if useIndirect: 29 else: 28
    const unpaid = 0
    result = default(ArmFusionEncoding)
    if not item.complete or token < 1 or token > NativeFusionBlockLimit: return
    if item.indirect and not useIndirect and item.terminal == item.header+1: return
    let count = int(item.terminal-item.header)-1
    var words = newSeqOfCap[uint32](capacity)
    if words.rawData == nil: return
    var fixes = newSeqOfCap[ArmMemoryCycleFixup](count*11+(if useIndirect: 24 else: 8))
    if fixes.rawData == nil: return
    var labels = default(array[int(NativeReadFactLimit)+3, int])
    var table = -1
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
    words.add(0xd2800017'u32 or (uint32(NativeFusionVisitLimit) shl 5)) # MOV X23,bounded horizon.
    cycleAddImmediate(words, 24, 20, uint32(NativeFusionPathOffset))
    for slot in 0..12:
      cycleLoad(words, uint32(slot+4), 19, uint32(slot*8))
    if useIndirect: words.add(0x9e6703f1'u32) # FMOV D17,XZR initializes private exit metadata.
    let inner = words.len
    cycleCompareImmediate(words, 23, 0)
    cycleEdge(words, fixes, unpaid, 0)
    cycleCompareImmediate(words, 22, item.span)
    cycleEdge(words, fixes, unpaid, 3)
    cyclePriceGuard(words, fixes, item.price, unpaid)
    cyclePriceChange(words, item.price)
    cycleAddImmediate(words, 22, 22, item.span, true)
    cycleAddImmediate(words, 23, 23, 1, true)
    armCompactImmediate(words, 1, uint64(token))
    words.add(0x38001701'u32) # STRB W1,[X24],#1 appends only after the visit guard and debit.
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
    if item.indirect and useIndirect:
      if words.len > capacity-64-returnWords*(2+countSetBits(item.guards)): return
      table = armFusionIndirect(words, fixes, labels, item, count+1, count+2, count+3)
      labels[count+1] = words.len
      armFusionReturn(words, item.terminal, true, useIndirect)
    elif item.targets[0] == NativeEntryFailure:
      armFusionReturn(words, item.terminal, true, useIndirect)
    else:
      if item.branch.opcode == 80:
        let branch = item.branch
        armCompactImmediate(words, uint32(branch.slots.aIndex)+4, branch.immediate)
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
          armFusionReturn(words, item.targets[edge], false, useIndirect)

    labels[unpaid] = words.len
    armFusionReturn(words, item.header, false, useIndirect)
    for index in 0..<count:
      if (item.guards and (1'u32 shl index)) != 0:
        labels[index+1] = words.len
        armFusionReturn(words, item.header+uint32(index)+1, true, useIndirect)
    if words.len <= capacity and armMacroPatch(words, fixes, labels):
      result = ArmFusionEncoding(words: move(words), inner: inner*4, edges: edges, table: table)
