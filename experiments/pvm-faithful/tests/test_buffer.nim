# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise exclusive vector moves, reset, retained capacity and independent host readback.

import std/[assertions, syncio]
import ../buffer

proc exercise() =
  ## A moved source is reusable; overwriting another owner releases its prior allocation.
  var first = cloneBytes([1'u8, 2, 3, 4])
  first.reserveExact(8192)
  let capacity = first.capacity
  var second = move(first)
  assert first.len == 0 and first.capacity == 0 and first.data == nil
  first.resizeZero(17)
  first.writeByte(0, 99)
  assert second.readByte(0) == 1
  second.clear()
  assert second.len == 0 and second.capacity == capacity
  second.resizeZero(4096)
  for i in 0..<second.len: assert second.readByte(i) == 0
  second.writeByte(4095, 77)
  var tail = default(array[4, byte])
  second.copyTo(4092, tail)
  assert tail == [0'u8, 0, 0, 77]
  second = move(first)
  assert first.len == 0 and first.data == nil
  assert second.len == 17 and second.readByte(0) == 99

for iteration in 0..<1000:
  # Repeated destruction and reallocation detects stale moved-from ownership.
  exercise()
echo "faithful exclusive byte ownership passed"
