# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original-source fusion IR reads immutable admission/source only:
## it never asks which checked worker currently owns a node or which operands are cached.
## Logical source addresses remain separate from the physical overlay coordinates.

when declared(FlatPlan):
  type FusionSourceBlock = object
    ## A bounded copied original block; no program, frame, memory or callback borrow is retained.
    start, terminalPc: CodeAddress
    first, span, bodyCount, guards: uint32
    price: uint64
    locations: array[NativeReadFactLimit, CodeAddress]
    operations: array[int(NativeReadFactLimit)-1, NativeOperation]
    terminal: NativeOperation
    targets: array[2, CodeAddress]
    targetValid: array[2, bool]

  func fusionSourceTarget(item: Instruction, target: var CodeAddress): bool =
    ## Resolve the mathematical displacement without wrapping a negative or overflowing address.
    let pc = uint64(item.address)
    if item.displacement < 0:
      # The owner decoder limits displacements to signed 32 bits; retain a widened magnitude.
      let distance = uint64(-(item.displacement+1))+1
      if distance > pc: return false
      target = CodeAddress(pc-distance)
    else:
      let distance = uint64(item.displacement)
      if distance > high(uint64)-pc: return false
      target = CodeAddress(pc+distance)
    true

  proc decodeFusionSource(plan: FlatPlan, pc: CodeAddress, found: var FusionSourceBlock): bool =
    ## Decode at most one bounded original block independently of the lazy checked catalogue.
    ## Failure leaves the caller's output untouched. Source/gas limits are the admitted owner's.
    if plan == nil or plan.singleStep or uint64(pc) >= uint64(plan.codeBytes): return false
    let containing = containingBlockStart(plan.source, pc)
    if containing.error != ProgramError.None or containing.value != pc: return false
    let ranks {.cursor.} = plan.ranks
    if ranks == nil: return false
    let wordIndex = int(uint64(pc) div 64)
    if wordIndex >= ranks.words.len or wordIndex >= ranks.prefixes.len: return false
    let bit = 1'u64 shl int(uint64(pc) mod 64)
    if (ranks.words[wordIndex] and bit) == 0: return false
    let prefix = ranks.prefixes[wordIndex]
    let before = uint32(countSetBits(ranks.words[wordIndex] and (bit-1)))
    if prefix >= plan.admittedFacts or before >= plan.admittedFacts-prefix: return false
    let first = prefix+before
    var candidate = FusionSourceBlock(start: pc, first: first)
    var cursor = pc
    for position in 0'u32..<NativeReadFactLimit:
      # No metadata is materialized and no source-sized scratch is allocated during reconstruction.
      if candidate.span >= plan.admittedFacts-first: return false
      let decoded = instruction(plan.source, cursor)
      if decoded.error != ProgramError.None: return false
      let item = decoded.value
      if item.address != cursor or uint64(cursor) > high(uint64)-1-uint64(item.skip): return false
      let next = CodeAddress(uint64(cursor)+1+uint64(item.skip))
      candidate.locations[int(position)] = cursor
      inc candidate.span
      if terminatesBlock(item.opcode):
        # The terminal remains original source even when native lowering must leave it checked.
        candidate.terminalPc = cursor
        candidate.terminal = NativeOperation(opcode: item.opcode, slots: instructionRegisters(
            decoded),
          immediate: uint64(item.x))
        case item.opcode
        of 1:
          candidate.targets[0] = next
          candidate.targetValid[0] = instructionHasFallthrough(decoded)
        of 40, 80:
          var target = CodeAddress(0)
          candidate.targetValid[0] = instructionTargetStartsBlock(decoded) and
            fusionSourceTarget(item, target)
          candidate.targets[0] = target
          if item.opcode == 40: candidate.terminal.immediate = 0
        of 81..90, 170..175:
          candidate.targets[0] = next
          candidate.targetValid[0] = instructionHasFallthrough(decoded)
          var target = CodeAddress(0)
          candidate.targetValid[1] = instructionTargetStartsBlock(decoded) and
            fusionSourceTarget(item, target)
          candidate.targets[1] = target
          candidate.terminal.immediate = if item.opcode <= 90:
              flatSext32(uint32(uint64(item.x) and 0xffffffff'u64)) else: 0'u64
        of 180:
          candidate.terminal.immediate = (uint64(item.x) and 0xffffffff'u64) or
            ((uint64(item.y) and 0xffffffff'u64) shl 32)
        else:
          discard # Dynamic and unsupported terminals acquire their entry/fallback policy at binding.
        let priced = blockGas(plan.source, pc, plan.cycles)
        if priced.error != GasError.None: return false
        candidate.price = uint64(priced.value)
        found = candidate
        return true
      if not instructionHasFallthrough(decoded): return false
      if item.opcode != 2:
        # Folded noops consume source span and price while preserving a dense body operation array.
        if candidate.bodyCount >= uint32(candidate.operations.len): return false
        let index = int(candidate.bodyCount)
        if nativeMixedLoopStoreWidth(item.opcode) != 0 or
            nativeReadOpcode(nativeReadEncodingOpcode(item.opcode)):
          candidate.guards = candidate.guards or (1'u32 shl candidate.bodyCount)
        elif not supportedScalarOpcode(item.opcode):
          return false
        candidate.operations[index] = NativeOperation(opcode: item.opcode,
            slots: instructionRegisters(decoded),
          immediate: uint64(item.x))
        inc candidate.bodyCount
      cursor = next
    false
