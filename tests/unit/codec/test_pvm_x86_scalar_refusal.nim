# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Scalar and branch builders must never return a publishable prefix after malformed input.

import std/[assertions, syncio]
import ../../../src/pvm/program
import ../../../src/pvm/internal/x86_jit

proc scalarRefusal() =
  ## An unsupported operation poisons preceding and subsequent bytes until this builder is discarded.
  let slots = default(RegisterSlots)
  var control = default(X86Block)
  emitX86Operation(control, 20, slots, 42)
  assert control.error == X86EmissionError.None
  assert takeX86Instructions(control) == @[0x48'u8, 0xb8, 42, 0, 0, 0, 0, 0, 0, 0,
    0x48, 0x89, 0x47, 0], "valid scalar encoding changed"
  for opcode in [0'u8, 10, 50, 80, 255]:
    var code = default(X86Block)
    emitX86Operation(code, 20, slots, 42)
    emitX86Operation(code, opcode, slots, 0)
    emitX86Operation(code, 20, slots, 43)
    assert code.error == X86EmissionError.UnsupportedOpcode
    emitX86Branch(code, 170, slots, 0, high(uint32), 32)
    assert code.error == X86EmissionError.UnsupportedOpcode, "later refusal erased the first cause"
    assert takeX86Instructions(code).len == 0, "unsupported scalar published partial machine code"
    emitX86Operation(code, 20, slots, 44)
    assert takeX86Instructions(code).len == 0, "taking failed bytes must not reset the refusal"

proc branchRefusal() =
  ## Invalid conditions and reserved destinations refuse the whole builder, including a valid prefix.
  let slots = default(RegisterSlots)
  var control = default(X86Block)
  emitX86Branch(control, 170, slots, 0, 16, 32)
  assert control.error == X86EmissionError.None
  assert takeX86Instructions(control) == @[0x48'u8, 0x8b, 0x47, 0, 0x48, 0x8b, 0x4f, 0,
    0x48, 0x39, 0xc8, 0xb8, 32, 0, 0, 0, 0xba, 16, 0, 0, 0, 0x0f, 0x44, 0xc2],
    "valid branch encoding changed"
  for opcode in [0'u8, 20, 80, 91, 169, 176, 255]:
    var code = default(X86Block)
    emitX86Operation(code, 20, slots, 42)
    emitX86Branch(code, opcode, slots, 0, 16, 32)
    assert code.error == X86EmissionError.UnsupportedOpcode
    assert takeX86Instructions(code).len == 0, "invalid branch published partial machine code"
  for target in [2147483646'u32, 2147483647, high(uint32)]:
    for yes in [false, true]:
      var code = default(X86Block)
      emitX86Branch(code, 170, slots, 0, (if yes: target else: 16'u32),
        (if yes: 32'u32 else: target))
      assert code.error == X86EmissionError.InvalidDestination
      assert takeX86Instructions(code).len == 0, "reserved branch destination was published"

proc publicationRefusal() =
  ## Consumers that bypass extraction must still refuse private partial bytes before touching OS/cache state.
  let slots = default(RegisterSlots)
  let jit = newX86Jit()
  assert x86Entry(jit, 0, 5) == 0
  var code = default(X86Block)
  for value in 0'u64..3: emitX86Operation(code, 20, slots, value)
  emitX86Operation(code, 0, slots, 0)
  assert not publishX86Entry(jit, 0, 4, 4, code)
  assert x86Entry(jit, 0, 5) == 0, "refused builder changed the reusable coordinate or storage policy"
  assert jit.fragments == 0 and jit.codeBytes == 0
  var body = default(X86Block)
  emitX86Operation(body, 20, slots, 42)
  emitX86Branch(body, 170, slots, 0, 3, 4)
  emitX86Operation(body, 0, slots, 0)
  var blocks = default(array[2, X86RegionBlock])
  blocks[0] = X86RegionBlock(header: 0, span: 2, operations: 2, yes: 3, no: 4,
    price: 2, body: move(body))
  assert not publishX86Region(jit, blocks, 1)
  assert not publishX86Region(jit, blocks, 1), "refused composition poisoned the next region attempt"
  assert jit.fragments == 0 and jit.codeBytes == 0

scalarRefusal()
branchRefusal()
publicationRefusal()
echo "PVM x86 scalar refusal passed"
