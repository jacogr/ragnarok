## GP 0.8.0 C.2 availability specifications and accumulation input records; see spec/c2-records.md.
import ./[natural, fixed_unsigned, bounded, composite, work_digest, work_report, assurances]

type
  # Missing/default outcomes cannot expose a fabricated fixed record, retained owner or cursor.
  RecordError* {.pure.} = enum
    Uninitialized, None, Truncated, NonCanonical, LimitExceeded, InvalidTag, InvalidConfig,
    InvalidOwner, NoPayload, OutputTooSmall, AliasedBuffers, LengthOverflow
  # Success alone carries a complete copied value, owner or byte extent.
  RecordResult*[T] = object
    case error*: RecordError
    of RecordError.None:
      # Caller must select successful validation before reading any value/progress.
      value*: T
    else:
      # Every failed/default result contains only its reason.
      discard
  # Fixed availability fields use the existing report hash/length/cardinality domains, without context fields.
  AvailabilitySpec* {.byref.} = object
    packageHash*: PackageHash
    bundleLength*: BundleLength
    erasureRoot*: ErasureRoot
    erasureShards*: ErasureShards
    segmentRoot*: SegmentRoot
    segmentCount*: SegmentCount
  # Caller core ceiling bounds structural shard cardinality; matching the active set still needs state.
  AvailabilityConfig* = object
    cores*: CoreCount
    maxBytes*: ByteLimit
  # Availability decoding copies all fields and consumes exactly its 104-byte prefix, retaining no input pointer.
  AvailabilityRead* = object
    value*: AvailabilitySpec
    consumed*: int
  # Transfer balance is not implicitly interchangeable with gas or ordinary uint64 values.
  TransferBalance* = distinct uint64
  # A transfer memo always owns exactly 128 octets and has no length discriminator.
  TransferMemo* = distinct array[128, byte]
  # Transfers own every field; the standalone C.2 representation includes the outer tag one.
  DeferredTransfer* {.byref.} = object
    source*, destination*: ServiceIndex
    amount*: TransferBalance
    memo*: TransferMemo
    gas*: Gas
  # Copied transfer fields require no heap owner, source buffer or later extraction coordinates.
  TransferRead* = object
    value*: DeferredTransfer
    consumed*: int
  # Logical source output owns a borrowed-during-call sequence only on the success alternative.
  OperandOutput* = object
    case kind*: WorkKind
    of WorkKind.Success:
      # The encoder borrows this public sequence synchronously; decoding never returns this mutable source.
      payload*: seq[byte]
    else:
      # Work errors are valid application values and contain no default payload.
      discard
  # Source descriptors borrow their sequences only until complete preflight/commit; all hash roles remain nominal.
  AccumulationOperand* {.byref.} = object
    packageHash*: PackageHash
    segmentRoot*: SegmentRoot
    authorizer*: AuthorizerHash
    payloadHash*: PayloadHash
    gas*: Gas
    output*: OperandOutput
    authTrace*: seq[byte]
  # Explicit caller resource ceilings are not invented protocol maxima for standalone accumulator records.
  OperandLimits* = object
    outputBytes*, authBytes*, totalBlobBytes*, maxBytes*: ByteLimit
  # Copied output metadata carries a length only for a successful work result, never a detached span.
  OperandOutputInfo* = object
    case kind*: WorkKind
    of WorkKind.Success:
      # The matching immutable operand owner authorizes later payload copies.
      length*: int
    else:
      # Error alternatives expose only their protocol reason tag.
      discard
  # Complete metadata copies fixed fields and logical lengths without exposing mutable private wire storage.
  OperandInfo* = object
    packageHash*: PackageHash
    segmentRoot*: SegmentRoot
    authorizer*: AuthorizerHash
    payloadHash*: PayloadHash
    gas*: Gas
    output*: OperandOutputInfo
    authBytes*, consumed*: int
  # Private layout keeps validated input coordinates internal until a complete capture succeeds.
  OperandLayout = object
    info: OperandInfo
    output, auth: BlobSpan
  # Private acyclic ARC storage binds exact wire bytes to their validated layout and all application metadata.
  OperandData = ref object
    wire: seq[byte]
    layout: OperandLayout
  # Retaining a handle preserves immutable bytes independently of the caller's original buffer or other handles.
  OwnedOperand* {.byref.} = object
    data: OperandData
  # Successful operand decoding returns one complete owner with exact whole-record prefix consumption.
  OperandRead* = object
    owner*: OwnedOperand
    consumed*: int
  # The two accumulation input alternatives share their actual C.2 outer tags, not an extra wrapper tag.
  AccumulationKind* {.pure.} = enum
    Operand, Transfer
  # Independent source alternatives are passed by reference so alias preflight protects the entire active descriptor.
  AccumulationSource* {.byref.} = object
    case kind*: AccumulationKind
    of AccumulationKind.Operand:
      # Operand sources borrow sequences only for the synchronous encode operation.
      operand*: AccumulationOperand
    of AccumulationKind.Transfer:
      # Transfers contain only complete fixed values and a fixed memo.
      transfer*: DeferredTransfer
  # Successful union decoding exposes only the selected valid alternative, with no inactive default operand/transfer.
  AccumulationValue* = object
    case kind*: AccumulationKind
    of AccumulationKind.Operand:
      # Variable fields stay bound to their matching immutable owner.
      operand*: OwnedOperand
    of AccumulationKind.Transfer:
      # Fixed transfer fields are independent value copies.
      transfer*: DeferredTransfer
  # One successful union read advances by exactly the selected operand or transfer record.
  AccumulationRead* = object
    value*: AccumulationValue
    consumed*: int

# Preserve child composite wire errors without publishing child values, spans or partial progress.
proc convert(error: CompositeError): RecordError =
  case error
  of CompositeError.Truncated: RecordError.Truncated # Child input is incomplete.
  of CompositeError.NonCanonical: RecordError.NonCanonical # Count/tag natural is overlong.
  of CompositeError.LimitExceeded: RecordError.LimitExceeded # Explicit payload policy failed.
  of CompositeError.InvalidTag: RecordError.InvalidTag # Work-output tag is outside its defined domain.
  of CompositeError.LengthOverflow: RecordError.LengthOverflow # Host extent cannot be represented.
  else: RecordError.InvalidConfig # Other statuses are impossible on this no-write child decoding path.

# Preserve bounded byte framing failures from the final authorization trace without leaking its borrowed span.
proc convert(error: ContainerError): RecordError =
  case error
  of ContainerError.Truncated: RecordError.Truncated # Count or payload bytes are missing.
  of ContainerError.NonCanonical: RecordError.NonCanonical # Blob count is overlong.
  of ContainerError.LimitExceeded: RecordError.LimitExceeded # Trace or remaining aggregate limit is exceeded.
  else: RecordError.InvalidConfig # No other bounded-byte read status is expected here.

# Compare address distances without overflowing pointer endpoint sums or inspecting empty-range pointers.
proc overlaps(a: pointer, an: int, b: pointer, bn: int): bool =
  # Empty ranges cannot share a written byte.
  if an == 0 or bn == 0: return false
  let left = cast[uint](a)
  let right = cast[uint](b)
  # Use the lower-address range's length in the distance comparison.
  if left <= right: right-left < uint(an)
  else:
    # Exchanging the ranges preserves the same safe intersection test.
    left-right < uint(bn)

# Copy a fully proved fixed byte field into independent value storage.
proc fixed[N: static int](input: openArray[byte], start: int): array[N, byte] =
  # Callers prove complete field presence before any byte access or this bounded loop.
  for i in 0..<N: result[i] = input[start+i]

# Read an already proved fixed unsigned field through the existing scalar codec.
proc number(input: openArray[byte], start, width: int): uint64 =
  uint64(decodeFixed(input.toOpenArray(start, start+width-1), ByteWidth(width)).value)

# Commit a previously sized fixed scalar, reusing the canonical little-endian primitive encoder.
proc put(value: uint64, width: int, output: var openArray[byte], cursor: var int) =
  let encoded = encodeFixed(FixedUnsigned(value), ByteWidth(width))
  # All callers use domain-bounded E2/E4/E8 values and preflight the complete destination.
  for i in 0..<width: output[cursor+i] = encoded.encoded.bytes[i]
  cursor += width

# Commit complete already-proved fixed or borrowed bytes after whole-parent source/capacity/alias preflight.
proc put(bytes: openArray[byte], output: var openArray[byte], cursor: var int) =
  # A zero-byte payload emits nothing and never needs an element address.
  for value in bytes:
    output[cursor] = value
    inc cursor

# Commit a general natural for operand gas, tags or variable byte counts without an E8 substitution.
proc putNatural(value: uint64, output: var openArray[byte], cursor: var int) =
  let encoded = natural.encode(JamNatural(value))
  # Canonical scalar bytes fit the fully measured destination.
  for i in 0..<encoded.len: output[cursor+i] = encoded.bytes[i]
  cursor += encoded.len

# Read a canonical general natural while exposing no progress on incomplete or overlong input.
proc readNatural(input: openArray[byte], cursor: var int): RecordResult[uint64] =
  let parsed = natural.decode(input.toOpenArray(cursor, input.high))
  # Prefix framing is checked before count/tag policy or host conversions.
  if not parsed.ok:
    # Keep incomplete input distinct from an overlong representation of a complete scalar.
    if parsed.error == natural.truncated: return RecordResult[uint64](error: RecordError.Truncated)
    else:
      # Only the canonical encoder's image is accepted.
      return RecordResult[uint64](error: RecordError.NonCanonical)
  cursor += parsed.consumed
  RecordResult[uint64](error: RecordError.None, value: uint64(parsed.value))

# Validate configured core bounds independently of input and actual active-validator membership.
proc valid(config: AvailabilityConfig): bool = uint64(config.cores) >= 2 and uint64(config.cores) <= 341

# Apply the same GP valcount domain as reports, with the caller's extra configured core ceiling.
proc valid(spec: AvailabilitySpec, config: AvailabilityConfig): bool =
  let shards = uint16(spec.erasureShards)
  shards >= 6 and shards <= 3*uint64(config.cores) and shards mod 3 == 0

# Decode exactly one fixed 104-byte availability specification, not the following report context.
proc decodeAvailability*(input: openArray[byte], config: AvailabilityConfig): RecordResult[
    AvailabilityRead] =
  # Invalid configured domains precede untrusted wire access.
  if not valid(config): return RecordResult[AvailabilityRead](error: RecordError.InvalidConfig)
  # Complete field availability precedes individual cardinality and byte-budget policy.
  if input.len < 104: return RecordResult[AvailabilityRead](error: RecordError.Truncated)
  let value = AvailabilitySpec(packageHash: PackageHash(bytes: fixed[32](input, 0)),
    bundleLength: BundleLength(number(input, 32, 4)), erasureRoot: ErasureRoot(bytes: fixed[32](
        input, 36)),
    erasureShards: ErasureShards(number(input, 68, 2)), segmentRoot: SegmentRoot(bytes: fixed[32](
        input, 70)),
    segmentCount: SegmentCount(number(input, 102, 2)))
  # Structural shard counts must be multiples of three in the supplied core domain.
  if not valid(value, config): return RecordResult[AvailabilityRead](
      error: RecordError.LimitExceeded)
  # The complete record prefix, excluding unrelated suffix bytes, must fit caller policy.
  if uint64(config.maxBytes) < 104: return RecordResult[AvailabilityRead](
      error: RecordError.LimitExceeded)
  RecordResult[AvailabilityRead](error: RecordError.None, value: AvailabilityRead(value: value,
      consumed: 104))

# Encode one complete availability value after source, whole capacity and descriptor-alias checks.
proc encodeAvailability*(value: AvailabilitySpec, config: AvailabilityConfig,
    output: var openArray[byte]): RecordResult[int] =
  # Configuration and structural source policies precede output sizing.
  if not valid(config): return RecordResult[int](error: RecordError.InvalidConfig)
  if not valid(value, config) or uint64(config.maxBytes) < 104:
    return RecordResult[int](error: RecordError.LimitExceeded)
  # No hash/root prefix is written until the entire fixed tuple fits.
  if output.len < 104: return RecordResult[int](error: RecordError.OutputTooSmall)
  # Borrowed source fields must remain intact until every field is committed.
  if overlaps(unsafeAddr value, sizeof(value), addr output[0], 104):
    return RecordResult[int](error: RecordError.AliasedBuffers)
  var cursor = 0
  put(value.packageHash.bytes, output, cursor)
  put(uint64(value.bundleLength), 4, output, cursor)
  put(value.erasureRoot.bytes, output, cursor)
  put(uint64(value.erasureShards), 2, output, cursor)
  put(value.segmentRoot.bytes, output, cursor)
  put(uint64(value.segmentCount), 2, output, cursor)
  RecordResult[int](error: RecordError.None, value: cursor)

# Decode a tagged fixed transfer; state balance/service checks are not part of structural deserialization.
proc decodeTransfer*(input: openArray[byte], maxBytes: ByteLimit): RecordResult[TransferRead] =
  var cursor = 0
  let tag = readNatural(input, cursor)
  # Preserve missing/overlong discriminator failures before choosing a schema.
  if tag.error != RecordError.None: return RecordResult[TransferRead](error: tag.error)
  if tag.value != 1: return RecordResult[TransferRead](
      error: RecordError.InvalidTag) # Only transfer tag one belongs here.
  # The complete fixed fields and 128-byte memo must be present before copying any application value.
  if input.len-cursor < 152: return RecordResult[TransferRead](error: RecordError.Truncated)
  if uint64(maxBytes) < 153: return RecordResult[TransferRead](
      error: RecordError.LimitExceeded) # Budget includes tag one.
  let value = DeferredTransfer(source: ServiceIndex(number(input, cursor, 4)),
    destination: ServiceIndex(number(input, cursor+4, 4)), amount: TransferBalance(number(input,
        cursor+8, 8)),
    memo: TransferMemo(fixed[128](input, cursor+16)), gas: Gas(number(input, cursor+144, 8)))
  RecordResult[TransferRead](error: RecordError.None, value: TransferRead(value: value,
      consumed: cursor+152))

# Encode all fixed transfer fields atomically, with E8 gas and a fixed memo rather than operand gas framing.
proc encodeTransfer*(value: DeferredTransfer, maxBytes: ByteLimit,
    output: var openArray[byte]): RecordResult[int] =
  # Explicit serialized budget precedes capacity and alias decisions.
  if uint64(maxBytes) < 153: return RecordResult[int](error: RecordError.LimitExceeded)
  if output.len < 153: return RecordResult[int](error: RecordError.OutputTooSmall) # No partial memo/header can be emitted.
  if overlaps(unsafeAddr value, sizeof(value), addr output[0], 153):
    return RecordResult[int](error: RecordError.AliasedBuffers) # Protect the complete borrowed fixed descriptor.
  var cursor = 0
  putNatural(1, output, cursor)
  put(uint64(value.source), 4, output, cursor)
  put(uint64(value.destination), 4, output, cursor)
  put(uint64(value.amount), 8, output, cursor)
  put(array[128, byte](value.memo), output, cursor)
  put(uint64(value.gas), 8, output, cursor)
  RecordResult[int](error: RecordError.None, value: cursor)

# Scan a complete operand with private coordinates, applying payload/whole-byte bounds before any snapshot allocation.
proc scanOperand(input: openArray[byte], limits: OperandLimits): RecordResult[OperandLayout] =
  var cursor = 0
  let tag = readNatural(input, cursor)
  # The outer operand discriminator is canonical natural zero, not a second work-result tag.
  if tag.error != RecordError.None: return RecordResult[OperandLayout](error: tag.error)
  if tag.value != 0: return RecordResult[OperandLayout](
      error: RecordError.InvalidTag) # Transfer/unknown schemas cannot reinterpret as operands.
  if input.len-cursor < 128: return RecordResult[OperandLayout](
      error: RecordError.Truncated) # Four complete hash fields are mandatory.
  var layout: OperandLayout
  layout.info.packageHash = PackageHash(bytes: fixed[32](input, cursor))
  layout.info.segmentRoot = SegmentRoot(bytes: fixed[32](input, cursor+32))
  layout.info.authorizer = AuthorizerHash(bytes: fixed[32](input, cursor+64))
  layout.info.payloadHash = PayloadHash(fixed[32](input, cursor+96))
  cursor += 128
  if uint64(cursor) > uint64(limits.maxBytes): return RecordResult[OperandLayout](
      error: RecordError.LimitExceeded) # Bound traversal after fixed fields.
  let gas = readNatural(input, cursor)
  if gas.error != RecordError.None: return RecordResult[OperandLayout](
      error: gas.error) # Missing/overlong operand gas cannot expose hashes.
  layout.info.gas = Gas(gas.value)
  if uint64(cursor) > uint64(limits.maxBytes): return RecordResult[OperandLayout](
      error: RecordError.LimitExceeded) # Gas contributes to complete prefix size.
  let work = decodeWorkBorrowed(input.toOpenArray(cursor, input.high),
    ByteLimit(min(uint64(limits.outputBytes), uint64(limits.totalBlobBytes))))
  if work.error != CompositeError.None: return RecordResult[OperandLayout](error: convert(
      work.error)) # Reuse exact existing work tags and payload rules.
  var remaining = uint64(limits.totalBlobBytes)
  # Only successful work results carry a payload and consume aggregate blob budget.
  if work.value.kind == WorkKind.Success:
    layout.output = BlobSpan(offset: cursor+work.value.blob.offset, length: work.value.blob.length)
    layout.info.output = OperandOutputInfo(kind: WorkKind.Success, length: work.value.blob.length)
    remaining -= uint64(work.value.blob.length)
  else:
    # Work errors preserve their tag, without a fabricated default output length/span.
    layout.info.output = OperandOutputInfo(kind: work.value.kind)
  cursor += work.consumed
  if uint64(cursor) > uint64(limits.maxBytes): return RecordResult[OperandLayout](
      error: RecordError.LimitExceeded) # All work framing counts toward wire policy.
  let auth = decodeBytesBorrowed(input.toOpenArray(cursor, input.high),
    ByteLimit(min(uint64(limits.authBytes), remaining)))
  if auth.error != ContainerError.None: return RecordResult[OperandLayout](error: convert(
      auth.error)) # A late trace failure discards every earlier field.
  layout.auth = BlobSpan(offset: cursor+auth.offset, length: auth.length)
  cursor += auth.consumed
  if uint64(cursor) > uint64(limits.maxBytes): return RecordResult[OperandLayout](
      error: RecordError.LimitExceeded) # No capture until the complete final field fits.
  layout.info.authBytes = auth.length
  layout.info.consumed = cursor
  RecordResult[OperandLayout](error: RecordError.None, value: layout)

# Decode one complete tagged operand into private immutable ARC storage after all fields and limits validate.
proc decodeOperand*(input: openArray[byte], limits: OperandLimits): RecordResult[OperandRead] =
  let parsed = scanOperand(input, limits)
  # No partial owner or coordinate leaves a failed complete-record scan.
  if parsed.error != RecordError.None: return RecordResult[OperandRead](error: parsed.error)
  let data = OperandData(layout: parsed.value, wire: newSeq[byte](parsed.value.info.consumed))
  # Copy only the validated prefix, excluding all caller suffix bytes.
  for i in 0..<data.wire.len: data.wire[i] = input[i]
  RecordResult[OperandRead](error: RecordError.None,
    value: OperandRead(owner: OwnedOperand(data: data), consumed: data.wire.len))

# Grow complete output size only after proving host arithmetic and caller serialized-byte policy.
proc grow(total: var int, amount: int, limits: OperandLimits): RecordError =
  # Subtraction avoids overflowing a sum while measuring adversarially large source sequences.
  if amount > high(int)-total: return RecordError.LengthOverflow
  total += amount
  if uint64(total) > uint64(limits.maxBytes): return RecordError.LimitExceeded # All prefixes count toward this budget.
  RecordError.None

# Measure every source field and aggregate payload before capacity, alias checks or committing any output byte.
proc measure(value: AccumulationOperand, limits: OperandLimits): RecordResult[int] =
  var remaining = uint64(limits.totalBlobBytes)
  var total = 129
  if uint64(total) > uint64(limits.maxBytes): return RecordResult[int](
      error: RecordError.LimitExceeded) # Tag/four hashes need policy first.
  var error = grow(total, natural.encode(JamNatural(uint64(value.gas))).len, limits)
  if error != RecordError.None: return RecordResult[int](error: error) # Gas is a natural, not fixed E8.
  # A success has a variable blob; protocol error alternatives emit their tag alone.
  if value.output.kind == WorkKind.Success:
    let length = value.output.payload.len
    if uint64(length) > min(uint64(limits.outputBytes), remaining):
      return RecordResult[int](error: RecordError.LimitExceeded) # Individual/aggregate payload limits precede sizing.
    remaining -= uint64(length)
    error = grow(total, 1+natural.encode(JamNatural(uint64(length))).len, limits)
    if error != RecordError.None: return RecordResult[int](
        error: error) # Work tag/count framing contributes to parent budget.
    error = grow(total, length, limits)
  else:
    # Error work alternatives carry no length discriminator or byte pool.
    error = grow(total, 1, limits)
  if error != RecordError.None: return RecordResult[int](
      error: error) # No late error can permit partial source progress.
  if uint64(value.authTrace.len) > min(uint64(limits.authBytes), remaining):
    return RecordResult[int](error: RecordError.LimitExceeded) # Final trace policy is checked before destination capacity.
  error = grow(total, natural.encode(JamNatural(uint64(value.authTrace.len))).len, limits)
  if error != RecordError.None: return RecordResult[int](
      error: error) # Final count must fit even for an empty trace.
  error = grow(total, value.authTrace.len, limits)
  if error != RecordError.None: return RecordResult[int](
      error: error) # Entire trace extent must fit before writing the first tag.
  RecordResult[int](error: RecordError.None, value: total)

# Check all borrowed source storage against the whole written destination, including cross-field/header overlaps.
proc aliases(value: AccumulationOperand, output: var openArray[byte], total: int): bool =
  if overlaps(unsafeAddr value, sizeof(value), addr output[0],
      total): return true # Protect variant/sequence descriptors and all fixed fields.
  if value.output.kind == WorkKind.Success and value.output.payload.len > 0:
    # Earlier header output cannot overwrite a successful result's later borrowed payload.
    if overlaps(unsafeAddr value.output.payload[0], value.output.payload.len, addr output[0],
        total): return true
  if value.authTrace.len > 0:
    # Final trace bytes need the same whole-destination protection as earlier result bytes.
    if overlaps(unsafeAddr value.authTrace[0], value.authTrace.len, addr output[0],
        total): return true
  false

# Encode one operand atomically after all source, payload, wire-size, capacity and alias preflight succeeds.
proc encodeOperand*(value: AccumulationOperand, limits: OperandLimits,
    output: var openArray[byte]): RecordResult[int] =
  let measured = measure(value, limits)
  if measured.error != RecordError.None: return measured # Late trace/source errors precede any output inspection or mutation.
  let total = measured.value
  if output.len < total: return RecordResult[int](
      error: RecordError.OutputTooSmall) # Whole tuple capacity precedes pointer access.
  if aliases(value, output, total): return RecordResult[int](
      error: RecordError.AliasedBuffers) # Protect every source before tag emission.
  var cursor = 0
  putNatural(0, output, cursor)
  put(value.packageHash.bytes, output, cursor)
  put(value.segmentRoot.bytes, output, cursor)
  put(value.authorizer.bytes, output, cursor)
  put(array[32, byte](value.payloadHash), output, cursor)
  putNatural(uint64(value.gas), output, cursor)
  putNatural(uint64(ord(value.output.kind)), output, cursor)
  # Only successful work outputs encode an additional natural byte length and payload.
  if value.output.kind == WorkKind.Success:
    putNatural(uint64(value.output.payload.len), output, cursor)
    put(value.output.payload, output, cursor)
  putNatural(uint64(value.authTrace.len), output, cursor)
  put(value.authTrace, output, cursor)
  doAssert cursor == total
  RecordResult[int](error: RecordError.None, value: cursor)

# Copy complete operand metadata through its matching retained owner, with no mutable bytes or detached spans.
proc operandInfo*(owner: OwnedOperand): RecordResult[OperandInfo] =
  if owner.data.isNil: return RecordResult[OperandInfo](
      error: RecordError.InvalidOwner) # Defaults contain no validated frame.
  RecordResult[OperandInfo](error: RecordError.None, value: owner.data.layout.info)

# Copy an owner-bound private interval atomically; only validated internal coordinates can select its bytes.
proc extract(owner: OwnedOperand, span: BlobSpan, output: var openArray[byte]): RecordResult[int] =
  if output.len < span.length: return RecordResult[int](
      error: RecordError.OutputTooSmall) # Complete selected payload must fit.
  # Protect the retained caller-handle descriptor before copying any selected private payload byte.
  if span.length > 0 and overlaps(unsafeAddr owner, sizeof(owner), addr output[0], span.length):
    return RecordResult[int](error: RecordError.AliasedBuffers)
  if span.length > 0 and overlaps(unsafeAddr owner.data.wire[0], owner.data.wire.len, addr output[
      0], span.length):
    return RecordResult[int](error: RecordError.AliasedBuffers) # Any private-wire overwrite would invalidate the retained owner.
  var cursor = 0
  put(owner.data.wire.toOpenArray(span.offset, span.offset+span.length-1), output, cursor)
  RecordResult[int](error: RecordError.None, value: cursor)

# Copy only a successful operand result's payload through its matching immutable owner.
proc copyOperandOutput*(owner: OwnedOperand, output: var openArray[byte]): RecordResult[int] =
  if owner.data.isNil: return RecordResult[int](error: RecordError.InvalidOwner) # No default payload coordinates exist.
  if owner.data.layout.info.output.kind != WorkKind.Success:
    return RecordResult[int](error: RecordError.NoPayload) # Work errors cannot fabricate an empty success payload.
  extract(owner, owner.data.layout.output, output)

# Copy the complete authorization trace through its matching immutable operand owner, including a valid empty trace.
proc copyOperandTrace*(owner: OwnedOperand, output: var openArray[byte]): RecordResult[int] =
  if owner.data.isNil: return RecordResult[int](error: RecordError.InvalidOwner) # Default owners cannot authorize extraction.
  extract(owner, owner.data.layout.auth, output)

# Re-emit exact immutable operand bytes only after checking the current caller's policy, capacity and private-wire aliases.
proc encodeOwnedOperand*(owner: OwnedOperand, limits: OperandLimits,
    output: var openArray[byte]): RecordResult[int] =
  if owner.data.isNil: return RecordResult[int](error: RecordError.InvalidOwner) # Defaults differ from validated empty payloads.
  let parsed = scanOperand(owner.data.wire, limits)
  if parsed.error != RecordError.None: return RecordResult[int](
      error: parsed.error) # Stricter new limits are not bypassed by old capture.
  if output.len < owner.data.wire.len: return RecordResult[int](
      error: RecordError.OutputTooSmall) # Whole frame must fit.
  # The public byref owner type preserves caller-handle identity for this complete descriptor alias check.
  if overlaps(unsafeAddr owner, sizeof(owner), addr output[0], owner.data.wire.len):
    return RecordResult[int](error: RecordError.AliasedBuffers)
  if overlaps(unsafeAddr owner.data.wire[0], owner.data.wire.len, addr output[0],
      owner.data.wire.len):
    return RecordResult[int](error: RecordError.AliasedBuffers) # Exact copy cannot mutate any retained snapshot byte.
  var cursor = 0
  put(owner.data.wire, output, cursor)
  RecordResult[int](error: RecordError.None, value: cursor)

# Decode either accumulation input using its canonical outer tag, without an additional union wrapper or partial value.
proc decodeAccumulationInput*(input: openArray[byte], limits: OperandLimits): RecordResult[
    AccumulationRead] =
  var cursor = 0
  let tag = readNatural(input, cursor)
  if tag.error != RecordError.None: return RecordResult[AccumulationRead](
      error: tag.error) # Missing/overlong tags cannot select an alternative.
  case tag.value
  of 0:
    # The operand decoder reuses the original outer tag and validates every variable field before capture.
    let parsed = decodeOperand(input, limits)
    if parsed.error != RecordError.None: return RecordResult[AccumulationRead](
        error: parsed.error) # No earlier partial owner escapes.
    RecordResult[AccumulationRead](error: RecordError.None, value: AccumulationRead(
      value: AccumulationValue(kind: AccumulationKind.Operand, operand: parsed.value.owner),
          consumed: parsed.value.consumed))
  of 1:
    # Transfers use only the shared whole-input byte budget, not operand-only blob ceilings.
    let parsed = decodeTransfer(input, limits.maxBytes)
    if parsed.error != RecordError.None: return RecordResult[AccumulationRead](
        error: parsed.error) # No partial fixed transfer escapes.
    RecordResult[AccumulationRead](error: RecordError.None, value: AccumulationRead(
      value: AccumulationValue(kind: AccumulationKind.Transfer, transfer: parsed.value.value),
          consumed: parsed.value.consumed))
  else:
    # No undefined outer accumulation input alternative is accepted.
    RecordResult[AccumulationRead](error: RecordError.InvalidTag)

# Encode an independently selected accumulation source, protecting the whole union descriptor before child writes.
proc encodeAccumulationInput*(value: AccumulationSource, limits: OperandLimits,
    output: var openArray[byte]): RecordResult[int] =
  var total = 153
  # Validate selected sources before output capacity and whole-union descriptor aliases.
  case value.kind
  of AccumulationKind.Operand:
    # An operand's final payload policy may fail before any destination byte is inspected.
    let measured = measure(value.operand, limits)
    if measured.error != RecordError.None: return measured # Failed source contains no usable complete extent.
    total = measured.value
  of AccumulationKind.Transfer:
    # Fixed transfers consume no operand blob budget and have no input-derived source lengths.
    if uint64(limits.maxBytes) < 153: return RecordResult[int](error: RecordError.LimitExceeded)
  if output.len < total: return RecordResult[int](
      error: RecordError.OutputTooSmall) # Whole selected record must fit.
  if overlaps(unsafeAddr value, sizeof(value), addr output[0], total):
    return RecordResult[int](error: RecordError.AliasedBuffers) # Protect inactive/active union state as well as child fields.
  case value.kind
  of AccumulationKind.Operand: encodeOperand(value.operand, limits,
      output) # Child preflight also protects all borrowed blob storage.
  of AccumulationKind.Transfer: encodeTransfer(value.transfer, limits.maxBytes,
      output) # Reuse exact standalone transfer wire, with no extra tag.
