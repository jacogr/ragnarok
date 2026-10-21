# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded service reads from an immutable configured genesis map, using GP 0.8.0 state namespaces.
## Exposes serviceData, serviceValue, servicePreimage and serviceRequest with guarded read results.
## Missing entries carry no value; StateValue views retain the snapshot and copy bytes on extraction.
## Successful request lookups return independent fixed histories with no retained borrows.

import ./genesis
import ../state/store
import ../codec/[state_layout, state_accounts, state_service_values, state_requests, bounded]
import ../crypto/primitives
export ServiceIndex, ServicePreimageHash, StateValue, byteLength, bytes, ByteLimit

export RequestHistory, RequestLength, RequestState, state, since, availableFrom, unavailableFrom,
  originalFrom, removedAt, restoredAt

const MaxServiceKeyBytes* = 4096 ## Bound raw storage-key hashing independently of JSON input limits.

type
  ServiceReadError* {.pure.} = enum ## Missing data is distinct from a malformed account, resource limit or native hash failure.
    Uninitialized, None, Missing, Malformed, LimitExceeded, BackendFailure, AmbiguousNamespace, InvalidLength
  ServiceReadResult* = object ## Only complete success contains an owner-bound immutable value view.
    case status: ServiceReadError
    of None:
      completed: StateValue
    else:
      discard                 # A missing or failed lookup cannot masquerade as a present empty blob.

  ServiceRequestResult* = object ## Request histories contain only fixed copied timestamps; absence is never a default empty history.
    case status: ServiceReadError
    of None:
      completed: RequestHistory
    else:
      discard # Failure/absence carries no history payload.

func error*(value: ServiceRequestResult): ServiceReadError =
  ## Inspect request lookup status without permitting result retagging.
  value.status
func value*(value: ServiceRequestResult): RequestHistory {.requires: value.status ==
    ServiceReadError.None.} =
  ## Return a fixed independent history only after successful lookup and complete decoding.
  value.completed

func error*(value: ServiceReadResult): ServiceReadError =
  ## Inspect the read reason without granting mutation or access to a failed payload.
  value.status
func value*(value: ServiceReadResult): StateValue {.requires: value.status ==
    ServiceReadError.None.} =
  ## Extract only a successful immutable view; bytes() returns an independent copy.
  value.completed

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

proc serviceData*(view: Genesis, service: ServiceIndex, limit: ByteLimit): ServiceReadResult =
  ## Read the exact version-zero C(255, service) account record, rejecting malformed imported metadata.
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

proc serviceValue*(view: Genesis, service: ServiceIndex, key: openArray[byte],
    limit: ByteLimit): ServiceReadResult =
  ## Read a raw storage value using the maintained E4(uint32-max) namespace constructor.
  let account = serviceData(view, service, ByteLimit(ServiceMetadataBytes))
  if account.error != ServiceReadError.None: return account # An orphan keyed entry does not establish a service.
  if key.len > MaxServiceKeyBytes: return ServiceReadResult(
      status: ServiceReadError.LimitExceeded) # Bound key hashing.
  let derived = serviceStorageKey(service, key, ByteLimit(MaxServiceKeyBytes))
  if derived.error != ServiceValueError.None:
    return ServiceReadResult(status: ServiceReadError.BackendFailure) # No guessed key after native hashing failure.
  read(view, derived.value, limit)

proc servicePreimage*(view: Genesis, service: ServiceIndex, hash: ServicePreimageHash,
    limit: ByteLimit): ServiceReadResult =
  ## Read and verify a bounded preimage from the E4(uint32-max-1) namespace.
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

proc serviceRequest*(view: Genesis, service: ServiceIndex, hash: ServicePreimageHash,
    length: RequestLength): ServiceRequestResult =
  ## Read a fixed history from the current bounded request namespace, without length-sized allocation.
  ## Reserved E4 prefixes refuse before state lookup or hashing; legacy ambiguity status is retained for compatibility.
  if uint32(length) >= high(uint32) - 1:
    return ServiceRequestResult(status: ServiceReadError.InvalidLength) # Invalid input cannot become absent data or backend failure.
  let account = serviceData(view, service, ByteLimit(ServiceMetadataBytes))
  if account.error != ServiceReadError.None:
    return ServiceRequestResult(status: account.error) # An absent account cannot supply request state.
  let derived = serviceRequestKey(service, hash, length, ByteLimit(32))
  if derived.error != RequestError.None:
    return ServiceRequestResult(status: ServiceReadError.BackendFailure) # Backend refusal is distinct from absent data.
  let found = view.lookup(derived.value)
  if found.error == StateStoreError.MissingKey:
    return ServiceRequestResult(status: ServiceReadError.Missing) # A valid request key can prove a history absent.
  if found.error != StateStoreError.None:
    return ServiceRequestResult(status: ServiceReadError.BackendFailure) # Never publish an invalid owner.
  if found.value.byteLength > 13:
    return ServiceRequestResult(status: ServiceReadError.Malformed) # At most a count plus three E4 slots, before copying.
  let wire = found.value.bytes
  let decoded = decodeRequestHistory(wire, RequestHistoryConfig(items: ElementLimit(3),
      maxBytes: ByteLimit(13)))
  if decoded.error != RequestError.None:
    return ServiceRequestResult(status: ServiceReadError.Malformed) # Reject bad counts, truncated slots and noncanonical counts.
  if decoded.value.consumed != wire.len:
    return ServiceRequestResult(status: ServiceReadError.Malformed) # A valid prefix cannot hide trailing bytes.
  ServiceRequestResult(status: ServiceReadError.None, completed: decoded.value.history)
