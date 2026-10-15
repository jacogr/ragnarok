## GP v0.7.1 C.2 assurances: allocation-free owned records and atomic caller-buffer operations.
import ./natural

type
  # Configuration domains remain distinct from each other and from encoded validator indices.
  CoreCount* = distinct uint64
  ValidatorCount* = distinct uint64
  ValidatorIndex* = distinct uint16
  # Fixed identity wrappers prevent anchor, availability and signature substitution.
  AssuranceAnchor* = object
    bytes*: array[32, byte]
  AssuranceBits* = object
    bytes*: array[43, byte]
  AssuranceSignature* = object
    bytes*: array[64, byte]
  # Explicit profile bounds are checked before accessing external input.
  AssuranceConfig* = object
    cores*: CoreCount
    validators*: ValidatorCount
  # All record fields own their bytes; no allocation, source pointer or reference cycle remains.
  Assurance* = object
    anchor*: AssuranceAnchor
    bits*: AssuranceBits
    validator*: ValidatorIndex
    signature*: AssuranceSignature
  # Default is a failure; None is selected only after complete validation and commit.
  AssuranceError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, Truncated, NonCanonical, LimitExceeded,
    OutputTooSmall, AliasedBuffers, LengthOverflow, InvalidValidator
  # Encoder progress exists exclusively in the checked success branch.
  AssuranceWriteResult* = object
    case error*: AssuranceError
    of AssuranceError.None:
      # A successful result selects exactly the written output prefix.
      written*: int
    else:
      # Failure never exposes partial progress.
      discard
  # Caller-owned typed records are selected exclusively by successful decode metadata.
  AssuranceDecodeResult* = object
    case error*: AssuranceError
    of AssuranceError.None:
      # Unused output elements remain unchanged and trailing input belongs to the caller.
      count*, consumed*: int
    else:
      # Failed decodes expose neither a default record nor consumed metadata.
      discard

# Validate configuration in its unsigned domain before any conversion or byte access.
proc validConfig(config: AssuranceConfig): bool {.raises: [].} =
  uint64(config.cores) in 1'u64..341'u64 and uint64(config.validators) in 1'u64..1023'u64

# Compare address distances, avoiding overflowing address-end sums and empty-span pointer access.
proc overlaps(a: pointer, aLen: int, b: pointer, bLen: int): bool {.raises: [].} =
  # An empty span borrows no bytes.
  if aLen == 0 or bLen == 0: return false
  let left = cast[uint](a)
  let right = cast[uint](b)
  # Subtraction from the earlier address cannot underflow.
  if left <= right: right - left < uint(aLen)
  else:
    # Reversing the addresses requires the other span's extent.
    left - right < uint(bLen)

# Validate one record in index/order/padding precedence without writing caller storage.
proc recordError(value: Assurance, config: AssuranceConfig,
    previous: int): AssuranceError {.raises: [].} =
  # A fixed E2 index may still be outside the configured validator set.
  if uint64(value.validator) >= uint64(config.validators): return AssuranceError.InvalidValidator
  # Canonical assurances are unique and strictly ascending by validator.
  if int(value.validator) <= previous: return AssuranceError.NonCanonical
  let width = (int(config.cores) + 7) div 8
  let remainder = int(config.cores) mod 8
  # Partial final bytes must not assign availability to nonexistent cores.
  if remainder != 0 and (int(value.bits.bytes[width-1]) shr remainder) != 0:
    return AssuranceError.NonCanonical
  for i in width..<43:
    if value.bits.bytes[i] != 0:
      # Nonzero unused storage has no canonical wire representation under this configuration.
      return AssuranceError.NonCanonical
  AssuranceError.None

# Read fixed owned fields only after the caller proves the complete record extent.
proc readRecord(input: openArray[byte], start, width: int): Assurance {.raises: [].} =
  # Hash bytes retain wire identity order.
  for i in 0..<32: result.anchor.bytes[i] = input[start+i]
  # Default zero initialization extends the bitset beyond the profile's wire width.
  for i in 0..<width: result.bits.bytes[i] = input[start+32+i]
  let position = start+32+width
  result.validator = ValidatorIndex(uint16(input[position]) or (uint16(input[position+1]) shl 8))
  # Signatures are opaque bytes; cryptographic verification requires external context.
  for i in 0..<64: result.signature.bytes[i] = input[position+2+i]

# Encode stable borrowed records atomically into separate caller-owned byte storage.
proc encodeAssurances*(values: openArray[Assurance], config: AssuranceConfig,
                       output: var openArray[byte]): AssuranceWriteResult {.raises: [].} =
  # Configuration takes precedence even when the sequence is empty.
  if not validConfig(config): return AssuranceWriteResult(error: AssuranceError.InvalidConfig)
  # Apply the policy before output capacity or host arithmetic.
  if uint64(values.len) > uint64(config.validators):
    return AssuranceWriteResult(error: AssuranceError.LimitExceeded)
  let width = (int(config.cores)+7) div 8
  let stride = 98+width
  let prefix = natural.encode(JamNatural(values.len))
  # Division proves the complete output product without overflowing it.
  if output.len < prefix.len or values.len > (output.len-prefix.len) div stride:
    return AssuranceWriteResult(error: AssuranceError.OutputTooSmall)
  let total = prefix.len+values.len*stride
  # Typed metadata byte extents require their own checked product.
  if values.len > high(int) div sizeof(Assurance):
    return AssuranceWriteResult(error: AssuranceError.LengthOverflow)
  # Empty sequences need no source pointer; nonempty sources must be disjoint from all written bytes.
  if values.len > 0 and overlaps(unsafeAddr values[0], values.len*sizeof(Assurance),
                                addr output[0], total):
    return AssuranceWriteResult(error: AssuranceError.AliasedBuffers)
  var previous = -1
  # Preflight the final record too before committing any output byte.
  for value in values:
    let error = recordError(value, config, previous)
    if error != AssuranceError.None:
      # Return only the reason, never partial progress or a default value.
      return AssuranceWriteResult(error: error)
    previous = int(value.validator)
  # Stable disjoint validated input makes this commit phase infallible.
  for i in 0..<prefix.len: output[i] = prefix.bytes[i]
  # Every destination index is covered by the complete output extent proof.
  for i, value in values:
    let start = prefix.len+i*stride
    # Copy the hash's declared identity bytes.
    for j in 0..<32: output[start+j] = value.anchor.bytes[j]
    # Fixed profile bitfields carry no inner length prefix.
    for j in 0..<width: output[start+32+j] = value.bits.bytes[j]
    let position = start+32+width
    output[position] = byte(uint16(value.validator) and 255)
    output[position+1] = byte(uint16(value.validator) shr 8)
    # Preserve every signature byte without interpreting cryptographic validity.
    for j in 0..<64: output[position+2+j] = value.signature.bytes[j]
  AssuranceWriteResult(error: AssuranceError.None, written: total)

# Decode one prefix into independent caller records; the whole destination survives any failure.
proc decodeAssurances*(input: openArray[byte], config: AssuranceConfig,
                       output: var openArray[Assurance]): AssuranceDecodeResult {.raises: [].} =
  # Reject invalid profiles before reading even the count header.
  if not validConfig(config): return AssuranceDecodeResult(error: AssuranceError.InvalidConfig)
  let prefix = natural.decode(input)
  # Preserve the primitive's canonicality and truncation distinction.
  if not prefix.ok:
    if prefix.error == natural.truncated:
      # No count is available for subsequent record parsing.
      return AssuranceDecodeResult(error: AssuranceError.Truncated)
    else:
      # An overlong count cannot describe a canonical sequence.
      return AssuranceDecodeResult(error: AssuranceError.NonCanonical)
  let count = uint64(prefix.value)
  # Ceiling applies before input extent, typed capacity and narrowing.
  if count > uint64(config.validators): return AssuranceDecodeResult(
      error: AssuranceError.LimitExceeded)
  let width = (int(config.cores)+7) div 8
  let stride = 98+width
  # Division proves both complete wire extent and safe host conversion.
  if count > uint64((input.len-prefix.consumed) div stride):
    return AssuranceDecodeResult(error: AssuranceError.Truncated)
  # A complete wire frame can still exceed the caller's typed capacity.
  if count > uint64(output.len): return AssuranceDecodeResult(error: AssuranceError.OutputTooSmall)
  # Prove the typed storage product before comparing address ranges.
  if count > uint64(high(int) div sizeof(Assurance)):
    return AssuranceDecodeResult(error: AssuranceError.LengthOverflow)
  let length = int(count)
  # Protect the entire original input, including bytes after the decoded prefix.
  if length > 0 and overlaps(unsafeAddr input[0], input.len, addr output[0], length*sizeof(Assurance)):
    return AssuranceDecodeResult(error: AssuranceError.AliasedBuffers)
  var previous = -1
  # Semantic validation is a separate pass so late failures cannot partially initialize output.
  for i in 0..<length:
    let value = readRecord(input, prefix.consumed+i*stride, width)
    let error = recordError(value, config, previous)
    if error != AssuranceError.None:
      # Failure contains no count or consumed fields.
      return AssuranceDecodeResult(error: error)
    previous = int(value.validator)
  # After full preflight, copy owned fields into only the initialized destination prefix.
  for i in 0..<length: output[i] = readRecord(input, prefix.consumed+i*stride, width)
  AssuranceDecodeResult(error: AssuranceError.None, count: length,
      consumed: prefix.consumed+length*stride)
