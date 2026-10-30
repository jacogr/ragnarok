# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exclusive bounded E4 receiver for descending ancestor responses; callbacks copy bytes only.
## Request FIN and actual response FIN are independent; decoding remains an explicit producer operation.
import std/assertions
import ./response as ancestor_response
import ../../codec/[bounded, block_codec]

type
  AncestorReceiveId* = distinct uint64 ## Local generations prevent delayed callbacks from changing a reused receiver.
  AncestorReceiveStage* {.pure.} = enum ## Raw completion remains owned until explicit cancellation/acknowledgement.
    Idle, Receiving, Ready, Failed
  AncestorReceiveError* {.pure.} = enum ## Framing failures are distinct from later block/ancestry decoder reasons.
    Uninitialized, None, Busy, InvalidRequest, InvalidPolicy, Exhausted, Stale,
    NotReady, Truncated, Trailing, LimitExceeded
  AncestorReceiveResult*[T] = object ## Only successful operations supply a generation or fixed request bytes.
    case status: AncestorReceiveError
    of None:
      completed: T
    else:
      discard # Failed/default results carry no usable payload.
  AncestorReceiver* = object ## One mutable buffer and callback generation; no canonical state/map is retained.
    next: uint64
    id: AncestorReceiveId
    state: AncestorReceiveStage
    reason: AncestorReceiveError
    requestOwner: AncestorRequest
    ceiling: uint64
    prefix: array[4, byte]
    prefixBytes, received: int
    requestFin, responseFin, announced: bool
    payload: seq[byte]

proc `=copy`*(destination: var AncestorReceiver, source: AncestorReceiver) {.error:
    "AncestorReceiver owns reception".}
  ## Mutable buffer offsets and generation cancellation must never acquire a second owner.

proc `=dup`*(source: AncestorReceiver): AncestorReceiver {.error.}
  ## Explicit duplication is forbidden through the actual owned sequence lowering too.

proc `==`*(left, right: AncestorReceiveId): bool {.borrow.}
  ## Compare only local receiver generations.

func stage*(receiver: AncestorReceiver): AncestorReceiveStage =
  ## Read scalar state without borrowing or exposing payload storage.
  receiver.state

func error*[T](outcome: AncestorReceiveResult[T]): AncestorReceiveError =
  ## Inspect success/refusal without exposing its private tag.
  outcome.status

func value*[T](outcome: AncestorReceiveResult[T]): T {.inline, requires:
    outcome.status == AncestorReceiveError.None.} =
  ## Extract only a checked generation or exact captured request.
  outcome.completed

func failure*(receiver: AncestorReceiver): AncestorReceiveError {.requires:
    receiver.state == AncestorReceiveStage.Failed.} =
  ## Observe the selected terminal framing reason after callback retirement.
  receiver.reason

proc fail(receiver: var AncestorReceiver, reason: AncestorReceiveError): AncestorReceiveError =
  ## A late failure releases all raw response bytes before exposing its terminal scalar reason.
  receiver.payload = @[]
  receiver.state = AncestorReceiveStage.Failed
  receiver.reason = reason
  reason

proc begin*(receiver: var AncestorReceiver, request: AncestorRequest,
    maxBytes: ByteLimit): AncestorReceiveResult[AncestorReceiveId] =
  ## Validate the whole allocation ceiling before reserving a new generation; refusal leaves the owner unchanged.
  if receiver.state != AncestorReceiveStage.Idle:
    return AncestorReceiveResult[AncestorReceiveId](status: AncestorReceiveError.Busy)
  if not request.valid:
    return AncestorReceiveResult[AncestorReceiveId](status: AncestorReceiveError.InvalidRequest)
  if uint64(maxBytes) > uint64(high(uint32)) or uint64(maxBytes) > uint64(high(int)):
    return AncestorReceiveResult[AncestorReceiveId](status: AncestorReceiveError.InvalidPolicy)
  if receiver.next == high(uint64):
    return AncestorReceiveResult[AncestorReceiveId](status: AncestorReceiveError.Exhausted)
  let next = receiver.next + 1 # Exhaustion is checked before generation arithmetic.
  receiver = AncestorReceiver(next: next, id: AncestorReceiveId(next),
      state: AncestorReceiveStage.Receiving,
    reason: AncestorReceiveError.None, requestOwner: request, ceiling: uint64(maxBytes),
    prefix: default(array[4, byte]), prefixBytes: 0, received: 0,
    requestFin: false, responseFin: false, announced: false, payload: @[])
  AncestorReceiveResult[AncestorReceiveId](status: AncestorReceiveError.None,
      completed: receiver.id)

proc request*(receiver: AncestorReceiver, id: AncestorReceiveId): AncestorReceiveResult[array[42, byte]] =
  ## Native binding requires the current receiving generation's exact immutable request.
  if receiver.state != AncestorReceiveStage.Receiving or receiver.id != id:
    return AncestorReceiveResult[array[42, byte]](status: AncestorReceiveError.Stale)
  AncestorReceiveResult[array[42, byte]](status: AncestorReceiveError.None,
    completed: receiver.requestOwner.requestBytes)

proc finish(receiver: var AncestorReceiver) =
  ## Byte completeness alone cannot replace either direction's actual FIN acknowledgement.
  if receiver.requestFin and receiver.responseFin:
    receiver.state = AncestorReceiveStage.Ready # Empty payload is decoded as the distinct valid Empty protocol outcome.

proc requestFinished*(receiver: var AncestorReceiver, id: AncestorReceiveId): AncestorReceiveError =
  ## The transport calls this only after queueing its request FIN.
  if receiver.state != AncestorReceiveStage.Receiving or receiver.id != id:
    return AncestorReceiveError.Stale # Late writes cannot finish another generation.
  receiver.requestFin = true
  receiver.finish()
  AncestorReceiveError.None

proc append*(receiver: var AncestorReceiver, id: AncestorReceiveId,
    fragment: openArray[byte], fin: bool): AncestorReceiveError =
  ## Consume one bounded fragment and actual EOF without decoding, hashing or executing historical data.
  if receiver.state notin [AncestorReceiveStage.Receiving, AncestorReceiveStage.Ready] or
      receiver.id != id:
    return AncestorReceiveError.Stale
  if receiver.state == AncestorReceiveStage.Ready or receiver.responseFin:
    return AncestorReceiveError.Busy # Complete captured bytes remain immutable through late/replayed callbacks.
  var cursor = 0
  while cursor < fragment.len and receiver.prefixBytes < 4:
    receiver.prefix[receiver.prefixBytes] = fragment[cursor]
    inc receiver.prefixBytes
    inc cursor # Both fixed header and current fragment extents were checked before access.
  if receiver.prefixBytes == 4 and not receiver.announced:
    var claimed = 0'u64
    for index in 0..<4:
      claimed = claimed or (uint64(receiver.prefix[index]) shl (index *
          8)) # E4, never compact or element-count framing.
    if claimed > receiver.ceiling:
      return receiver.fail(AncestorReceiveError.LimitExceeded) # No allocation precedes the complete bounded claim.
    receiver.payload = newSeq[byte](int(claimed))
    receiver.announced = true
  if receiver.announced and cursor < fragment.len:
    let count = fragment.len - cursor
    if count > receiver.payload.len - receiver.received:
      return receiver.fail(AncestorReceiveError.Trailing) # Suffixes and second messages never enter captured storage.
    for index in 0..<count:
      receiver.payload[receiver.received + index] = fragment[cursor +
          index] # Proven remaining capacity bounds both accesses.
    receiver.received += count
  if fin:
    if not receiver.announced or receiver.received != receiver.payload.len:
      return receiver.fail(AncestorReceiveError.Truncated) # A header or body prefix cannot be decoded as a response.
    receiver.responseFin = true
    receiver.finish()
  AncestorReceiveError.None

proc response*(receiver: AncestorReceiver, id: AncestorReceiveId, frame: FrameConfig,
    headerBytes: ByteLimit): AncestorResponseResult[AncestorResponse] {.requires:
    receiver.state == AncestorReceiveStage.Ready and receiver.id == id.} =
  ## Producer decoding is explicit after both FINs; native consumers must additionally retire stream callbacks first.
  decodeAncestorResponse(receiver.requestOwner, receiver.payload, frame, ByteLimit(
      receiver.ceiling), headerBytes)

proc cancel*(receiver: var AncestorReceiver, id: AncestorReceiveId): bool =
  ## Release/acknowledge only the selected generation after its callback binding has been retired.
  if receiver.state == AncestorReceiveStage.Idle or receiver.id !=
      id: return false # Stale cancellation cannot erase current bytes.
  let next = receiver.next
  receiver = AncestorReceiver(next: next) # Preserve monotonic identity across success, failure and explicit cancellation.
  true
