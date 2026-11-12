# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exclusive mutable byte storage for the standalone port. This models Rust Vec<u8>
## length/capacity and explicit reserve_exact; reads borrow, and reset can retain capacity.
## No immutable publication, copy-on-write, refcount or production PVM type is involved.
## libc allocation matches Rust's system allocator on the benchmark's Linux targets.

import std/assertions

proc realloc(data: nil pointer, size: csize_t): nil pointer
    {.importc, header: "<stdlib.h>", raises: [].}
  ## Preserve an existing allocation's prefix while changing its reserved size.

proc free(data: nil pointer) {.importc, header: "<stdlib.h>", raises: [].}
  ## Release an allocation, accepting a moved-from nil sentinel.

type
  Bytes* = object
    ## One exclusive vector owner; published pointers are temporary borrows only.
    data*: nil ptr UncheckedArray[byte]
    len*, capacity*: int

proc `=destroy`*(buffer: Bytes) =
  ## Raw byte elements have no child owners; free only this allocation.
  free(buffer.data)

proc `=wasMoved`*(buffer: var Bytes) {.nodestroy.} =
  ## A transferred owner becomes an empty vector that can be reused or destroyed.
  buffer.data = nil
  buffer.len = 0
  buffer.capacity = 0

proc `=copy`*(destination: var Bytes, source: Bytes) {.error.}
  ## Rust Vec is not implicitly copied; a port must request any clone explicitly.

proc `=dup`*(source: Bytes): Bytes {.error.}
  ## Reject hidden duplication at container and call boundaries.

proc reserveExact*(buffer: var Bytes, capacity: int) =
  ## Grow without changing initialized length; allocation failure aborts like Rust's allocator.
  assert capacity >= 0
  if capacity <= buffer.capacity: return
  let storage = realloc(buffer.data, csize_t(capacity))
  assert storage != nil, "faithful byte allocation failed"
  buffer.data = cast[ptr UncheckedArray[byte]](storage)
  buffer.capacity = capacity

proc resizeZero*(buffer: var Bytes, length: int) =
  ## Initialize newly exposed bytes; shrinking retains allocation for later reset/reuse.
  assert length >= 0
  buffer.reserveExact(length)
  let data = buffer.data
  if length > buffer.len:
    assert data != nil
    for index in buffer.len..<length: data[index] = 0
  buffer.len = length

proc clear*(buffer: var Bytes) {.inline.} =
  ## Rust Vec::clear preserves byte capacity and performs no allocation.
  buffer.len = 0

proc readByte*(buffer: Bytes, index: int): byte {.inline.} =
  ## Borrow one initialized byte, preserving checked access in the port.
  assert index >= 0 and index < buffer.len
  let data = buffer.data
  assert data != nil
  data[index]

proc writeByte*(buffer: var Bytes, index: int, value: byte) {.inline.} =
  ## Mutate one initialized byte through the exclusive owner.
  assert index >= 0 and index < buffer.len
  let data = buffer.data
  assert data != nil
  data[index] = value

proc copyFrom*(buffer: var Bytes, offset: int, source: openArray[byte]) =
  ## Copy host input into an already sized destination; borrowed input must not overlap it.
  assert offset >= 0 and offset <= buffer.len and source.len <= buffer.len-offset
  if source.len == 0: return
  let data = buffer.data
  assert data != nil
  copyMem(addr data[offset], unsafeAddr source[0], source.len)

proc cloneBytes*(source: openArray[byte]): Bytes =
  ## Explicitly capture initial module bytes once, without any implicit owner copies.
  var buffer = default(Bytes)
  buffer.reserveExact(source.len)
  buffer.len = source.len
  buffer.copyFrom(0, source)
  move(buffer)

proc copyTo*(buffer: Bytes, offset: int, destination: var openArray[byte]) =
  ## Expose bytes to a host-owned destination while retaining the mutable instance's allocation.
  assert offset >= 0 and offset <= buffer.len and destination.len <= buffer.len-offset
  if destination.len == 0: return
  let data = buffer.data
  assert data != nil
  copyMem(addr destination[0], addr data[offset], destination.len)

proc copyWithinOwner*(destination: var Bytes, at: int, source: Bytes, first, length: int) =
  ## Copy between disjoint exclusive owners after proving initialized source/destination extents.
  assert at >= 0 and length >= 0 and at <= destination.len and length <= destination.len-at
  assert first >= 0 and first <= source.len and length <= source.len-first
  if length == 0: return
  let output = destination.data
  let input = source.data
  assert output != nil and input != nil and output != input
  copyMem(addr output[at], addr input[first], length)

proc fillZero*(buffer: var Bytes, first, length: int) =
  ## Clear one already initialized interval, preserving the vector's length/capacity.
  assert first >= 0 and length >= 0 and first <= buffer.len and length <= buffer.len-first
  if length == 0: return
  let data = buffer.data
  assert data != nil
  zeroMem(addr data[first], length)

proc cloneBytes*(source {.byref.}: string, first, length: int): Bytes =
  ## Capture one checked file/string interval into a transferable byte-vector owner.
  assert first >= 0 and length >= 0 and first <= source.len and length <= source.len-first
  var bytes = default(Bytes)
  bytes.reserveExact(length)
  bytes.len = length
  if length != 0:
    let output = bytes.data
    assert output != nil
    copyMem(output, readRawData(source, first), length)
  move(bytes)
