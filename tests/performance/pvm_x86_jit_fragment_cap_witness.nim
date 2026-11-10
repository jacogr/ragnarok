# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prove the shared x86 leaf/region publication budget and refusal preservation at its boundaries.

import std/[assertions, syncio]
import ../../src/pvm/[program, machine]
import ../../src/pvm/internal/x86_jit

proc pureLeaf(): X86Block =
  ## Four ordinary scalar operations give the publisher a valid callable leaf.
  var body = default(X86Block)
  let slots = default(RegisterSlots)
  for index in 0..<4:
    emitX86Operation(body, 51'u8, slots, uint64(index+1))
  body

proc conditionalLeaf(): X86Block =
  ## The fifth operation upgrades the same source span to a checked branch.
  var body = pureLeaf()
  emitX86Branch(body, 171'u8, default(RegisterSlots), 0, 4, 5)
  body

proc oversizedLeaf(): X86Block =
  ## A cold candidate exceeding the per-image ceiling must not consume a fragment.
  var body = default(X86Block)
  for index in 0..<400:
    emitX86Operation(body, 51'u8, default(RegisterSlots), uint64(index))
  body

proc largeLeaf(): X86Block =
  ## A still-admitted image fills the unchanged arena before the fragment quota.
  var body = default(X86Block)
  for index in 0..<250:
    emitX86Operation(body, 51'u8, default(RegisterSlots), uint64(index))
  body

proc regionBlocks(): array[2, X86RegionBlock] =
  ## One complete pure block has a local self edge and an external checked exit.
  result = default(array[2, X86RegionBlock])
  var body = default(X86Block)
  emitX86Operation(body, 149'u8, default(RegisterSlots), 1)
  emitX86Branch(body, 171'u8, default(RegisterSlots), 0, 7, 9)
  result[0] = X86RegionBlock(header: 7, span: 2, operations: 2,
      yes: 7, no: 9, price: 3, body: move(body))

proc admittedOwner(): X86Jit =
  ## Begin each native boundary case with real executable storage and one live leaf.
  result = newX86Jit()
  assert x86Entry(result, 0, 8) == 0
  assert publishX86Entry(result, 0, 4, 4, pureLeaf())
  assert result.fragments == 1 and result.codeBytes > 0

proc checkExisting(jit: X86Jit) =
  ## Later refusal must leave an earlier entry callable with its original result.
  var registers = default(RegisterFile)
  assert callX86Entry(jit, 0, registers) == 4
  assert uint64(registers[0]) == 4

proc nativeBoundaries() =
  ## Artificial near-limit counts exercise real publication and the actual shared quota.
  block leaf_then_region:
    let jit = admittedOwner()
    jit.fragments = 8190
    assert publishX86Entry(jit, 1, 5, 4, pureLeaf())
    assert jit.fragments == 8191
    let before = jit.codeBytes
    assert not publishX86Entry(jit, 2, 6, 4, pureLeaf())
    assert x86Entry(jit, 2, 8) == 1 and jit.codeBytes == before
    assert publishX86Region(jit, regionBlocks(), 1)
    assert jit.fragments == 8192 and x86RegionStatus(jit) == 2
    checkExisting(jit)
  block region_at_final_slot:
    let jit = admittedOwner()
    jit.fragments = 8191
    assert publishX86Region(jit, regionBlocks(), 1)
    assert jit.fragments == 8192
    assert not publishX86Entry(jit, 1, 5, 4, pureLeaf())
    assert x86Entry(jit, 1, 8) == 1
    checkExisting(jit)
  block region_then_leaf:
    let jit = admittedOwner()
    assert publishX86Region(jit, regionBlocks(), 1)
    jit.fragments = 8190
    assert publishX86Entry(jit, 1, 5, 4, pureLeaf())
    assert jit.fragments == 8191 and x86RegionStatus(jit) == 2
    assert not publishX86Entry(jit, 2, 6, 4, pureLeaf())
    checkExisting(jit)
  block exhausted_region:
    let jit = admittedOwner()
    jit.fragments = 8192
    let before = jit.codeBytes
    assert not publishX86Region(jit, regionBlocks(), 1)
    assert x86RegionStatus(jit) == 1 and jit.codeBytes == before
    checkExisting(jit)
  block refused_promotion:
    let jit = admittedOwner()
    jit.fragments = 8191
    let before = jit.codeBytes
    assert not publishX86Entry(jit, 0, 4, 5, conditionalLeaf(), conditional = true)
    assert jit.fragments == 8191 and jit.codeBytes == before
    checkExisting(jit)
  block final_nonregion_promotion:
    let jit = admittedOwner()
    jit.fragments = 8190
    assert publishX86Entry(jit, 0, 4, 5, conditionalLeaf(), conditional = true)
    assert jit.fragments == 8191
    var registers = default(RegisterFile)
    assert callX86Branch(jit, 0, registers) == 5
    assert uint64(registers[0]) == 4
  block oversized_candidate:
    let jit = admittedOwner()
    let before = jit.codeBytes
    assert not publishX86Entry(jit, 1, 5, 4, oversizedLeaf())
    assert x86Entry(jit, 1, 8) == 1 and jit.codeBytes == before
    checkExisting(jit)
  block byte_arena_ceiling:
    let jit = newX86Jit()
    assert x86Entry(jit, 0, 352) == 0
    assert publishX86Entry(jit, 0, 4, 4, pureLeaf())
    let image = largeLeaf()
    var refused = false
    for offset in 1'u32..348'u32:
      if not publishX86Entry(jit, offset, offset+4, 4, image):
        assert x86Entry(jit, offset, 352) == 1
        refused = true
        break
    assert refused and jit.fragments >= 250 and jit.fragments < 8191
    assert jit.codeBytes <= 1048576
    checkExisting(jit)
  stdout.writeLine("X86_FRAGMENT_CAP_NATIVE_OK")

proc forcedRefusal() =
  ## The explicit OS-allocation refusal proves no publication or stale callable entry.
  let jit = newX86Jit()
  assert x86Entry(jit, 0, 8) == 0
  assert not publishX86Entry(jit, 0, 4, 4, pureLeaf())
  assert jit.fragments == 0 and jit.codeBytes == 0
  assert x86Entry(jit, 0, 8) == 1
  var registers = default(RegisterFile)
  assert callX86Entry(jit, 0, registers) == high(uint32)
  assert not publishX86Region(jit, regionBlocks(), 1)
  assert x86RegionStatus(jit) == 1
  stdout.writeLine("X86_FRAGMENT_CAP_FORCED_REFUSAL_OK")

when defined(pvmX86JitRefuse):
  forcedRefusal()
elif defined(linux) and defined(amd64):
  nativeBoundaries()
else:
  stdout.writeLine("X86_FRAGMENT_CAP_NATIVE_DEFERRED")
