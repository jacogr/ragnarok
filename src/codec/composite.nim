# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Composite codecs, pinned Gray Paper v0.8.0 C.1.3/C.2. No heap allocation.
##
## Exposes explicit optional/work variants and borrowed optional, work-result and preimage
## codecs with measured write/decode results.

import ./natural
import ./fixed_unsigned
import ./bounded

type
  # Caller-supplied or decoded coordinates in a borrowed pool; encoders validate bounds against that pool.
  BlobSpan* = object
    offset*, length*: int
  # The four-byte service field is nominally different from counts and ordinary machine values.
  ServiceIndex* = distinct uint32
  # Presence carries a span; absence has no payload fields or bytes.
  OptionalBlob* = object
    case isPresent: bool
    of true:
      # Only the present branch refers to the associated byte pool.
      payloadSpan: BlobSpan
    of false:
      # Absence is represented solely by discriminator zero.
      discard
  # Exact C.2 work-output tags; Bad/Big retain the paper's names rather than inferred semantics.
  WorkKind* {.pure.} = enum
    Success, OutOfGas, Panic, BadExports, Oversize, Bad, Big
  # Success carries a borrowed source/decoded span; all error variants contain only their tag.
  WorkOutput* = object
    case outputKind: WorkKind
    of Success:
      # Span coordinates refer to the same caller-owned pool/wire as the result.
      payloadSpan: BlobSpan
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
  # Completed output extent; callers cannot retag failures or read uncommitted progress.
  CompositeWrite* = object
    case status: CompositeError
    of None:
      # Only the defining codec constructs complete success data.
      byteWritten: int
    else:
      # Default and failed alternatives carry no usable payload.
      discard
  # Validated optional value and prefix; payloads remain private until success.
  OptionalResult* = object
    case status: CompositeError
    of None:
      # Only the defining codec constructs complete success data.
      decodedValue: OptionalBlob
      byteConsumed: int
    else:
      # Default and failed alternatives carry no usable payload.
      discard
  # Validated work-output value and prefix; failures expose their reason alone.
  WorkResult* = object
    case status: CompositeError
    of None:
      # Only the defining codec constructs complete success data.
      decodedValue: WorkOutput
      byteConsumed: int
    else:
      # Default and failed alternatives carry no usable payload.
      discard
  # Completed caller-storage prefix; failures cannot authorize records or cursor progress.
  PreimageResult* = object
    case status: CompositeError
    of None:
      # Only the defining codec constructs complete success data.
      elementCount, byteConsumed: int
    else:
      # Default and failed alternatives carry no usable payload.
      discard
  # Internal discriminator proof before constructing public variants.
  TaggedResult = object
    case error: CompositeError
    of None:
      # Only success carries decoded/committed data and its completed extent.
      tag: uint64
      blob: BlobSpan
      consumed: int
    else:
      # Failure has no value, span, count or consumed/written metadata.
      discard

# Construct a payload-free optional source descriptor without borrowing any buffer.
func absentBlob*(): OptionalBlob = OptionalBlob(isPresent: false)
# Construct a present source descriptor; the encoder still validates span bounds against its pool.
func presentBlob*(span: BlobSpan): OptionalBlob = OptionalBlob(isPresent: true, payloadSpan: span)
# Read optional presence without permitting callers to retag an absent value.
func present*(value: OptionalBlob): bool = value.isPresent
# Only present optionals contain a span; returned coordinates are copied, not writable aliases.
func blob*(value: OptionalBlob): BlobSpan {.inline, requires: value.isPresent.} = value.payloadSpan

# Construct a successful work source descriptor; pool-dependent validation remains with the encoder.
func successfulWork*(span: BlobSpan): WorkOutput = WorkOutput(outputKind: WorkKind.Success,
    payloadSpan: span)
# Payload-free work descriptors cannot use the Success tag, which requires an explicit span.
func failedWork*(kind: WorkKind): WorkOutput {.requires: kind != WorkKind.Success.} =
  WorkOutput(outputKind: kind)
# Inspect a work tag without allowing mutations that could manufacture a success payload.
func kind*(value: WorkOutput): WorkKind = value.outputKind
# Only Success carries a span; all six work-error tags reject payload access.
func blob*(value: WorkOutput): BlobSpan {.inline, requires: value.outputKind == WorkKind.Success.} =
  value.payloadSpan

# Sibling encoders may report a typed failure, but cannot label a missing extent as success.
func compositeFailure*(reason: CompositeError): CompositeWrite {.requires: reason !=
    CompositeError.None.} =
  CompositeWrite(status: reason)
# Sibling encoders explicitly report their completed nonnegative extent after their own preflight/commit.
func compositeWritten*(extent: int): CompositeWrite {.requires: extent >= 0.} =
  CompositeWrite(status: CompositeError.None, byteWritten: extent)

# Read the CompositeWrite reason without exposing a writable discriminator.
func error*(value: CompositeWrite): CompositeError = value.status
# Read the OptionalResult reason without exposing a writable discriminator.
func error*(value: OptionalResult): CompositeError = value.status
# Read the WorkResult reason without exposing a writable discriminator.
func error*(value: WorkResult): CompositeError = value.status
# Read the PreimageResult reason without exposing a writable discriminator.
func error*(value: PreimageResult): CompositeError = value.status
# Only completed writes publish a committed extent.
func written*(value: CompositeWrite): int {.inline, requires: value.status ==
    CompositeError.None.} =
  value.byteWritten
# Only complete optional decodes expose their selected variant.
func value*(value: OptionalResult): OptionalBlob {.inline, requires: value.status ==
    CompositeError.None.} =
  value.decodedValue
# Failed optional decodes cannot advance a byte cursor.
func consumed*(value: OptionalResult): int {.inline, requires: value.status ==
    CompositeError.None.} =
  value.byteConsumed
# Only complete work-output decodes expose their selected variant.
func value*(value: WorkResult): WorkOutput {.inline, requires: value.status ==
    CompositeError.None.} =
  value.decodedValue
# Failed work-output decodes cannot publish prefix progress.
func consumed*(value: WorkResult): int {.inline, requires: value.status == CompositeError.None.} =
  value.byteConsumed
# Only a completed preimage decode authorizes its caller-owned record prefix.
func count*(value: PreimageResult): int {.inline, requires: value.status == CompositeError.None.} =
  value.elementCount
# Failed preimage scans/decodes cannot expose partial progress.
func consumed*(value: PreimageResult): int {.inline, requires: value.status ==
    CompositeError.None.} =
  value.byteConsumed

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
  of None: CompositeError.None # Validation succeeded.
  of Truncated: CompositeError.Truncated # Prefix/payload bytes are missing.
  of NonCanonical: CompositeError.NonCanonical # Overlong natural count.
  of LimitExceeded: CompositeError.LimitExceeded # Caller policy was exceeded.
  of OutputTooSmall: CompositeError.OutputTooSmall # Complete destination required.
  of AliasedBuffers: CompositeError.AliasedBuffers # Protect borrowed source storage.
  else: CompositeError.InvalidSpan # Reject an unexpected status rather than interpreting it as success.

# Validate both span endpoints by subtraction, including empty spans at the end of the pool.
proc validSpan(span: BlobSpan, size: int): bool {.raises: [].} =
  span.offset >= 0 and span.length >= 0 and span.offset <= size and span.length <= size - span.offset

# Measure a validated tag/blob without writing, so enclosing tuples can preflight all their fields.
proc tagSize(tag: int, hasBlob: bool, span: BlobSpan, poolSize: int,
             limit: ByteLimit): CompositeWrite {.raises: [].} =
  # Reject discriminators before narrowing or interpreting payloads.
  if tag < 0 or tag > 6: return CompositeWrite(status: CompositeError.InvalidTag)
  # Payload-free values borrow no pool and contain exactly one tag byte.
  if not hasBlob: return CompositeWrite(status: CompositeError.None, byteWritten: 1)
  # Prove source endpoints before converting the signed length.
  if not validSpan(span, poolSize): return CompositeWrite(status: CompositeError.InvalidSpan)
  # Apply caller policy before calculating encoded extent.
  if uint64(span.length) > uint64(limit): return CompositeWrite(
      status: CompositeError.LimitExceeded)
  let length = natural.encode(JamNatural(uint64(span.length)))
  # Headers must fit in the host extent without overflowing the sum.
  if span.length > high(int) - 1 - length.len: return CompositeWrite(
      status: CompositeError.LengthOverflow)
  CompositeWrite(status: CompositeError.None, byteWritten: 1 + int(length.len) + span.length)

# Emit checked bytes only after size, capacity and whole borrowed-pool overlap checks.
proc writeTag(tag: int, hasBlob: bool, span: BlobSpan, pool: openArray[byte], limit: ByteLimit,
              output: var openArray[byte]): CompositeWrite {.raises: [].} =
  let size = tagSize(tag, hasBlob, span, pool.len, limit)
  # Invalid source or policy cannot produce even a discriminator byte.
  if size.error != CompositeError.None: return size
  # The destination must hold the complete variant.
  if output.len < size.written: return CompositeWrite(status: CompositeError.OutputTooSmall)
  # Only payload-bearing variants borrow the pool; protect unused source bytes too.
  if hasBlob and pool.len > 0 and alias(unsafeAddr pool[0], pool.len, addr output[0], size.written):
    return CompositeWrite(status: CompositeError.AliasedBuffers)
  output[0] = byte(tag)
  # Present/success values append the canonical length and identity payload.
  if hasBlob:
    let length = natural.encode(JamNatural(uint64(span.length)))
    # Copy the complete canonical length before the blob.
    for i in 0..<length.len: output[1 + i] = length.bytes[i]
    # Span bounds and output capacity were proved above.
    if span.length > 0:
      # The measured frame and valid span prove both extents; whole-pool alias rejection permits copyMem.
      copyMem(addr output[1 + length.len], unsafeAddr pool[span.offset], span.length)
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
  let blob = decodeBytesBorrowed(input.toOpenArray(tag.consumed, input.len - 1), limit)
  if blob.error != ContainerError.None: return TaggedResult(error: blobError(blob.error)) # Nested preflight.
  TaggedResult(error: CompositeError.None, tag: value, blob: BlobSpan(offset: tag.consumed + blob.offset, length: blob.length),
               consumed: tag.consumed + blob.consumed)

# C.1.3 optional-blob schema: zero for absent, or one followed by a variable blob.
proc encodeOptionalBorrowed*(value: OptionalBlob, pool: openArray[byte], limit: ByteLimit,
                     output: var openArray[byte]): CompositeWrite {.raises: [].} =
  if value.present: writeTag(1, true, value.blob, pool, limit, output) # Present branch validates its span.
  else: writeTag(0, false, BlobSpan(), pool, limit, output) # Absent branch has no payload.

# Return a typed optional view only after validating discriminator and any present blob completely.
proc decodeOptionalBorrowed*(input: openArray[byte], limit: ByteLimit): OptionalResult {.raises: [].} =
  let parsed = readTag(input, 1, 1, limit)
  if parsed.error != CompositeError.None: return OptionalResult(
      status: parsed.error) # No usable value on failure.
  if parsed.tag == 0: return OptionalResult(status: CompositeError.None, decodedValue: OptionalBlob(
      isPresent: false), byteConsumed: parsed.consumed) # Absent.
  OptionalResult(status: CompositeError.None, decodedValue: OptionalBlob(isPresent: true,
      payloadSpan: parsed.blob), byteConsumed: parsed.consumed)

# C.2 work-output O: success zero plus a variable blob, or one of six payload-free errors.
proc encodeWorkBorrowed*(value: WorkOutput, pool: openArray[byte], limit: ByteLimit,
                 output: var openArray[byte]): CompositeWrite {.raises: [].} =
  if value.kind == WorkKind.Success: return writeTag(0, true, value.blob, pool, limit, output) # Success payload.
  writeTag(ord(value.kind), false, BlobSpan(), pool, limit, output) # Error tag is range checked before narrowing.

# Decode exactly the work-output discriminator set; preserve trailing fields in either variant.
proc decodeWorkBorrowed*(input: openArray[byte], limit: ByteLimit): WorkResult {.raises: [].} =
  let parsed = readTag(input, 6, 0, limit)
  if parsed.error != CompositeError.None: return WorkResult(
      status: parsed.error) # No enum conversion on bad data.
  if parsed.tag == 0:
    return WorkResult(status: CompositeError.None, decodedValue: WorkOutput(
        outputKind: WorkKind.Success, payloadSpan: parsed.blob), byteConsumed: parsed.consumed) # Blob branch.
  WorkResult(status: CompositeError.None, decodedValue: WorkOutput(outputKind: WorkKind(
      parsed.tag)), byteConsumed: parsed.consumed)

# Traverse nested records either without writes or as a commit pass after stable input has been proved valid.
proc walk(input: openArray[byte], offset, count: int, limits: PreimageLimits,
          output: var openArray[Preimage], commit: bool,
          wireLimit: ByteLimit = ByteLimit(high(uint64))): PreimageResult {.raises: [].} =
  var cursor = offset
  var budget = uint64(limits.totalBlobBytes)
  # A compositional inspection also bounds framing bytes; existing callers retain the unlimited default.
  if uint64(cursor) > uint64(wireLimit): return PreimageResult(status: CompositeError.LimitExceeded)
  # Validate each tuple in wire order while subtracting its payload from the aggregate budget.
  for index in 0..<count:
    if input.len - cursor < 4: return PreimageResult(status: CompositeError.Truncated) # Missing service field.
    # Bound per-record traversal before a parent can scan arbitrarily far beyond its frame budget.
    if uint64(cursor+4) > uint64(wireLimit): return PreimageResult(
        status: CompositeError.LimitExceeded)
    let service = decodeFixed(input.toOpenArray(cursor, cursor + 3), ByteWidth(4))
    cursor += 4
    let blob = decodeBytesBorrowed(input.toOpenArray(cursor, input.len - 1), ByteLimit(min(uint64(
        limits.perBlob), budget)))
    if blob.error != ContainerError.None: return PreimageResult(status: blobError(
        blob.error)) # Both blob policies checked early.
    # Nested input extent is proved by decodeBytesBorrowed; only then can the exact wire endpoint be added.
    if uint64(cursor+blob.consumed) > uint64(wireLimit):
      return PreimageResult(status: CompositeError.LimitExceeded)
    if commit:
      # Only the second pass initializes record views; failed last records cannot expose an earlier partial prefix.
      output[index] = Preimage(service: ServiceIndex(uint32(uint64(service.value))),
                     blob: BlobSpan(offset: cursor + blob.offset, length: blob.length))
    budget -= uint64(blob.length)
    cursor += blob.consumed
  PreimageResult(status: CompositeError.None, elementCount: count, byteConsumed: cursor)

# Decode the full preimage extrinsic into caller-owned records, retaining blob locations as original-input spans.
proc decodePreimagesBorrowed*(input: openArray[byte], limits: PreimageLimits,
                      output: var openArray[Preimage]): PreimageResult {.raises: [].} =
  let prefix = natural.decode(input)
  if not prefix.ok:
    # An invalid outer discriminator cannot advance a cursor or initialize any record.
    return PreimageResult(status: if prefix.error ==
        natural.truncated: CompositeError.Truncated else: CompositeError.NonCanonical)
  let claimed = uint64(prefix.value)
  if claimed > uint64(limits.items): return PreimageResult(
      status: CompositeError.LimitExceeded) # Outer count policy.
  if claimed > uint64((input.len - prefix.consumed) div 5): return PreimageResult(
      status: CompositeError.Truncated) # Minimum record extent.
  if claimed > uint64(output.len): return PreimageResult(
      status: CompositeError.OutputTooSmall) # Host conversion/storage proof.
  if claimed > uint64(high(int) div sizeof(Preimage)): return PreimageResult(
      status: CompositeError.LengthOverflow) # Typed memory size.
  let count = int(claimed)
  if count > 0 and alias(unsafeAddr input[0], input.len, addr output[0], count * sizeof(Preimage)):
    return PreimageResult(status: CompositeError.AliasedBuffers) # Includes trailing input fields.
  let checked = walk(input, prefix.consumed, count, limits, output, false)
  if checked.error != CompositeError.None: return checked # Whole-frame validation precedes any record write.
  walk(input, prefix.consumed, count, limits, output, true)

# Encode nested tuples from a shared byte pool, preflighting every span, count, byte budget and destination extent.
proc encodePreimagesBorrowed*(values: openArray[Preimage], pool: openArray[byte], limits: PreimageLimits,
                      output: var openArray[byte]): CompositeWrite {.raises: [].} =
  if uint64(values.len) > uint64(limits.items): return CompositeWrite(
      status: CompositeError.LimitExceeded) # Count ceiling.
  let prefix = natural.encode(JamNatural(uint64(values.len)))
  if output.len < prefix.len: return CompositeWrite(status: CompositeError.OutputTooSmall) # Outer header extent.
  var required = int(prefix.len)
  var budget = uint64(limits.totalBlobBytes)
  # Prove every source span and destination extent before committing even the outer header.
  for value in values:
    if not validSpan(value.blob, pool.len): return CompositeWrite(
        status: CompositeError.InvalidSpan) # Checked source endpoints.
    if uint64(value.blob.length) > min(uint64(limits.perBlob), budget):
      return CompositeWrite(status: CompositeError.LimitExceeded) # Nested and aggregate policy.
    let length = natural.encode(JamNatural(uint64(value.blob.length)))
    if output.len - required < 4 + length.len or value.blob.length > output.len - required - 4 - length.len:
      return CompositeWrite(status: CompositeError.OutputTooSmall) # Safe total size by subtraction.
    required += 4 + length.len + value.blob.length
    budget -= uint64(value.blob.length)
  if values.len > high(int) div sizeof(Preimage): return CompositeWrite(
      status: CompositeError.LengthOverflow) # Alias span size.
  if pool.len > 0 and alias(unsafeAddr pool[0], pool.len, addr output[0], required):
    return CompositeWrite(status: CompositeError.AliasedBuffers) # Pool must remain stable through commit.
  if values.len > 0 and alias(unsafeAddr values[0], values.len * sizeof(Preimage), addr output[0], required):
    return CompositeWrite(status: CompositeError.AliasedBuffers) # Descriptor storage must survive output writes too.
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
    if value.blob.length > 0:
      # Every nested span/capacity and the whole pool were checked before committing the outer prefix.
      copyMem(addr output[cursor], unsafeAddr pool[value.blob.offset], value.blob.length)
    cursor += value.blob.length
  CompositeWrite(status: CompositeError.None, byteWritten: required)

# Inspect preimage framing/payload policy without allocation or exposing source coordinates.
proc inspectPreimages*(input: openArray[byte], limits: PreimageLimits,
    wireLimit: ByteLimit): PreimageResult {.raises: [].} =
  let prefix = natural.decode(input)
  # Preserve primitive framing errors before choosing a count.
  if not prefix.ok:
    return PreimageResult(status: if prefix.error == natural.truncated: CompositeError.Truncated
      else: CompositeError.NonCanonical) # Parent composition cannot normalize overlong counts.
  let count = uint64(prefix.value)
  # Policy and minimum-wire proof precede any conversion or record iteration.
  if count > uint64(limits.items): return PreimageResult(status: CompositeError.LimitExceeded)
  if count > uint64((input.len-int(prefix.consumed)) div 5):
    return PreimageResult(status: CompositeError.Truncated) # Every record needs E4 service and at least one length octet.
  # Keep parent acceptance compatible with later materialization through the existing typed preimage-owner API.
  if count > uint64(high(int) div sizeof(Preimage)):
    return PreimageResult(status: CompositeError.LengthOverflow)
  var unused: array[0, Preimage] = default(array[0, Preimage])
  walk(input, int(prefix.consumed), int(count), limits, unused, false, wireLimit)
