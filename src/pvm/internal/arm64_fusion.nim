# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included by the ARM64 emitter. Retain the complete guest bank across source-checked edges.
## X23 bounds visits. In ordinary entries X24 logs a token after each successful reservation.
## Compact entries for certified scalar and guarded SCCs count up to 4096 reservations and link
## only their sole cyclic successor. A guard refusal returns paid at the last reserved block's
## certified memory instruction. All exits set their original continuation and paid marker
## before one block-local restoration tail. Sharing this tail keeps guard-heavy entries
## within the existing 4 KiB code ceiling without changing their source or reservation limits.
## Optional bounded same-kind memory groups retain one proved true-view pointer in X17 across
## scalar work. A failed whole-window proof resumes paid at the first original memory operation.
## Standalone source audits import an empty fragment.

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

  proc armFusionBranchWord(words: var ArmWords, at, delta: int): bool =
    ## Cold composition retains relocation failure; finalized public fusion parts keep their checked bool patch API.
    if words.failure != ArmEmissionError.None: return false
    if not armFusionBranchWord(words.data, at, delta):
      refuseArmWords(words, ArmEmissionError.InvalidFixup)
      return false
    true

  proc armWindowCondition(words: var ArmWords, at, target: int, condition: uint32): bool =
    ## Patch a local forward staging edge; the enclosing encoder still owns every instruction.
    if words.failure != ArmEmissionError.None: return false
    if at < 0 or at >= words.len or target < 0 or target > words.len or condition > 15:
      return false
    let delta = int64(target)-int64(at)
    if delta < -262144 or delta > 262143: return false
    words[at] = 0x54000000'u32 or
      (uint32(cast[uint64](delta) and 0x7ffff'u64) shl 5) or condition
    true

  proc armWindowAddress(words: var ArmWords, window: NativeMemoryWindow) =
    ## X3 captures the original modulo-32 minimum address without changing a guest lane.
    if words.failure != ArmEmissionError.None: return
    if window.absolute:
      armCompactImmediate(words, 3, uint64(window.displacement))
    else:
      let source = uint32(window.baseLane)+4
      words.add(0x2a0003e3'u32 or (source shl 16)) # MOV W3,Wsource.
      if window.displacement != 0:
        armCompactImmediate(words, 2, uint64(window.displacement))
        words.add(0x0b020063'u32) # ADD W3,W3,W2 wraps the original address once.

  proc armWindowRegions(words: var ArmWords, fixes: var seq[ArmMemoryCycleFixup],
      window: NativeMemoryWindow, refusal: int): bool =
    ## Select the first nonempty region intersecting the whole window. Partial overlap declines
    ## at the first original site, preserving descriptor priority and checked partial behavior.
    ## X3 is the proved virtual start; X17 receives the sole accepted host-window pointer.
    if words.failure != ArmEmissionError.None: return false
    let writing = window.kind == NativeWindowKind.Write
    let regions = if writing: 2 else: 3
    let first = if writing: uint32(NativeCycleWritableOffset) else: 0'u32
    let stride = if writing: uint32(sizeof(NativeCycleWritable)) else: uint32(sizeof(NativeReadRegion))
    armCompactImmediate(words, 0, uint64(window.span))
    var accepted = default(array[3, int])
    for region in 0..<regions:
      # Empty views have no precedence. A nonempty nil view conservatively stays checked.
      let offset = first+uint32(region)*stride
      cycleLoad(words, 1, 20, offset)
      cycleLoad(words, 2, 20, offset+8)
      cycleLoad(words, 17, 20, offset+16)
      cycleCompareImmediate(words, 2, 0)
      let empty = words.len
      words.add(0)
      cycleCompareImmediate(words, 17, 0)
      cycleEdge(words, fixes, refusal, 0)
      cycleCompare(words, 1, 3)
      let before = words.len
      words.add(0)
      words.add(0xcb010061'u32) # SUB X1,X3,X1: nonnegative region-relative start.
      cycleCompare(words, 1, 2)
      let outside = words.len
      words.add(0)
      words.add(0xcb010042'u32) # SUB X2,X2,X1: remaining true bytes.
      cycleCompare(words, 2, 0)
      cycleEdge(words, fixes, refusal, 3)
      words.add(0x8b010231'u32) # ADD X17,X17,X1 keeps only a proved borrowed address.
      accepted[region] = words.len
      words.add(0)
      let earlier = words.len
      words.add(0xcb030021'u32) # SUB X1,X1,X3: positive gap before this region.
      cycleCompare(words, 1, 0)
      cycleEdge(words, fixes, refusal, 3)
      let following = words.len
      if not armWindowCondition(words, empty, following, 0) or
          not armWindowCondition(words, before, earlier, 8) or
          not armWindowCondition(words, outside, following, 2): return false
    cycleEdge(words, fixes, refusal, 16)
    let following = words.len
    for region in 0..<regions:
      # Every accepted view bypasses all later descriptors and the common refusal.
      if not armFusionBranchWord(words, accepted[region], following-accepted[region]): return false
    true

  proc armFusionWindowGuard(words: var ArmWords, fixes: var seq[ArmMemoryCycleFixup],
      window: NativeMemoryWindow, refusal: int): bool =
    ## Preflight true bounds and existing dirty authority before the group's first mutation.
    ## At most two pages cover a 4 KiB window. Dirty checks preserve X3 and never set a bit.
    if words.failure != ArmEmissionError.None: return false
    if not window.ready or window.span == 0 or window.span > 4096 or
        window.baseLane < 0 or window.baseLane > 12: return false
    armWindowAddress(words, window)
    armCompactImmediate(words, 1, 65536)
    cycleCompare(words, 3, 1)
    cycleEdge(words, fixes, refusal, 3)
    armCompactImmediate(words, 2, 0xffffffff'u64-uint64(window.span))
    cycleCompare(words, 3, 2)
    cycleEdge(words, fixes, refusal, 8)
    if window.kind == NativeWindowKind.Write:
      # Check the first page and, only when distinct, the final page before borrowing data.
      armCycleDirtyPage(words, fixes, refusal)
      cycleAddImmediate(words, 0, 3, window.span-1)
      words.add(0xd34cfc61'u32) # LSR X1,X3,#12.
      words.add(0xd34cfc02'u32) # LSR X2,X0,#12.
      cycleCompare(words, 1, 2)
      let samePage = words.len
      words.add(0)
      cycleMove(words, 3, 0)
      armCycleDirtyPage(words, fixes, refusal)
      armWindowAddress(words, window)
      if not armWindowCondition(words, samePage, words.len, 0): return false
    armWindowRegions(words, fixes, window, refusal)

  proc armFusionWindowOperation(words: var ArmWords, op: NativeOperation,
      window: NativeMemoryWindow): bool =
    ## A whole-view proof covers each original scalar transfer, including signed/unaligned loads.
    if words.failure != ArmEmissionError.None: return false
    let encoding = nativeWindowOpcode(op.opcode)
    if encoding < 120 or encoding > 130: return false
    let width = indirectMemoryAccess(range[120..130](encoding)).width
    let delta = uint32(op.immediate and 0xffffffff'u64)-window.displacement
    if delta >= window.span or width > window.span-delta or delta mod width != 0: return false
    let instruction = case encoding
      of 120: 0x39000000'u32
      of 121: 0x79000000'u32
      of 122: 0xb9000000'u32
      of 123: 0xf9000000'u32
      of 124: 0x39400000'u32
      of 125: 0x39800000'u32
      of 126: 0x79400000'u32
      of 127: 0x79800000'u32
      of 128: 0xb9400000'u32
      of 129: 0xb9800000'u32
      else: 0xf9400000'u32
    words.add(instruction or ((delta div width) shl 10) or (17'u32 shl 5) or
      (uint32(op.slots.aIndex)+4))
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

  proc armFusionIndirect(words: var ArmWords, fixes: var seq[ArmMemoryCycleFixup],
      labels: var array[int(NativeReadFactLimit)+4, int], item: NativeFusionBlock,
      refusal, probe, found: int): int =
    ## Guard a checked cache tag before probing immutable source-authorized native entries.
    ## X0..X3/X17 are scratch; D17 retains the pre-write address across later bodies.
    if words.failure != ArmEmissionError.None: return -1
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
    words.add(0x12000063'u32 or (uint32(DynamicJumpCacheBits-1) shl 10)) # AND W3,W3,low ordinal mask.
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

  proc armFusionReturn(words: var ArmWords, fixes: var seq[ArmMemoryCycleFixup],
      next: uint32, paid: bool, finish: int) =
    ## Set the original continuation and paid marker before one block-local restoration tail.
    ## X0 and X2 are reserved host scratch; the resident guest bank is still untouched.
    if words.failure != ArmEmissionError.None: return
    armCompactImmediate(words, 0, uint64(next))
    armCompactImmediate(words, 2, uint64(ord(paid)))
    cycleEdge(words, fixes, finish, 16)

  proc armFusionFinish(words: var ArmWords, useIndirect: bool, horizon: uint32) =
    ## Commit the original guest bank, debits, path length and pre-write address exactly once.
    ## X0 carries the original continuation and X2 the paid marker from every return stub.
    if words.failure != ArmEmissionError.None: return
    for slot in 0..12:
      cycleStore(words, uint32(slot+4), 19, uint32(slot*8))
    cycleStore(words, 21, 20, uint32(NativeFusionGasOffset))
    cycleStore(words, 22, 20, uint32(NativeFusionQuotaOffset))
    armCompactImmediate(words, 1, uint64(horizon))
    cycleAddRegister(words, 1, 1, 23, true)
    cycleStore(words, 1, 20, uint32(NativeFusionVisitsOffset))
    cycleStore(words, 2, 20, uint32(NativeFusionPaidOffset))
    if useIndirect:
      words.add(0xfd000291'u32 or ((uint32(NativeFusionAddressOffset) div 8) shl 10)) # STR D17,[X20,address].
    words.add(0xa94053f3'u32) # LDP X19,X20,[SP].
    words.add(0xa9415bf5'u32) # LDP X21,X22,[SP,#16].
    words.add(0xa94263f7'u32) # LDP X23,X24,[SP,#32].
    words.add(0x9100c3ff'u32) # ADD SP,SP,#48.
    words.add(0xd65f03c0'u32) # RET.

  proc encodeArmFusion*(item: NativeFusionBlock, token: int, useIndirect: bool): ArmFusionEncoding =
    ## Reserve checked capacities before reusing the existing mixed memory and scalar emitters.
    const capacity = NativeImageByteLimit div 4
    const operationWords = 64
    const windowWords = 128 # Includes both dirty-page guards and the first scalar transfer.
    const returnWords = 4 # Two continuation words, one paid-marker word and one branch.
    const epilogueWords = 25 # Includes the optional pre-write D17 address store.
    const unpaid = 0
    result = default(ArmFusionEncoding)
    if not item.complete or token < 1 or token > NativeFusionBlockLimit: return
    if item.indirect and not useIndirect and item.terminal == item.header+1: return
    let count = int(item.terminal-item.header)-1
    let compact = item.cycleNext != 0
    let horizon = uint32(if compact: NativeFusionCycleVisitLimit else: NativeFusionVisitLimit)
    let finish = count+4
    var words = ArmWords(data: newSeqOfCap[uint32](capacity))
    if words.data.rawData == nil: return
    # Each memory guard retains its body edges and one return-stub edge to the common tail.
    var fixes = newSeqOfCap[ArmMemoryCycleFixup](count*12+(if useIndirect: 28 else: 12))
    if fixes.rawData == nil: return
    # Unpaid/body/indirect labels precede one disjoint finish label after the dynamic probe.
    var labels = default(array[int(NativeReadFactLimit)+4, int])
    var table = -1
    var scratch = default(ArmReadSpan)
    scratch.body = newArmRegionBody()
    scratch.body.words = ArmWords(data: newSeqOfCap[uint32](operationWords))
    scratch.body.terminal = ArmWords(data: newSeqOfCap[uint32](5))
    scratch.guards = newSeqOfCap[ArmReadGuard](1)
    if scratch.body.words.data.rawData == nil or scratch.body.terminal.data.rawData == nil or
        scratch.guards.rawData == nil: return

    words.add(0xd100c3ff'u32) # SUB SP,SP,#48.
    words.add(0xa90053f3'u32) # STP X19,X20,[SP].
    words.add(0xa9015bf5'u32) # STP X21,X22,[SP,#16].
    words.add(0xa90263f7'u32) # STP X23,X24,[SP,#32].
    cycleMove(words, 19, 0)
    cycleMove(words, 20, 1)
    cycleLoad(words, 21, 20, uint32(NativeFusionGasOffset))
    cycleLoad(words, 22, 20, uint32(NativeFusionQuotaOffset))
    words.add(0xd2800017'u32 or (horizon shl 5)) # MOV X23,bounded horizon.
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
    if not compact:
      # A certified cycle returns a count; every other graph retains its ordered byte log.
      armCompactImmediate(words, 1, uint64(token))
      words.add(0x38001701'u32) # STRB W1,[X24],#1 follows the visit guard and debit.
    var window = default(NativeMemoryWindow)
    for index in 0..<count:
      let op = item.operations[index]
      if nativeWindowOpcode(op.opcode) != 0 and index >= window.past:
        window = nativeMemoryWindow(item.operations, count, index)
        if window.ready and words.len > capacity-windowWords:
          # Ordinary lowering retains admission when the conservative optional forecast cannot fit.
          window = default(NativeMemoryWindow)
      if window.contains(index):
        if index == window.first:
          if not armFusionWindowGuard(words, fixes, window, index+1): return
        if words.len >= capacity or not armFusionWindowOperation(words, op, window): return
        continue
      if words.len > capacity-operationWords: return
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
          if not appendArmCycleRead(words, fixes, scratch, index+1): return
        else:
          emitArmOperation(scratch.body, op.opcode, op.slots, op.immediate)
          if scratch.body.failure != ArmEmissionError.None: return
          words.add(scratch.body.words)
    if words.len > capacity-returnWords*(3+countSetBits(item.guards))-epilogueWords-8: return

    var edges = [-1, -1]
    if item.indirect and useIndirect:
      if words.len > capacity-64-returnWords*(2+countSetBits(item.guards))-epilogueWords: return
      table = armFusionIndirect(words, fixes, labels, item, count+1, count+2, count+3)
      labels[count+1] = words.len
      armFusionReturn(words, fixes, item.terminal, true, finish)
    elif item.targets[0] == NativeEntryFailure:
      armFusionReturn(words, fixes, item.terminal, true, finish)
    else:
      if item.branch.opcode == 80:
        let branch = item.branch
        armCompactImmediate(words, uint32(branch.slots.aIndex)+4, branch.immediate)
      if item.targets[1] != NativeEntryFailure:
        let branch = item.branch
        let condition = armBranchCompare(scratch.body, branch.opcode,
          branch.slots.aIndex, branch.slots.bIndex, branch.immediate)
        if scratch.body.failure != ArmEmissionError.None: return
        words.add(scratch.body.terminal)
        words.add(0x54000040'u32 or condition) # B.cond over the false edge.
      for edge in 0..1:
        if item.targets[edge] != NativeEntryFailure:
          edges[edge] = words.len
          words.add(0)
      for edge in 0..1:
        if edges[edge] >= 0:
          if not armFusionBranchWord(words, edges[edge], words.len-edges[edge]): return
          armFusionReturn(words, fixes, item.targets[edge], false, finish)

    labels[unpaid] = words.len
    armFusionReturn(words, fixes, item.header, false, finish)
    for index in 0..<count:
      if (item.guards and (1'u32 shl index)) != 0:
        labels[index+1] = words.len
        armFusionReturn(words, fixes, item.header+uint32(index)+1, true, finish)
    labels[finish] = words.len
    armFusionFinish(words, useIndirect, horizon)
    if words.len <= capacity and armMacroPatch(words, fixes, labels):
      if words.failure != ArmEmissionError.None: return default(ArmFusionEncoding)
      result = ArmFusionEncoding(words: takeArmWords(words), inner: inner*4, edges: edges, table: table)
