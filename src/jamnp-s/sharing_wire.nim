# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable untrusted CE134 messages carry no sender, assignment, authorization or signature authority.
import std/assertions
import ../codec/bounded
from ../codec/work/package import MaxBundleBytes

const
  MaxSharingHeaderBytes* = 517 ## E2 core, E2 shards, one canonical count and at most eight64-byte mappings.
  MaxSharingBundleBytes* = MaxBundleBytes ## The same complete auditable-bundle ceiling used by the original package pipeline.
  SharingResponseBytes* = 96 ## Exact report hash followed by one ordinary Ed25519 signature.
type
  SharingWireError* {.pure.} = enum ## Defaults and refusals expose no accepted message prefix.
    Uninitialized, None, InvalidOwner, InvalidMessage, LimitExceeded
  SharingWireInfo* = object ## Detached byte extents can be charged before making independent message copies.
    headerBytes*, bundleBytes*: int
  SharingWireData = ref object ## Private copied buffers never alias mutable native transport storage.
    first, bundle: seq[byte]
  SharedWorkRequest* = object ## Wire completion alone cannot construct a source-qualified report or contribution.
    data: nil SharingWireData
  SharingWireResult*[T] = object ## Only selected complete success has a payload.
    case status: SharingWireError
    of None: completed: T
    else: discard                # No partial/default transcript escapes.
func error*[T](outcome: SharingWireResult[T]): SharingWireError =
  ## Observe framing/ownership refusal without writable status access.
  outcome.status
func value*[T](outcome: SharingWireResult[T]): T {.requires: outcome.status ==
    SharingWireError.None.} =
  ## Only complete wire capture grants byte ownership, never semantic authority.
  outcome.completed
func valid*(request: SharedWorkRequest): bool =
  ## Defaults contain no complete pair of messages.
  request.data != nil
proc sharingInfo*(request: SharedWorkRequest): SharingWireResult[SharingWireInfo] =
  ## Inspect fixed extents before allocating detached message scratch.
  let data = request.data
  if data == nil: return SharingWireResult[SharingWireInfo](status: SharingWireError.InvalidOwner)
  SharingWireResult[SharingWireInfo](status: SharingWireError.None,
    completed: SharingWireInfo(headerBytes: data.first.len, bundleBytes: data.bundle.len))
proc firstMessage*(request: SharedWorkRequest): seq[byte] {.requires: request.data != nil.} =
  ## Return independent small header bytes; caller mutation cannot change the immutable request.
  let data = request.data
  assert data != nil
  result = newSeq[byte](data.first.len)
  for index in 0..<result.len: result[index] = data.first[index]
proc bundleMessage*(request: SharedWorkRequest): seq[byte] {.requires: request.data != nil.} =
  ## Copy only after the receiving worker has preflighted the actual independent local bundle ceiling.
  let data = request.data
  assert data != nil
  result = newSeq[byte](data.bundle.len)
  for index in 0..<result.len: result[index] = data.bundle[index]
proc captureSharedWork*(first, bundle: openArray[byte]): SharingWireResult[SharedWorkRequest] =
  ## Preflight both complete messages before copying any prefix; exact E4/FIN handling belongs to the native route.
  if first.len > MaxSharingHeaderBytes or bundle.len > MaxSharingBundleBytes:
    return SharingWireResult[SharedWorkRequest](status: SharingWireError.LimitExceeded)
  if first.len < 5 or bundle.len == 0:
    return SharingWireResult[SharedWorkRequest](status: SharingWireError.InvalidMessage)
  var small = newSeq[byte](first.len)
  var large = newSeq[byte](bundle.len)
  for index in 0..<small.len: small[index] = first[index]
  for index in 0..<large.len: large[index] = bundle[index]
  SharingWireResult[SharedWorkRequest](status: SharingWireError.None,
    completed: SharedWorkRequest(data: SharingWireData(first: small, bundle: large)))

proc detachedSharingRequest*(request: SharedWorkRequest): SharingWireResult[SharedWorkRequest] =
  ## CPU capture must not share ARC counters with a disposable native task or its host staging aliases.
  let data = request.data
  if data == nil: return SharingWireResult[SharedWorkRequest](status: SharingWireError.InvalidOwner)
  captureSharedWork(data.first, data.bundle)
