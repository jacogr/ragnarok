# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exclusive Rust Vec-shaped storage for scalar cache entries and function pointers.
## T must be trivially copyable and have no destruction hook or managed references.
## The interpreter uses this only for uint32, Args and non-closure Handler values.

import std/assertions
import ./buffer

type PlainVector*[T] = object
  ## Raw allocation owner with initialized element length and retained capacity.
  storage: Bytes
  length: int

proc `=wasMoved`*[T](vector: var PlainVector[T]) {.nodestroy.} =
  ## Moving the allocation must also clear its sibling scalar element count.
  `=wasMoved`(vector.storage)
  vector.length = 0

proc len*[T](vector: PlainVector[T]): int {.inline.} =
  ## Read the initialized element count without copying the allocation.
  vector.length

proc capacity*[T](vector: PlainVector[T]): int {.inline.} =
  ## Expose capacity in elements, as Rust Vec does.
  vector.storage.capacity div sizeof(T)

proc `[]`*[T](vector: PlainVector[T], index: int): T {.inline.} =
  ## Return one scalar value after checking the initialized extent.
  assert index >= 0 and index < vector.length
  let data = cast[nil ptr UncheckedArray[T]](vector.storage.data)
  assert data != nil
  data[index]

proc `[]=`*[T](vector: var PlainVector[T], index: int, value: T) {.inline.} =
  ## Replace a trivially copyable initialized element through its sole owner.
  assert index >= 0 and index < vector.length
  let data = cast[nil ptr UncheckedArray[T]](vector.storage.data)
  assert data != nil
  data[index] = value

proc reserveExact*[T](vector: var PlainVector[T], capacity: int) =
  ## Reserve exactly the requested total element capacity without changing length.
  assert capacity >= 0 and capacity <= high(int) div sizeof(T)
  vector.storage.reserveExact(capacity * sizeof(T))

proc add*[T](vector: var PlainVector[T], value: T) {.inline.} =
  ## Match RawVec amortized growth: double capacity, with the source minimum of four.
  if vector.length == vector.capacity:
    let minimum = if sizeof(T) == 1: 8 elif sizeof(T) <= 1024: 4 else: 1
    vector.reserveExact(max(minimum, max(vector.length + 1, vector.capacity * 2)))
  let data = cast[nil ptr UncheckedArray[T]](vector.storage.data)
  assert data != nil
  data[vector.length] = value
  vector.length += 1
  vector.storage.len = vector.length * sizeof(T)

proc resizeZero*[T](vector: var PlainVector[T], length: int) =
  ## Used for the zero-filled offset table; preserve an existing allocation when shrinking.
  assert length >= 0 and length <= high(int) div sizeof(T)
  vector.storage.resizeZero(length * sizeof(T))
  vector.length = length

proc zero*[T](vector: var PlainVector[T]) =
  ## Rewrite the initialized table only when its epoch field wraps.
  vector.storage.fillZero(0, vector.storage.len)

proc clear*[T](vector: var PlainVector[T]) {.inline.} =
  ## Clear scalar entries while retaining the source cache's allocation.
  vector.storage.clear()
  vector.length = 0

proc reset*[T](vector: var PlainVector[T]) =
  ## Drop the allocation, matching assignment of Vec::new rather than Vec::clear.
  vector.storage = default(Bytes)
  vector.length = 0
