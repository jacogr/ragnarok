# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 Boolean and packed bitstring codecs; see spec/bitstrings.md for wire and lifetime rules.
import ./natural

type
  # A logical bit count is distinct from byte extents and from resource ceilings.
  BitCount* = distinct uint64
  # Caller policy bounds logical bits, including claims that would overflow naive ceil arithmetic.
  BitLimit* = distinct uint64
  # Default/failure alternatives contain no decoded value, owner or progress.
  BitError* {.pure.} = enum
    Uninitialized, None, Truncated, NonCanonical, LimitExceeded, InvalidCount,
    InvalidOwner, InvalidIndex, OutputTooSmall, AliasedBuffers, LengthOverflow
  # Every operation must select success before reading its complete result.
  BitResult*[T] = object
    case status: BitError
    of None:
      # Success alone authorizes access to a complete value or written extent.
      completed: T
    else:
      # Failures publish only their reason, never partial values or counts.
      discard
  # Standalone Boolean decoding copies the value and consumes exactly one canonical octet.
  BooleanRead* = object
    value*: bool
    consumed*: int
  # Private acyclic ARC storage owns only validated packed payload bytes, not an input pointer.
  BitsData = ref object
    packed: seq[byte]
    count: BitCount
  # Copying a handle retains immutable bytes; default handles differ from validated empty strings.
  OwnedBits* = object
    data: nil BitsData
  # Decoding returns one complete immutable owner and the exact consumed prefix, including any count.
  BitsRead* = object
    owner*: OwnedBits
    consumed*: int
  # Copied logical/physical metadata grants no access to private backing storage.
  BitsInfo* = object
    count*: BitCount
    packedBytes*: int
  # Private preflight coordinates cannot escape independently of the owner they authorize capturing.
  Layout = object
    count: BitCount
    offset, length, consumed: int

# Read outcomes without granting mutable access to the private result discriminator.
func error*[T](value: BitResult[T]): BitError = value.status
# Only complete success authorizes copied values, ownership or consumed/written progress.
func value*[T](value: BitResult[T]): T {.inline, requires: value.status == BitError.None.} =
  value.completed

# Compare address distances without overflowing endpoint sums; empty ranges need no valid pointer.
proc overlaps(a: pointer, an: int, b: pointer, bn: int): bool {.raises: [].} =
  # No shared byte can exist when either range is empty.
  if an == 0 or bn == 0: return false
  let left = cast[uint](a)
  let right = cast[uint](b)
  # Measure from the lower address, using that range's length as the intersection bound.
  if left <= right: right-left < uint(an)
  else:
    # Exchanging the ranges preserves the same overflow-free distance test.
    left-right < uint(bn)

# A ceiling division by eight must not form count+7, which can overflow at the uint64 boundary.
proc packedLength(count: uint64): uint64 {.raises: [].} =
  count div 8 + uint64(ord(count mod 8 != 0))

# Read a standalone Boolean prefix without allocation; trailing bytes belong to the next field.
proc decodeBoolean*(input: openArray[byte]): BitResult[BooleanRead] {.raises: [].} =
  # Both false and true require one wire octet.
  if input.len == 0: return BitResult[BooleanRead](status: BitError.Truncated)
  # Only the two images of the Boolean encoder are canonical.
  if input[0] > 1: return BitResult[BooleanRead](status: BitError.NonCanonical)
  BitResult[BooleanRead](status: BitError.None,
    completed: BooleanRead(value: input[0] == 1, consumed: 1))

# Encode a copied Boolean atomically; no source pointer or borrowing survives the call.
proc encodeBoolean*(value: bool, output: var openArray[byte]): BitResult[int] {.raises: [].} =
  # Capacity precedes the only write and preserves empty destinations on failure.
  if output.len == 0: return BitResult[int](status: BitError.OutputTooSmall)
  output[0] = byte(ord(value))
  BitResult[int](status: BitError.None, completed: 1)

# Validate count policy, complete packed extent and canonical padding before allocation or host conversion.
proc inspect(input: openArray[byte], count: BitCount, offset: int,
    limit: BitLimit): BitResult[Layout] {.raises: [].} =
  let n = uint64(count)
  # Resource policy is independent of whether the declared input bytes are present.
  if n > uint64(limit): return BitResult[Layout](status: BitError.LimitExceeded)
  let length = packedLength(n)
  # The uint64 comparison proves length fits available host indexing before it is narrowed.
  if length > uint64(input.len-offset): return BitResult[Layout](status: BitError.Truncated)
  let size = int(length)
  let used = int(n mod 8)
  # The encoder emits zeroes above the last logical bit; accepting other padding would be noncanonical.
  if used != 0 and (input[offset+size-1] shr used) != 0:
    return BitResult[Layout](status: BitError.NonCanonical)
  BitResult[Layout](status: BitError.None,
    completed: Layout(count: count, offset: offset, length: size, consumed: offset+size))

# Capture only a completely validated payload; no length discriminator or caller suffix is retained.
proc capture(input: openArray[byte], layout: Layout): BitsRead =
  let data = BitsData(count: layout.count, packed: newSeq[byte](layout.length))
  # Copying each payload octet severs the association with mutable caller storage.
  for i in 0..<layout.length: data.packed[i] = input[layout.offset+i]
  BitsRead(owner: OwnedBits(data: data), consumed: layout.consumed)

# Decode a fixed logical bit count without a wire prefix; caller input stays stable only during this call.
proc decodeFixedBits*(input: openArray[byte], count: BitCount, limit: BitLimit): BitResult[BitsRead] =
  let checked = inspect(input, count, 0, limit)
  # A failed preflight authorizes neither a snapshot allocation nor partial metadata.
  if checked.error != BitError.None: return BitResult[BitsRead](status: checked.error)
  BitResult[BitsRead](status: BitError.None, completed: capture(input, checked.value))

# Decode a variable bitstring whose canonical natural length counts bits, not packed octets.
proc decodeBits*(input: openArray[byte], limit: BitLimit): BitResult[BitsRead] =
  let prefix = natural.decode(input)
  # Primitive framing failures precede any declared-count policy or input-derived allocation.
  if not prefix.ok:
    # Incomplete natural frames and complete overlong frames retain distinct failure reasons.
    if prefix.error == natural.truncated: return BitResult[BitsRead](status: BitError.Truncated)
    else:
      # An overlong bit count cannot choose a second encoding of the same logical string.
      return BitResult[BitsRead](status: BitError.NonCanonical)
  let checked = inspect(input, BitCount(uint64(prefix.value)), prefix.consumed, limit)
  # Every packed byte and final padding bit must validate before a private snapshot is allocated.
  if checked.error != BitError.None: return BitResult[BitsRead](status: checked.error)
  BitResult[BitsRead](status: BitError.None, completed: capture(input, checked.value))

# Preflight the borrowed bool sequence, complete output and whole written destination before packing any bit.
proc encode(values: openArray[bool], count: BitCount, limit: BitLimit, variable: bool,
    output: var openArray[byte]): BitResult[int] {.raises: [].} =
  # Fixed schemas require exact source cardinality rather than dropping or inventing logical bits.
  if uint64(values.len) != uint64(count): return BitResult[int](status: BitError.InvalidCount)
  # Counts are checked before calculating a packed destination size.
  if uint64(count) > uint64(limit): return BitResult[int](status: BitError.LimitExceeded)
  let prefix = natural.encode(JamNatural(uint64(count)))
  let offset = (if variable: int(prefix.len) else: 0) # Only variable terms carry a natural bit count.
  let length = int(packedLength(uint64(count)))
  # Subtraction proves offset+length fits actual output and therefore host arithmetic.
  if output.len < offset or length > output.len-offset:
    return BitResult[int](status: BitError.OutputTooSmall)
  let total = offset+length
  # Typed source strides must be representable before using them in a byte-range overlap check.
  if values.len > high(int) div sizeof(bool): return BitResult[int](status: BitError.LengthOverflow)
  # A count prefix must not overwrite a later bool source before that source is packed.
  if values.len > 0 and total > 0 and overlaps(unsafeAddr values[0], values.len*sizeof(bool),
      addr output[0], total): return BitResult[int](status: BitError.AliasedBuffers)
  # Commit only after every source, policy, extent and alias check has passed.
  if variable:
    # Fixed-length terms deliberately omit this discriminator, including for zero bits.
    for i in 0..<prefix.len: output[i] = prefix.bytes[i]
  # Initializing full payload bytes guarantees canonical zero padding in the last partial octet.
  for i in 0..<length: output[offset+i] = 0
  # Little-significance-first positions follow C.1.4, independently of the notation's bits(blob) helper.
  for i, value in values:
    # A false source bit contributes no set bit to the already-cleared destination.
    if value: output[offset+i div 8] = output[offset+i div 8] or byte(1 shl (i mod 8))
  BitResult[int](status: BitError.None, completed: total)

# Encode a variable borrowed logical bit sequence with a canonical natural bit-count prefix.
proc encodeBits*(values: openArray[bool], limit: BitLimit,
    output: var openArray[byte]): BitResult[int] {.raises: [].} =
  encode(values, BitCount(uint64(values.len)), limit, true, output)

# Encode exactly the caller's fixed schema count, without a count discriminator or partial writes.
proc encodeFixedBits*(values: openArray[bool], count: BitCount, limit: BitLimit,
    output: var openArray[byte]): BitResult[int] {.raises: [].} =
  encode(values, count, limit, false, output)

# Copy logical/physical metadata through a retained immutable owner, never detached source coordinates.
proc bitsInfo*(owner: OwnedBits): BitResult[BitsInfo] {.raises: [].} =
  let data = owner.data
  # Validated zero-length bitstrings still have a nondefault owner.
  if data == nil: return BitResult[BitsInfo](status: BitError.InvalidOwner)
  BitResult[BitsInfo](status: BitError.None,
    completed: BitsInfo(count: data.count, packedBytes: data.packed.len))

# Copy one Boolean through its matching owner; negative and out-of-range indices fail without accessing bytes.
proc bitAt*(owner: OwnedBits, index: int): BitResult[bool] {.raises: [].} =
  let data = owner.data
  # Missing ownership precedes index checks so defaults never resemble valid empty strings.
  if data == nil: return BitResult[bool](status: BitError.InvalidOwner)
  # Compare in uint64 only after the signed lower bound has been checked.
  if index < 0 or uint64(index) >= uint64(data.count):
    return BitResult[bool](status: BitError.InvalidIndex)
  BitResult[bool](status: BitError.None,
    completed: (data.packed[index div 8] and byte(1 shl (index mod 8))) != 0)

# Re-emit immutable packed payload with optional framing after complete new policy/capacity/alias checks.
proc reemit(owner: OwnedBits, count: BitCount, limit: BitLimit, variable: bool,
    output: var openArray[byte]): BitResult[int] {.raises: [].} =
  let data = owner.data
  # A default snapshot contains no canonical payload, including no validated empty string.
  if data == nil: return BitResult[int](status: BitError.InvalidOwner)
  # A fixed encoder may not silently reinterpret the owner's exact logical length.
  if uint64(count) != uint64(data.count): return BitResult[int](status: BitError.InvalidCount)
  # Retained owners must obey new caller resource ceilings too.
  if uint64(count) > uint64(limit): return BitResult[int](status: BitError.LimitExceeded)
  let prefix = natural.encode(JamNatural(uint64(count)))
  let offset = (if variable: int(prefix.len) else: 0) # Fixed re-emission has no natural prefix.
  let length = data.packed.len
  # Prove total host extent against actual output capacity before forming its sum.
  if output.len < offset or length > output.len-offset:
    return BitResult[int](status: BitError.OutputTooSmall)
  let total = offset+length
  # Protect all retained packed bytes from any part of the whole written destination.
  if length > 0 and total > 0 and overlaps(unsafeAddr data.packed[0], length,
      addr output[0], total): return BitResult[int](status: BitError.AliasedBuffers)
  # No later failure remains possible after these preflight checks.
  if variable:
    # A variable empty string still emits its one-byte zero count.
    for i in 0..<prefix.len: output[i] = prefix.bytes[i]
  # Fixed empty owners write nothing; nonempty owners copy only their exact immutable payload.
  for i in 0..<length: output[offset+i] = data.packed[i]
  BitResult[int](status: BitError.None, completed: total)

# Re-emit a retained bitstring in variable framing, even when originally captured as a fixed term.
proc encodeOwnedBits*(owner: OwnedBits, limit: BitLimit,
    output: var openArray[byte]): BitResult[int] {.raises: [].} =
  let data = owner.data
  # Avoid accessing a default owner's count before reemit can enforce ownership.
  if data == nil: return BitResult[int](status: BitError.InvalidOwner)
  reemit(owner, data.count, limit, true, output)

# Re-emit a retained bitstring with an explicitly matching fixed count and no discriminator.
proc encodeOwnedFixedBits*(owner: OwnedBits, count: BitCount, limit: BitLimit,
    output: var openArray[byte]): BitResult[int] {.raises: [].} =
  reemit(owner, count, limit, false, output)
