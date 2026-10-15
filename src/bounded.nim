## Bounded containers: Gray Paper v0.8.0 C.1.2/C.1.3, with C.1.1/C.1.7 primitives.
import ./natural
import ./fixed_unsigned

type
  # A byte-string resource ceiling, never confused implicitly with an element count.
  ByteLimit* = distinct uint64
  # A sequence-element ceiling; it applies even when elements occupy zero wire bytes.
  ElementLimit* = distinct uint64
  # Typed failure reasons shared by the bounded container operations; None denotes success.
  ContainerError* {.pure.} = enum
    Uninitialized, None, Truncated, NonCanonical, LimitExceeded, OutputTooSmall,
    InvalidWidth, ValueOutOfRange, AliasedBuffers, LengthOverflow
  # Encoder output is stored in the caller's buffer; only successful results carry written.
  WriteResult* = object
    case error*: ContainerError
    of ContainerError.None:
      # Only success carries decoded/committed data and its completed extent.
      written*: int
    else:
      # Failure has no value, span, count or consumed/written metadata.
      discard
  # A validated span in the original input, not a retained pointer or an allocated byte string.
  BlobResult* = object
    case error*: ContainerError
    of ContainerError.None:
      # Only success carries decoded/committed data and its completed extent.
      offset*, length*, consumed*: int
    else:
      # Failure has no value, span, count or consumed/written metadata.
      discard
  # Values are copied into caller-owned typed storage; count selects the initialized prefix.
  SequenceResult* = object
    case error*: ContainerError
    of ContainerError.None:
      # Only success carries decoded/committed data and its completed extent.
      count*, consumed*: int
    else:
      # Failure has no value, span, count or consumed/written metadata.
      discard
  # Internal frame proof: count remains uint64 until a caller proves it fits host indexing.
  FrameResult = object
    case error: ContainerError
    of ContainerError.None:
      # Only success carries decoded/committed data and its completed extent.
      count: uint64
      offset, consumed: int
    else:
      # Failure has no value, span, count or consumed/written metadata.
      discard

# Check address-range intersection without adding a length to a possibly large pointer value.
proc overlaps(a: pointer, aLen: int, b: pointer, bLen: int): bool {.raises: [].} =
  # Empty spans cannot alias; their pointers may also be nil and need not be inspected.
  if aLen == 0 or bLen == 0: return false
  let left = cast[uint](a)
  let right = cast[uint](b)
  # Compare the distance from the earlier address, avoiding pointer-end arithmetic overflow.
  if left <= right: right - left < uint(aLen)
  else:
    # The same check applies with the later and earlier spans exchanged.
    left - right < uint(bLen)

# Validate a canonical length prefix, limit and complete fixed-stride payload without multiplying first.
proc readFrame(input: openArray[byte], stride: int, limit: uint64): FrameResult {.raises: [].} =
  let prefix = natural.decode(input)
  # Preserve the distinction between incomplete and overlong natural length prefixes.
  if not prefix.ok:
    if prefix.error == natural.truncated:
      # No complete length was available, so no payload may be inspected.
      return FrameResult(error: ContainerError.Truncated)
    else:
      # The prefix is present but does not belong to the canonical encoder's image.
      return FrameResult(error: ContainerError.NonCanonical)
  let count = uint64(prefix.value)
  # Reject excessive claims while still uint64, before host-int conversion or any output write.
  if count > limit: return FrameResult(error: ContainerError.LimitExceeded)
  let remaining = input.len - prefix.consumed
  # Division proves the complete payload exists without overflowing count * stride.
  if stride > 0 and count > uint64(remaining div stride):
    return FrameResult(error: ContainerError.Truncated)
  var payload = 0
  # A positive stride proves count fits host int; zero-width items occupy no payload bytes.
  if stride > 0: payload = int(count) * stride
  FrameResult(error: ContainerError.None, count: count, offset: prefix.consumed,
      consumed: prefix.consumed + payload)

# Return a span for one bounded byte string; caller retains the original input and advances on success only.
proc decodeBytesBorrowed*(input: openArray[byte], limit: ByteLimit): BlobResult {.raises: [].} =
  let frame = readFrame(input, 1, uint64(limit))
  # Failure exposes no span and consumes nothing.
  if frame.error != ContainerError.None: return BlobResult(error: frame.error)
  BlobResult(error: ContainerError.None, offset: frame.offset, length: int(frame.count),
      consumed: frame.consumed)

# Encode a canonical byte count and payload into a separate caller-owned output buffer, without allocation.
proc encodeBytes*(value: openArray[byte], limit: ByteLimit,
                  output: var openArray[byte]): WriteResult {.raises: [].} =
  # Apply the resource ceiling before output-size calculations or copying.
  if uint64(value.len) > uint64(limit): return WriteResult(error: ContainerError.LimitExceeded)
  let prefix = natural.encode(JamNatural(uint64(value.len)))
  # Check available capacity by subtraction so prefix + payload cannot overflow a host int.
  if output.len < prefix.len or value.len > output.len - prefix.len:
    return WriteResult(error: ContainerError.OutputTooSmall)
  let total = prefix.len + value.len
  # Detect overlapping input/output before changing either; empty payloads have no input storage to alias.
  if value.len > 0 and overlaps(unsafeAddr value[0], value.len, addr output[0], total):
    return WriteResult(error: ContainerError.AliasedBuffers)
  # All failure checks have passed; emit the canonical prefix followed by exactly the borrowed payload.
  for i in 0..<prefix.len: output[i] = prefix.bytes[i]
  # The checked capacity and nonoverlap proof permit one standard byte copy.
  if value.len > 0:
    # Empty open arrays need no valid element address; copy only the validated payload extent.
    copyMem(addr output[prefix.len], unsafeAddr value[0], value.len)
  WriteResult(error: ContainerError.None, written: total)

# Encode a homogeneous fixed-width unsigned sequence after validating every element and all capacity.
proc encodeSequence*(values: openArray[FixedUnsigned], width: ByteWidth, limit: ElementLimit,
                     output: var openArray[byte]): WriteResult {.raises: [].} =
  let stride = int(width)
  # Width validation precedes all size arithmetic, including empty sequences.
  if stride < 0 or stride > 8: return WriteResult(error: ContainerError.InvalidWidth)
  # Counts are resources even when the wire payload is empty at width zero.
  if uint64(values.len) > uint64(limit): return WriteResult(error: ContainerError.LimitExceeded)
  let prefix = natural.encode(JamNatural(uint64(values.len)))
  # Bound the product against actual output capacity before multiplying it.
  if output.len < prefix.len or (stride > 0 and values.len > (output.len - prefix.len) div stride):
    return WriteResult(error: ContainerError.OutputTooSmall)
  # Typed input storage also needs a representable byte length for the alias check.
  if values.len > high(int) div sizeof(FixedUnsigned):
    return WriteResult(error: ContainerError.LengthOverflow)
  let total = prefix.len + values.len * stride
  # Reject aliasing before validating/writing fields, preserving the original values and output on failure.
  if values.len > 0 and overlaps(unsafeAddr values[0], values.len * sizeof(FixedUnsigned),
                                addr output[0], total):
    return WriteResult(error: ContainerError.AliasedBuffers)
  # A preflight pass rejects even a late overflowing element before any earlier element is written.
  for value in values:
    let encoded = encodeFixed(value, width)
    if not encoded.ok:
      # Width is already valid, so only value-range failure can occur here (including nonzero width-zero items).
      return WriteResult(error: ContainerError.ValueOutOfRange)
  # Commit the length and elements only after the entire operation is known to fit and succeed.
  for i in 0..<prefix.len: output[i] = prefix.bytes[i]
  for index, value in values:
    let encoded = encodeFixed(value, width)
    # Each element uses the already validated stride, so this destination stays inside the proved capacity.
    for i in 0..<stride: output[prefix.len + index * stride + i] = encoded.encoded.bytes[i]
  WriteResult(error: ContainerError.None, written: total)

# Decode fixed-width elements into separate caller-owned storage, with no partial writes on any failure.
proc decodeSequence*(input: openArray[byte], width: ByteWidth, limit: ElementLimit,
                     output: var openArray[FixedUnsigned]): SequenceResult {.raises: [].} =
  let stride = int(width)
  # Validate width even for an empty/invalid prefix; no input is read before this check.
  if stride < 0 or stride > 8: return SequenceResult(error: ContainerError.InvalidWidth)
  let frame = readFrame(input, stride, uint64(limit))
  # Prefix, count-limit and payload failures leave output untouched.
  if frame.error != ContainerError.None: return SequenceResult(error: frame.error)
  # Comparing in uint64 proves the count fits the caller's host-indexed storage, including width zero.
  if frame.count > uint64(output.len): return SequenceResult(error: ContainerError.OutputTooSmall)
  # Guard the typed storage's byte size before calculating it for overlap detection.
  if frame.count > uint64(high(int) div sizeof(FixedUnsigned)):
    return SequenceResult(error: ContainerError.LengthOverflow)
  let count = int(frame.count)
  # Protect the entire borrowed input, including trailing fields, from typed output writes.
  if count > 0 and overlaps(unsafeAddr input[0], input.len, addr output[0],
                           count * sizeof(FixedUnsigned)):
    return SequenceResult(error: ContainerError.AliasedBuffers)
  for index in 0..<count:
    let start = frame.offset + index * stride
    let value = decodeFixed(input.toOpenArray(start, start + stride - 1), width)
    output[index] = value.value
  SequenceResult(error: ContainerError.None, count: count, consumed: frame.consumed)
