# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Lower a source-certified mixed byte-store self-loop.
## Included beside the checked Read-cycle emitter so it can share its memory guards.

type X86MixedLoopLabels = array[6+4*(int(NativeReadFactLimit)-2), int]
  ## Four fixed targets, two Store targets and four per possible read.

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

proc mixedLoopByteStore(code: var X86Block, fixes: var seq[X86CycleFixup],
    labels: var X86MixedLoopLabels, op: NativeOperation, refusal: byte, nextLabel: var byte) =
  ## The only mutation needs a current writable byte and existing dirty membership.
  const stackOffset = byte(NativeCycleWritableOffset)
  const rwOffset = stackOffset+24
  let access = X86CanonicalAccess()
  readBodyBase(code, access, op.slots.bIndex)
  put(code, [0x81'u8, 0xc2]) # ADD EDX,disp32 captures the old staged base.
  cycleWord(code, uint32(op.immediate and 0xffffffff'u64))
  put(code, [0x81'u8, 0xfa]) # CMP EDX,65536 protects the low pages.
  cycleWord(code, 65536)
  cycleEdge(code, fixes, 0x82, refusal)
  put(code, [0x83'u8, 0xfa, 0xfe]) # CMP EDX,0xfffffffe excludes the top byte.
  cycleEdge(code, fixes, 0x87, refusal)
  let rw = nextLabel
  let ready = nextLabel+1
  nextLabel += 2
  # A selected stack extent shadows the RW extent even when the stack is empty.
  put(code, [0x49'u8, 0x3b, 0x52, stackOffset]) # CMP RDX,[R10+stack.first].
  cycleEdge(code, fixes, 0x82, rw)
  emitCheckedExtent(code, fixes, stackOffset, 1, refusal, ready)
  labels[int(rw)] = code.bytes.len
  emitCheckedExtent(code, fixes, rwOffset, 1, refusal, ready)
  labels[int(ready)] = code.bytes.len
  put(code, [0x48'u8, 0x85, 0xc9]) # TEST RCX,RCX requires live writable storage.
  cycleEdge(code, fixes, 0x84, refusal)
  put(code, [0x4c'u8, 0x8d, 0x04, 0x01]) # LEA R8,[RCX+RAX] holds the exact byte address.
  readCycleContextOp(code, [0x49'u8, 0x8b, 0xb2], NativeCycleDirtyOffset)
  put(code, [0x48'u8, 0x85, 0xf6]) # TEST RSI,RSI checks the dirty bitmap pointer.
  cycleEdge(code, fixes, 0x84, refusal)
  readCycleDirtyPage(code, fixes, refusal, false)
  readAccess(code, access, op.slots.aIndex, false)
  put(code, [0x41'u8, 0x88, 0x00]) # MOV [R8],AL commits only after every guard.

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
  for fix in fixes:
    # The single checked self-edge can patch backward. Every target is image-local.
    let target = labels[int(fix.target)]
    assert target > 0 and target < code.bytes.len
    let delta = cast[uint32](int32(target-(fix.at+4)))
    for shift in 0..<4:
      code.bytes[fix.at+shift] = byte((delta shr (shift*8)) and 255)
  takeX86Instructions(code)
