# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 T: service storage/preimage keyed entries and immutable raw trie-value capture. Hash
## domains are explicit; raw values have no framing prefix and capture requires no reversible
## original key.
##
## Exposes service storage/preimage key and entry constructors, immutable value capture and
## bounded value copying.

import std/assertions
import ../[bounded, composite]
import ./[layout as state_layout, trie as state_trie]
export ServiceIndex, StateKey

type
  ServicePreimageHash* = distinct array[32, byte] ## A preimage lookup identity is distinct from a code hash, output commitment or final state key.
  ServiceEntryLimits* = object ## Independent caller limits for logical raw key/hash bytes and raw value bytes; namespace prefixes are fixed overhead.
    keyBytes*, valueBytes*: ByteLimit
  ServiceValueError* {.pure.} = enum ## Failed/default results contain reasons alone, never keys, values, owners or completed copy progress.
    Uninitialized, None, LimitExceeded, LengthOverflow, BackendFailure, InvalidServiceKey,
    InvalidOwner, OutputTooSmall, AliasedBuffers
  ServiceValueResult*[T] = object ## Only selected complete success exposes its application payload.
    case status: ServiceValueError
    of None:
      completed: T                # The guarded accessor alone authorizes a complete payload.
    else:
      discard                     # A failure cannot fabricate an empty captured value or default state key.
  ## Private acyclic ARC storage binds independent raw value bytes to their exact supplied key and service.
  ServiceValueData = ref object
    service: ServiceIndex
    key: StateKey
    bytes: seq[byte]
  ServiceValueSnapshot* = object ## Value handles share immutable private storage; replacing one handle never changes another's data.
    data: nil ServiceValueData
  ServiceValueInfo* = object ## Fixed copied identity/size metadata exports neither backing bytes nor reusable detached coordinates.
    service*: ServiceIndex
    key*: StateKey
    length*: int

func error*[T](value: ServiceValueResult[T]): ServiceValueError =
  ## Read-only reasons never authorize retained keys, raw bytes or completed copy progress.
  value.status

func value*[T](value: ServiceValueResult[T]): T
    {.inline, requires: value.status == ServiceValueError.None.} =
  ## Public payloads and internal scratch extents require successful result selection.
  value.completed

proc storageExtent(length: int): ServiceValueResult[int] =
  ## Prove fixed-prefix addition for a nonnegative native key length before scratch allocation.
  if length > high(int)-4:
    return ServiceValueResult[int](status: ServiceValueError.LengthOverflow) # Never wrap a native scratch extent.
  ServiceValueResult[int](status: ServiceValueError.None, completed: length+4)

proc keyError(error: StateLayoutError): ServiceValueError =
  ## Preserve the maintained state-key constructor's policy/backend failure without exporting unrelated node statuses.
  case error
  of StateLayoutError.LimitExceeded: ServiceValueError.LimitExceeded # Key policy failed before hashing.
  else: ServiceValueError.BackendFailure # A key is never fabricated after native hash failure.

proc serviceStorageKey*(service: ServiceIndex, key: openArray[byte],
    maxKeyBytes: ByteLimit): ServiceValueResult[StateKey] =
  ## Derive C(service, E4(uint32-max) || raw_storage_key), without natural/key-length framing.
  if uint64(key.len) > uint64(maxKeyBytes):
    return ServiceValueResult[StateKey](status: ServiceValueError.LimitExceeded) # Logical key policy excludes the fixed namespace overhead.
  let checked = storageExtent(key.len)
  if checked.error != ServiceValueError.None:
    return ServiceValueResult[StateKey](status: checked.error) # Prove prefixed scratch allocation before addition.
  var preimage = newSeq[byte](checked.value)
  for i in 0..<4: preimage[i] = 255 # E4(uint32-max) selects storage, including the empty raw key.
  for i in 0..<key.len: preimage[i+4] = key[i] # Raw key octets are neither naturally prefixed nor hashed separately.
  let derived = hashedServiceKey(service, preimage, ByteLimit(preimage.len))
  if derived.error != StateLayoutError.None:
    return ServiceValueResult[StateKey](status: keyError(derived.error)) # No key after a backend rejection.
  ServiceValueResult[StateKey](status: ServiceValueError.None, completed: derived.value)

proc servicePreimageKey*(service: ServiceIndex, hash: ServicePreimageHash,
    maxKeyBytes: ByteLimit): ServiceValueResult[StateKey] =
  ## Derive C(service, E4(uint32-max-1) || lookup_hash) using a fixed local preimage buffer.
  if uint64(maxKeyBytes) < 32:
    return ServiceValueResult[StateKey](status: ServiceValueError.LimitExceeded) # The logical lookup identity always contains exactly 32 bytes.
  var preimage = default(array[36, byte])
  preimage[0] = 254
  for i in 1..<4: preimage[i] = 255 # Explicit E4(uint32-max-1) domain, distinct from storage and request lengths.
  let bytes = array[32, byte](hash)
  for i in 0..<32: preimage[i+4] = bytes[i] # The lookup hash is raw fixed bytes, not recomputed from the value here.
  let derived = hashedServiceKey(service, preimage, ByteLimit(preimage.len))
  if derived.error != StateLayoutError.None:
    return ServiceValueResult[StateKey](status: keyError(
        derived.error)) # Preserve maintained native hash failure.
  ServiceValueResult[StateKey](status: ServiceValueError.None, completed: derived.value)

proc entry(key: StateKey, value: openArray[byte]): StateEntry =
  ## Copy a complete raw value after callers have proved policy and key derivation, without a blob-length prefix.
  result = StateEntry(key: key, value: newSeq[byte](value.len))
  for i in 0..<value.len: result.value[i] = value[
      i] # Fresh output never aliases caller input or retained owner bytes.

proc serviceStorageEntry*(service: ServiceIndex, key, value: openArray[byte],
    limits: ServiceEntryLimits): ServiceValueResult[StateEntry] =
  ## Construct one storage mapping after value/key policy and complete namespace-key derivation.
  if uint64(value.len) > uint64(limits.valueBytes):
    return ServiceValueResult[StateEntry](status: ServiceValueError.LimitExceeded) # Reject oversized values before key scratch/hash work.
  let derived = serviceStorageKey(service, key, limits.keyBytes)
  if derived.error != ServiceValueError.None:
    return ServiceValueResult[StateEntry](status: derived.error) # No raw output allocation before key success.
  ServiceValueResult[StateEntry](status: ServiceValueError.None, completed: entry(derived.value, value))

proc servicePreimageEntry*(service: ServiceIndex, hash: ServicePreimageHash, value: openArray[byte],
    limits: ServiceEntryLimits): ServiceValueResult[StateEntry] =
  ## Construct one preimage mapping while preserving the supplied hash/value relationship as raw state data.
  if uint64(value.len) > uint64(limits.valueBytes):
    return ServiceValueResult[StateEntry](status: ServiceValueError.LimitExceeded) # Complete value policy precedes key hashing.
  let derived = servicePreimageKey(service, hash, limits.keyBytes)
  if derived.error != ServiceValueError.None:
    return ServiceValueResult[StateEntry](status: derived.error) # No output after key policy/backend failure.
  ServiceValueResult[StateEntry](status: ServiceValueError.None, completed: entry(derived.value, value))

proc captureServiceValue*(service: ServiceIndex, key: StateKey, value: openArray[byte],
    maxBytes: ByteLimit): ServiceValueResult[ServiceValueSnapshot] =
  ## Capture a complete externally delimited raw value using its existing trie key, without requiring original storage keys.
  if uint64(value.len) > uint64(maxBytes):
    return ServiceValueResult[ServiceValueSnapshot](
        status: ServiceValueError.LimitExceeded) # Bound copies before allocation or identity traversal.
  let bytes = array[31, byte](key)
  let number = uint32(service)
  for i in 0..<4:
    if bytes[2*i] != byte((number shr (i*8)) and 255):
      return ServiceValueResult[ServiceValueSnapshot](
          status: ServiceValueError.InvalidServiceKey) # Supplied hashed-key service octets must match context.
  let data = ServiceValueData(service: service, key: key, bytes: newSeq[byte](value.len))
  for i in 0..<value.len: data.bytes[i] = value[i] # Entire input is the raw value; no prefix or suffix can be inferred internally.
  ServiceValueResult[ServiceValueSnapshot](status: ServiceValueError.None,
      completed: ServiceValueSnapshot(data: data))

proc serviceValueInfo*(owner: ServiceValueSnapshot): ServiceValueResult[ServiceValueInfo] =
  ## Return copied service/key/length metadata without exposing retained mutable arrays.
  let data = owner.data
  if data == nil:
    return ServiceValueResult[ServiceValueInfo](status: ServiceValueError.InvalidOwner) # Default handles differ from captured empty raw values.
  ServiceValueResult[ServiceValueInfo](status: ServiceValueError.None,
    completed: ServiceValueInfo(service: data.service, key: data.key,
        length: data.bytes.len))

proc overlaps(owner: ServiceValueData, output: var openArray[byte]): bool =
  ## Check address differences rather than overflowing end pointers when guarding a native destination.
  if owner.bytes.len == 0 or output.len == 0: return false # Empty copies have no address to inspect.
  let source = cast[uint](unsafeAddr owner.bytes[0])
  let destination = cast[uint](addr output[0])
  if source <= destination: destination-source < uint(owner.bytes.len) # Destination begins inside retained bytes.
  else: source-destination < uint(output.len) # Source begins inside caller output.

proc copyServiceValue*(owner: ServiceValueSnapshot, output: var openArray[
    byte]): ServiceValueResult[int] =
  ## Atomically copy all retained raw bytes, checking owner, capacity and disjointness before any write.
  let data = owner.data
  if data == nil:
    return ServiceValueResult[int](status: ServiceValueError.InvalidOwner) # Missing owners cannot authorize a fabricated empty copy.
  if output.len < data.bytes.len:
    return ServiceValueResult[int](status: ServiceValueError.OutputTooSmall) # No partial prefix is written on a short destination.
  if overlaps(data, output):
    return ServiceValueResult[int](status: ServiceValueError.AliasedBuffers) # Safe APIs expose no alias, but native misuse must not mutate retained data.
  for i in 0..<data.bytes.len: output[i] = data.bytes[
      i] # Only the completed raw-value prefix changes; destination suffix stays untouched.
  ServiceValueResult[int](status: ServiceValueError.None, completed: data.bytes.len)

proc serviceValueEntry*(owner: ServiceValueSnapshot, maxBytes: ByteLimit): ServiceValueResult[StateEntry] =
  ## Re-emit one retained keyed raw value to fresh output under the caller's current byte policy.
  let data = owner.data
  if data == nil:
    return ServiceValueResult[StateEntry](status: ServiceValueError.InvalidOwner) # No default key/value from missing storage.
  if uint64(data.bytes.len) > uint64(maxBytes):
    return ServiceValueResult[StateEntry](status: ServiceValueError.LimitExceeded) # A narrower new policy is enforced before allocation.
  ServiceValueResult[StateEntry](status: ServiceValueError.None, completed: entry(data.key,
      data.bytes))
