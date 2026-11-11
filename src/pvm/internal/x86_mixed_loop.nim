# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Lower source-certified transactional and paid-prefix mixed self-loops.
## Included beside the checked Read-cycle emitter so it can share its memory guards.

when declared(X86Block):
  type X86MixedLoopLabels = array[3+5*(int(NativeReadFactLimit)-1), int]
    ## The paid loop has three fixed targets and at most five targets per body operation.

  func mixedLoopPosition(fixes: openArray[X86CycleFixup], savings: openArray[byte],
      original: int): int =
    ## Map an original boundary after selected, disjoint branch contractions.
    assert fixes.len == savings.len
    result = original
    for index in 0..<fixes.len:
      # A boundary before this displacement retains every byte of this edge.
      if fixes[index].at+4 <= original: result -= int(savings[index])

  proc sealMixedLoop(code: var X86Block, fixes: openArray[X86CycleFixup],
      labels: X86MixedLoopLabels): seq[byte] =
    ## Record all relative fields as sorted disjoint rel32 edges with instruction-boundary labels.
    ## Each edge contracts once; distances never grow, so the monotone fixed point is finite.
    ## Preserve other bytes and entry zero; retain the caller's conservative pre-relax 4 KiB cap.
    var savings = newSeq[byte](fixes.len)
    var starts = newSeq[int](fixes.len)
    var shortOpcodes = newSeq[byte](fixes.len)
    var previousEnd = 0
    for index in 0..<fixes.len:
      # Fixups describe complete original rel32 instructions in emission order.
      let fix = fixes[index]
      assert fix.at >= 1 and fix.at+4 <= code.bytes.len
      if code.bytes[fix.at-1] == 0xe9:
        starts[index] = fix.at-1
        shortOpcodes[index] = 0xeb
      else:
        assert fix.at >= 2 and code.bytes[fix.at-2] == 0x0f
        assert code.bytes[fix.at-1] >= 0x80 and code.bytes[fix.at-1] <= 0x8f
        starts[index] = fix.at-2
        shortOpcodes[index] = code.bytes[fix.at-1]-0x10
      assert starts[index] >= previousEnd
      previousEnd = fix.at+4
      let target = labels[int(fix.target)]
      assert target >= 0 and target < code.bytes.len
    for fix in fixes:
      # No recorded target may land within any instruction being contracted.
      let target = labels[int(fix.target)]
      for index in 0..<fixes.len:
        assert target <= starts[index] or target >= fixes[index].at+4

    var changed = true
    while changed:
      # At most one transition per edge is possible; no selected edge widens again.
      changed = false
      for index in 0..<fixes.len:
        if savings[index] != 0: continue
        let fix = fixes[index]
        let saved = byte(fix.at+4-starts[index]-2)
        let start = mixedLoopPosition(fixes, savings, starts[index])
        var target = mixedLoopPosition(fixes, savings, labels[int(fix.target)])
        if labels[int(fix.target)] >= fix.at+4:
          # A forward target also moves when this same edge becomes shorter.
          target -= int(saved)
        let delta = target-(start+2)
        if delta >= -128 and delta <= 127:
          savings[index] = saved
          changed = true

    result = @[]
    var cursor = 0
    for index in 0..<fixes.len:
      # Preserve every nonbranch byte, including all guards and memory operations.
      let fix = fixes[index]
      while cursor < starts[index]:
        result.add(code.bytes[cursor])
        inc cursor
      assert result.len == mixedLoopPosition(fixes, savings, starts[index])
      let target = mixedLoopPosition(fixes, savings, labels[int(fix.target)])
      if savings[index] != 0:
        let delta = target-(result.len+2)
        assert delta >= -128 and delta <= 127
        result.add(shortOpcodes[index])
        result.add(byte(cast[uint32](int32(delta)) and 255))
      else:
        # A remaining long edge keeps its condition and exact mapped target.
        while cursor < fix.at:
          result.add(code.bytes[cursor])
          inc cursor
        let delta = cast[uint32](int32(target-(result.len+4)))
        for shift in 0..<4: result.add(byte((delta shr (shift*8)) and 255))
      cursor = fix.at+4
    while cursor < code.bytes.len:
      result.add(code.bytes[cursor])
      inc cursor
    assert result.len == mixedLoopPosition(fixes, savings, code.bytes.len)

  when defined(pvmX86MixedRelaxWitness) or defined(pvmSharedAsyncWitness):
    proc x86MixedLoopRelaxProof*(padding: int, backward: bool,
        condition: byte): seq[byte] =
      ## Private literal layouts exercise signed displacement boundaries through real fixups.
      assert padding >= 0 and padding <= 256
      assert condition == 0 or (condition >= 0x80 and condition <= 0x8f)
      var code = default(X86Block)
      var fixes: seq[X86CycleFixup] = @[]
      var labels = default(X86MixedLoopLabels)
      if backward:
        # The original entry itself is a legal self/backward target.
        labels[0] = 0
        for _ in 0..<padding: put(code, [0x90'u8])
        cycleEdge(code, fixes, condition, 0)
      else:
        cycleEdge(code, fixes, condition, 0)
        for _ in 0..<padding: put(code, [0x90'u8])
        labels[0] = code.bytes.len
      put(code, [0xc3'u8])
      sealMixedLoop(code, fixes, labels)

    proc x86MixedLoopRelaxCascadeProof*(): seq[byte] =
      ## The first edge fits only after the later edge contracts on an earlier pass.
      var code = default(X86Block)
      var fixes: seq[X86CycleFixup] = @[]
      var labels = default(X86MixedLoopLabels)
      cycleEdge(code, fixes, 0x85, 0)
      for _ in 0..<124: put(code, [0x90'u8])
      cycleEdge(code, fixes, 0, 0)
      labels[0] = code.bytes.len
      put(code, [0xc3'u8])
      sealMixedLoop(code, fixes, labels)

  proc mixedLoopReadPointer(code: var X86Block, fixes: var seq[X86CycleFixup],
      labels: var X86MixedLoopLabels, width, refusal: byte, nextLabel: var byte) =
    ## RDX holds the guest address. Preserve checked descriptor order and full access width.
    let accepted = nextLabel
    inc nextLabel
    for region in 0..<3:
      # A short extent falls through to the next original readable descriptor.
      let nextRegion = nextLabel
      inc nextLabel
      emitCheckedExtent(code, fixes, byte(region*24), width, nextRegion, accepted)
      labels[int(nextRegion)] = code.bytes.len
    cycleEdge(code, fixes, 0, refusal)
    labels[int(accepted)] = code.bytes.len
    put(code, [0x48'u8, 0x85, 0xc9]) # TEST RCX,RCX checks readable storage.
    cycleEdge(code, fixes, 0x84, refusal)

  proc mixedLoopAbsolutePointer(code: var X86Block, fixes: var seq[X86CycleFixup],
      labels: var X86MixedLoopLabels, address: uint32, slot, refusal: byte,
      nextLabel: var byte) =
    ## Hoist only the descriptor proof. Guest values are still read at their original operations.
    put(code, [0xba'u8]) # MOV EDX,absolute32.
    cycleWord(code, address)
    mixedLoopReadPointer(code, fixes, labels, 8, refusal, nextLabel)
    put(code, [0x48'u8, 0x8d, 0x04, 0x01]) # LEA RAX,[RCX+RAX] keeps the proved address.
    put(code, [0x48'u8, 0x89, 0x44, 0x24, slot]) # MOV [RSP+slot],RAX.

  proc mixedLoopLoad(code: var X86Block, fixes: var seq[X86CycleFixup],
      labels: var X86MixedLoopLabels, op: NativeOperation, encoding, refusal: byte,
      nextLabel: var byte) =
    ## Resolve the original absolute or wrapped relative address at its source position.
    let access = X86CanonicalAccess()
    if encoding == op.opcode:
      # The staged base may also be this read's destination.
      readBodyBase(code, access, op.slots.bIndex)
      put(code, [0x81'u8, 0xc2]) # ADD EDX,disp32 wraps modulo 2^32.
    else:
      put(code, [0xba'u8]) # MOV EDX,absolute32.
    cycleWord(code, uint32(op.immediate and 0xffffffff'u64))
    let opcode = int(encoding)
    assert opcode >= 124 and opcode <= 130
    let width = byte(indirectMemoryAccess(range[120..130](opcode)).width)
    mixedLoopReadPointer(code, fixes, labels, width, refusal, nextLabel)
    emitCheckedReadValue(code, encoding)
    writeAccess(code, access, op.slots.aIndex)

  proc mixedLoopStore(code: var X86Block, fixes: var seq[X86CycleFixup],
      labels: var X86MixedLoopLabels, op: NativeOperation, width, refusal: byte,
      nextLabel: var byte) =
    ## Prove the selected writable extent and every touched dirty page before the Store.
    const stackOffset = byte(NativeCycleWritableOffset)
    const rwOffset = stackOffset+24
    let access = X86CanonicalAccess()
    if width == 4:
      put(code, [0xba'u8]) # MOV EDX,absolute32 for opcode 61.
    else:
      readBodyBase(code, access, op.slots.bIndex)
      put(code, [0x81'u8, 0xc2]) # ADD EDX,disp32 wraps the current base modulo 2^32.
    cycleWord(code, uint32(op.immediate and 0xffffffff'u64))
    put(code, [0x81'u8, 0xfa]) # CMP EDX,65536 protects the low pages.
    cycleWord(code, 65536)
    cycleEdge(code, fixes, 0x82, refusal)
    put(code, [0x83'u8, 0xfa, 255'u8-width]) # CMP EDX,UINT32_MAX-width excludes the top byte.
    cycleEdge(code, fixes, 0x87, refusal)
    let rw = nextLabel
    let ready = nextLabel+1
    nextLabel += 2
    # A selected stack extent shadows the RW extent even when the stack is empty.
    put(code, [0x49'u8, 0x3b, 0x52, stackOffset]) # CMP RDX,[R10+stack.first].
    cycleEdge(code, fixes, 0x82, rw)
    emitCheckedExtent(code, fixes, stackOffset, width, refusal, ready)
    labels[int(rw)] = code.bytes.len
    emitCheckedExtent(code, fixes, rwOffset, width, refusal, ready)
    labels[int(ready)] = code.bytes.len
    put(code, [0x48'u8, 0x85, 0xc9]) # TEST RCX,RCX requires live writable storage.
    cycleEdge(code, fixes, 0x84, refusal)
    put(code, [0x4c'u8, 0x8d, 0x04, 0x01]) # LEA R8,[RCX+RAX] holds the exact write address.
    readCycleContextOp(code, [0x49'u8, 0x8b, 0xb2], NativeCycleDirtyOffset)
    put(code, [0x48'u8, 0x85, 0xf6]) # TEST RSI,RSI checks the dirty bitmap pointer.
    cycleEdge(code, fixes, 0x84, refusal)
    readCycleDirtyPage(code, fixes, refusal, false)
    if width == 4:
      # A word crossing a page needs both bits before the single write.
      readCycleDirtyPage(code, fixes, refusal, true)
    readAccess(code, access, op.slots.aIndex, false)
    if width == 4: put(code, [0x41'u8, 0x89, 0x00]) # MOV [R8],EAX commits the word.
    else: put(code, [0x41'u8, 0x88, 0x00]) # MOV [R8],AL commits the byte.

  template mixedLoopByteStore(code: var X86Block, fixes: var seq[X86CycleFixup],
      labels: var X86MixedLoopLabels, op: NativeOperation, refusal: byte, nextLabel: var byte) =
    ## The transactional leaf's unique Store retains its original one-byte encoding.
    mixedLoopStore(code, fixes, labels, op, 1, refusal, nextLabel)

  proc x86MixedLoopInstructions*(operations: openArray[NativeOperation]): seq[byte] =
    ## Emit exact SysV (registers, context) -> (completed visits | checked-exit bit).
    ## Only ordered reads and staged scalar writes may precede the sole byte Store.
    ## Its suffix contains only infallible scalars or noops before the terminal BNE.
    ## The caller proves source edges, dirty-list ownership and the funded visit cap.
    const
      visit = 0'u8
      unpaid = 1'u8
      outside = 2'u8
      finish = 3'u8
      pointerSlots = [104'u8, 112]
      frameBytes = 120'u8
    if operations.len < 3 or operations.len > int(NativeReadFactLimit): return @[]
    let terminal = operations.len-1
    let branch = operations[terminal]
    if branch.opcode != 171: return @[]

    var writes = 0'u16
    var sawRead = false
    var sawStore = false
    var hoisted = 0
    var absoluteReads = [-1, -1]
    for index in 0..<terminal:
      let op = operations[index]
      if op.opcode == 120:
        # At least one read precedes the unique Store.
        if not sawRead or sawStore: return @[]
        sawStore = true
      elif nativeReadOpcode(nativeReadEncodingOpcode(op.opcode)):
        # A refused read must be able to leave the entire visit unpaid.
        if sawStore: return @[]
        sawRead = true
        writes = writes or (1'u16 shl int(op.slots.aIndex))
        if op.opcode == 58 and hoisted < pointerSlots.len:
          # Up to two immutable descriptor addresses can use existing stack slots.
          absoluteReads[hoisted] = index
          inc hoisted
      elif supportedScalarOpcode(op.opcode):
        writes = writes or (1'u16 shl int(op.slots.destinationIndex))
      elif op.opcode != 2:
        return @[]
    if not sawStore: return @[]
    assert sizeof(RegisterFile) == int(pointerSlots[0]) and NativeCycleGasOffset == 136

    var code = default(X86Block)
    var fixes: seq[X86CycleFixup] = @[]
    var labels = default(X86MixedLoopLabels)
    var nextLabel = 4'u8
    let access = X86CanonicalAccess()
    put(code, [0x41'u8, 0x54, 0x41, 0x55]) # PUSH R12; PUSH R13 saves callee registers.
    put(code, [0x48'u8, 0x83, 0xec, frameBytes]) # SUB RSP,120.
    put(code, [0x45'u8, 0x31, 0xe4]) # XOR R12D,R12D initializes completed visits.
    put(code, [0x49'u8, 0x89, 0xf2]) # MOV R10,RSI holds the invocation context.
    readCycleContextOp(code, [0x4d'u8, 0x8b, 0xaa], NativeCycleGasOffset) # MOV R13,[R10+136].
    put(code, [0x4d'u8, 0x85, 0xed]) # TEST R13,R13.
    cycleEdge(code, fixes, 0x84, unpaid)
    put(code, [0x49'u8, 0x81, 0xfd]) # CMP R13,256.
    cycleWord(code, 256)
    cycleEdge(code, fixes, 0x87, unpaid)
    for index in 0..<hoisted:
      let op = operations[absoluteReads[index]]
      mixedLoopAbsolutePointer(code, fixes, labels, uint32(op.immediate and 0xffffffff'u64),
        pointerSlots[index], unpaid, nextLabel)

    # Copy once. The stage carries the most recent committed visit across the native backedge.
    put(code, [0x49'u8, 0x89, 0xfb]) # MOV R11,RDI keeps the original register file.
    put(code, [0x48'u8, 0x89, 0xfe, 0x48, 0x89, 0xe7]) # MOV RSI,RDI; MOV RDI,RSP.
    put(code, [0xb9'u8]) # MOV ECX,13.
    cycleWord(code, 13)
    put(code, [0xf3'u8, 0x48, 0xa5]) # REP MOVSQ copies the canonical register file.
    put(code, [0x48'u8, 0x89, 0xe7]) # MOV RDI,RSP points canonical emission at the stage.

    labels[int(visit)] = code.bytes.len
    for index in 0..<terminal:
      let op = operations[index]
      let encoding = nativeReadEncodingOpcode(op.opcode)
      if index == absoluteReads[0] or index == absoluteReads[1]:
        # Load the current eight bytes in source order, even if an earlier visit aliased this address.
        let slot = if index == absoluteReads[0]: pointerSlots[0] else: pointerSlots[1]
        put(code, [0x48'u8, 0x8b, 0x44, 0x24, slot, 0x48, 0x8b, 0x00])
        writeAccess(code, access, op.slots.aIndex)
      elif nativeReadOpcode(encoding):
        mixedLoopLoad(code, fixes, labels, op, encoding, unpaid, nextLabel)
      elif op.opcode == 120:
        mixedLoopByteStore(code, fixes, labels, op, unpaid, nextLabel)
      elif op.opcode != 2:
        # The staged prefix and infallible suffix share the canonical scalar emitter.
        emitX86OperationAccess(code, access, op.opcode, op.slots, op.immediate)
    for slot in 0..12:
      if (writes and (1'u16 shl slot)) != 0:
        # Publish only successful visits. A later refusal leaves this last complete state live.
        readAccess(code, access, slot, false)
        put(code, [0x49'u8, 0x89, 0x43, byte(slot*8)]) # MOV [R11+slot*8],RAX.
    put(code, [0x41'u8, 0xff, 0xc4]) # INC R12D counts one original complete visit.
    readAccess(code, access, branch.slots.aIndex, false)
    readAccess(code, access, branch.slots.bIndex, true)
    put(code, [0x48'u8, 0x39, 0xc8]) # CMP RAX,RCX.
    cycleEdge(code, fixes, 0x84, outside) # Equality takes the original false edge.
    put(code, [0x45'u8, 0x39, 0xec]) # CMP R12D,R13D.
    cycleEdge(code, fixes, 0x82, visit) # The certified true edge retries while funded.
    labels[int(unpaid)] = code.bytes.len
    put(code, [0x44'u8, 0x89, 0xe0]) # MOV EAX,R12D with no exit bit.
    cycleEdge(code, fixes, 0, finish)
    labels[int(outside)] = code.bytes.len
    put(code, [0x44'u8, 0x89, 0xe0, 0x0d]) # MOV EAX,R12D; OR EAX,exit bit.
    cycleWord(code, 0x80000000'u32)
    labels[int(finish)] = code.bytes.len
    put(code, [0x48'u8, 0x83, 0xc4, frameBytes, 0x41, 0x5d, 0x41, 0x5c, 0xc3])

    if code.bytes.len > NativeImageByteLimit: return @[]
    sealMixedLoop(code, fixes, labels)

  proc x86PaidMixedLoopInstructions*(operations: openArray[NativeOperation],
      guards: uint32): seq[byte] =
    ## Publish every successful operation before the next guard. A guard names the
    ## first uncommitted physical operation and leaves its checked worker the live prefix.
    ## The caller binds the original source interval, edges and funded visit ceiling.
    const
      visit = 0'u8
      capped = 1'u8
      outside = 2'u8
    result = @[]
    if operations.len < int(NativeMixedLoopMinimum) or operations.len > int(NativeReadFactLimit):
      return
    let terminal = operations.len-1
    let branch = operations[terminal]
    if branch.opcode != 171 or guards == 0: return

    var code = default(X86Block)
    var fixes: seq[X86CycleFixup] = @[]
    var labels = default(X86MixedLoopLabels)
    var guardLabels = default(array[int(NativeReadFactLimit)-1, byte])
    var nextLabel = 3'u8
    var emittedGuards = 0'u32
    let access = X86CanonicalAccess()
    # RDI stays canonical. All body operations preserve R9, R10 and R11.
    put(code, [0x49'u8, 0x89, 0xf2, 0x45, 0x31, 0xc9]) # Context R10, visits R9D.
    readCycleContextOp(code, [0x4d'u8, 0x8b, 0x9a], NativeMixedLoopVisitLimitOffset) # Cap R11.
    put(code, [0x4d'u8, 0x85, 0xdb]) # TEST R11,R11.
    cycleEdge(code, fixes, 0x84, capped)
    put(code, [0x49'u8, 0x81, 0xfb]) # CMP R11,256.
    cycleWord(code, NativeMixedLoopVisitLimit)
    cycleEdge(code, fixes, 0x87, capped)

    labels[int(visit)] = code.bytes.len
    for index in 0..<terminal:
      let op = operations[index]
      let encoding = nativeReadEncodingOpcode(op.opcode)
      let width = nativeMixedLoopStoreWidth(op.opcode)
      if width != 0 or nativeReadOpcode(encoding):
        let guard = nextLabel
        inc nextLabel
        guardLabels[index] = guard
        emittedGuards = emittedGuards or (1'u32 shl index)
        if width != 0:
          mixedLoopStore(code, fixes, labels, op, byte(width), guard, nextLabel)
        else:
          mixedLoopLoad(code, fixes, labels, op, encoding, guard, nextLabel)
      elif supportedScalarOpcode(op.opcode):
        emitX86OperationAccess(code, access, op.opcode, op.slots, op.immediate)
      else:
        return # The source certificate omits folded no-ops and binds the unique terminal.
    if emittedGuards != guards: return

    put(code, [0x41'u8, 0xff, 0xc1]) # INC R9D after the complete original body.
    readAccess(code, access, branch.slots.aIndex, false)
    readAccess(code, access, branch.slots.bIndex, true)
    put(code, [0x48'u8, 0x39, 0xc8]) # CMP RAX,RCX selects the original BNE edge.
    cycleEdge(code, fixes, 0x84, outside)
    put(code, [0x45'u8, 0x39, 0xd9]) # CMP R9D,R11D retries only while funded.
    cycleEdge(code, fixes, 0x82, visit)

    labels[int(capped)] = code.bytes.len
    put(code, [0x44'u8, 0x89, 0xc8, 0xc3]) # MOV EAX,R9D; RET at the original header.
    labels[int(outside)] = code.bytes.len
    put(code, [0x44'u8, 0x89, 0xc8, 0x0d]) # MOV EAX,R9D; OR EAX,checked outside bit.
    cycleWord(code, NativeMixedLoopExitBit)
    put(code, [0xc3'u8])
    for index in 0..<terminal:
      let guard = guardLabels[index]
      if guard != 0:
        labels[int(guard)] = code.bytes.len
        put(code, [0x44'u8, 0x89, 0xc8, 0x0d]) # MOV EAX,R9D; OR EAX,one-based guard.
        cycleWord(code, uint32(index+1) shl NativeMixedLoopGuardShift)
        put(code, [0xc3'u8])

    if code.bytes.len > NativeImageByteLimit: return
    result = sealMixedLoop(code, fixes, labels)
