# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private proof controls for ARM read refusal; emitted malformed images are never executed.

proc witnessArmReadGuards*() =
  ## Real complete requests and malformed private relocations exercise the same production finishers.
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
    span.body.words = @[0x14000000'u32, 0x14000000'u32]
    span.guards = @[ArmReadGuard(at: 0), ArmReadGuard(at: 1)]
    let original = @[0xd503201f'u32, 0x14000000'u32, 0x14000000'u32, 0xd65f03c0'u32]
    var words = original
    assert armReadPatchGuards(words, span, 0, 3)
    assert words == @[0xd503201f'u32, 0x14000002'u32, 0x14000001'u32, 0xd65f03c0'u32]
    for scenario in 0..<8:
      # The second malformed edge must not leave the first valid edge patched.
      words = original
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
      assert words == original, "failed patch changed a preceding valid relocation"

  block refusedImage:
    # A late relocation refusal clears image offsets as well as words; no finisher can add a RET-only image.
    var span = default(ArmReadSpan)
    span.body.words = @[0x14000000'u32]
    span.guards = @[ArmReadGuard(at: 0, conditional: true)]
    assert finishArmCheckedRead(span).len == 0
    let macroImage = armMacroReadImage(span)
    assert macroImage.words.len == 0 and macroImage.successAt == 0 and macroImage.refusalAt == 0
    span.body.terminal = @[0xd503201f'u32]
    let resident = armReadImage(span, 1, true, true)
    assert resident.words.len == 0 and resident.successAt == 0 and resident.refusalAt == 0
    assert armReadImage(span, 1, false, false).words.len == 0
    span.body.terminal = @[]
    assert armReadImage(span, 1, false, true).words.len == 0

  when NativeReadCycleEnabled:
    block inlineRefusal:
      # Invalid inline edges leave both existing caller buffers intact; a valid edge has the exact source shift.
      var span = default(ArmReadSpan)
      span.body.words = @[0x14000000'u32]
      span.guards = @[ArmReadGuard(at: 0, conditional: true)]
      var words = @[0xd503201f'u32]
      var fixes = @[ArmMemoryCycleFixup(at: 0, target: 3, condition: 16)]
      assert not appendArmCycleRead(words, fixes, span, 7)
      assert words == @[0xd503201f'u32] and fixes.len == 1 and fixes[0].target == 3
      span.guards[0].conditional = false
      assert appendArmCycleRead(words, fixes, span, 7)
      assert words == @[0xd503201f'u32, 0xaa1403f1'u32, 0x14000000'u32]
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
