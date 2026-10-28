# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable bounded full sealed-header context linked to an explicitly supplied parent.
## Structural ancestry does not authenticate the caller's parent or publish historical state.
import std/assertions
import ../codec/bounded as codec_bounded
import ../codec/header as codec_header
import ../crypto/primitives as crypto_primitives

type
  AncestorContextLimits* = object ## Parent-inclusive count, serialized bytes and exact header profile.
    header*: HeaderConfig
    headers*: ElementLimit
    maxBytes*: ByteLimit
  AncestorContextError* {.pure.} = enum ## Refusal contains no validated prefix or fabricated chain.
    Uninitialized, None, LimitExceeded, InvalidHeader, BrokenAncestry, BackendFailure, InvalidIndex,
    MissingLookupAnchor, WrongLookupSlot, MissingLookupChild, WrongLookupState
  AncestorContextData = ref object ## Private acyclic immutable owners and corresponding full sealed identities.
    headers: seq[OwnedHeader]
    hashes: seq[HeaderParent]
    bytes: uint64
  AncestorContext* = object ## Copies retain read-only context; observers never receive sequence backing storage.
    data: nil AncestorContextData
  AncestorContextResult*[T] = object ## Default and refused alternatives carry only their exact reason.
    case status: AncestorContextError
    of None:
      completed: T
    else:
      discard # No usable context survives partial validation.

func error*[T](outcome: AncestorContextResult[T]): AncestorContextError =
  ## Read status without allowing external retagging.
  outcome.status
func value*[T](outcome: AncestorContextResult[T]): T {.inline, requires:
    outcome.status == AncestorContextError.None.} =
  ## Extract only the selected complete success.
  outcome.completed
func valid*(context: AncestorContext): bool =
  ## A default differs from a valid parent-only context.
  context.data != nil
proc len*(context: AncestorContext): int =
  ## Count includes the selected parent; default context contains no headers.
  let data = context.data
  if data == nil: return 0 # No implicit parent.
  data.headers.len
proc serializedBytes*(context: AncestorContext): uint64 =
  ## Count exact retained sealed bytes, including markers and seals.
  let data = context.data
  if data == nil: return 0 # No default byte claim.
  data.bytes
proc headerAt*(context: AncestorContext, index: int): AncestorContextResult[OwnedHeader] =
  ## Retain an immutable owner by newest-first ordinal without a mutable sequence view.
  let data = context.data
  if data == nil: return AncestorContextResult[OwnedHeader](
      status: AncestorContextError.Uninitialized)
  if index < 0 or index >= data.headers.len:
    return AncestorContextResult[OwnedHeader](status: AncestorContextError.InvalidIndex)
  AncestorContextResult[OwnedHeader](status: AncestorContextError.None, completed: data.headers[index])
proc hashAt*(context: AncestorContext, index: int): AncestorContextResult[HeaderParent] =
  ## Copy the sealed hash corresponding to exactly one retained header.
  let data = context.data
  if data == nil: return AncestorContextResult[HeaderParent](
      status: AncestorContextError.Uninitialized)
  if index < 0 or index >= data.hashes.len:
    return AncestorContextResult[HeaderParent](status: AncestorContextError.InvalidIndex)
  AncestorContextResult[HeaderParent](status: AncestorContextError.None, completed: data.hashes[index])

proc captureAncestorContext*(parent: OwnedHeader, older: openArray[OwnedHeader],
    limits: AncestorContextLimits): AncestorContextResult[AncestorContext] =
  ## Preflight every owner/extent before copying or hashing; then re-decode and link exact sealed bytes.
  if uint64(older.len) >= uint64(limits.headers) or older.len == high(int):
    return AncestorContextResult[AncestorContext](status: AncestorContextError.LimitExceeded)
  let count = older.len + 1
  if count > high(int) div sizeof(OwnedHeader) or count > high(int) div sizeof(HeaderParent):
    return AncestorContextResult[AncestorContext](status: AncestorContextError.LimitExceeded)
  var bytes = 0'u64
  for index in 0..<count:
    # Parent consumes the same independent count/byte quotas as each supplied older header.
    let owner = if index == 0: parent else: older[index - 1]
    let info = owner.headerInfo
    if info.error != HeaderError.None:
      return AncestorContextResult[AncestorContext](status: AncestorContextError.InvalidHeader)
    let size = uint64(info.value.consumed)
    if size > uint64(limits.header.maxBytes) or size > uint64(limits.maxBytes) - bytes:
      return AncestorContextResult[AncestorContext](status: AncestorContextError.LimitExceeded)
    bytes += size # Preflight maintains bytes <= maxBytes, including the selected parent.
  var headers = newSeq[OwnedHeader](count)
  var hashes = newSeq[HeaderParent](count)
  for index in 0..<count:
    # Recapture under this consumer's profile rather than trusting the source decoder's limits.
    let owner = if index == 0: parent else: older[index - 1]
    var wire = newSeq[byte](owner.headerInfo.value.consumed)
    if encodeOwnedHeader(owner, wire).error != HeaderError.None:
      return AncestorContextResult[AncestorContext](status: AncestorContextError.InvalidHeader)
    let decoded = decodeHeader(wire, limits.header)
    if decoded.error == HeaderError.LimitExceeded:
      return AncestorContextResult[AncestorContext](status: AncestorContextError.LimitExceeded)
    if decoded.error != HeaderError.None or decoded.value.consumed != wire.len:
      return AncestorContextResult[AncestorContext](status: AncestorContextError.InvalidHeader)
    let digest = blake2b256(wire)
    if digest.error != CryptoError.None:
      return AncestorContextResult[AncestorContext](status: AncestorContextError.BackendFailure)
    headers[index] = decoded.value.owner
    hashes[index] = HeaderParent(array[32, byte](digest.value))
    if index > 0:
      # Full seals participate in the parent link, and skipped slots remain legal.
      let child = headers[index - 1].headerInfo.value.unsigned
      let fields = headers[index].headerInfo.value.unsigned
      if array[32, byte](child.parent) != array[32, byte](hashes[index]) or
          uint32(fields.slot) >= uint32(child.slot):
        return AncestorContextResult[AncestorContext](status: AncestorContextError.BrokenAncestry)
  AncestorContextResult[AncestorContext](status: AncestorContextError.None,
    completed: AncestorContext(data: AncestorContextData(headers: headers, hashes: hashes,
        bytes: bytes)))

proc extendAncestorContext*(context: AncestorContext, older: openArray[OwnedHeader],
    limits: AncestorContextLimits): AncestorContextResult[AncestorContext] =
  ## Atomically append older context under current limits; refusal never changes the existing context.
  let data = context.data
  if data == nil:
    return AncestorContextResult[AncestorContext](status: AncestorContextError.Uninitialized)
  let retained = data.headers.len
  if uint64(retained) > uint64(limits.headers) or
      uint64(older.len) > uint64(limits.headers) - uint64(retained) or
      older.len > high(int) div sizeof(OwnedHeader) - retained:
    return AncestorContextResult[AncestorContext](status: AncestorContextError.LimitExceeded)
  let count = retained - 1 + older.len # Initialized contexts always retain at least one parent.
  var combined = newSeq[OwnedHeader](count)
  for index in 1..<retained:
    combined[index - 1] = data.headers[index] # Existing newest-first prefix is never replaced or reordered.
  for index, owner in older:
    combined[retained - 1 + index] = owner # Count proof bounds every descriptor before allocation/indexing.
  captureAncestorContext(data.headers[0], combined, limits)

proc findLookupAnchor*(context: AncestorContext, hash: HeaderParent, slot: HeaderSlot,
    root: PriorStateRoot): AncestorContextResult[int] =
  ## Locate the exact sealed hash/slot and prove its posterior root using the retained newer child's prior root.
  let data = context.data
  if data == nil:
    return AncestorContextResult[int](status: AncestorContextError.Uninitialized)
  for index in 0..<data.hashes.len:
    let identity = data.hashes[index]
    # A hash with the wrong slot or no retained child is a permanent mismatch, never an older-header hint.
    if array[32, byte](identity) != array[32, byte](hash): continue
    if uint32(data.headers[index].headerInfo.value.unsigned.slot) != uint32(slot):
      return AncestorContextResult[int](status: AncestorContextError.WrongLookupSlot)
    if index == 0:
      return AncestorContextResult[int](status: AncestorContextError.MissingLookupChild)
    if array[32, byte](data.headers[index - 1].headerInfo.value.unsigned.priorState) != array[32,
        byte](root):
      return AncestorContextResult[int](status: AncestorContextError.WrongLookupState)
    return AncestorContextResult[int](status: AncestorContextError.None, completed: index)
  AncestorContextResult[int](status: AncestorContextError.MissingLookupAnchor)
