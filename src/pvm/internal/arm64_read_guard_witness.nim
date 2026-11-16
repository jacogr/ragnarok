# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private proof controls for ARM read refusal; emitted malformed images are never executed.

when NativeReadCycleEnabled:
  proc witnessArmCycleHardwareRefusal*(cycle: NativeReadCycle) =
    ## Inject a late hardware-operand refusal through every real layout retry, then recover on the same request.
    let valid = armReadCycleInstructions(cycle)
    assert valid.len > 0, "complete cycle control did not encode"
    armCycleInvalidOperandWitness = true
    let refused = armReadCycleInstructions(cycle)
    armCycleInvalidOperandWitness = false
    assert refused.len == 0, "read cycle published a partial image after late operand refusal"
    assert armReadCycleInstructions(cycle) == valid

proc witnessArmReadGuards*() =
  ## Real complete requests and malformed private relocations exercise the same production finishers.
  block hardwareRefusal:
    # A late malformed operand cannot expose a preceding valid instruction or erase its first refusal.
    var words = ArmWords(data: @[0xd503201f'u32])
    cycleLoad(words, 4, 20, 1)
    assert words.failure == ArmEmissionError.InvalidCertificate and words.data == @[0xd503201f'u32]
    cycleImmediate(words, 31, 42)
    assert words.failure == ArmEmissionError.InvalidCertificate
    assert takeArmWords(words).len == 0 and takeArmWords(words).len == 0
    var outer = ArmWords(data: @[0xd65f03c0'u32])
    outer.add(words)
    assert outer.failure == ArmEmissionError.InvalidCertificate and outer.data == @[0xd65f03c0'u32]
    assert takeArmWords(outer).len == 0
    for terminal in [false, true]:
      # Both leaf sections contribute their refusal before scalar/branch renderers inspect any prefix.
      var leaf = default(ArmBlock)
      emitArmOperation(leaf, 20, default(RegisterSlots), 42)
      if terminal: armImmediate(leaf.terminal, 17, 42)
      else: armImmediate(leaf.words, 17, 42)
      emitArmOperation(leaf, 0, default(RegisterSlots), 0)
      assert leaf.error == ArmEmissionError.InvalidRegister and armInstructions(leaf).len == 0
    words = default(ArmWords)
    assert not armSmallIndirectAddress(words, 17, 0, false)
    assert words.failure == ArmEmissionError.InvalidRegister and takeArmWords(words).len == 0
    words = default(ArmWords)
    assert not armSmallIndirectAddress(words, 4, 0x80000000'u32, false)
    assert words.failure == ArmEmissionError.None
    armImmediate(words, 16, 42)
    assert takeArmWords(words) == @[0xd2800550'u32, 0xf2a00010'u32, 0xf2c00010'u32, 0xf2e00010'u32]
  block operandBoundaries:
    # Exercise each hardware helper's refusal after a valid prefix; scratch reset cannot revive it.
    for scenario in 0..<12:
      var words = ArmWords(data: @[0xd503201f'u32])
      case scenario
      of 0: armCompactImmediate(words, 17, 42)
      of 1: cycleLoad(words, 31, 20, 0)
      of 2: cycleLoad(words, 4, 20, 32768)
      of 3: cycleStore(words, 32, 20, 0)
      of 4: cycleStore(words, 4, 20, 1)
      of 5: cycleImmediate(words, 31, 42)
      of 6: cycleMove(words, 4, 31)
      of 7: cycleCompare(words, 4, 31)
      of 8: cycleCompareImmediate(words, 4, 4096)
      of 9: cycleAddImmediate(words, 4, 20, 4096)
      of 10: cycleAddRegister(words, 4, 20, 31)
      else: words[1] = 0xd65f03c0'u32
      let failure = words.failure
      assert failure != ArmEmissionError.None and words.data == @[0xd503201f'u32]
      words.shrink(0)
      cycleLoad(words, 4, 20, 0)
      assert words.failure == failure and words.data == @[0xd503201f'u32]
      assert takeArmWords(words).len == 0
    var words = default(ArmWords)
    # The largest aligned LDR offset and the architectural zero-register STR are both legal.
    cycleLoad(words, 30, 30, 32760)
    cycleStore(words, 31, 30, 32760)
    assert words.failure == ArmEmissionError.None
    assert takeArmWords(words) == @[0xf97fffde'u32, 0xf93fffdf'u32]
  var body = initNativeReadBody(0, 3, 0, 3, 1)
  for position in 1'u32..2:
    # Copy two contiguous loads through ordinary request admission before checking the positive producer.
    assert addReadBodyOperation(body, position, position,
      NativeOperation(opcode: 130, slots: default(RegisterSlots), immediate: 0))
  assert body.complete and armCheckedReadInstructions(body).len > 0
  assert armCheckedReadInstructions(default(NativeReadBody)).len == 0
  assert encodeArmRegisterRing(default(NativeRegisterRing)).len == 0

  block windowRefusal:
    # An invalid range must fail before unsigned subtraction, and unaligned loads must fail before encoding.
    for scenario in 0..<3:
      var span = default(ArmReadSpan)
      case scenario
      of 0: beginArmReadWindow(span, 0, 1, 0)
      of 1: beginArmReadWindow(span, 0, 0, 4089)
      else:
        beginArmReadWindow(span, 0, 0, 8)
        emitArmWindowRead(span, 0, 1)
      assert span.body.error == ArmEmissionError.InvalidCertificate
      assert finishArmCheckedRead(span).len == 0
    var span = default(ArmReadSpan)
    beginArmReadWindow(span, 0, 0, 8)
    emitArmWindowRead(span, 0, 8)
    assert span.body.error == ArmEmissionError.None and armReadInstructions(span, 1).len > 0
    span = default(ArmReadSpan)
    emitArmReadArithmetic(span, 0, default(RegisterSlots), 0)
    beginArmReadWindow(span, 0, 1, 0)
    emitArmCheckedReadAt(span, 31, 130)
    assert span.body.error == ArmEmissionError.UnsupportedOpcode
    assert finishArmCheckedRead(span).len == 0

  block hardwareDestination:
    # A hardware-only read cannot reinterpret SP/XZR or an out-of-range value as a destination.
    for destination in [31'u32, 32, high(uint32)]:
      var span = default(ArmReadSpan)
      emitArmCheckedReadAt(span, destination, 130)
      assert span.body.error == ArmEmissionError.InvalidRegister
      assert span.body.words.len == 0 and finishArmCheckedRead(span).len == 0

  block relocations:
    # Independent B encodings pin forward word displacements without sharing the patch calculation.
    var span = default(ArmReadSpan)
    span.body.words = ArmWords(data: @[0x14000000'u32, 0x14000000'u32])
    span.guards = @[ArmReadGuard(at: 0), ArmReadGuard(at: 1)]
    let original = @[0xd503201f'u32, 0x14000000'u32, 0x14000000'u32, 0xd65f03c0'u32]
    var words = ArmWords(data: original)
    assert armReadPatchGuards(words, span, 0, 3)
    assert words.data == @[0xd503201f'u32, 0x14000002'u32, 0x14000001'u32, 0xd65f03c0'u32]
    for scenario in 0..<8:
      # The second malformed edge must not leave the first valid edge patched.
      words = ArmWords(data: original)
      span.guards[1] = ArmReadGuard(at: 1)
      var leading = 0
      var failure = 3
      case scenario
      of 0: span.guards[1].at = -1
      of 1: span.guards[1].at = high(int)
      of 2: span.guards[1].at = 2
      of 3: span.guards[1].conditional = true
      of 4: leading = high(int)
      of 5: leading = -2
      of 6: failure = high(int)
      else: failure = 0
      assert not armReadPatchGuards(words, span, leading, failure)
      assert words.data == original, "failed patch changed a preceding valid relocation"

  block refusedImage:
    # A late relocation refusal clears image offsets as well as words; no finisher can add a RET-only image.
    var span = default(ArmReadSpan)
    span.body.words = ArmWords(data: @[0x14000000'u32])
    span.guards = @[ArmReadGuard(at: 0, conditional: true)]
    assert finishArmCheckedRead(span).len == 0
    let macroImage = armMacroReadImage(span)
    assert macroImage.words.len == 0 and macroImage.successAt == 0 and macroImage.refusalAt == 0
    span.body.terminal = ArmWords(data: @[0xd503201f'u32])
    let resident = armReadImage(span, 1, true, true)
    assert resident.words.len == 0 and resident.successAt == 0 and resident.refusalAt == 0
    assert armReadImage(span, 1, false, false).words.len == 0
    span.body.terminal = ArmWords(data: @[])
    assert armReadImage(span, 1, false, true).words.len == 0

  when NativeReadCycleEnabled:
    block inlineRefusal:
      # Invalid inline edges leave both existing caller buffers intact; a valid edge has the exact source shift.
      var span = default(ArmReadSpan)
      span.body.words = ArmWords(data: @[0x14000000'u32])
      span.guards = @[ArmReadGuard(at: 0, conditional: true)]
      var words = ArmWords(data: @[0xd503201f'u32])
      var fixes = @[ArmMemoryCycleFixup(at: 0, target: 3, condition: 16)]
      assert not appendArmCycleRead(words, fixes, span, 7)
      assert words.data == @[0xd503201f'u32] and fixes.len == 1 and fixes[0].target == 3
      span.guards[0].conditional = false
      assert appendArmCycleRead(words, fixes, span, 7)
      assert words.data == @[0xd503201f'u32, 0xaa1403f1'u32, 0x14000000'u32]
      assert fixes.len == 2 and fixes[1].at == 2 and fixes[1].target == 7

  block regionPolicy:
    # Two genuine branch blocks remain compilable; rotation requires the complete three-role region.
    var blocks = default(array[3, ArmRegionBlock])
    for index in 0..<2:
      var scalar = default(ArmBlock)
      emitArmOperation(scalar, 20, default(RegisterSlots), 42)
      emitArmBranch(scalar, 170, default(RegisterSlots), 0, 0, 4)
      blocks[index] = ArmRegionBlock(header: uint32(index*2), span: 2, operations: 2,
        yes: 0, no: 4, price: 1, body: move(scalar))
    assert armRegionWords(blocks, 2, false).len > 0
    assert armRegionWords(blocks, 2, true).len == 0
    assert armRegionWords(blocks, 2, false, NativeRingRoundBudget(enabled: true)).len == 0
