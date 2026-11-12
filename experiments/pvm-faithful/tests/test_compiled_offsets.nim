# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Check cache presence, validity, overwrite, allocation lifetime and epoch rollover.

import std/assertions
import ../[compiled_offsets, plain_vector]

proc exercise() =
  ## Large tables force an epoch wrap within a small number of clears; every old entry must vanish.
  var offsets = default(CompiledOffsets)
  assert not offsets.allocated
  assert not offsets.get(0).present
  discard offsets.clear()
  for length in [1'u32, 2, 17, 65537, 1048577]:
    offsets.allocate(length)
    assert offsets.allocated
    for pc in 0'u32..<length:
      offsets.insert(pc, pc * 3, (pc and 1) == 0)
    for pc in 0'u32..<length:
      let entry = offsets.get(pc)
      assert entry.present and entry.target == pc * 3 and entry.validJump == ((pc and 1) == 0)
    assert not offsets.get(length).present
    offsets.insert(0, 0, false)
    assert offsets.get(0).present and not offsets.get(0).validJump
    var rewrites = 0
    for epoch in 0..<1024:
      if offsets.clear(): rewrites += 1
      assert not offsets.get(0).present
      assert not offsets.get(length - 1).present
      offsets.insert(0, 0, true)
      offsets.insert(length - 1, length - 1, false)
    if length == 1048577: assert rewrites > 0, "epoch rollover"
    offsets.reset()
    assert not offsets.allocated and not offsets.get(0).present

proc vectorOwnership() =
  ## Growth, clear and moves retain values without implicit duplication or shared mutation.
  var values = default(PlainVector[uint32])
  for value in 0'u32..<4096: values.add(value * 17)
  assert values.capacity == 4096
  var moved = move(values)
  assert values.len == 0, "moved vector length"
  for value in 0'u32..<4096: assert moved[int(value)] == value * 17
  moved.clear()
  assert moved.len == 0 and moved.capacity == 4096
  moved.add(42)
  assert moved[0] == 42
  moved.reset()
  assert moved.capacity == 0

exercise()
vectorOwnership()
