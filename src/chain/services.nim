# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded service reads from an immutable configured genesis map, using GP 0.8.0 state namespaces.
## Exposes serviceData, serviceValue and servicePreimage with guarded read results. Missing entries
## carry no value; successful StateValue views retain the snapshot and copy bytes only on extraction.

import ./genesis
import ../state/store
import ../codec/[state_layout, state_accounts, state_service_values, bounded]
import ../crypto/primitives
export ServiceIndex, ServicePreimageHash, StateValue, byteLength, bytes, ByteLimit

const MaxServiceKeyBytes* = 4096 ## Bound raw storage-key hashing independently of JSON input limits.

type
  ## Missing data is distinct from a malformed account, resource limit or native hash failure.
  ServiceReadError* {.pure.} = enum
    Uninitialized, None, Missing, Malformed, LimitExceeded, BackendFailure
  ## Only complete success contains an owner-bound immutable value view.
  ServiceReadResult* = object
    case status: ServiceReadError
    of None:
      completed: StateValue
    else:
      discard # A missing or failed lookup cannot masquerade as a present empty blob.

## Inspect the read reason without granting mutation or access to a failed payload.
func error*(value: ServiceReadResult): ServiceReadError = value.status
## Extract only a successful immutable view; bytes() returns an independent copy.
func value*(value: ServiceReadResult): StateValue {.requires: value.status ==
    ServiceReadError.None.} = value.completed

## Find one serialized entry and check its size before any value copy or Base64 allocation.
proc read(view: Genesis, key: StateKey, limit: ByteLimit): ServiceReadResult =
  let found = view.lookup(key)
  if found.error == StateStoreError.Uninitialized:
    return ServiceReadResult(status: ServiceReadError.Uninitialized) # Default genesis handles are typed failures.
  if found.error == StateStoreError.MissingKey:
    return ServiceReadResult(status: ServiceReadError.Missing) # Absence is not an empty byte string.
  if found.error != StateStoreError.None:
    return ServiceReadResult(status: ServiceReadError.BackendFailure) # Never turn an invalid owner into absence.
  if uint64(found.value.byteLength) > uint64(limit):
    return ServiceReadResult(status: ServiceReadError.LimitExceeded) # Apply caller's response budget before copying.
  ServiceReadResult(status: ServiceReadError.None, completed: found.value)

## Read the exact version-zero C(255, service) account record, rejecting malformed imported metadata.
proc serviceData*(view: Genesis, service: ServiceIndex, limit: ByteLimit): ServiceReadResult =
  let found = read(view, chapterServiceKey(StateChapter(255), service), ByteLimit(ServiceMetadataBytes))
  if found.error != ServiceReadError.None:
    return found # An absent account is null; oversized or otherwise unreadable metadata is an error.
  let wire = found.value.bytes
  let decoded = decodeServiceMetadata(wire, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None or wire.len != ServiceMetadataBytes:
    return ServiceReadResult(status: ServiceReadError.Malformed) # Do not serve unsupported or truncated account data.
  if uint64(wire.len) > uint64(limit):
    return ServiceReadResult(status: ServiceReadError.LimitExceeded) # The account also obeys the per-response allowance.
  found

## Read a raw storage value using the maintained E4(uint32-max) namespace constructor.
proc serviceValue*(view: Genesis, service: ServiceIndex, key: openArray[byte],
    limit: ByteLimit): ServiceReadResult =
  let account = serviceData(view, service, ByteLimit(ServiceMetadataBytes))
  if account.error != ServiceReadError.None: return account # An orphan keyed entry does not establish a service.
  if key.len > MaxServiceKeyBytes: return ServiceReadResult(
      status: ServiceReadError.LimitExceeded) # Bound key hashing.
  let derived = serviceStorageKey(service, key, ByteLimit(MaxServiceKeyBytes))
  if derived.error != ServiceValueError.None:
    return ServiceReadResult(status: ServiceReadError.BackendFailure) # No guessed key after native hashing failure.
  read(view, derived.value, limit)

## Read and verify a bounded preimage from the E4(uint32-max-1) namespace.
proc servicePreimage*(view: Genesis, service: ServiceIndex, hash: ServicePreimageHash,
    limit: ByteLimit): ServiceReadResult =
  let account = serviceData(view, service, ByteLimit(ServiceMetadataBytes))
  if account.error != ServiceReadError.None: return account # Only an existing structurally valid account can supply data.
  let derived = servicePreimageKey(service, hash, ByteLimit(32))
  if derived.error != ServiceValueError.None:
    return ServiceReadResult(status: ServiceReadError.BackendFailure) # Key hashing failure cannot become absence.
  let found = read(view, derived.value, limit)
  if found.error != ServiceReadError.None: return found # Reject oversize before copying or hashing the value.
  let hashed = blake2b256(found.value.bytes)
  if hashed.error != CryptoError.None:
    return ServiceReadResult(status: ServiceReadError.BackendFailure) # Preserve primitive refusal.
  if array[32, byte](hashed.value) != array[32, byte](hash):
    return ServiceReadResult(status: ServiceReadError.Malformed) # Imported opaque maps may contain inconsistent preimages.
  found
