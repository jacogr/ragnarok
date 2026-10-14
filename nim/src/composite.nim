## Composite codecs, pinned Gray Paper v0.7.1 C.1.3/C.2. No heap allocation.
import ./natural
import ./fixed_unsigned
import ./bounded

type
  # A validated location in the caller's pool or original wire input; no pointer is retained.
  BlobSpan* = object
    offset*, length*: int
  # The four-byte service field is nominally different from counts and ordinary machine values.
  ServiceIndex* = distinct uint32
  # Presence carries a span; absence has no payload fields or bytes.
  OptionalBlob* = object
    case present*: bool
    of true:
      # Only the present branch refers to the associated byte pool.
      blob*: BlobSpan
    of false:
      # Absence is represented solely by discriminator zero.
      discard
  # Exact C.2 work-output tags; Bad/Big retain the paper's names rather than inferred semantics.
  WorkKind* {.pure.} = enum
    Success, OutOfGas, Panic, BadExports, Oversize, Bad, Big
  # Success carries a bounded blob; all error variants contain only their tag.
  WorkOutput* = object
    case kind*: WorkKind
    of WorkKind.Success:
      # Span coordinates refer to the same caller-owned pool/wire as the result.
      blob*: BlobSpan
    else:
      # Error variants have no encoded blob length or payload.
      discard
  # A preimage record contains a nominal service index and one nested variable blob.
  Preimage* = object
    service*: ServiceIndex
    blob*: BlobSpan
  # Separate policies bound record count, a single blob and aggregate payload bytes.
  PreimageLimits* = object
    items*: ElementLimit
    perBlob*, totalBlobBytes*: ByteLimit
  # Typed status discriminator: Uninitialized is the default failure; None selects completed data.
  CompositeError* {.pure.} = enum
    Uninitialized, None, Truncated, NonCanonical, LimitExceeded, OutputTooSmall,
    AliasedBuffers, LengthOverflow, InvalidTag, InvalidSpan
  # Encoded storage belongs to the caller; only success carries written.
  CompositeWrite* = object
    case error*: CompositeError
    of CompositeError.None:
      # Only success carries decoded/committed data and its completed extent.
      written*: int
    else:
      # Failure has no value, span, count or consumed/written metadata.
      discard
  # A decoded optional value, referring to input by coordinates rather than an allocated copy.
  OptionalResult* = object
    case error*: CompositeError
    of CompositeError.None:
      # Only success carries decoded/committed data and its completed extent.
      value*: OptionalBlob
      consumed*: int
    else:
      # Failure has no value, span, count or consumed/written metadata.
      discard
  # A decoded work-output variant and its completed prefix length.
  WorkResult* = object
    case error*: CompositeError
    of CompositeError.None:
      # Only success carries decoded/committed data and its completed extent.
      value*: WorkOutput
      consumed*: int
    else:
      # Failure has no value, span, count or consumed/written metadata.
      discard
  # Selects initialized caller-owned record storage only after every nested record validates.
  PreimageResult* = object
    case error*: CompositeError
    of CompositeError.None:
      # Only success carries decoded/committed data and its completed extent.
      count*, consumed*: int
    else:
      # Failure has no value, span, count or consumed/written metadata.
      discard
  # Internal discriminator proof before constructing public variants.
  TaggedResult = object
    case error: CompositeError
    of CompositeError.None:
      # Only success carries decoded/committed data and its completed extent.
      tag: uint64
      blob: BlobSpan
      consumed: int
    else:
      # Failure has no value, span, count or consumed/written metadata.
      discard

# Compare address differences so overlap detection never overflows a pointer-end addition.
proc alias(a: pointer, alen: int, b: pointer, blen: int): bool {.raises: [].} =
  if alen == 0 or blen == 0: return false # Empty buffers have no intersection.
  let left = cast[uint](a)
  let right = cast[uint](b)
  if left <= right: right - left < uint(alen) # Measure from the earlier address.
  else: left - right < uint(blen) # Exchange the spans when b begins first.

# Preserve nested blob failures; unrelated container statuses cannot occur in this blob-only path.
proc blobError(error: ContainerError): CompositeError {.raises: [].} =
  case error
  of ContainerError.None: CompositeError.None # Validation succeeded.
  of ContainerError.Truncated: CompositeError.Truncated # Prefix/payload bytes are missing.
  of ContainerError.NonCanonical: CompositeError.NonCanonical # Overlong natural count.
  of ContainerError.LimitExceeded: CompositeError.LimitExceeded # Caller policy was exceeded.
  of ContainerError.OutputTooSmall: CompositeError.OutputTooSmall # Complete destination required.
  of ContainerError.AliasedBuffers: CompositeError.AliasedBuffers # Protect borrowed source storage.
  else: CompositeError.InvalidSpan # Reject an unexpected status rather than interpreting it as success.

# Validate both span endpoints by subtraction, including empty spans at the end of the pool.
proc validSpan(span: BlobSpan, size: int): bool {.raises: [].} =
  span.offset >= 0 and span.length >= 0 and span.offset <= size and span.length <= size - span.offset

# Measure a validated tag/blob without writing, so enclosing tuples can preflight all their fields.
proc tagSize(tag: int, hasBlob: bool, span: BlobSpan, poolSize: int,
             limit: ByteLimit): CompositeWrite {.raises: [].} =
  # Reject discriminators before narrowing or interpreting payloads.
  if tag < 0 or tag > 6: return CompositeWrite(error: CompositeError.InvalidTag)
  # Payload-free values borrow no pool and contain exactly one tag byte.
  if not hasBlob: return CompositeWrite(error: CompositeError.None, written: 1)
  # Prove source endpoints before converting the signed length.
  if not validSpan(span, poolSize): return CompositeWrite(error: CompositeError.InvalidSpan)
  # Apply caller policy before calculating encoded extent.
  if uint64(span.length) > uint64(limit): return CompositeWrite(error: CompositeError.LimitExceeded)
  let length = natural.encode(JamNatural(uint64(span.length)))
  # Headers must fit in the host extent without overflowing the sum.
  if span.length > high(int) - 1 - length.len: return CompositeWrite(
      error: CompositeError.LengthOverflow)
  CompositeWrite(error: CompositeError.None, written: 1 + int(length.len) + span.length)

# Emit checked bytes only after size, capacity and whole borrowed-pool overlap checks.
proc writeTag(tag: int, hasBlob: bool, span: BlobSpan, pool: openArray[byte], limit: ByteLimit,
              output: var openArray[byte]): CompositeWrite {.raises: [].} =
  let size = tagSize(tag, hasBlob, span, pool.len, limit)
  # Invalid source or policy cannot produce even a discriminator byte.
  if size.error != CompositeError.None: return size
  # The destination must hold the complete variant.
  if output.len < size.written: return CompositeWrite(error: CompositeError.OutputTooSmall)
  # Only payload-bearing variants borrow the pool; protect unused source bytes too.
  if hasBlob and pool.len > 0 and alias(unsafeAddr pool[0], pool.len, addr output[0], size.written):
    return CompositeWrite(error: CompositeError.AliasedBuffers)
  output[0] = byte(tag)
  # Present/success values append the canonical length and identity payload.
  if hasBlob:
    let length = natural.encode(JamNatural(uint64(span.length)))
    # Copy the complete canonical length before the blob.
    for i in 0..<length.len: output[1 + i] = length.bytes[i]
    # Span bounds and output capacity were proved above.
    for i in 0..<span.length: output[1 + length.len + i] = pool[span.offset + i]
  size

# Validate and measure a work output without mutation; enclosing codecs use this for atomic preflight.
proc measureWork*(value: WorkOutput, poolSize: int, limit: ByteLimit): CompositeWrite {.raises: [].} =
  # Only success contains a borrowed payload descriptor.
  if value.kind == WorkKind.Success: return tagSize(0, true, value.blob, poolSize, limit)
  tagSize(ord(value.kind), false, BlobSpan(), poolSize, limit)

# Read a canonical discriminator, accepting only the defined schema tags before any enum conversion.
proc readTag(input: openArray[byte], maximum, blobTag: uint64,
    limit: ByteLimit): TaggedResult {.raises: [].} =
  let tag = natural.decode(input)
  if not tag.ok:
    # Distinguish incomplete from overlong discriminators before interpreting a variant.
    return TaggedResult(error: if tag.error == natural.truncated: CompositeError.Truncated else: CompositeError.NonCanonical)
  let value = uint64(tag.value)
  if value > maximum: return TaggedResult(error: CompositeError.InvalidTag) # Unsupported schema value.
  if value != blobTag: return TaggedResult(error: CompositeError.None, tag: value,
      consumed: tag.consumed) # No payload for this branch.
  let blob = decodeBytes(input.toOpenArray(tag.consumed, input.len - 1), limit)
  if blob.error != ContainerError.None: return TaggedResult(error: blobError(blob.error)) # Nested preflight.
  TaggedResult(error: CompositeError.None, tag: value, blob: BlobSpan(offset: tag.consumed + blob.offset, length: blob.length),
               consumed: tag.consumed + blob.consumed)

# C.1.3 optional-blob schema: zero for absent, or one followed by a variable blob.
proc encodeOptional*(value: OptionalBlob, pool: openArray[byte], limit: ByteLimit,
                     output: var openArray[byte]): CompositeWrite {.raises: [].} =
  if value.present: writeTag(1, true, value.blob, pool, limit, output) # Present branch validates its span.
  else: writeTag(0, false, BlobSpan(), pool, limit, output) # Absent branch has no payload.

# Return a typed optional view only after validating discriminator and any present blob completely.
proc decodeOptional*(input: openArray[byte], limit: ByteLimit): OptionalResult {.raises: [].} =
  let parsed = readTag(input, 1, 1, limit)
  if parsed.error != CompositeError.None: return OptionalResult(error: parsed.error) # No usable value on failure.
  if parsed.tag == 0: return OptionalResult(error: CompositeError.None, value: OptionalBlob(
      present: false), consumed: parsed.consumed) # Absent.
  OptionalResult(error: CompositeError.None, value: OptionalBlob(present: true, blob: parsed.blob),
      consumed: parsed.consumed)

# C.2 work-output O: success zero plus a variable blob, or one of six payload-free errors.
proc encodeWork*(value: WorkOutput, pool: openArray[byte], limit: ByteLimit,
                 output: var openArray[byte]): CompositeWrite {.raises: [].} =
  if value.kind == WorkKind.Success: return writeTag(0, true, value.blob, pool, limit, output) # Success payload.
  writeTag(ord(value.kind), false, BlobSpan(), pool, limit, output) # Error tag is range checked before narrowing.

# Decode exactly the work-output discriminator set; preserve trailing fields in either variant.
proc decodeWork*(input: openArray[byte], limit: ByteLimit): WorkResult {.raises: [].} =
  let parsed = readTag(input, 6, 0, limit)
  if parsed.error != CompositeError.None: return WorkResult(error: parsed.error) # No enum conversion on bad data.
  if parsed.tag == 0:
    return WorkResult(error: CompositeError.None, value: WorkOutput(kind: WorkKind.Success,
        blob: parsed.blob), consumed: parsed.consumed) # Blob branch.
  WorkResult(error: CompositeError.None, value: WorkOutput(kind: WorkKind(parsed.tag)),
      consumed: parsed.consumed)

# Traverse nested records either without writes or as a commit pass after stable input has been proved valid.
proc walk(input: openArray[byte], offset, count: int, limits: PreimageLimits,
          output: var openArray[Preimage], commit: bool): PreimageResult {.raises: [].} =
  var cursor = offset
  var budget = uint64(limits.totalBlobBytes)
  # Validate each tuple in wire order while subtracting its payload from the aggregate budget.
  for index in 0..<count:
    if input.len - cursor < 4: return PreimageResult(error: CompositeError.Truncated) # Missing service field.
    let service = decodeFixed(input.toOpenArray(cursor, cursor + 3), ByteWidth(4))
    cursor += 4
    let blob = decodeBytes(input.toOpenArray(cursor, input.len - 1), ByteLimit(min(uint64(
        limits.perBlob), budget)))
    if blob.error != ContainerError.None: return PreimageResult(error: blobError(
        blob.error)) # Both blob policies checked early.
    if commit:
      # Only the second pass initializes record views; failed last records cannot expose an earlier partial prefix.
      output[index] = Preimage(service: ServiceIndex(uint32(uint64(service.value))),
                     blob: BlobSpan(offset: cursor + blob.offset, length: blob.length))
    budget -= uint64(blob.length)
    cursor += blob.consumed
  PreimageResult(error: CompositeError.None, count: count, consumed: cursor)

# Decode the full preimage extrinsic into caller-owned records, retaining blob locations as original-input spans.
proc decodePreimages*(input: openArray[byte], limits: PreimageLimits,
                      output: var openArray[Preimage]): PreimageResult {.raises: [].} =
  let prefix = natural.decode(input)
  if not prefix.ok:
    # An invalid outer discriminator cannot advance a cursor or initialize any record.
    return PreimageResult(error: if prefix.error ==
        natural.truncated: CompositeError.Truncated else: CompositeError.NonCanonical)
  let claimed = uint64(prefix.value)
  if claimed > uint64(limits.items): return PreimageResult(
      error: CompositeError.LimitExceeded) # Outer count policy.
  if claimed > uint64((input.len - prefix.consumed) div 5): return PreimageResult(
      error: CompositeError.Truncated) # Minimum record extent.
  if claimed > uint64(output.len): return PreimageResult(
      error: CompositeError.OutputTooSmall) # Host conversion/storage proof.
  if claimed > uint64(high(int) div sizeof(Preimage)): return PreimageResult(
      error: CompositeError.LengthOverflow) # Typed memory size.
  let count = int(claimed)
  if count > 0 and alias(unsafeAddr input[0], input.len, addr output[0], count * sizeof(Preimage)):
    return PreimageResult(error: CompositeError.AliasedBuffers) # Includes trailing input fields.
  let checked = walk(input, prefix.consumed, count, limits, output, false)
  if checked.error != CompositeError.None: return checked # Whole-frame validation precedes any record write.
  walk(input, prefix.consumed, count, limits, output, true)

# Encode nested tuples from a shared byte pool, preflighting every span, count, byte budget and destination extent.
proc encodePreimages*(values: openArray[Preimage], pool: openArray[byte], limits: PreimageLimits,
                      output: var openArray[byte]): CompositeWrite {.raises: [].} =
  if uint64(values.len) > uint64(limits.items): return CompositeWrite(
      error: CompositeError.LimitExceeded) # Count ceiling.
  let prefix = natural.encode(JamNatural(uint64(values.len)))
  if output.len < prefix.len: return CompositeWrite(error: CompositeError.OutputTooSmall) # Outer header extent.
  var required = int(prefix.len)
  var budget = uint64(limits.totalBlobBytes)
  # Prove every source span and destination extent before committing even the outer header.
  for value in values:
    if not validSpan(value.blob, pool.len): return CompositeWrite(
        error: CompositeError.InvalidSpan) # Checked source endpoints.
    if uint64(value.blob.length) > min(uint64(limits.perBlob), budget):
      return CompositeWrite(error: CompositeError.LimitExceeded) # Nested and aggregate policy.
    let length = natural.encode(JamNatural(uint64(value.blob.length)))
    if output.len - required < 4 + length.len or value.blob.length > output.len - required - 4 - length.len:
      return CompositeWrite(error: CompositeError.OutputTooSmall) # Safe total size by subtraction.
    required += 4 + length.len + value.blob.length
    budget -= uint64(value.blob.length)
  if values.len > high(int) div sizeof(Preimage): return CompositeWrite(
      error: CompositeError.LengthOverflow) # Alias span size.
  if pool.len > 0 and alias(unsafeAddr pool[0], pool.len, addr output[0], required):
    return CompositeWrite(error: CompositeError.AliasedBuffers) # Pool must remain stable through commit.
  if values.len > 0 and alias(unsafeAddr values[0], values.len * sizeof(Preimage), addr output[0], required):
    return CompositeWrite(error: CompositeError.AliasedBuffers) # Descriptor storage must survive output writes too.
  for i in 0..<prefix.len: output[i] = prefix.bytes[i] # Commit validated outer count.
  var cursor = int(prefix.len)
  # Commit each fully validated tuple using the same stable descriptors and source pool.
  for value in values:
    let service = encodeFixed(FixedUnsigned(uint64(uint32(value.service))), ByteWidth(4))
    for i in 0..<4: output[cursor + i] = service.encoded.bytes[i] # Tuple's little-endian nominal service ID.
    cursor += 4
    let length = natural.encode(JamNatural(uint64(value.blob.length)))
    for i in 0..<length.len: output[cursor + i] = length.bytes[i] # Nested length prefix.
    cursor += length.len
    for i in 0..<value.blob.length: output[cursor + i] = pool[value.blob.offset + i] # Raw nested payload.
    cursor += value.blob.length
  CompositeWrite(error: CompositeError.None, written: required)
