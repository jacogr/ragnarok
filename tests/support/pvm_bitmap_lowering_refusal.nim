# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Qualify failure-atomic bitmap emission under the pinned recoverable heap cap.

import std/assertions
import ../../src/pvm/program
import ../../src/pvm/internal/[native_bitmap_loop, native_ir]
import ./pvm_bitmap_fixture

import ../../src/pvm/internal/native_platform
when defined(pvmX86Jit):
  import ../../src/pvm/internal/x86_jit
else:
  import ../../src/pvm/internal/arm64_jit

proc runBitmapLoweringRefusal*() =
  ## Compare constrained emission with a known complete image and the same worker lowerer.
  let owner = bitmapOwner()
  var proof = NativeBitmapLoop(epoch: 1,
    sites: [NativeBitmapSite(header: 100, first: 10, price: 2),
      NativeBitmapSite(header: 200, first: 20, price: 3),
      NativeBitmapSite(header: 300, first: 30, price: 5),
      NativeBitmapSite(header: 400, first: 40, price: 7),
      NativeBitmapSite(header: 500, first: 50, price: 11)],
    exits: [600'u32, 700, 800])
  for index, pc in [5'u64, 8, 11, 14, 17, 20, 23, 26, 29, 32, 35, 38, 40, 43, 46, 49]:
    let item = instruction(owner, CodeAddress(pc))
    assert item.error == ProgramError.None, "decode literal bitmap operation"
    proof.operations[index] = NativeOperation(opcode: item.value.opcode,
      slots: instructionRegisters(item), immediate: uint64(item.value.x))
  assert proof.complete, "heap pressure uses a valid certificate"
  template encode(): untyped =
    ## Exercise the production encoder of the selected ISA.
    when defined(pvmX86Jit): encodeX86BitmapLoop(proof)
    else: encodeArmBitmapLoop(proof)
  block:
    let original = encode()
    assert original.len > 0 and lowerNativeBitmapLoop(proof).ready, "unconstrained image publishes"
  # Full-width prices and multi-halfword targets exercise the largest ARM encodings.
  for role in BitmapBlock:
    proof.sites[role].price = 0x123456789abcdef0'u64
    proof.sites[role].header += 0x10100
  for side in BitmapExit:
    proof.exits[side] += 0x10100
  assert proof.complete
  let expected = encode()
  assert expected.len > 0
  const heapCap = 1024*1024
  for headroom in [192, 384, 1024]:
    # The first two refuse the instruction allocation. At 1 KiB the instructions
    # fit but the combined instruction and fixup buffers do not.
    let filler = alloc(heapCap-getOccupiedMem()-headroom)
    assert filler != nil
    let actual = encode()
    let image = lowerNativeBitmapLoop(proof)
    dealloc(filler)
    assert actual.len == 0 and not image.ready, "no partial image under heap pressure"
  assert encode() == expected and lowerNativeBitmapLoop(proof).ready,
    "independent lowering recovers with identical machine code"
