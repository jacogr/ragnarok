# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Direct operands require a complete admitted Ring and one map for all decoded source,
## destination and predicate lanes after register saturation. The six preserved GPRs hold
## the entire map across every rotation. If the map or resident image does not fit, the
## caller uses the canonical renderer. The region owns guards and source receipts.

when declared(X86ResidentAccess) and declared(NativeRegisterRing):
  func ringLane(slot: range[0..12]): uint32 =
    ## Record the original decoded lane, including saturated aliases.
    1'u32 shl int(slot)

  func ringLaneUse(ring: NativeRegisterRing): tuple[used, written: uint32] =
    ## The complete shape contains ADD64, SHR32, ADDW and both 64-bit shifts.
    ## Every immediate body reads B; ADD64 reads A too. All predicates read A.
    assert ring.complete
    var used = 0'u32
    var written = 0'u32
    for item in ring.blocks:
      used = used or ringLane(item.branch.slots.aIndex)
      if item.branch.opcode == 173:
        used = used or ringLane(item.branch.slots.bIndex)
      for position in 0..<int(item.span)-1:
        let op = item.body[position]
        used = used or ringLane(op.slots.bIndex)
        if op.opcode == 200:
          used = used or ringLane(op.slots.aIndex)
        written = written or ringLane(op.slots.destinationIndex)
    (used or written, written)

  func ringHardware(bank: X86ResidentAccess, slot: range[0..12]): uint8 =
    ## A preflight bank covers every original operand. Zero cannot name hardware.
    let encoded = bank.registers[slot]
    assert encoded != 0
    encoded-1

  proc ringModRm(code: var X86Block, opcode, reg, rm: uint8, wide: bool) =
    ## Encode a GPR ModRM or opcode extension. No memory form is allowed here.
    let rex = 0x40'u8 or (if wide: 8'u8 else: 0'u8) or
      ((reg and 8) shr 1) or ((rm and 8) shr 3)
    if rex != 0x40:
      put(code, [rex])
    put(code, [opcode, 0xc0'u8 or ((reg and 7) shl 3) or (rm and 7)])

  proc emitRingOperand(code: var X86Block, bank: X86ResidentAccess, op: NativeOperation) =
    ## Use preflight hardware operands and preserve signed low-word results.
    let b = ringHardware(bank, op.slots.bIndex)
    let dst = ringHardware(bank, op.slots.destinationIndex)
    case op.opcode
    of 200:
      let a = ringHardware(bank, op.slots.aIndex)
      if dst == b:
        # The old B value is already in the destination of this commutative ADD.
        ringModRm(code, 0x01, a, dst, true)
      else:
        # A distinct destination consumes A without overwriting B.
        if dst != a:
          ringModRm(code, 0x89, a, dst, true)
        ringModRm(code, 0x01, b, dst, true)
    of 131:
      # A 32-bit ADD truncates the immediate and both inputs before signed extension.
      if dst != b:
        ringModRm(code, 0x89, b, dst, false)
      let value = uint32(op.immediate and 0xffffffff'u64)
      if value <= 127 or value >= 0xffffff80'u32:
        ringModRm(code, 0x83, 0, dst, false)
        put(code, [byte(value and 255)])
      else:
        ringModRm(code, 0x81, 0, dst, false)
        regionWord(code, value)
      ringModRm(code, 0x63, dst, dst, true) # MOVSXD r64,r32.
    of 139:
      let count = byte(op.immediate and 31)
      if count == 0:
        # With no shift, bit 31 can still require sign extension.
        ringModRm(code, 0x63, dst, b, true)
      else:
        # A nonzero logical count clears bit 31. The 32-bit write clears the high half.
        if dst != b:
          ringModRm(code, 0x89, b, dst, false)
        ringModRm(code, 0xc1, 5, dst, false)
        put(code, [count])
    else:
      # The admitted wide shifts each consume the current B and overwrite the original destination.
      assert op.opcode in [151'u8, 152]
      let count = byte(op.immediate and 63)
      if dst != b:
        ringModRm(code, 0x89, b, dst, true)
      if count != 0:
        ringModRm(code, 0xc1, (if op.opcode == 151: 4'u8 else: 5'u8), dst, true)
        put(code, [count])

  proc emitRingShiftPair(code: var X86Block, bank: X86ResidentAccess,
      first, second: NativeOperation): bool =
    ## Equal shifts leave the low 64-count bits of the original source.
    ## Decline before writing any bytes when two immediate shifts are needed.
    if not matchesNativeRingShiftPair(first, second): return false
    let count = int(first.immediate and 63)
    if count in 1..31: return false
    let source = ringHardware(bank, first.slots.bIndex)
    let dst = ringHardware(bank, first.slots.destinationIndex)
    if count == 0:
      # A zero pair is a full-width copy, which can be omitted for an alias.
      if dst != source:
        ringModRm(code, 0x89, source, dst, true)
    elif count == 32:
      # The 32-bit MOV clears the upper half even when source and destination alias.
      ringModRm(code, 0x89, source, dst, false)
    else:
      # For 1 to 31 retained bits, the 32-bit AND also clears the upper half.
      if dst != source:
        ringModRm(code, 0x89, source, dst, false)
      ringModRm(code, 0x81, 4, dst, false)
      regionWord(code, (1'u32 shl (64-count))-1)
    true
