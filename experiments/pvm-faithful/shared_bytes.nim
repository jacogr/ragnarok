# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable source storage and cheap retained slices, corresponding to PolkaVM ArcBytes.
## Slicing never allocates or copies bytes; empty slices retain no owner. ARC replaces
## Rust's atomic Arc lifetime accounting. Mutable guest buffers use the separate Bytes owner.

import std/assertions
import ./buffer

type
  ByteStorage = ref object
    ## The only owner of the backing allocation; never exported for mutation.
    bytes: Bytes
  SharedBytes* = object
    ## Read pointer/length plus retained lifetime, matching the ArcBytes ownership model.
    data: nil ptr UncheckedArray[byte]
    length: int
    storage: nil ByteStorage

proc sharedBytes*(input: openArray[byte]): SharedBytes =
  ## Capture nonempty input once; empty ArcBytes requires neither storage nor reference counting.
  result = default(SharedBytes)
  if input.len != 0:
    let storage = ByteStorage(bytes: cloneBytes(input))
    result = SharedBytes(data: storage.bytes.data, length: input.len, storage: storage)

proc len*(source: SharedBytes): int {.inline.} =
  ## Length is independent of the retained parent allocation's full size.
  source.length

proc slice*(source: SharedBytes, first, length: int): SharedBytes =
  ## Retain the same source owner after proving the complete child extent; empty loses its owner.
  assert first >= 0 and length >= 0 and first <= source.length and length <= source.length-first
  result = default(SharedBytes)
  if length != 0:
    let data = source.data
    assert data != nil
    result = SharedBytes(data: cast[ptr UncheckedArray[byte]](addr data[first]),
      length: length, storage: source.storage)

proc view*(source {.byref.}: SharedBytes): openArray[byte]
    {.inline, establishesBorrow, readonlyView.} =
  ## Borrow bytes from this exact retained owner; callers cannot mutate the immutable view.
  let data = source.data
  if data == nil:
    assert source.length == 0
    const empty: array[0, byte] = []
    result = empty
  else:
    result = toOpenArray(data, 0, source.length-1)

proc copyTo*(source: SharedBytes, first: int, destination: var openArray[byte]) =
  ## Read into host-owned storage after a complete range proof, with no publication allocation.
  assert first >= 0 and first <= source.length and destination.len <= source.length-first
  if destination.len != 0:
    let data = source.data
    assert data != nil
    copyMem(addr destination[0], addr data[first], destination.len)

proc copyInto*(source: SharedBytes, first: int, destination: var Bytes, at, length: int) =
  ## Initialize an exclusive mutable buffer from immutable module data; owners are disjoint.
  assert first >= 0 and length >= 0 and first <= source.length and length <= source.length-first
  assert at >= 0 and at <= destination.len and length <= destination.len-at
  if length != 0:
    let input = source.data
    let output = destination.data
    assert input != nil and output != nil
    copyMem(addr output[at], addr input[first], length)

proc readBits*[Width: static[int]](source: SharedBytes, offset: int): uint64 {.inline.} =
  ## Load source scalar bytes using the same checked little-endian interpretation as guest RAM.
  assert Width in [1, 2, 4, 8] and offset >= 0 and offset <= source.length-Width
  let data = source.data
  assert data != nil
  result = 0
  for index in 0..<Width: result = result or (uint64(data[offset+index]) shl (8*index))

proc sharedBytes*(input {.byref.}: string, first, length: int): SharedBytes =
  ## Capture a fixture string span once, matching Rust slice.to_vec without a staging allocation.
  assert first >= 0 and length >= 0 and first <= input.len and length <= input.len-first
  result = default(SharedBytes)
  if length != 0:
    var bytes = default(Bytes)
    bytes.reserveExact(length)
    bytes.len = length
    let output = bytes.data
    assert output != nil
    copyMem(output, readRawData(input, first), length)
    let storage = ByteStorage(bytes: move(bytes))
    result = SharedBytes(data: storage.bytes.data, length: length, storage: storage)

proc sharedBytes*(input: sink Bytes): SharedBytes =
  ## Vec-to-ArcBytes moves a preexisting file buffer; cold admission must not clone its bytes.
  result = default(SharedBytes)
  if input.len != 0:
    let length = input.len
    let storage = ByteStorage(bytes: move(input))
    result = SharedBytes(data: storage.bytes.data, length: length, storage: storage)
