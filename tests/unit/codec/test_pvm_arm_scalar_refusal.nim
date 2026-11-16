# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Scalar and branch builders must never return a publishable prefix after malformed input.

import std/[assertions, syncio]
import ../../../src/pvm/program
import ../../../src/pvm/internal/arm64_jit

proc scalarRefusal() =
  ## An unsupported operation poisons preceding and subsequent bytes until this builder is discarded.
  let slots = default(RegisterSlots)
  var control = default(ArmBlock)
  emitArmOperation(control, 20, slots, 42)
  assert control.error == ArmEmissionError.None
  assert armInstructions(control) == @[0xd2800544'u32, 0xf2a00004'u32, 0xf2c00004'u32,
    0xf2e00004'u32,
    0xf9000004'u32], "valid scalar encoding changed"
  for opcode in [0'u8, 10, 50, 80, 255]:
    var code = default(ArmBlock)
    emitArmOperation(code, 20, slots, 42)
    emitArmOperation(code, opcode, slots, 0)
    emitArmOperation(code, 20, slots, 43)
    assert code.error == ArmEmissionError.UnsupportedOpcode
    emitArmBranch(code, 170, slots, 0, high(uint32), 32)
    assert code.error == ArmEmissionError.UnsupportedOpcode, "later refusal erased the first cause"
    assert armInstructions(code).len == 0, "unsupported scalar published partial machine code"
    emitArmOperation(code, 20, slots, 44)
    assert armInstructions(code).len == 0, "extracting failed words must not reset the refusal"

proc branchRefusal() =
  ## Invalid conditions and reserved destinations refuse the whole builder, including a valid prefix.
  let slots = default(RegisterSlots)
  var control = default(ArmBlock)
  emitArmBranch(control, 170, slots, 0, 16, 32)
  assert control.error == ArmEmissionError.None
  assert armInstructions(control) == @[0xf9400004'u32, 0xeb04009f'u32, 0x52800201'u32,
    0x72a00001'u32,
    0x52800402'u32, 0x72a00002'u32, 0x1a820020'u32], "valid branch encoding changed"
  for opcode in [0'u8, 20, 80, 91, 169, 176, 255]:
    var code = default(ArmBlock)
    emitArmOperation(code, 20, slots, 42)
    emitArmBranch(code, opcode, slots, 0, 16, 32)
    assert code.error == ArmEmissionError.UnsupportedOpcode
    assert armInstructions(code).len == 0, "invalid branch published partial machine code"
  for target in [2147483646'u32, 2147483647, high(uint32)]:
    for yes in [false, true]:
      var code = default(ArmBlock)
      emitArmBranch(code, 170, slots, 0, (if yes: target else: 16'u32),
        (if yes: 32'u32 else: target))
      assert code.error == ArmEmissionError.InvalidDestination
      assert armInstructions(code).len == 0, "reserved branch destination was published"

proc publicationRefusal() =
  ## Nested consumers must refuse a failed body before changing OS or cache state.
  let slots = default(RegisterSlots)
  let jit = newArmJit()
  assert armEntry(jit, 0, 5) == 0
  var code = default(ArmBlock)
  for value in 0'u64..3: emitArmOperation(code, 20, slots, value)
  emitArmOperation(code, 0, slots, 0)
  var words = armInstructions(code)
  assert not publishArmEntry(jit, 0, 4, 4, words)
  assert words.len == 0 and jit.fragments == 0 and jit.codeBytes == 0
  var body = default(ArmBlock)
  emitArmOperation(body, 20, slots, 42)
  emitArmBranch(body, 170, slots, 0, 3, 4)
  emitArmOperation(body, 0, slots, 0)
  var blocks = default(array[3, ArmRegionBlock])
  blocks[0] = ArmRegionBlock(header: 0, span: 2, operations: 2, yes: 3, no: 4,
    price: 2, body: move(body))
  assert not publishArmRegion(jit, blocks, 2)
  assert not publishArmRegion(jit, blocks, 2), "refused composition poisoned the next region attempt"
  assert jit.fragments == 0 and jit.codeBytes == 0

scalarRefusal()
branchRefusal()
publicationRefusal()
echo "PVM ARM scalar refusal passed"
