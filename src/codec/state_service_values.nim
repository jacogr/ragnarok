## GP 0.8.0 T: service storage/preimage keyed entries and immutable raw trie-value capture.
## Hash domains are explicit; raw values have no framing prefix and capture requires no reversible original key.
import ./[bounded, composite, state_layout, state_trie]
export ServiceIndex, StateKey

type
  ## A preimage lookup identity is distinct from a code hash, output commitment or final state key.
  ServicePreimageHash* = distinct array[32, byte]
  ## Independent caller limits for logical raw key/hash bytes and raw value bytes; namespace prefixes are fixed overhead.
  ServiceEntryLimits* = object
    keyBytes*, valueBytes*: ByteLimit
  ## Failed/default results contain reasons alone, never keys, values, owners or completed copy progress.
  ServiceValueError* {.pure.} = enum
    Uninitialized, None, LimitExceeded, LengthOverflow, BackendFailure, InvalidServiceKey,
    InvalidOwner, OutputTooSmall, AliasedBuffers
  ## Only selected complete success exposes its application payload.
  ServiceValueResult*[T] = object
    case error*: ServiceValueError
    of ServiceValueError.None:
      value*: T # Runtime field guards protect failure-only alternatives in checked builds.
    else:
      discard   # A failure cannot fabricate an empty captured value or default state key.
  ## Private acyclic ARC storage binds independent raw value bytes to their exact supplied key and service.
  ServiceValueData = ref object
    service: ServiceIndex
    key: StateKey
    bytes: seq[byte]
  ## Value handles share immutable private storage; replacing one handle never changes another's data.
  ServiceValueSnapshot* = object
    data: ServiceValueData
  ## Fixed copied identity/size metadata exports neither backing bytes nor reusable detached coordinates.
  ServiceValueInfo* = object
    service*: ServiceIndex
    key*: StateKey
    length*: int

## Preserve the maintained state-key constructor's policy/backend failure without exporting unrelated node statuses.
proc keyError(error: StateLayoutError): ServiceValueError =
  case error
  of StateLayoutError.LimitExceeded: ServiceValueError.LimitExceeded # Key policy failed before hashing.
  else: ServiceValueError.BackendFailure # A key is never fabricated after native hash failure.

## Derive C(service, E4(uint32-max) || raw_storage_key), without natural/key-length framing.
proc serviceStorageKey*(service: ServiceIndex, key: openArray[byte],
    maxKeyBytes: ByteLimit): ServiceValueResult[StateKey] =
  if uint64(key.len) > uint64(maxKeyBytes):
    return ServiceValueResult[StateKey](error: ServiceValueError.LimitExceeded) # Logical key policy excludes the fixed namespace overhead.
  if key.len > high(int)-4:
    return ServiceValueResult[StateKey](error: ServiceValueError.LengthOverflow) # Prove prefixed scratch allocation before addition.
  var preimage = newSeq[byte](key.len+4)
  for i in 0..<4: preimage[i] = 255 # E4(uint32-max) selects storage, including the empty raw key.
  for i in 0..<key.len: preimage[i+4] = key[i] # Raw key octets are neither naturally prefixed nor hashed separately.
  let derived = hashedServiceKey(service, preimage, ByteLimit(preimage.len))
  if derived.error != StateLayoutError.None:
    return ServiceValueResult[StateKey](error: keyError(derived.error)) # No key after a backend rejection.
  ServiceValueResult[StateKey](error: ServiceValueError.None, value: derived.value)

## Derive C(service, E4(uint32-max-1) || lookup_hash) using a fixed local preimage buffer.
proc servicePreimageKey*(service: ServiceIndex, hash: ServicePreimageHash,
    maxKeyBytes: ByteLimit): ServiceValueResult[StateKey] =
  if uint64(maxKeyBytes) < 32:
    return ServiceValueResult[StateKey](error: ServiceValueError.LimitExceeded) # The logical lookup identity always contains exactly 32 bytes.
  var preimage: array[36, byte]
  preimage[0] = 254
  for i in 1..<4: preimage[i] = 255 # Explicit E4(uint32-max-1) domain, distinct from storage and request lengths.
  let bytes = array[32, byte](hash)
  for i in 0..<32: preimage[i+4] = bytes[i] # The lookup hash is raw fixed bytes, not recomputed from the value here.
  let derived = hashedServiceKey(service, preimage, ByteLimit(preimage.len))
  if derived.error != StateLayoutError.None:
    return ServiceValueResult[StateKey](error: keyError(derived.error)) # Preserve maintained native hash failure.
  ServiceValueResult[StateKey](error: ServiceValueError.None, value: derived.value)

## Copy a complete raw value after callers have proved policy and key derivation, without a blob-length prefix.
proc entry(key: StateKey, value: openArray[byte]): StateEntry =
  result = StateEntry(key: key, value: newSeq[byte](value.len))
  for i in 0..<value.len: result.value[i] = value[
      i] # Fresh output never aliases caller input or retained owner bytes.

## Construct one storage mapping after value/key policy and complete namespace-key derivation.
proc serviceStorageEntry*(service: ServiceIndex, key, value: openArray[byte],
    limits: ServiceEntryLimits): ServiceValueResult[StateEntry] =
  if uint64(value.len) > uint64(limits.valueBytes):
    return ServiceValueResult[StateEntry](error: ServiceValueError.LimitExceeded) # Reject oversized values before key scratch/hash work.
  let derived = serviceStorageKey(service, key, limits.keyBytes)
  if derived.error != ServiceValueError.None:
    return ServiceValueResult[StateEntry](error: derived.error) # No raw output allocation before key success.
  ServiceValueResult[StateEntry](error: ServiceValueError.None, value: entry(derived.value, value))

## Construct one preimage mapping while preserving the supplied hash/value relationship as raw state data.
proc servicePreimageEntry*(service: ServiceIndex, hash: ServicePreimageHash, value: openArray[byte],
    limits: ServiceEntryLimits): ServiceValueResult[StateEntry] =
  if uint64(value.len) > uint64(limits.valueBytes):
    return ServiceValueResult[StateEntry](error: ServiceValueError.LimitExceeded) # Complete value policy precedes key hashing.
  let derived = servicePreimageKey(service, hash, limits.keyBytes)
  if derived.error != ServiceValueError.None:
    return ServiceValueResult[StateEntry](error: derived.error) # No output after key policy/backend failure.
  ServiceValueResult[StateEntry](error: ServiceValueError.None, value: entry(derived.value, value))

## Capture a complete externally delimited raw value using its existing trie key, without requiring original storage keys.
proc captureServiceValue*(service: ServiceIndex, key: StateKey, value: openArray[byte],
    maxBytes: ByteLimit): ServiceValueResult[ServiceValueSnapshot] =
  if uint64(value.len) > uint64(maxBytes):
    return ServiceValueResult[ServiceValueSnapshot](
        error: ServiceValueError.LimitExceeded) # Bound copies before allocation or identity traversal.
  let bytes = array[31, byte](key)
  let number = uint32(service)
  for i in 0..<4:
    if bytes[2*i] != byte((number shr (i*8)) and 255):
      return ServiceValueResult[ServiceValueSnapshot](
          error: ServiceValueError.InvalidServiceKey) # Supplied hashed-key service octets must match context.
  let data = ServiceValueData(service: service, key: key, bytes: newSeq[byte](value.len))
  for i in 0..<value.len: data.bytes[i] = value[i] # Entire input is the raw value; no prefix or suffix can be inferred internally.
  ServiceValueResult[ServiceValueSnapshot](error: ServiceValueError.None,
      value: ServiceValueSnapshot(data: data))

## Return copied service/key/length metadata without exposing retained mutable arrays.
proc serviceValueInfo*(owner: ServiceValueSnapshot): ServiceValueResult[ServiceValueInfo] =
  if owner.data.isNil:
    return ServiceValueResult[ServiceValueInfo](error: ServiceValueError.InvalidOwner) # Default handles differ from captured empty raw values.
  ServiceValueResult[ServiceValueInfo](error: ServiceValueError.None,
    value: ServiceValueInfo(service: owner.data.service, key: owner.data.key,
        length: owner.data.bytes.len))

## Check address differences rather than overflowing end pointers when guarding a native destination.
proc overlaps(owner: ServiceValueData, output: var openArray[byte]): bool =
  if owner.bytes.len == 0 or output.len == 0: return false # Empty copies have no address to inspect.
  let source = cast[uint](unsafeAddr owner.bytes[0])
  let destination = cast[uint](addr output[0])
  if source <= destination: destination-source < uint(owner.bytes.len) # Destination begins inside retained bytes.
  else: source-destination < uint(output.len) # Source begins inside caller output.

## Atomically copy all retained raw bytes, checking owner, capacity and disjointness before any write.
proc copyServiceValue*(owner: ServiceValueSnapshot, output: var openArray[
    byte]): ServiceValueResult[int] =
  if owner.data.isNil:
    return ServiceValueResult[int](error: ServiceValueError.InvalidOwner) # Missing owners cannot authorize a fabricated empty copy.
  if output.len < owner.data.bytes.len:
    return ServiceValueResult[int](error: ServiceValueError.OutputTooSmall) # No partial prefix is written on a short destination.
  if overlaps(owner.data, output):
    return ServiceValueResult[int](error: ServiceValueError.AliasedBuffers) # Safe APIs expose no alias, but native misuse must not mutate retained data.
  for i in 0..<owner.data.bytes.len: output[i] = owner.data.bytes[
      i] # Only the completed raw-value prefix changes; destination suffix stays untouched.
  ServiceValueResult[int](error: ServiceValueError.None, value: owner.data.bytes.len)

## Re-emit one retained keyed raw value to fresh output under the caller's current byte policy.
proc serviceValueEntry*(owner: ServiceValueSnapshot, maxBytes: ByteLimit): ServiceValueResult[StateEntry] =
  if owner.data.isNil:
    return ServiceValueResult[StateEntry](error: ServiceValueError.InvalidOwner) # No default key/value from missing storage.
  if uint64(owner.data.bytes.len) > uint64(maxBytes):
    return ServiceValueResult[StateEntry](error: ServiceValueError.LimitExceeded) # A narrower new policy is enforced before allocation.
  ServiceValueResult[StateEntry](error: ServiceValueError.None, value: entry(owner.data.key,
      owner.data.bytes))
