# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Typed service reads consume authenticated partial evidence without claiming a complete account map.
## Missing witnesses, proven absence and malformed present bytes remain separate outcomes.
import ./[proof_view, trie_proof]
import ../crypto/primitives
import ../codec/[bounded, state_accounts, state_layout, state_service_values, state_requests]

type
  ServiceProofError* {.pure.} = enum ## Failed/default reads expose only a reason, never a fabricated value.
    Uninitialized, None, MissingWitness, AbsentValue, InvalidValue, LimitExceeded,
    BackendFailure, InvalidInput
  ServiceProofResult*[T] = object ## Success alone grants access to a complete typed read.
    case status: ServiceProofError
    of None:
      completed: T
    else:
      discard                     # Refused reads retain no successful prefix or default account.

func error*[T](outcome: ServiceProofResult[T]): ServiceProofError =
  ## Inspect a reason without authorizing payload access.
  outcome.status
func value*[T](outcome: ServiceProofResult[T]): T {.inline,
    requires: outcome.status == ServiceProofError.None.} =
  ## Extract only explicitly successful typed reads in checked optimized builds.
  outcome.completed
func viewReason(reason: ProofViewError): ServiceProofError =
  ## Exact lookup has no malformed-value interpretation; preserve absent evidence separately.
  case reason
  of ProofViewError.MissingWitness: ServiceProofError.MissingWitness # Unknown never means absent.
  else: ServiceProofError.Uninitialized # Default views cannot authorize any query.

proc readProofAccount*(view: ProofView, service: ServiceIndex): ServiceProofResult[
    ServiceMetadata] =
  ## Decode exact current C(255, service), without claiming validity of its unqueried nested maps.
  let found = view.lookup(chapterServiceKey(StateChapter(255), service))
  if found.error != ProofViewError.None:
    return ServiceProofResult[ServiceMetadata](status: viewReason(found.error))
  if not found.value.present:
    return ServiceProofResult[ServiceMetadata](status: ServiceProofError.AbsentValue)
  if found.value.byteLength != ServiceMetadataBytes:
    return ServiceProofResult[ServiceMetadata](status: ServiceProofError.InvalidValue)
  let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None:
    return ServiceProofResult[ServiceMetadata](status: ServiceProofError.InvalidValue)
  if decoded.value.consumed != ServiceMetadataBytes:
    return ServiceProofResult[ServiceMetadata](status: ServiceProofError.InvalidValue)
  ServiceProofResult[ServiceMetadata](status: ServiceProofError.None,
      completed: decoded.value.metadata)

proc presentRead(view: ProofView, key: StateKey, limit: ByteLimit): ServiceProofResult[
    VerifiedStateLookup] =
  ## Inspect immutable authenticated extents before any caller-controlled value copy.
  let found = view.lookup(key)
  if found.error != ProofViewError.None:
    return ServiceProofResult[VerifiedStateLookup](status: viewReason(found.error))
  if not found.value.present:
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.AbsentValue)
  if uint64(found.value.byteLength) > uint64(limit):
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.LimitExceeded)
  ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.None, completed: found.value)

proc readProofStorage*(view: ProofView, service: ServiceIndex, key: openArray[byte],
    limits: ServiceEntryLimits): ServiceProofResult[VerifiedStateLookup] =
  ## Require the same view's canonical account before resolving its bounded raw storage namespace.
  if uint64(key.len) > uint64(limits.keyBytes):
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.LimitExceeded)
  let account = view.readProofAccount(service)
  if account.error != ServiceProofError.None:
    return ServiceProofResult[VerifiedStateLookup](status: account.error)
  let derived = serviceStorageKey(service, key, limits.keyBytes)
  if derived.error != ServiceValueError.None:
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.BackendFailure)
  presentRead(view, derived.value, limits.valueBytes)

proc readProofPreimage*(view: ProofView, service: ServiceIndex, hash: ServicePreimageHash,
    limit: ByteLimit): ServiceProofResult[VerifiedStateLookup] =
  ## Authenticate the same-root account and bounded preimage, then verify its actual content digest.
  let account = view.readProofAccount(service)
  if account.error != ServiceProofError.None:
    return ServiceProofResult[VerifiedStateLookup](status: account.error)
  let derived = servicePreimageKey(service, hash, ByteLimit(32))
  if derived.error != ServiceValueError.None:
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.BackendFailure)
  let found = presentRead(view, derived.value, limit)
  if found.error != ServiceProofError.None:
    return found
  let digest = blake2b256(found.value.bytes)
  if digest.error != CryptoError.None:
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.BackendFailure)
  if array[32, byte](digest.value) != array[32, byte](hash):
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.InvalidValue)
  found

proc readProofRequest*(view: ProofView, service: ServiceIndex, hash: ServicePreimageHash,
    length: RequestLength): ServiceProofResult[RequestHistory] =
  ## Refuse reserved lengths before account access or hashing, then decode an exact canonical history.
  if uint32(length) >= high(uint32)-1:
    return ServiceProofResult[RequestHistory](status: ServiceProofError.InvalidInput)
  let account = view.readProofAccount(service)
  if account.error != ServiceProofError.None:
    return ServiceProofResult[RequestHistory](status: account.error)
  let derived = serviceRequestKey(service, hash, length, ByteLimit(32))
  if derived.error != RequestError.None:
    return ServiceProofResult[RequestHistory](status: ServiceProofError.BackendFailure)
  let found = presentRead(view, derived.value, ByteLimit(13))
  if found.error == ServiceProofError.LimitExceeded:
    return ServiceProofResult[RequestHistory](status: ServiceProofError.InvalidValue)
  if found.error != ServiceProofError.None:
    return ServiceProofResult[RequestHistory](status: found.error)
  let decoded = decodeRequestHistory(found.value.bytes,
    RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(13)))
  if decoded.error != RequestError.None:
    return ServiceProofResult[RequestHistory](status: ServiceProofError.InvalidValue)
  if decoded.value.consumed != found.value.byteLength:
    return ServiceProofResult[RequestHistory](status: ServiceProofError.InvalidValue)
  ServiceProofResult[RequestHistory](status: ServiceProofError.None,
      completed: decoded.value.history)

proc proofPreimageRequested*(view: ProofView, service: ServiceIndex, hash: ServicePreimageHash,
    length: RequestLength): ServiceProofResult[bool] =
  ## Proven absent accounts/requests are false; unknown witnesses and malformed state cannot decide solicitation.
  let history = view.readProofRequest(service, hash, length)
  if history.error == ServiceProofError.AbsentValue:
    return ServiceProofResult[bool](status: ServiceProofError.None, completed: false)
  if history.error != ServiceProofError.None:
    return ServiceProofResult[bool](status: history.error)
  ServiceProofResult[bool](status: ServiceProofError.None,
    completed: history.value.state == RequestState.Requested)

func availableAt(history: RequestHistory, slot: RequestSlot): bool =
  ## Apply the pinned four-shape availability equation without adding chronological constraints.
  let time = uint32(slot)
  case history.state
  of RequestState.Requested:
    false # No supply interval exists for an outstanding request.
  of RequestState.Available:
    uint32(history.since) <= time
  of RequestState.Unavailable:
    uint32(history.availableFrom) <= time and time < uint32(history.unavailableFrom)
  of RequestState.Reavailable:
    (uint32(history.originalFrom) <= time and time < uint32(history.removedAt)) or
      uint32(history.restoredAt) <= time

proc readProofHistoricalPreimage*(view: ProofView, service: ServiceIndex,
    hash: ServicePreimageHash, slot: RequestSlot, limit: ByteLimit): ServiceProofResult[
        VerifiedStateLookup] =
  ## Compose account, content and actual-length history facts from one immutable root at an explicit time.
  let preimage = view.readProofPreimage(service, hash, limit)
  if preimage.error != ServiceProofError.None:
    return preimage
  let size = uint64(preimage.value.byteLength)
  if size >= uint64(high(uint32))-1:
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.InvalidValue)
  let history = view.readProofRequest(service, hash, RequestLength(uint32(size)))
  if history.error == ServiceProofError.AbsentValue:
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.InvalidValue)
  if history.error != ServiceProofError.None:
    return ServiceProofResult[VerifiedStateLookup](status: history.error)
  if not availableAt(history.value, slot):
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.AbsentValue)
  preimage

proc readProofCode*(view: ProofView, service: ServiceIndex, slot: RequestSlot,
    limit: ByteLimit): ServiceProofResult[VerifiedStateLookup] =
  ## Resolve current account code identity internally, then require its authenticated historical preimage.
  let account = view.readProofAccount(service)
  if account.error != ServiceProofError.None:
    return ServiceProofResult[VerifiedStateLookup](status: account.error)
  let hash = ServicePreimageHash(array[32, byte](account.value.codeHash))
  view.readProofHistoricalPreimage(service, hash, slot, limit)
